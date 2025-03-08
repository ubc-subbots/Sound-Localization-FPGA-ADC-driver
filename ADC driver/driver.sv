`timescale 1ns/1ps
`default_nettype none

/**
 * ADS8528 ADC Controller
 *
 * This module configures an ADS8528 ADC to run in the 'parallel' mode with an external clk then
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
    input  wire         clk,
    input  wire         sresetn,
    input  wire         busy,          // Indicates a conversion is taking place on ADS8528 (Active-high)
    
    inout  wire      [15:0] data_adc,  // input/output databits from ADS8528

    // ADS8528 Control Signals
    output logic        read_n,        // Tells ADS8528 its data output has been read (Active-low)
    output logic        write_n,       // Tells ADS8528 a write operation taking place (Active-low)
    output logic        chipselect_n,  // Chip-select bit, must be deasserted for operation (Active-low)
    output logic        software_mode, // Controls whether ADS8528 is in software or hardware mode
    output logic        serial_mode,   // Controls whether ADS8528 is in serial or parallel mode
    output logic        standby_n,     // Powers entire device down when deasserted and in hardware mode

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


    typedef enum {
        WRITE_ON,
        WRITE_OFF,
        START_CONV,
        WAIT_BUSY,
        READ_ON,
        DATA_OUT
    } state_t;


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Signal Declarations


    // Driver FSM state register
    state_t state_ff;

    // Controls all 4 conv_start bits with one bit
    logic conv_start;

    // Controls number of transactions of reads/writes throughout ADC Driver FSM
    logic [3:0] num_transactions;

    // Raw data to drive to ADC databits
    logic [15:0] data_adc_out;


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Output Assignments


    assign data_adc = (!read_n || (write_n && chipselect_n)) ? 16'bz : data_adc_out;

    assign software_mode = 1'b1;
    assign serial_mode   = 1'b0;
    assign standby_n     = 1'b1;
    assign chipselect_n  = 1'b0;

    // All channel conversions are started simultaneously
    assign conv_start_a = conv_start;
    assign conv_start_b = conv_start;
    assign conv_start_c = conv_start;
    assign conv_start_d = conv_start;


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Logic Implementation


    // ADS8528 Driver State Machine Transition Control
    always_ff @(posedge clk) begin
        if (!sresetn) begin
            state_ff         <= WRITE_ON;
            num_transactions <= '0;
            data_out         <= 'X;
            data_valid       <= 1'b0;

        end else begin
            case (state_ff)
                // Drive write_n with databits with config register info
                WRITE_ON: begin
                    state_ff         <= WRITE_OFF;
                    num_transactions <= num_transactions + 1'b1;
                end

                // Deassert write_n to allow the config register to then latch the next set of bits
                WRITE_OFF: begin
                    if (num_transactions == 4'd2) begin
                        state_ff <= START_CONV;
                    end else begin
                        state_ff <= WRITE_ON;
                    end
                end

                // Initiate a conversion and wait for busy to be asserted
                START_CONV: begin
                    num_transactions <= '0;
                    if (busy) begin
                        state_ff     <= WAIT_BUSY;
                    end
                end

                // Wait for busy to be deasserted
                WAIT_BUSY: begin
                    if (~busy) begin
                        state_ff <= READ_ON;
                    end
                end

                // Read an ADC data sample
                READ_ON: begin
                    state_ff         <= DATA_OUT;
                    num_transactions <= num_transactions + 1'b1;
                    data_out         <= data_adc;
                    data_valid       <= 1'b1;
                end

                // Send the ADC sample to output register (no backpressure, must be read immediately)
                DATA_OUT: begin
                    data_out   <= 'X;
                    data_valid <= 1'b0;
                    if (num_transactions == 4'd8) begin
                        state_ff  <= START_CONV;
                    end else begin
                        state_ff  <= READ_ON;
                    end
                end

                default: begin
                    state_ff         <= WRITE_ON;
                    num_transactions <= '0;
                end
            endcase
        end
    end

    // ADS8528 Driver State Machine Output Control
    always_comb begin
        // Default deasserted combinational values
        conv_start   = 1'b0;
        write_n      = 1'b1;
        read_n       = 1'b1;
        data_adc_out = 'X;

        case (state_ff)
            // Assert write with LSB/MSB of config register
            WRITE_ON: begin
                write_n = 1'b0;
                if (num_transactions == '0) begin
                    data_adc_out = 16'h8054; // First config register

                end else begin 
                    data_adc_out = 16'h43FF; // Second config register
                end
            end

            // Assert conversion start bits
            START_CONV: begin
                conv_start = 1'b1;
            end

            // Assert read
            READ_ON: begin
                read_n = 1'b0;
            end
        endcase

        // Hold write deasserted during reset
        if (!sresetn) begin
            write_n = 1'b1;
        end
    end
endmodule

`default_nettype wire
