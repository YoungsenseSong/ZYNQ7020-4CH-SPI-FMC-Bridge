`timescale 1ns/1ps
module tb_dual_fmc;
    reg pl_clk=0, ext_reset_n=0;
    always #10 pl_clk=~pl_clk;
    wire [3:0] spi_drdy,spi_miso,spi_sclk,spi_mosi,spi_cs_n,spi_sync_out,nrf_reset_n;
    wire fmc_nwait_n,fpga_irq,status_led;
    wire [287:0] debug_probe;
    wire [15:0] fmc_ad;
    reg [15:0] drive=0;
    reg drive_enable=0;
    reg fmc_nadv_n=1,fmc_ne1_n=1,fmc_noe_n=1,fmc_nwe_n=1;
    assign fmc_ad=drive_enable?drive:16'hzzzz;
    assign spi_drdy[3:2]=0;
    assign spi_miso[3:2]=0;
    multichannel_product_top #(
        .ACTIVE_CHANNEL_MASK(4'b0011),.SCLK_HZ(5000000),
        .AB_GAP_CYCLES(8),.B_TO_NEXT_A_GAP_CYCLES(15),
        .FIFO_DEPTH(512),.FIFO_ADDR_WIDTH(9),.FIFO_HIGH_WATER(450),
        .TARGET_PAYLOAD_BYTES(992),.MAX_PAYLOAD_BYTES(1984),
        .BLOCK_BYTES(2048),.BLOCK_TIMEOUT_CYCLES(0)
    ) dut(.*);
    genvar channel;
    generate for(channel=0;channel<2;channel=channel+1) begin: sensors
        two_channel_spi_slave_model #(.CHANNEL(channel)) model(
            .reset_n(nrf_reset_n[channel]),.enable(1'b1),
            .sclk(spi_sclk[channel]),.mosi(spi_mosi[channel]),
            .cs_n(spi_cs_n[channel]),.miso(spi_miso[channel]),
            .drdy(spi_drdy[channel]),.committed(),.bad_peeks(),.flushes());
    end endgenerate
    task wr(input [15:0] address,input [15:0] data);
        begin
            @(negedge pl_clk);
            drive_enable=1;drive=16'h12ab;fmc_ne1_n=0;fmc_nadv_n=0;
            fmc_nwe_n=0;
            repeat(3) @(negedge pl_clk);drive=address>>1;
            repeat(5) @(negedge pl_clk);fmc_nadv_n=1;
            repeat(2) @(negedge pl_clk);drive=data;
            repeat(6) @(negedge pl_clk);fmc_nwe_n=1;fmc_ne1_n=1;drive_enable=0;
            repeat(5) @(negedge pl_clk);
        end
    endtask
    task rd(input [15:0] address,output [15:0] data);
        integer guard;
        begin
            @(negedge pl_clk);
            drive_enable=1;drive=address>>1;fmc_ne1_n=0;fmc_nadv_n=0;
            repeat(6) @(negedge pl_clk);fmc_nadv_n=1;drive_enable=0;fmc_noe_n=0;
            guard=0;
            while(fmc_nwait_n && guard<100) begin @(negedge pl_clk);guard=guard+1;end
            if(guard==100) $fatal(1,"NWAIT missing %h",address);
            while(!fmc_nwait_n && guard<200) begin @(negedge pl_clk);guard=guard+1;end
            if(guard==200) $fatal(1,"read timeout %h",address);
            repeat(2) @(negedge pl_clk);data=fmc_ad;
            fmc_noe_n=1;fmc_ne1_n=1;
            repeat(6) @(negedge pl_clk);
        end
    endtask
    reg [15:0] value;
    integer block,offset,file_handle;
    string output_dir;
    initial begin
        if(!$value$plusargs("OUT=%s",output_dir)) $fatal(1,"OUT required");
        repeat(8) @(negedge pl_clk);ext_reset_n=1;
        repeat(10) @(negedge pl_clk);
        rd(0,value);if(value!==16'h5343) $fatal(1,"ID %h",value);
        rd(4,value);if(value!==16'h0602) $fatal(1,"build %h",value);
        wr(16'h0030,16'h0103);
        rd(16'h0032,value);
        if(value[3:0]!==0 || !value[8]) $fatal(1,"ARM falsely reports physical lock %h",value);
        wr(16'h0022,16'ha55a);rd(16'h0022,value);
        if(value!==16'ha55a) $fatal(1,"write phase %h",value);
        wr(16'h0010,5);
        wait(status_led);
        for(block=0;block<2;block=block+1) begin
            wait(dut.block_ready);
            rd(16'h0042,value);if(value!==1056) $fatal(1,"length %d",value);
            rd(16'h0044,value);if(value!==block) $fatal(1,"ACK register not ready sequence");
            file_handle=$fopen($sformatf("%s/block%0d.bin",output_dir,block),"wb");
            for(offset=0;offset<1056;offset=offset+2) begin
                rd(16'h1000+offset,value);
                $fwrite(file_handle,"%c%c",value[7:0],value[15:8]);
            end
            $fclose(file_handle);
            wr(16'h0044,block);
        end
        repeat(200) @(negedge pl_clk);
        if(dut.delivered_count!=={32'd0,32'd0,32'd4,32'd4}) $fatal(1,"delivery %h",dut.delivered_count);
        if(dut.crc_error_count!=0 || dut.timeout_count!=0 || dut.commit_error_count!=0)
            $fatal(1,"transport errors");
        if(dut.block_ready || dut.fifo_levels!=0) $fatal(1,"not drained");
        if(spi_sclk[3:2]!=0 || spi_cs_n[3:2]!=3) $fatal(1,"disabled lane");
        $display("DUAL_FMC_OK blocks=2 records=8 lanes=0,1 CRC ACK ARM_NOT_LOCKED");
        $finish;
    end
    initial begin #200000000;$fatal(1,"dual FMC watchdog");end
endmodule
