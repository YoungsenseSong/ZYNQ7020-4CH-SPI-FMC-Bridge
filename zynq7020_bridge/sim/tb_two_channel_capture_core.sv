`timescale 1ns/1ps
module tb_two_channel_capture_core;
    reg clk=0, reset_n=0;
    always #10 clk=~clk;
    reg [1:0] enable=2'b01;
    wire [1:0] spi_drdy,spi_miso,spi_sclk,spi_mosi,spi_cs_n,sync_out;
    wire [7:0] record_data;
    wire record_channel,record_valid,record_last;
    reg record_ready=0;
    wire [11:0] debug_state;
    wire [63:0] crc_error_count,commit_ok_count,commit_error_count;
    wire [63:0] timeout_count,envelope_error_count,delivered_count;
    wire [31:0] commits0,commits1,bad0,bad1,flush0,flush1;
    integer received[0:1], position[0:1];
    integer locked_channel=-1, run_id=0, output_file, cycle=0;
    reg stalled=0;
    reg [9:0] held;
    reg allow_output=0;
    string output_path;
    // Faster digital transactions for regression; production defaults stay 1 MHz
    // and 5 ms re-arm gaps. This test cannot validate real SPIS timing.
    two_channel_capture_core #(
        .SCLK_HZ(5000000), .AB_GAP_CYCLES(8), .CS_INACTIVE_CYCLES(15),
        .B_TO_NEXT_A_GAP_CYCLES(15), .STARTUP_DELAY_CYCLES(5),
        .RETRY_DELAY_CYCLES(9), .SYNC_WIDTH_CYCLES(50)
    ) dut (.*);
    two_channel_spi_slave_model #(.CHANNEL(0)) slave0 (
        .reset_n(reset_n),.enable(enable[0]),.sclk(spi_sclk[0]),
        .mosi(spi_mosi[0]),.cs_n(spi_cs_n[0]),.miso(spi_miso[0]),
        .drdy(spi_drdy[0]),.committed(commits0),.bad_peeks(bad0),.flushes(flush0)
    );
    two_channel_spi_slave_model #(.CHANNEL(1),.CORRUPT_FIRST_PEEK(1)) slave1 (
        .reset_n(reset_n),.enable(enable[1]),.sclk(spi_sclk[1]),
        .mosi(spi_mosi[1]),.cs_n(spi_cs_n[1]),.miso(spi_miso[1]),
        .drdy(spi_drdy[1]),.committed(commits1),.bad_peeks(bad1),.flushes(flush1)
    );
    always @(negedge clk) begin
        cycle=cycle+1;
        record_ready=allow_output && ((cycle%7)!=0) && ((cycle%11)!=0);
    end
    always @(posedge clk) begin
        if(!reset_n) begin
            received[0]=0; received[1]=0; position[0]=0; position[1]=0;
            locked_channel=-1; stalled=0;
        end else begin
            if(stalled && (!record_valid || held !== {record_channel,record_last,record_data}))
                $fatal(1,"integrated output unstable under backpressure");
            stalled=record_valid&&!record_ready;
            held={record_channel,record_last,record_data};
            if(record_valid&&record_ready) begin
                if(received[record_channel]>=4) $fatal(1,"extra record");
                if(locked_channel<0) locked_channel=record_channel;
                if(locked_channel!=record_channel) $fatal(1,"integrated stream interleaving");
                if(record_channel==0) begin
                    if(record_data !== slave0.golden[received[0]*248+position[0]]) $fatal(1,"CH0 byte mismatch");
                end else begin
                    if(record_data !== slave1.golden[received[1]*248+position[1]]) $fatal(1,"CH1 byte mismatch");
                end
                if(record_last !== (position[record_channel]==247)) $fatal(1,"integrated last mismatch");
                $fdisplay(output_file,"%0d,%0d,%0d,%0d,%0d,%02x",run_id,cycle,record_channel,received[record_channel],position[record_channel],record_data);
                if(record_last) begin
                    received[record_channel]=received[record_channel]+1;
                    position[record_channel]=0; locked_channel=-1;
                end else position[record_channel]=position[record_channel]+1;
            end
        end
    end
    task restart(input integer new_run);
        begin
            @(negedge clk); reset_n=0;
            repeat(8) @(negedge clk);
            run_id=new_run; reset_n=1;
        end
    endtask
    task check_complete;
        begin
            wait(received[0]==4 && received[1]==4);
            repeat(100) @(negedge clk);
            if(delivered_count !== {32'd4,32'd4} || commit_ok_count !== {32'd4,32'd4}) $fatal(1,"commit/delivery accounting");
            if(commits0!=4 || commits1!=4 || crc_error_count !== {32'd1,32'd0}) $fatal(1,"CRC isolation");
            if(commit_error_count!=0 || timeout_count!=0 || envelope_error_count!=0) $fatal(1,"unexpected errors");
            if(bad1!=1 || flush1!=1) $fatal(1,"missing CRC recovery exercise");
            $display("MC_RUN_OK run=%0d delivered=4/4 CRC_rejected=0/1 seq_wrap=ffffffff_to_0",run_id);
        end
    endtask
    initial begin
        if(!$value$plusargs("MC_CAPTURE=%s",output_path)) $fatal(1,"MC_CAPTURE required");
        output_file=$fopen(output_path,"w");
        if(!output_file) $fatal(1,"capture file");
        $fdisplay(output_file,"run,cycle,channel,record,offset,data");
        restart(0); allow_output=1;
        // CH0 can finish two complete records while CH1 has no data.
        wait(received[0]>=2);
        if(received[1]!=0) $fatal(1,"disabled CH1 delivered");
        @(negedge clk); enable=3;
        check_complete();
        // Both controllers may commit into local buffers while the sink stalls.
        // Global reset intentionally discards that run: do not call it lossless.
        allow_output=0; restart(1);
        wait(commit_ok_count=={32'd1,32'd1});
        repeat(250) @(negedge clk);
        if(delivered_count!=0 || !record_valid) $fatal(1,"backpressure bypass");
        restart(2);
        repeat(20) @(negedge clk);
        if(record_valid || delivered_count!=0) $fatal(1,"old run leaked after reset");
        allow_output=1;
        check_complete();
        $fclose(output_file);
        $display("TB_TWO_CHANNEL_CAPTURE_CORE_OK bytes=3968 absent_peer crc_retry backpressure global_reset");
        $finish;
    end
    initial begin #100000000; $fatal(1,"integration watchdog state=%h counts=%h",debug_state,delivered_count); end
endmodule
