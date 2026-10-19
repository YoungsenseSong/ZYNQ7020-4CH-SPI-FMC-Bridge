`timescale 1ns/1ps
module tb_four_channel_bridge_core;
    reg clk=0,reset_n=0;always #10 clk=~clk;
    wire [3:0] spi_drdy,spi_miso,spi_sclk,spi_mosi,spi_cs_n,sync_out;
    reg flush=0,host_read_request=0,host_read_bank=0;
    reg [14:0] host_read_word_address=0;
    wire host_read_valid;wire [15:0] host_read_data;
    reg host_claim_valid=0,host_claim_bank=0,host_ack_valid=0;
    reg [15:0] host_ack_value=0;
    wire block_ready,block_ready_bank;wire [15:0] block_ready_length;wire [31:0] block_ready_sequence;
    wire [2:0] owner_bank0,owner_bank1;
    wire [23:0] debug_state;
    wire [127:0] crc_error_count,commit_ok_count,commit_error_count,timeout_count,envelope_error_count,delivered_count;
    wire [63:0] fifo_levels;wire [3:0] fifo_almost_full;wire [127:0] fifo_blocked_cycles;wire degraded;
    wire [127:0] commits,bad,flushes;
    integer file_handle,b,w,block_length;reg bank;reg [31:0] seq_value;
    string path;
    four_channel_bridge_core #(.SCLK_HZ(5000000),.AB_GAP_CYCLES(8),.CS_INACTIVE_CYCLES(15),
        .B_TO_NEXT_A_GAP_CYCLES(15),.STARTUP_DELAY_CYCLES(5),.RETRY_DELAY_CYCLES(9),
        .FIFO_DEPTH(512),.FIFO_ADDR_WIDTH(9),.FIFO_HIGH_WATER(450),
        .BLOCK_BYTES(2048),.TARGET_PAYLOAD_BYTES(992),.MAX_PAYLOAD_BYTES(1984),.BLOCK_TIMEOUT_CYCLES(0)) dut(.*);
    genvar ch;
    generate for(ch=0;ch<4;ch=ch+1) begin: slaves
        two_channel_spi_slave_model #(.CHANNEL(ch),.CORRUPT_FIRST_PEEK(ch==1 || ch==3)) model(
            .reset_n(reset_n),.enable(1'b1),.sclk(spi_sclk[ch]),.mosi(spi_mosi[ch]),
            .cs_n(spi_cs_n[ch]),.miso(spi_miso[ch]),.drdy(spi_drdy[ch]),
            .committed(commits[ch*32+:32]),.bad_peeks(bad[ch*32+:32]),.flushes(flushes[ch*32+:32]));
    end endgenerate
    task acknowledge(input [15:0] value);
        begin @(negedge clk);host_ack_value=value;host_ack_valid=1;@(negedge clk);host_ack_valid=0;end
    endtask
    initial begin
        if(!$value$plusargs("MC_BLOCK_CAPTURE=%s",path)) $fatal(1,"missing capture path");
        file_handle=$fopen(path,"w");$fdisplay(file_handle,"block,offset,data");
        repeat(8) @(negedge clk);reset_n=1;
        // Stall the host until both banks seal. Allocation must not steal a bank.
        wait(owner_bank0==2 && owner_bank1==2);repeat(200) @(negedge clk);
        for(b=0;b<4;b=b+1) begin
            wait(block_ready);@(negedge clk);
            bank=block_ready_bank;seq_value=block_ready_sequence;block_length=block_ready_length;
            if(seq_value!=b || block_length!=1056) $fatal(1,"block ordering/length %0d %0d",seq_value,block_length);
            acknowledge(seq_value[15:0]);
            if((bank?owner_bank1:owner_bank0)!=2) $fatal(1,"unclaimed ACK released bank");
            @(negedge clk);host_claim_bank=bank;host_claim_valid=1;
            @(negedge clk);host_claim_valid=0;
            acknowledge(seq_value[15:0]+1);
            if((bank?owner_bank1:owner_bank0)!=3) $fatal(1,"wrong ACK released bank");
            for(w=0;w<block_length/2;w=w+1) begin
                @(negedge clk);host_read_request=1;host_read_bank=bank;host_read_word_address=w;
                @(posedge clk);#1;if(!host_read_valid) $fatal(1,"missing read response");
                $fdisplay(file_handle,"%0d,%0d,%02x",b,w*2,host_read_data[7:0]);
                $fdisplay(file_handle,"%0d,%0d,%02x",b,w*2+1,host_read_data[15:8]);
                @(negedge clk);host_read_request=0;
            end
            acknowledge(seq_value[15:0]);
            if((bank?owner_bank1:owner_bank0)==3) $fatal(1,"matching ACK did not release bank");
        end
        repeat(200) @(negedge clk);
        if(delivered_count!=={32'd4,32'd4,32'd4,32'd4} || commit_ok_count!==delivered_count || commits!==delivered_count) $fatal(1,"lost/extra records");
        if(crc_error_count!=={32'd1,32'd0,32'd1,32'd0} || !degraded) $fatal(1,"quality counters");
        if(block_ready || fifo_levels!=0 || commit_error_count!=0 || timeout_count!=0 || envelope_error_count!=0) $fatal(1,"not drained");
        $fclose(file_handle);
        $display("TB_FOUR_CHANNEL_BRIDGE_CORE_OK blocks=4 records=16 claim ACK wrong_ACK dual_bank host_read");$finish;
    end
    initial begin #200000000;$fatal(1,"bridge watchdog owners=%d/%d delivered=%h",owner_bank0,owner_bank1,delivered_count);end
endmodule
