`timescale 1ns/1ps
`default_nettype none

/**
 * ADS8528 ADC Controller
 *
 * This module configures an ADS8528 ADC to run in the 'parallel' mode with an internal conversion clock then
 * collects data on a periodic basis, outputting the data using a data_valid signal.
 *
 * Note: this module does not support backpressure on the output.
 *
 * TODO:
 *      - rename module to adc_ads8528_ctrl without breaking Quartus project
 *      - Remove bloat/refactor module
 *      - Confirm module is working in hardware-testing
 *         - Create ADS8528 interface to use as port to this module (ADS8528.Master will contain all adc control signals)
 *      - Standardize the output interface (AXI-Stream?)
 *        - Backpressure support
 *        - Generalize module to adc_ads85x8_ctrl (add parameter for datawidth to support 12, 14, and 16 chip versions)
 */
module driver (
    input  logic        clk,
    input  logic        sresetn,
    input  logic        busy,          // Indicates a conversion is taking place on ADS8528 (Active-high)
    
    inout  logic [15:0] data_adc,      // input/output databits from ADS8528

    // ADS8528 Control Signals
    output logic        read_n,        // Tells ADS8528 its data output has been read (Active-low)
    output logic        write_n,       // Tells ADS8528 a write operation taking place (Active-low)
    output logic        chipselect_n,  // Chip-select bit, must be deasserted for operation (Active-low)
    output logic        software_mode, // Controls whether ADS8528 is in software or hardware mode
    output logic        serial_mode,   // Controls whether ADS8528 is in serial or parallel mode
    output logic        standby_n,       // Powers entire device down when deasserted and in hardware mode

    // ADS8528 starts conversion of channel 'x' on rising-edge of conv_start_x
    output logic        conv_start_a,
    output logic        conv_start_b,
    output logic        conv_start_c,
    output logic        conv_start_d,

    // Driver handshake
    output logic [15:0] data_out,      // ADC data sample out
    output logic        data_valid     // Indicates that data_out is valid
);


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Types and Constants Declarations

    // ADS8528 CONFIG fields: datasheet SBAS543C, section 9.5.1.1, pages 39-41.
    // These compile-time settings are written once after driver reset.
    // HW/SW and PAR/SER are separate mode-selection pins, not CONFIG fields.
    localparam logic CONFIG_WRITE_EN = 1'b1; // C31: 0 = no update, 1 = update CONFIG
    localparam logic CONFIG_READ_EN  = 1'b0; // C30: 0 = conversion data, 1 = CONFIG readback
    localparam logic CONFIG_CLKSEL   = 1'b0; // C29: 0 = internal conversion clock, 1 = external XCLK
    localparam logic CONFIG_CLKOUT   = 1'b0; // C28: 1 = output internal clock on RANGE/XCLK
    localparam logic CONFIG_BUSY_INT = 1'b0; // C27: 0 = BUSY, 1 = interrupt mode
    localparam logic CONFIG_BUSY_POL = 1'b0; // C26: 0 = active-high BUSY/INT, 1 = active-low
    localparam logic CONFIG_STBY     = 1'b0; // C25: 0 = normal operation, 1 = device powered down
    localparam logic CONFIG_RANGE_A  = 1'b0; // C24: 0 = +/-4 VREF, 1 = +/-2 VREF
    localparam logic CONFIG_RANGE_B  = 1'b0; // C23: 0 = +/-4 VREF, 1 = +/-2 VREF
    localparam logic CONFIG_PD_B     = 1'b0; // C22: 0 = pair B active, 1 = pair B powered down
    localparam logic CONFIG_RANGE_C  = 1'b0; // C21: 0 = +/-4 VREF, 1 = +/-2 VREF
    localparam logic CONFIG_PD_C     = 1'b0; // C20: 0 = pair C active, 1 = pair C powered down
    localparam logic CONFIG_RANGE_D  = 1'b0; // C19: 0 = +/-4 VREF, 1 = +/-2 VREF
    localparam logic CONFIG_PD_D     = 1'b1; // C18: 0 = pair D active, 1 = pair D powered down
    localparam logic [1:0] CONFIG_UNUSED_17_16 = 2'b00; // C17:C16: unused, keep at default
    localparam logic CONFIG_REF_EN   = 1'b1; // C15: 1 = internal reference enabled
    localparam logic CONFIG_REFBUF   = 1'b0; // C14: 0 = reference buffers enabled, 1 = disabled
    localparam logic CONFIG_VREF     = 1'b0; // C13: 0 = 2.5 V reference range, 1 = 3.0 V
    localparam logic [2:0] CONFIG_UNUSED_12_10 = 3'b000; // C12:C10: unused, keep at default
    localparam logic [9:0] CONFIG_REFDAC = 10'h3FF; // C9:C0: full-scale reference DAC code

    // Concatenate from C31 (MSB) to C0 (LSB); parallel writes send the upper half first.
    localparam logic [31:0] ADC_CONFIG = {
        CONFIG_WRITE_EN, CONFIG_READ_EN, CONFIG_CLKSEL, CONFIG_CLKOUT,
        CONFIG_BUSY_INT, CONFIG_BUSY_POL, CONFIG_STBY, CONFIG_RANGE_A,
        CONFIG_RANGE_B, CONFIG_PD_B, CONFIG_RANGE_C, CONFIG_PD_C,
        CONFIG_RANGE_D, CONFIG_PD_D, CONFIG_UNUSED_17_16,
        CONFIG_REF_EN, CONFIG_REFBUF, CONFIG_VREF, CONFIG_UNUSED_12_10,
        CONFIG_REFDAC
    };

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: State Definitions



    typedef enum {
        CONFIG,
        CONV_START,
        ADC_READ,
        SAMPLE_OUT
    } state_t;


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Signal Declarations


    state_t state_ff;

    logic finished_write;
    logic conv_start;

    logic [3:0] selected_channel; // Indicates which channel of ADC is being read, resets to 0 after 5

    logic [6:0] write_count;

    logic [15:0] data_adc_out;
    logic [15:0] data_out_reg;


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Output Assignments


    assign data_adc = write_n ? 16'bz : data_adc_out;

    assign software_mode = 1'b1;
    assign serial_mode   = 1'b0;
    assign standby_n     = 1'b1;

    // All channel conversions are started simultaneously
    assign conv_start_a = conv_start;
    assign conv_start_b = conv_start;
    assign conv_start_c = conv_start;
    assign conv_start_d = conv_start;


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Logic Implementation


    // Chip Select Register
    always_ff @(posedge clk) begin
        // Initialize the chip as unselected
        if (!sresetn) begin
            chipselect_n <= 1'b1;

        end else begin
            if (finished_write) begin
                if (conv_start || state_ff == ADC_READ || state_ff == SAMPLE_OUT) begin
                    chipselect_n <= 1'b0;
                end else begin
                    chipselect_n <= 1'b1;
                end

            // While write is not finished, keep chip selected until the complete
            end else begin
                chipselect_n <= write_count == '0;
            end
        end
    end

    // Initial Write to ADS8528 Config-Register Control
    always_ff @(posedge clk) begin
        if (!sresetn) begin
            finished_write <= 1'b0;
            write_count    <= 3'd4;
            write_n        <= 1'b1;
            data_adc_out   <= 'X;

        end else begin 
            if (!finished_write) begin
                if (write_count == '0) begin
                    finished_write <= 1'b1;

                end else begin
                    write_count <= write_count - 1;
                    write_n     <= !write_n;
                end

                if (write_count > 3'd2) begin
                    data_adc_out <= ADC_CONFIG[31:16]; // Upper half of CONFIG

                end else begin 
                    data_adc_out <= ADC_CONFIG[15:0]; // Lower half of CONFIG
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!sresetn) begin
            state_ff         <= CONFIG;
            selected_channel <= 3'b000;
            conv_start       <= 1'b0;
            read_n           <= 1'b1;
            data_valid       <= 1'b0;

        end else begin
            case(state_ff)
                // Waiting while initial writes to ADC are completed
                CONFIG: begin
                    if (finished_write) begin
                        state_ff <= CONV_START;
                    end else begin
                        state_ff <= CONFIG;
                    end
                end

                // Initiates conversions
                CONV_START: begin
                    // Transitioning when busy goes high ensures that the conversion has actually
                    // begun before going to ADC_READ state.
                    if (conv_start) begin
                        state_ff <= ADC_READ;
                    end else begin
                        state_ff <= CONV_START;
                    end
                end

                // Wait for conversion completion, then spend one cycle with RD low before capture.
                ADC_READ: begin
                    if (selected_channel == 3'd6) begin
                        state_ff <= CONV_START;
                    end else if (busy) begin
                        state_ff <= ADC_READ;
                    end else if (!read_n) begin
                        state_ff <= SAMPLE_OUT;
                    end else begin
                        state_ff <= ADC_READ;
                    end
                end

                // Handshake ADC data_out
                SAMPLE_OUT: begin
                    state_ff <= ADC_READ;
                    end

                default: state_ff <= CONV_START;
            endcase

            // TODO: This case statement should be integrated with above, with register changes on
            //             state transitions.
            case(state_ff)
                CONFIG: begin
                    data_valid <= 1'b0;
                    read_n     <= 1'b1;
                    conv_start <= 1'b0;
                end

                CONV_START: begin
                    data_valid <= 1'b0;
                    read_n     <= 1'b1;
                    conv_start <= 1'b1;

                    selected_channel <= 3'b000;
                end

                ADC_READ: begin
                    data_valid   <= 1'b0;
                    read_n       <= busy || selected_channel == 3'd6;
                    conv_start   <= 1'b0;
                    // read_n is the previous cycle's value: capture only after a full low cycle.
                    // SAMPLE_OUT raises RD and publishes this captured word on the following edge.
                    if (!busy && selected_channel != 3'd6 && !read_n) begin
                        data_out_reg <= data_adc;
                    end
                end

                SAMPLE_OUT: begin
                    data_out   <= data_out_reg;
                    data_valid <= 1'b1;
                    read_n     <= 1'b1;

                    selected_channel <= selected_channel + 1'b1;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
