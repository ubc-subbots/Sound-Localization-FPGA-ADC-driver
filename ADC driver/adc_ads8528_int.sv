
/**



 */
interface ADS8528_Int #(
    parameter DATA_WIDTH = 16
) (
    input                  clk
);
    logic                  reset;
    logic [DATA_WIDTH-1:0] databits;        // Primary data-bus of the adc
    logic                  read_n;          // Tells ADS8528 its data output has been read (Active-low)
    logic                  write_n;         // Tells ADS8528 a write operation taking place (Active-low)
    logic                  chipselect_n;    // Chip-select bit, must be deasserted for operation (Active-low)
    logic                  hardware_mode_n; // Controls whether ADS8528 is in software or hardware mode
    logic                  parallel_mode_n; // Controls whether ADS8528 is in serial or parallel mode
    logic                  standby_n;       // Powers entire device down when deasserted and in hardware mode
    logic                  range_xclock;    // Analog voltage range (Hardware mode), external clock (Software mode)

    // Rising-edge indicates start of conversions
    logic                  conv_start_a;
    logic                  conv_start_b;
    logic                  conv_start_c;
    logic                  conv_start_d;

    logic                  busy;            // Indicates that a conversion is taking place

    modport Master (
        inout databits,

        output reset,
        output read_n,
        output write_n,
        output chipselect_n,
        output hardware_mode_n,
        output parallel_mode_n,
        output standby_n,
        output range_xclock,

        output conv_start_a,
        output conv_start_b,
        output conv_start_c,
        output conv_start_d,

        input busy
    );

    modport Slave (
        inout databits,

        input reset,
        input read_n,
        input write_n,
        input chipselect_n,
        input hardware_mode_n,
        input parallel_mode_n,
        input standby_n,
        input range_xclock,

        input conv_start_a,
        input conv_start_b,
        input conv_start_c,
        input conv_start_d,

        output busy
    );
endinterface