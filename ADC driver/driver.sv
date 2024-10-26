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


    typedef enum {
        HOLD,
        INIT,
        BUSY,
        MEM
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
                if (conv_start || state_ff == BUSY || state_ff == MEM) begin
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
                    data_adc_out <= 16'h8054; // First config register

                end else begin 
                    data_adc_out <= 16'h03FF; // Second config register
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!sresetn) begin
            state_ff         <= HOLD;
            selected_channel <= 3'b000;
            conv_start       <= 1'b0;
            read_n           <= 1'b1;
            data_valid       <= 1'b0;

        end else begin
            case(state_ff)
                // Waiting while initial writes to ADC are completed
                HOLD: begin
                    if (finished_write) begin
                        state_ff <= INIT;
                    end else begin
                        state_ff <= HOLD;
                    end
                end

                // Initiates conversions
                INIT: begin
                    // Transitioning when busy goes high ensures that the conversion has actually
                    // begun before going to BUSY state.
                    if (conv_start) begin
                        state_ff <= BUSY;
                    end else begin
                        state_ff <= INIT;
                    end
                end

                // Waits for busy to go low and then sets read_n low
                BUSY: begin
                    if (selected_channel == 3'd6) begin
                        state_ff <= INIT;
                    end else if (busy) begin
                        state_ff <= BUSY;
                    end else begin
                        state_ff <= MEM;
                    end
                end

                // Handshake ADC data_out
                MEM: begin
                    state_ff <= BUSY;
                    end

                default: state_ff <= INIT;
            endcase

            // TODO: This case statement should be integrated with above, with register changes on
            //             state transitions.
            case(state_ff)
                HOLD: begin
                    data_valid <= 1'b0;
                    read_n     <= 1'b1;
                    conv_start <= 1'b0;
                end

                INIT: begin
                    data_valid <= 1'b0;
                    read_n     <= 1'b1;
                    conv_start <= 1'b1;

                    selected_channel <= 3'b000;
                end

                BUSY: begin
                    data_valid   <= 1'b0;
                    read_n       <= busy || selected_channel == 3'd6;
                    conv_start   <= 1'b0;
                    data_out_reg <= data_adc;
                end

                MEM: begin
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
