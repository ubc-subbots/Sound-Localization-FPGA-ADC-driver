module driver_tb();

	// declare inputs and outputs to driver dut
	//inputs
	reg clk;
	reg sresetn;		//active low!
	reg busy;			//active high

	//in & out
	reg [15:0] data_adc;

	//outputs 
	reg read_n;			//active low
	reg write_n; 		//active low
	reg chipselect_n; 	// active low
	reg software_mode; 	//constant
	reg serial_mode;	//contant
	reg standby_n;		//constant

	reg conv_start_a;
	reg conv_start_b;
	reg conv_start_c;
	reg conv_start_d;

	reg [15:0] data_out
	reg data_valid;

	assign err = err_output;

	// tracking number of passed and failed tests
	integer num_passes = 0;
	integer num_fails = 0;

	//instantiating driver DUT
	driver DUT(.clk, .sresetn, .busy, .data_adc, .read_n,
				 .write_n, .chipselect_n, .software_mode,
				 .serial_mode, .standby_n, .conv_start_a,
				 .conv_start_b, .conv_start_c, .conv_start_d)

	// Clock with period of 10 ticks
	initial begin
		clk = 1'b1;
		forever #5 clk = ~clk;
	end

	// updates the number of tests that passes and fails
	// task to check data_adc 
	//when data_adc acts as an output
	task check_data_adc(input [15:0] exp_output, input string msg);
		assert(data_adc === exp_output) begin
			$display("[PASS] %s: data_adc is %b", msg, data_adc);
			num_passes = num_passes + 1;
		end else begin
			$error("[FAIL] %s: output is %b (expected %b)", msg, data_adc, exp_output);
			num_fails = num_fails + 1;
		end
	endtask

	// task to check read_n
	task check_read_n(input expected_read_n, input string msg);
		assert(read_n === expected_read_n) begin
			$display("[PASS] %s: read_n is %d", msg, read_n);
			num_passes = num_passes + 1;
		end else begin
			$error("[FAIL] %s: output is %d (expected %d)", msg, read_n, expected_read_n);
			num_fails = num_fails + 1;
		end
	endtask

	// task to check write_n
	task check_write_n(input expected_write_n, input string msg);
		assert(write_n === expected_write_n) begin
			$display("[PASS] %s: write_n is %d", msg, write_n);
			num_passes = num_passes + 1;
		end else begin
			$error("[FAIL] %s: output is %d (expected %d)", msg, write_n, expected_write_n);
			num_fails = num_fails + 1;
		end
	endtask

	// task to check chipselect_n
	task check_chipselect_n(input expected_chipselect_n, input string msg);
		assert(chipselect_n === expected_chipselect_n) begin
			$display("[PASS] %s: chipselect_n is %d", msg, chipselect_n);
			num_passes = num_passes + 1;
		end else begin
			$error("[FAIL] %s: output is %d (expected %d)", msg, chipselect_n, expected_chipselect_n);
			num_fails = num_fails + 1;
		end
	endtask

	// task to check conv_start_x
	//since all conv_x are equal just check conv a
	task check_conv_start_x(input expected_conv, input string msg);
		assert(conv_start_a === expected_conv) begin
			$display("[PASS] %s: conv_start_x is %d", msg, conv_start_a);
			num_passes = num_passes + 1;
		end else begin
			$error("[FAIL] %s: output is %d (expected %d)", msg, conv_start_a, expected_conv);
			num_fails = num_fails + 1;
		end
	endtask

	// task to check data_out 
	task check_data_out(input [15:0] exp_output, input string msg);
		assert(data_out === exp_output) begin
			$display("[PASS] %s: data_out is %b", msg, data_out);
			num_passes = num_passes + 1;
		end else begin
			$error("[FAIL] %s: output is %b (expected %b)", msg, data_out, exp_output);
			num_fails = num_fails + 1;
		end
	endtask

	task check_data_valid(input expected_d_valid, input string msg);
		assert(data_valid === expected_d_valid) begin
			$display("[PASS] %s: conv_start_x is %d", msg, conv_start_a);
			num_passes = num_passes + 1;
		end else begin
			$error("[FAIL] %s: output is %d (expected %d)", msg, data_valid, expected_d_valid);
			num_fails = num_fails + 1;
		end
	endtask

	task reset;

		reset_n = 1'b0;
		busy = 1'b1;
		
	endtask 


	//start testing
	initial begin

		reset;

		//offset input changes
		#7

		$display("\n\n==== Check outputs after reset ====");
			reset;
			#10 //wait for outputs to update
			check_chipselect_n(1'b1, "chipsel after reset")
			check_write_n(1'b1, "write after reset")
			check_conv_start_x(1'b0, "conv_x after reset")
			check_read_n(1'b1, "read after reset")
			check_data_valid(1'b0, "data valid after reset")

		$display("=========================\n\n");

		$display("\n\n==== Check  ====");
			reset;
			#10 //wait for chip sel to update
		$display("=========================\n\n");
			
	end
	
endmodule