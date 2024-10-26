/// # ADS8528 Memory Specification
///
/// ## Overview
///
/// This verilog code synethizes to 32 Kilo Bytes of RAM 
/// that stores the information collected by the
/// ADS8528 and sends it out in a FIFO style
///
/// ## IO Ports
/// clk: externally driven clk
/// rst: reset  
/// write: notifies the memory to prepare for write operation
/// read: notifies the memory to be read to output data
///
/// [DATA_WIDTH - 1:0] data_in : data input from the ADC
/// [DATA_WIDTH - 1:0] data_out: data output going towards the SPI for the raspberry PI
/// full: output to top level module to indicate the memory is full and cannot recieve anymore data
/// empty: output to top level module to indicate the memory is empty and cannot be read anymore
///
/// ## Parameters 
/// DEPTH: chosen to be 16384, as 16*16384 = 262144, i.e, just barely bigger then the memory needed
/// DATA_WIDTH: chosen to be 16, as ADC provides data in this format

  
module ADCmemory #(parameter DEPTH = 16384, DATA_WIDTH = 16) (
	input clk,
	input rst, //reset low
	input write,
	input read, 
	
	input [DATA_WIDTH - 1:0] data_in, //data to write to mem
   output logic [$clog2(DEPTH) - 1:0] count, //amount of data in mem
	output logic [DATA_WIDTH - 1:0] data_out, //data read from mem
	output full,
	output empty
);
	
	logic [DATA_WIDTH-1:0] storage [DEPTH]; //Memory
	logic [$clog2(DEPTH) - 1:0] write_ptr;	//Index in storage to write to 
	logic  [$clog2(DEPTH) - 1:0] read_ptr; //Index in storage to read from 

	assign full = (count == DEPTH); //Boolean, tells us if storage is full (indicated if there is space in memto write to)
	assign empty = (count == 0); //Boolean, tells us if storage is empty (indicates is the is info to read from mem)

	always_ff @(posedge clk) begin
		//reset
		 if (!rst) begin
			  write_ptr <= 0;
			  read_ptr <= 0;
			  count <= 0; 
		 end
		 //read from or write to mem
		 else begin
			  if (write & !full) begin  //write to mem if not full and write is 1
					storage[write_ptr] <= data_in;
					write_ptr <= write_ptr + 1;  //write_ptr over flows 
					count <= count + 1;
			  end
			  if (read & !empty) begin //read from mem if it is not empty and read is 1
					data_out <= storage[read_ptr];
					read_ptr <= read_ptr + 1;
					count <= count - 1;
			  end
		 end
	end
		

endmodule