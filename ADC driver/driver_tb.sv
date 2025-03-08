`timescale 1ns/1ns

module driver_tb();

    parameter bit VERBOSE      = 0;
	parameter int NUM_TESTS    = 100;
    parameter int CLOCK_PERIOD = 20;  // Definite minimum clock period


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Constants and Type Declarations


	localparam int        MIN_CONV_DELAY     = 133;    // Minimum time delay for a conversion to complete
	localparam int        MAX_CONV_DELAY     = 200;  // Maximum time delay for a conversion to complete
    localparam int        CONV_TO_BUSY_DELAY = 25;   // Time delay from conv_start assertion to busy assertion by ADC
    localparam int        READN_DATA_DELAY   = 15;   // Time delay from read_n assertion to data becoming valid
	localparam int        DATA_HOLD_DELAY    = 5;	 // Time delay to output being undefined after read_n goes high
	localparam int        DATA_TRI_DELAY     = 15;   // Time delay to output tri-state after chip_select_n goes high
	localparam int        DATA_HOLD_WRITE    = 5;    // Time delay required to hold data valid after rising edge of write_n

	localparam bit [31:0] CONFIG_REGISTER    = 32'h805443FF;


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Signal Declarations


    // Inputs
    logic clk;
    logic sresetn;         //active low
    logic busy;            //active high

    // in & out
	logic [15:0] data_adc_drive;
	wire  [15:0] data_adc;

    // Outputs 
    logic read_n;          // active low
    logic write_n;         // active low
    logic chipselect_n;    // active low
    logic software_mode;   // constant
    logic serial_mode;     // contant
    logic standby_n;       // constant

    logic conv_start_a;
    logic conv_start_b;
    logic conv_start_c;
    logic conv_start_d;

    logic [15:0] data_out;
    logic 		 data_valid;

    // Test signals
    logic [15:0] adc_data_queue [$];
    logic [15:0] received_data_queue [$];
    logic [15:0] golden_data_queue [$];
    logic [15:0] test_data;

	logic [31:0] config_register;

	logic [15:0] A, B;

	bit error;


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: DUT Instantiation


    driver DUT(
        .clk           ( clk           ),
        .sresetn       ( sresetn       ),
        .busy          ( busy          ),
        .data_adc      ( data_adc      ),
        .read_n        ( read_n        ),
            
        .write_n       ( write_n       ),
        .chipselect_n  ( chipselect_n  ),
        .software_mode ( software_mode ),
        
        .serial_mode   ( serial_mode   ),
        .standby_n     ( standby_n     ),
        .conv_start_a  ( conv_start_a  ),
        .conv_start_b  ( conv_start_b  ),
        .conv_start_c  ( conv_start_c  ),
        .conv_start_d  ( conv_start_d  ),

		.data_out      ( data_out      ),
		.data_valid    ( data_valid    )
    );


    ////////////////////////////////////////////////////////////////////////////////////////////////
    // SECTION: Test Implementation


	// Implement tri-state behavior
	assign data_adc = (!read_n || (write_n && chipselect_n)) ? data_adc_drive : 'z;

    // Clock with period of 20ns
    initial begin
        clk = 1'b1;
        forever #(CLOCK_PERIOD/2) clk = ~clk;
    end

	// Conversion Start Procedure
    initial forever begin
		@(posedge conv_start_a) begin
			// Assert BUSY signal after delay
			#CONV_TO_BUSY_DELAY;
			busy = 1'b1;

			// Fill queue with randomized data
			repeat (8) begin
				test_data = $urandom();
				golden_data_queue.push_back(test_data);
				adc_data_queue.push_back(test_data);

				if (VERBOSE) begin
					$display("Pushing test: %h", test_data);
				end
			end

			// Random conversion time delay
			#(($urandom() % MAX_CONV_DELAY) + MIN_CONV_DELAY);

			// Deassert BUSY signal
			busy = 1'b0;
		end
		#1;
	end

	// Load First Data Procedure
	initial forever begin
		@(negedge busy);
		#READN_DATA_DELAY;
		data_adc_drive = adc_data_queue.pop_front();
	end

	// Read Procedure
    initial forever begin
		@(posedge clk);
		if (~read_n && ~chipselect_n) begin
			// Fill databits with valid data after delay
			#READN_DATA_DELAY;
			data_adc_drive = adc_data_queue.pop_front();
		end
    end

	// Write Procedure
	initial forever begin
		if (~write_n && ~chipselect_n) begin
			// After hold time, latch config registers
			@(posedge write_n);
			#DATA_HOLD_WRITE;
			config_register[31:16] = data_adc;

			@(negedge write_n);

			@(posedge write_n);
			#DATA_HOLD_WRITE;
			config_register[15:0] = data_adc;
		end
		#1;
	end

    always_ff @(posedge clk) begin
        if (data_valid) begin
			received_data_queue.push_back(data_out);

			if (VERBOSE) begin
				$display("Time: %t, Receiving data: %h", $time(), data_out);
			end
        end
    end

    initial begin
		error = 1'b0;
		data_adc_drive = 'z;
		sresetn = 1'b1;
		@(posedge clk);

		sresetn = 1'b0;
		@(posedge clk);

		sresetn = 1'b1;
		@(posedge clk);

		repeat (NUM_TESTS) begin
			repeat(8) begin
				@(negedge data_valid);
				#1;
				A = golden_data_queue.pop_front();
				B = received_data_queue.pop_front();
				assert(A == B)
    				else begin
						$error("Received Data is Incorrect! %d != %d", A, B);
						error = 1'b1;
					end
			end
		end

		$display("|||||||||||||||||||||||||||||||||||||||||||||||||");
		if (~error) begin
			$display("SUCCESS! ALL TESTS PASSED!");
		end else begin
			$display("ERROR! TEST FAILED!");
		end
		$display("|||||||||||||||||||||||||||||||||||||||||||||||||");

		$stop();
    end

endmodule
