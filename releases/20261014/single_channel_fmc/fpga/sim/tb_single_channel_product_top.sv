`timescale 1ns/1ps
module tb_single_channel_product_top;
    reg pl_clk=0, ext_reset_n=0; always #10 pl_clk=~pl_clk;
    wire nrf_sclk,nrf_mosi,nrf_cs_n,nrf_reset_n,nrf_sync_out,nrf_drdy,nrf_miso;
    wire fmc_nwait_n, fpga_irq, status_led;
    wire [15:0] fmc_ad; reg [15:0] ad_drive; reg ad_oe;
    reg fmc_nadv_n=1, fmc_ne1_n=1, fmc_noe_n=1, fmc_nwe_n=1;
    assign fmc_ad = ad_oe ? ad_drive : 16'hzzzz;

    single_channel_product_top #(
        .SCLK_HZ(5000000), .AB_GAP_CYCLES(8), .CS_INACTIVE_CYCLES(15),
        .B_TO_NEXT_A_GAP_CYCLES(15), .STARTUP_DELAY_CYCLES(5),
        .RETRY_DELAY_CYCLES(9), .SYNC_WIDTH_CYCLES(10),
        .FIFO_DEPTH(256), .FIFO_ADDR_WIDTH(8), .FIFO_HIGH_WATER(224),
        .TARGET_PAYLOAD_BYTES(496), .MAX_PAYLOAD_BYTES(496),
        .BLOCK_TIMEOUT_CYCLES(1000000)
    ) dut(.pl_clk(pl_clk),.ext_reset_n(ext_reset_n),.nrf_sclk(nrf_sclk),
        .nrf_mosi(nrf_mosi),.nrf_miso(nrf_miso),.nrf_cs_n(nrf_cs_n),
        .nrf_drdy(nrf_drdy),.nrf_reset_n(nrf_reset_n),.nrf_sync_out(nrf_sync_out),
        .fmc_ad(fmc_ad),.fmc_nadv_n(fmc_nadv_n),.fmc_ne1_n(fmc_ne1_n),
        .fmc_noe_n(fmc_noe_n),.fmc_nwe_n(fmc_nwe_n),.fmc_nwait_n(fmc_nwait_n),
        .fpga_irq(fpga_irq),.status_led(status_led));
    single_channel_spi_sensor_model sensor(.reset_n(nrf_reset_n),.enable(1'b1),
        .sclk(nrf_sclk),.mosi(nrf_mosi),.cs_n(nrf_cs_n),.miso(nrf_miso),
        .drdy(nrf_drdy));

    task automatic fmc_write(input [15:0] byte_addr, input [15:0] value);
        reg [15:0] word_addr;
        begin
            word_addr=byte_addr>>1;
            @(negedge pl_clk); ad_oe=1; ad_drive=word_addr; fmc_ne1_n=0; fmc_nadv_n=0;
            repeat(4) @(negedge pl_clk); fmc_nadv_n=1; ad_drive=value; fmc_nwe_n=0;
            repeat(4) @(negedge pl_clk); fmc_nwe_n=1; fmc_ne1_n=1; ad_oe=0;
            repeat(4) @(negedge pl_clk);
        end
    endtask
    task automatic fmc_read(input [15:0] byte_addr, output [15:0] value);
        reg [15:0] word_addr; integer guard;
        begin
            word_addr=byte_addr>>1;
            @(negedge pl_clk); ad_oe=1; ad_drive=word_addr; fmc_ne1_n=0; fmc_nadv_n=0;
            repeat(4) @(negedge pl_clk); fmc_nadv_n=1; ad_oe=0; fmc_noe_n=0;
            guard=0; while(fmc_nwait_n && guard<100) begin @(negedge pl_clk); guard=guard+1; end
            if(guard>=100) $fatal(1,"FMC read did not assert NWAIT addr=%h",byte_addr);
            while(!fmc_nwait_n && guard<200) begin @(negedge pl_clk); guard=guard+1; end
            if(guard>=200) $fatal(1,"FMC read timeout addr=%h",byte_addr);
            repeat(2) @(negedge pl_clk); value=fmc_ad;
            fmc_noe_n=1; fmc_ne1_n=1; repeat(4) @(negedge pl_clk);
        end
    endtask

    reg [15:0] value; integer guard, offset, dump_file;
    string dump_path;
    initial begin
        ad_oe=0; ad_drive=0;
        repeat(8) @(negedge pl_clk); ext_reset_n=1;
        repeat(8) @(negedge pl_clk); // allow reset_clock_mgr to release PL reset
        fmc_read(16'h0000,value);
        if(value!==16'h5343) $fatal(1,"FPGA_ID mismatch %h",value);
        fmc_write(16'h0010,16'h0005); // enable + start
        guard=0; while(!status_led && guard<100) begin @(negedge pl_clk); guard=guard+1; end
        if(!status_led) $fatal(1,"stream did not start");
        wait(dut.block_ready);
        fmc_read(16'h0040,value);
        if(!value[0]) $fatal(1,"block not reported ready %h",value);
        fmc_read(16'h0042,value);
        if(value!==16'd560) $fatal(1,"unexpected single-channel block length %0d",value);
        fmc_read(16'h0080,value);
        if(!value[8] || !value[7:0]) $fatal(1,"signal stats missing %h",value);
        if(!$value$plusargs("MC_FMC_DUMP=%s",dump_path)) $fatal(1,"MC_FMC_DUMP required");
        dump_file=$fopen(dump_path,"wb");
        if(!dump_file) $fatal(1,"cannot open FMC dump");
        for(offset=0; offset<560; offset=offset+2) begin
            fmc_read(16'h1000+offset,value);
            $fwrite(dump_file,"%c%c",value[7:0],value[15:8]);
        end
        $fclose(dump_file);
        fmc_write(16'h0044,16'h0000);
        repeat(4) @(negedge pl_clk);
        if(dut.block_ready) $fatal(1,"block ACK did not release bank");
        if(sensor.committed!=2 || dut.stats_record_count!=2)
            $fatal(1,"record accounting commits=%0d stats=%0d",sensor.committed,dut.stats_record_count);
        $display("TB_SINGLE_CHANNEL_PRODUCT_TOP_OK FMC_ID=5343 block_bytes=560 records=2 stats=2 ACK=release");
        $finish;
    end
    initial begin #200000000; $fatal(1,"watchdog status=%b block=%b",status_led,dut.block_ready); end
endmodule
