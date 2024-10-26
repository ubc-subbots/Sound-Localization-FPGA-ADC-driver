/*
* SPI Controller Specification
*
* SPI controller for interfacing a Raspberry Pi (master) with FPGA-ADC module (slave).
*
* This synthizes into a SPI module capable of sending 16 bits of data to an external module once 
* the chip select signal is lowered by the master. 
*
*
*
*
*/




module spi (
/* IO Ports */

//1. Reset, 2. Serial clock from Raspberry Pi, 3. Chip select signal, switched low for any operation
	input logic rst,
	input logic sclk,
	input logic cs, //TODO: This signal is active low, change across ALL code
	
//2-byte input data from FPGA-ADC system to be serialized & sent to Raspberry Pi
	input logic [15:0] unprocessed_MISO, 

//1. Serialized output data to be sent to Raspberry Pi, 2. Ready flag for FPGA-ADC system, indicates it is ready for new operation
	output logic processed_MISO,
	output logic ready_for_data //TODO: Active low, check if top-level module even checks this

);

/* Wires */ 
	logic [3:0] MISO_counter; 
	logic notfinished;
	
/* Controller States */
	typedef enum {
		INIT, 
		SPI 
	} state_t;

	state_t state = INIT;

/* State Machine */
	always_ff@(posedge sclk or posedge cs) begin 

		//Wait for cs to be asserted 
		if(cs) begin

			MISO_counter <= 4'b1110;
			processed_MISO <= unprocessed_MISO[4'b1111];
			ready_for_data <= 1'b0;
			state <= INIT;

		end
		
		else begin
			//Synchronous reset
			if(~rst) begin

				state <= INIT;

			end else begin

				case(state)

					INIT: begin

						MISO_counter <= 4'b1110;
						processed_MISO <= unprocessed_MISO[4'b1111];
						ready_for_data <= 1'b0;
						state <= SPI; 

					end

					SPI: begin

						if(MISO_counter != 4'b0000) begin

							processed_MISO <= unprocessed_MISO[MISO_counter];
							MISO_counter <= MISO_counter - 1;
							ready_for_data <= 1'b0;
							notfinished <= 1'b1;

						end else if(notfinished) begin

							processed_MISO <= unprocessed_MISO[0];
							notfinished <= 1'b0;
							ready_for_data <= 1'b1;

						end else begin

							processed_MISO <= 1'bz;
							ready_for_data <= 1'b1;

						end

					end

				endcase
					
			end
		
		end
		
	end
		
	
endmodule

