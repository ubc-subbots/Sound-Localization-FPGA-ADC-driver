`timescale 1ns/1ps
`default_nettype none

/**
 * ADS8528 Sampler Top-level module
 *
 * This module connects the ADC ADS8528 Controller module to the sample buffer, which is connected
 * to the SPI slave that interacts with the RaspberryPi.
 *
 * TODO:
 *      - rename module to adc_ads8528_sampler_top without breaking Quartus project
 *      - THRESHOLD_VOLTAGE should be 12 bits to match number of actual data bits
 *      - What is the reason for the "less than" check in the current threshold detection always block
 *      - Should threshold_counter be reset if we get a voltage signal that doesnt exceed the threshold?
 *          - should the voltage values be consecutive
 *          - would this increase false negatives and lead to missing the start of a pulse?
 *      - Create moving average of last 10 samples
 *      - Remove unused variables
 */
module top #(
	parameter int 		 BUFFER_DEPTH          = 500,
    parameter int        PRE_THRESHOLD_SAMPLES = 40,     // Number of samples to save from before threshold detection
	parameter int 		 NUM_OUTPUT_SAMPLES    = 500,    // Number of ADC samples sent to raspberry pi
	parameter bit [11:0] THRESHOLD_VOLTAGE     = 12'd32,  // Any voltage above this threshold will be considered valid
    parameter int        NUM_CHANNELS          = 5
) (
    inout  wire  [15:0] DB,  //driver inputs
    input  wire  Busy,
    input  wire  CLOCK_27M,
    input  wire  rst,
    input  wire  KEY2,

    input  wire  sclk,   // Master clock for SPI, will come from ESP32?
    input  wire  SPI_cs, // Should be coming from the ESP32
    input  wire  transaction_done,

    output logic convst_A, //Driver outputs to ADC
    output logic convst_B,
    output logic convst_C,
    output logic convst_D,
    output logic RD_N,
    output logic ADC_CS_N,
    output logic HW_N,
    output logic PAR_N,
    output logic ADCrst,
    output logic STBY_N,
    output logic WR_N,
    output logic XCLK,

    output logic processed_MISO, //SPI outputs to Rasberry pi
    output logic SPI_RDY
);


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Types and Constants Declarations


    typedef enum {
        WAITING,
        FILL,
        WAIT_CS,
        CHECK_SPI_READY,
        SPI_SEND_CHANNEL_HEADER,
        CHECK_SPI_READY_DATA,
        SPI_SEND_CHANNEL_BUFFER

    } state_t;

    


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Signal Declarations


    state_t state;
    logic clk; 

    // Outputs of ADC ADS8528 Controller
    logic [15:0] adc_data_out;
    logic        adc_data_out_valid;

    // Outputs of ADC ADS8528 Controller sorted by channel
    logic [11:0]              adc_channel_data [NUM_CHANNELS-1:0];
    logic [NUM_CHANNELS-1:0]  adc_channel_data_valid;
    logic [11:0]              adc_channel_average [NUM_CHANNELS-1:0];
    logic [NUM_CHANNELS-1:0]  adc_channel_average_valid;

    // FIFO Buffer Signals
    logic                            write_to_buffer  [NUM_CHANNELS-1:0]; // Assert to write a value to the input of the buffer
    logic                            read_from_buffer [NUM_CHANNELS-1:0]; // Assert to read the value at the output of the buffer
    logic [$clog2(BUFFER_DEPTH)-1:0] buffer_count     [NUM_CHANNELS-1:0]; // Indicates the number of values stored in the buffer
    logic                            empty            [NUM_CHANNELS-1:0]; // Indicates if the buffer is empty
    logic                            full             [NUM_CHANNELS-1:0]; // Indicates if the buffer is full
    logic [15:0]                     buffer_data_out  [NUM_CHANNELS-1:0]; // Output of the buffer

    // SPI Slave signals
    logic ready_for_data;
    //logic spi_cs_L; -> should be supplied by esp32 whoops

    // TODO: Implement in SPI state machine?
    logic spi_read_data;
    logic spi_transaction_done;

    logic [31:0] fill_counter;    // Counter for filling buffer after threshold detection
    logic [15:0] buffer_data_to_SPI;
    
    //counter for buffers during spi
    logic [$clog2(BUFFER_DEPTH)-1:0] chan_counter;


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Output Assignments


    assign ADCrst  = ~KEY2;
    assign XCLK    = 1'b1; //should be clk
    assign SPI_RDY = state[2];


    // TODO: Implement these signals in spi controller
    assign spi_read_data        = 1'b1;
    assign spi_transaction_done = 1'b1;


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Logic Implementation


    // Clock Divider
    Clk_divider clk_divider_inst (
        .clk_in  ( CLOCK_27M ),
        .divisor ( 32'd4     ),
        .switch  ( 1'd1      ),
        .clk_out ( clk       )
    );

    // ADS8528 ADC Controller
    driver adc_ads8528_ctrl_inst (
        .clk           ( clk      ),
        .sresetn       ( rst      ),
        .busy          ( Busy     ),

        .data_adc      ( DB       ),

        // ADS8528 Control Signals
        .read_n        ( RD_N     ),
        .write_n       ( WR_N     ),
        .chipselect_n  ( ADC_CS_N ),
        .software_mode ( HW_N     ),
        .serial_mode   ( PAR_N    ),
        .standby_n     ( STBY_N   ),

        // ADS8528 starts conversion of channel 'x' on rising-edge of conv_start_x
        .conv_start_a  ( convst_A ),
        .conv_start_b  ( convst_B ),
        .conv_start_c  ( convst_C ),
        .conv_start_d  ( convst_D ),

        // Driver handshake
        .data_out      ( adc_data_out       ),
        .data_valid    ( adc_data_out_valid )
    );

    // Sort signals by channel for threshold detection
    genvar i;
    generate
        for (i = 0; i < NUM_CHANNELS; i++) begin : gen_avg_window_each_channel
            assign adc_channel_data[i] = adc_data_out[11:0];
            assign adc_channel_data_valid[i] = adc_data_out_valid && (adc_data_out[14:12] == i);

            avg_window #(
                .N          ( 4  ),
                .DATA_WIDTH ( 12 )
            ) avg_window_each_channel (
                .clk           ( clk                          ),
                .sresetn       ( rst                          ),
                .data_in       ( adc_channel_data[i]          ),
                .data_valid    ( adc_channel_data_valid[i]    ),
                .average       ( adc_channel_average[i]       ),
                .average_valid ( adc_channel_average_valid[i] )
            );

            // FIFO Buffer for ADC Data
            ADCmemory fifo_buffer_inst  (
                .clk      ( clk              ),
                .rst      ( rst              ),
                .write    ( write_to_buffer[i]  ),
                .read     ( read_from_buffer[i] ),
                .data_in  ( adc_data_out[i]     ),
                .count    ( buffer_count[i]     ),
                .data_out ( buffer_data_out[i]  ),
                .full     ( full[i]             ),
                .empty    ( empty[i]            )
            );
        end
    endgenerate



    // SPI Slave connected to RaspberryPi
    spi spi_slave_inst(
        .rst              ( rst             ),
        .sclk             ( sclk            ),
        .cs               ( SPI_cs          ),
        .unprocessed_MISO ( buffer_data_to_SPI),
        .processed_MISO   ( processed_MISO  ),
        .ready_for_data   ( ready_for_data  )
    );

    // Threshold Detection State Machine Control
    always_ff@(posedge clk or negedge rst) begin
        // Asynchronous reset
        if (!rst) begin
            state        <= WAITING;
            fill_counter <= '0;


        end else begin
            case(state)
                // Wait for moving average of last N samples of any channel to exceed the threshold voltage
                WAITING: begin
                    for (int i = 0; i < NUM_CHANNELS; i++) begin
                        //So if the channel average of one channel meets the threshold, we're filling the
                        if (adc_channel_average_valid[i] && adc_channel_average[i] > THRESHOLD_VOLTAGE) begin
                            state <= FILL;

                        end
                    end
                end

                // After threshold voltage is detected, fill remainder of buffer with
                // NUM_OUTPUT_SAMPLES - PRE_THRESHOLD_SAMPLES ADC samples
                FILL: begin
                    if (adc_data_out_valid) begin

                        fill_counter <= fill_counter + 'd1; //needs to be zero'd before we go to WAITING again


                        // If NUM_OUTPUT_SAMPLES is reached, move to EMPTY state to have SPI feed data to output
                        if (fill_counter == (NUM_OUTPUT_SAMPLES - PRE_THRESHOLD_SAMPLES - 1)) begin
                            chan_counter <= 3'b0;

                            //Shouldn't this be WAIT_CS?
                            //state <= CHECK_SPI_READY;
                            state <= WAIT_CS;

                        end
                    end
                end

                WAIT_CS: begin
                    
                    //checking if the esp32 wants to read data yet
                    if(SPI_cs) begin

                        state <= CHECK_SPI_READY;

                    end
                    
                    //Otherwise we spin this state

                end

                CHECK_SPI_READY: begin
                   
                   if(!ready_for_data)begin //active-low!

                        state <= SPI_SEND_CHANNEL_HEADER;

                   end
                   //Otherwise we spin this state

                end

                SPI_SEND_CHANNEL_HEADER: begin
                    
                    if(chan_counter == 3'b111)begin

                        state <= WAITING;
                        //fill_counter <= 32'b0;

                    end else begin

                        //The channel counter is the header
            
                        state <= CHECK_SPI_READY_DATA;
                        
                    end
                    
            
                end

                CHECK_SPI_READY_DATA: begin

                    if(!ready_for_data)begin //ready_for_data is active-low!

                        state <= SPI_SEND_CHANNEL_BUFFER;

                    end
                
                end

                SPI_SEND_CHANNEL_BUFFER: begin                   

                    if(empty[chan_counter])begin

                        state <= CHECK_SPI_READY;
                        chan_counter <= chan_counter + 'd1;

                    end
                
                end


                default: begin

                    state <= WAITING;

                end

            endcase
        end
    end

    always_comb begin
            for(int i = 0; i < NUM_CHANNELS; i++) begin
                write_to_buffer[i]  = 1'b0;
                read_from_buffer[i] = 1'b0;
            end
            buffer_data_to_SPI = 16'b0;

            case(state)
                // Wait for THRESHOLD_COUNT voltage values over THRESHOLD_VOLTAGE to be detected
                WAITING: begin

                    for(int i = 0; i < NUM_CHANNELS; i++) begin

                        write_to_buffer[i] = adc_channel_data_valid[i];
                        read_from_buffer[i] = adc_channel_data_valid[i] && (buffer_count[i] == BUFFER_DEPTH - 1);

                    end

                    // Read from buffer if writing and if we would be full next cycle without
                    // reading. One empty space must be left to enable unblocked writes whenever
                    // adc_data_out is valid.
                    
                end

                // After threshold voltage is detected, fill remainder of buffer with
                // NUM_OUTPUT_SAMPLES - PRE_THRESHOLD_SAMPLES ADC samples
                FILL: begin

                    for(int i = 0; i < NUM_CHANNELS; i++) begin

                        write_to_buffer[i] = adc_channel_data_valid[i];
                        read_from_buffer[i] = adc_channel_data_valid[i] && (buffer_count[i] == BUFFER_DEPTH - 1);

                    end

                    // Read from buffer if writing and if we would be full next cycle without
                    // reading. One empty space must be left to enable unblocked writes whenever
                    // adc_data_out is valid.
                    
                end

                SPI_SEND_CHANNEL_HEADER: begin
                    //ADC can no longer write to buffer for this channel
                    write_to_buffer[chan_counter]  = 0;
                    if(chan_counter != 3'b111) begin

                        buffer_data_to_SPI = {13'b0, chan_counter}; 
                        
                    end
                    

                end

                SPI_SEND_CHANNEL_BUFFER: begin
                    
                    
                    read_from_buffer[chan_counter] = 1'b1;
                    buffer_data_to_SPI = buffer_data_out[chan_counter];

                    if(empty[chan_counter])begin

                        //we stop reading once it is empty
                        read_from_buffer[chan_counter] = 0;
                    end

                end
                


                default: begin
                    buffer_data_to_SPI = 16'b0;
                end
            endcase
    end
endmodule

`default_nettype wire
