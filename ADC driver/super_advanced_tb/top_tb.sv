`timescale 1ns/1ps

`include "ADC_bfm.sv"
`include "tester.sv"

module top_tb;

    ADC_bfm bfm();

    top DUT(
        .DB               ( bfm.DB     ),
        .Busy             ( bfm.Busy   ),
        .CLOCK_27M        ( bfm.clk    ),
        .rst              ( bfm.rst    ),
        .KEY2             (            ),
        .sclk             ( bfm.sclk   ),
        .SPI_cs           ( bfm.SPI_cs ),
        .transaction_done ( bfm.transaction_done ),
        .convst_A         ( bfm.convst_A         ),
        .convst_B         ( bfm.convst_B         ),
        .convst_C         ( bfm.convst_C         ),
        .convst_D         ( bfm.convst_D         ),
        .RD_N             ( bfm.RD_N             ),
        .ADC_CS_N         ( bfm.ADC_CS_N         ),
        .HW_N             ( bfm.HW_N             ),
        .PAR_N            ( bfm.PAR_N            ),
        .ADCrst           ( bfm.ADCrst           ),
        .STBY_N           ( bfm.STBY_N           ),
        .WR_N             ( bfm.WR_N             ),
        .XCLK             ( bfm.XCLK             ),
        .processed_MISO   ( bfm.processed_MISO   ),
        .SPI_RDY          ( bfm.SPI_RDY			 )
    );

    initial begin
        tester tester_h;
        tester_h = new(bfm);
        tester_h.execute(16'b0000_0001_0000_0000);
    end

endmodule : top_tb
