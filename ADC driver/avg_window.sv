`timescale 1ns/1ps
`default_nettype none

/**
 * Average Value Shift Register module
 *
 * This module accepts a stream input that is piped into N shift registers. The output is the
 * average of all values contained in the shift registers.
 *
 * Note: N must be a power of two for this module to calculate the average value correctly.
 *          Module will probably work best with N = 4 or 8 due to NO pipelining in addition stages
 */
module avg_window #(
	parameter int N          = 8, // Number of shift registers to average
    parameter int DATA_WIDTH = 16 // Input/output data bitwidth
) (
    input  wire logic                  clk,
    input  wire logic                  sresetn,
    input  wire logic [DATA_WIDTH-1:0] data_in,
    input  wire logic                  data_valid,
    output logic [DATA_WIDTH-1:0] average,
    output logic                  average_valid
);


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Types and Constants Declarations


    localparam DIVISION_SHIFT = $clog2(N);


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Signal Declarations


    logic [DATA_WIDTH-1:0] shift_register [N-1:0];
    logic [N-1:0]          valid_shift_register;


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Output Assignments


    assign average_valid = valid_shift_register[N-1];


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Logic Implementation


    // Shift Register Control Logic
    always_ff @(posedge clk or negedge sresetn) begin
        // Asynchronous Active-Low Reset
        if (!sresetn) begin
            // Set all registers to zero on reset
            shift_register       <= '{default: '0};
            valid_shift_register <= '0;
        end else begin
            // Shift register logic, no backpressure, advance all registers on valid input
            if (data_valid) begin
                shift_register[0]       <= data_in;
                valid_shift_register[0] <= data_valid;

                for (int i = 1; i < N; i++) begin
                    shift_register[i]       <= shift_register[i-1];
                    valid_shift_register[i] <= valid_shift_register[i-1];
                end
            end
        end
    end

    // Averaging Combinational Logic
    always_comb begin
        average = '0;
        for (int i = 0; i < N; i++) begin
            average += shift_register[i] >>> DIVISION_SHIFT;
        end
    end
endmodule

`default_nettype wire
