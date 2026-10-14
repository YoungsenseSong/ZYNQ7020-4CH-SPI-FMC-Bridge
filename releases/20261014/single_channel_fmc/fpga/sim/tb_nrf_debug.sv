`timescale 1ns/1ps
module tb_nrf_debug;
    reg clk=0, reset_n=0;
    always #10 clk=~clk;
    wire sclk,mosi,miso,cs_n,drdy,sync_out,nrf_reset_n,led;
    wire [15:0] ad;
    single_channel_product_top #(
        .DEBUG_AUTONOMOUS(1), .DEBUG_START_CYCLES(20),
        .SCLK_HZ(5000000), .AB_GAP_CYCLES(8), .CS_INACTIVE_CYCLES(15),
        .B_TO_NEXT_A_GAP_CYCLES(15), .STARTUP_DELAY_CYCLES(5),
        .RETRY_DELAY_CYCLES(9), .SYNC_WIDTH_CYCLES(10),
        .TARGET_PAYLOAD_BYTES(496), .MAX_PAYLOAD_BYTES(496),
        .BLOCK_TIMEOUT_CYCLES(1000000)
    ) dut(.pl_clk(clk),.ext_reset_n(reset_n),.nrf_sclk(sclk),.nrf_mosi(mosi),
        .nrf_miso(miso),.nrf_cs_n(cs_n),.nrf_drdy(drdy),.nrf_sync_out(sync_out),
        .nrf_reset_n(nrf_reset_n),.fmc_ad(ad),.fmc_nadv_n(1'b1),.fmc_ne1_n(1'b1),
        .fmc_noe_n(1'b1),.fmc_nwe_n(1'b1),.status_led(led));
    single_channel_spi_sensor_model sensor(.reset_n(nrf_reset_n),.enable(1'b1),
        .sclk(sclk),.mosi(mosi),.cs_n(cs_n),.miso(miso),.drdy(drdy));
    integer f, emitted=0;
    initial f=$fopen("evidence/model_records.bin","wb");
    always @(posedge clk) if (dut.controller_record_valid && dut.controller_record_ready) begin
        $fwrite(f,"%c",dut.controller_record_data);
        emitted=emitted+1;
    end
    initial begin
        repeat(8) @(negedge clk);
        reset_n=1;
        wait(dut.dbg_ack_count==2);
        repeat(20) @(negedge clk);
        if (!led || sensor.committed!=4 || dut.crc_ok_count!=4 ||
            dut.commit_ok_count!=4 || dut.stats_record_count!=4 || emitted!=992)
            $fatal(1,"accounting led=%b committed=%d crc=%d commit=%d stats=%d bytes=%d",
                led,sensor.committed,dut.crc_ok_count,dut.commit_ok_count,dut.stats_record_count,emitted);
        if (dut.crc_error_count || dut.commit_error_count || dut.timeout_count ||
            dut.envelope_error_count || dut.stats_malformed_count || dut.block_ready)
            $fatal(1,"errors or un-released block");
        $fclose(f);
        $display("MC009_NRF_DEBUG_RTL_OK records=4 bytes=992 acked_blocks=2 errors=0");
        $finish;
    end
    initial begin #200000000; $fatal(1,"watchdog"); end
endmodule
