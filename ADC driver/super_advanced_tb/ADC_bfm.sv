`timescale 1ns/1ps

interface ADC_bfm; 
	wire [15:0] DB;
	
	reg Busy;
	reg clk; //called CLOCK_27 in the actual module 
	reg rst;
	reg KEY2; 
	
	reg sclk;
	reg SPI_cs; 
	reg transaction_done; 
	
	wire convst_A;
	wire convst_B;
	wire convst_C;
	wire convst_D;
	wire RD_N;
	wire ADC_CS_N; 
	wire HW_N; 
	wire PAR_N; 
	wire ADCrst; 
	wire STBY_N; 
	wire WR_N; 
	wire XCLK; 
	
	wire processed_MISO; 
	wire SPI_RDY; 
	
	reg [15:0] DBin;
	
	assign DB = (WR_N) ? DBin : 16'bz;

	initial begin
		clk = 1'b0; 
		forever begin
			#10;
			clk = ~clk; 
		end
	end
	
	
	task reset_FPGA(); 
		rst = 1'b0; 
		@(negedge clk); 
		@(negedge clk); 
		rst = 1'b1; 
	endtask : reset_FPGA 
	
	task sim_ADC_output(input shortint A0, input shortint A1, input shortint B0, input shortint B1, input shortint C0, input shortint C1, input shortint D0, input shortint D1);
		@(posedge convst_A or posedge convst_B or posedge convst_C or posedge convst_D); 
		Busy = 1'b1; 
		for(int i=0; i < 17; i=i+1) 
			@(posedge clk); 
		Busy = 1'b0; 
		@(negedge RD_N); 
		DBin = A0;
		$display("memout is %d", DUT.adc_ads8528_ctrl_inst.data_out); 
		@(negedge RD_N);
		DBin = A1;
		$display("memout is %d", DUT.adc_ads8528_ctrl_inst.data_out); 
		@(negedge RD_N);
		DBin = B0;
		$display("memout is %d", DUT.adc_ads8528_ctrl_inst.data_out); 
		@(negedge RD_N); 
		DBin = B1; 
		$display("memout is %d", DUT.adc_ads8528_ctrl_inst.data_out); 
		@(negedge RD_N); 
		DBin = C0;
		$display("memout is %d", DUT.adc_ads8528_ctrl_inst.data_out); 
		/*@(negedge RD_N); 
		DBin = C1; 
		@(negedge RD_N); 
		DBin = D0;
		@(negedge RD_N);
		DBin = D1;*/
		
	endtask: sim_ADC_output
	
	task sim_SPI();
			SPI_cs = 1'b0;
			#50;
			SPI_cs = 1'b1;
			transaction_done = 1'b0;
			@(posedge SPI_RDY);
		forever begin
			#10; 
			SPI_cs = 1'b0;
			transaction_done = 1'b0;
			sclk = 1'b0;
			for(int i = 0; i < 32; i=i+1) begin
				#20;
				sclk = ~sclk;
			end
			SPI_cs = 1'b1;
			transaction_done = 1'b1;
			@(posedge SPI_RDY); 
		end
	endtask: sim_SPI
	
	
endinterface : ADC_bfm
		
	
	
	