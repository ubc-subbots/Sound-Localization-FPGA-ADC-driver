class tester;

    virtual ADC_bfm bfm; 

    function new (virtual ADC_bfm b);
        bfm = b;
    endfunction : new

    protected function shortint get_ADC_junk_data();
        bit [3:0] zero_ones;
        zero_ones = $random;
        if(zero_ones == 4'b1111)
            return $random; //simulating noise
        else 
            return 16'd0;  //empty junk data
    endfunction : get_ADC_junk_data

    protected function shortint get_ADC_valid_data(shortint valid_voltage);
        return $urandom_range(valid_voltage, 16'h07FF);
    endfunction : get_ADC_valid_data

    task execute(shortint valid_voltage);
        shortint A0;
        shortint A1;
        shortint B0;
        shortint B1;
        shortint C0;
        shortint C1;
        shortint D0;
        shortint D1;

        bfm.reset_FPGA();
            fork
                begin
                    repeat(20) begin : junk_data_loop
                        A0 = get_ADC_junk_data();
                        A1 = get_ADC_junk_data();
                        B0 = get_ADC_junk_data();
                        B1 = get_ADC_junk_data();
                        C0 = get_ADC_junk_data();
                        C1 = get_ADC_junk_data();
                        D0 = get_ADC_junk_data();
                        D1 = get_ADC_junk_data();
                        bfm.sim_ADC_output(A0,A1,B0,B1,C0,C1,D0,D1);
                    end : junk_data_loop

                    repeat(20) begin : valid_data_loop
                        A0 = get_ADC_valid_data(valid_voltage);
                        A1 = get_ADC_valid_data(valid_voltage);
                        B0 = get_ADC_valid_data(valid_voltage);
                        B1 = get_ADC_valid_data(valid_voltage);
                        C0 = get_ADC_valid_data(valid_voltage);
                        C1 = get_ADC_valid_data(valid_voltage);
                        D0 = get_ADC_valid_data(valid_voltage);
                        D1 = get_ADC_valid_data(valid_voltage);
                        bfm.sim_ADC_output(A0,A1,B0,B1,C0,C1,D0,D1);
                    end : valid_data_loop

                end

                begin
                    bfm.sim_SPI();
                end
            join
        $stop;
    endtask : execute

endclass: tester
