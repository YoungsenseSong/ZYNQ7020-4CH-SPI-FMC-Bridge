`timescale 1ns/1ps
module tb_four_channel_capture_core;
    reg clk=0,reset_n=0; always #10 clk=~clk;
    reg [3:0] enable=1;
    wire [3:0] spi_drdy,spi_miso,spi_sclk,spi_mosi,spi_cs_n,sync_out;
    wire [7:0] record_data;wire [1:0] record_channel;
    wire record_valid,record_last; reg record_ready=0,allow_output=0;
    wire [23:0] debug_state;
    wire [127:0] crc_error_count,commit_ok_count,commit_error_count,timeout_count,envelope_error_count,delivered_count;
    wire [63:0] fifo_levels;wire [3:0] fifo_almost_full;wire [127:0] fifo_blocked_cycles;
    wire [127:0] commits,bad,flushes;
    reg [7:0] expected[0:3967];
    integer received[0:3],position[0:3];
    integer current=-1,run_id=0,output_file,cycle=0,f,n,k;
    reg stalled=0;reg [10:0] held;
    string output_path,golden_dir;
    four_channel_capture_core #(.SCLK_HZ(5000000),.AB_GAP_CYCLES(8),.CS_INACTIVE_CYCLES(15),
        .B_TO_NEXT_A_GAP_CYCLES(15),.STARTUP_DELAY_CYCLES(5),.RETRY_DELAY_CYCLES(9),
        .FIFO_DEPTH(256),.FIFO_ADDR_WIDTH(8),.FIFO_HIGH_WATER(220)) dut(.*);
    genvar ch;
    generate for(ch=0;ch<4;ch=ch+1) begin: slaves
        two_channel_spi_slave_model #(.CHANNEL(ch),.CORRUPT_FIRST_PEEK(ch==1 || ch==3)) model(
            .reset_n(reset_n),.enable(enable[ch]),.sclk(spi_sclk[ch]),.mosi(spi_mosi[ch]),
            .cs_n(spi_cs_n[ch]),.miso(spi_miso[ch]),.drdy(spi_drdy[ch]),
            .committed(commits[ch*32+:32]),.bad_peeks(bad[ch*32+:32]),.flushes(flushes[ch*32+:32]));
    end endgenerate
    always @(negedge clk) begin cycle=cycle+1;record_ready=allow_output && cycle%7!=0 && cycle%11!=0;end
    always @(posedge clk) begin
        if(!reset_n) begin
            for(integer j=0;j<4;j=j+1) begin received[j]=0;position[j]=0;end
            current=-1;stalled=0;
        end else begin
            if(stalled && (!record_valid || held!=={record_channel,record_last,record_data})) $fatal(1,"stall output changed");
            stalled=record_valid&&!record_ready;held={record_channel,record_last,record_data};
            if(record_valid&&record_ready) begin
                if(received[record_channel]>=4) $fatal(1,"extra record");
                if(current<0) current=record_channel;
                if(current!=record_channel) $fatal(1,"channel interleave");
                if(record_data!==expected[record_channel*992+received[record_channel]*248+position[record_channel]]) $fatal(1,"byte mismatch");
                if(record_last!==(position[record_channel]==247)) $fatal(1,"last mismatch");
                $fdisplay(output_file,"%0d,%0d,%0d,%0d,%0d,%02x",run_id,cycle,record_channel,received[record_channel],position[record_channel],record_data);
                if(record_last) begin received[record_channel]=received[record_channel]+1;position[record_channel]=0;current=-1;end
                else position[record_channel]=position[record_channel]+1;
            end
        end
    end
    task restart(input integer r);
        begin @(negedge clk);reset_n=0;repeat(8) @(negedge clk);run_id=r;reset_n=1;end
    endtask
    task complete;
        begin
            wait(received[0]==4 && received[1]==4 && received[2]==4 && received[3]==4);
            repeat(100) @(negedge clk);
            if(delivered_count!=={32'd4,32'd4,32'd4,32'd4} || commit_ok_count!==delivered_count || commits!==delivered_count) $fatal(1,"accounting");
            if(crc_error_count!=={32'd1,32'd0,32'd1,32'd0} || bad!==crc_error_count || flushes!==crc_error_count) $fatal(1,"CRC isolation/retry");
            if(commit_error_count!=0 || timeout_count!=0 || envelope_error_count!=0) $fatal(1,"unexpected transport errors");
        end
    endtask
    initial begin
        if(!$value$plusargs("MC_CAPTURE=%s",output_path) || !$value$plusargs("MC_GOLDEN_DIR=%s",golden_dir)) $fatal(1,"missing paths");
        for(k=0;k<4;k=k+1) begin
            f=$fopen($sformatf("%s/channel%0d.bin",golden_dir,k),"rb");
            n=$fread(expected,f,k*992,992);$fclose(f);if(n!=992) $fatal(1,"golden length");
        end
        output_file=$fopen(output_path,"w");$fdisplay(output_file,"run,cycle,channel,record,offset,data");
        restart(0);allow_output=1;
        wait(received[0]>=2);if(received[1]+received[2]+received[3]!=0) $fatal(1,"absent peers");
        @(negedge clk);enable=15;complete();
        // Finite FIFO saturates: upstream must stall, never overwrite/drop.
        allow_output=0;restart(1);
        wait(commit_ok_count=={32'd2,32'd2,32'd2,32'd2});
        repeat(400) @(negedge clk);
        if(delivered_count!=0 || fifo_almost_full!=15 || fifo_blocked_cycles==0) $fatal(1,"missing full backpressure");
        restart(2);repeat(20) @(negedge clk);
        if(record_valid || delivered_count!=0 || fifo_levels!=0) $fatal(1,"old run leaked");
        allow_output=1;complete();$fclose(output_file);
        $display("TB_FOUR_CHANNEL_CAPTURE_CORE_OK records=32 bytes=7936 four_ports CRC_isolation FIFO_full reset");$finish;
    end
    initial begin #200000000;$fatal(1,"capture watchdog %h",debug_state);end
endmodule
