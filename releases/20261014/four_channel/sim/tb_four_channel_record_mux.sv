`timescale 1ns/1ps
module tb_four_channel_record_mux;
    reg clk = 0, reset_n = 0;
    always #10 clk = ~clk;
    reg [31:0] in_data = 0;
    reg [3:0] in_valid = 0, in_last = 0;
    wire [3:0] in_ready;
    wire [7:0] out_data;
    wire [1:0] out_channel;
    wire out_valid, out_last;
    reg out_ready = 0;
    wire [127:0] delivered_count;
    integer bytes_seen[0:3], records_seen[0:3];
    integer current_channel = -1;
    reg stalled = 0;
    reg [10:0] held;
    integer cycle = 0, mode = 0;
    integer last_stall_cycles = 0;
    integer first_stalls = 0, middle_stalls = 0, last_stalls = 0;
    reg [31:0] random_state = 32'h45a1beef;
    four_channel_record_mux dut (.*);

    function [7:0] pattern(input integer ch, input integer rec, input integer pos);
        pattern = (ch * 131 + rec * 37 + pos * 11) & 255;
    endfunction

    always @(negedge clk) begin
        cycle = cycle + 1;
        random_state = {random_state[30:0], random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        if (mode == 1) out_ready = random_state[0] | random_state[3];
        if (mode == 2) out_ready = 1;
        if (mode == 1 && out_valid && out_last && last_stall_cycles < 4) begin
            out_ready = 0; last_stall_cycles = last_stall_cycles + 1;
        end
    end

    always @(posedge clk) begin
        if (!reset_n) begin
            for(integer k=0;k<4;k=k+1) bytes_seen[k]=0;
            for(integer k=0;k<4;k=k+1) records_seen[k]=0;
            current_channel = -1; stalled = 0;
        end else begin
            if (stalled && (!out_valid || {out_channel,out_last,out_data} !== held))
                $fatal(1, "output changed during backpressure");
            stalled = out_valid && !out_ready;
            held = {out_channel,out_last,out_data};
            if (out_valid && !out_ready) begin
                if (bytes_seen[out_channel] == 0) first_stalls = first_stalls + 1;
                else if (out_last) last_stalls = last_stalls + 1;
                else middle_stalls = middle_stalls + 1;
            end
            if(mode==2 && in_valid==15) begin
                for(integer a=0;a<4;a=a+1) for(integer b=0;b<4;b=b+1)
                    if(records_seen[a]-records_seen[b]>1) $fatal(1,"four-way fairness bound");
            end
            if (out_valid && out_ready) begin
                if (current_channel == -1) current_channel = out_channel;
                if (current_channel != out_channel) $fatal(1, "interleaved records");
                if (out_data !== pattern(out_channel, records_seen[out_channel], bytes_seen[out_channel]))
                    $fatal(1, "byte mismatch ch=%0d rec=%0d byte=%0d",out_channel,records_seen[out_channel],bytes_seen[out_channel]);
                if (out_last !== (bytes_seen[out_channel] == 247)) $fatal(1,"last mismatch");
                if (out_last) begin
                    records_seen[out_channel] = records_seen[out_channel] + 1;
                    bytes_seen[out_channel] = 0;
                    current_channel = -1;
                end else bytes_seen[out_channel] = bytes_seen[out_channel] + 1;
            end
        end
    end

    task automatic send_records(input integer ch, input integer first, input integer count, input integer gaps);
        integer r, b;
        begin
            for (r = first; r < first + count; r = r + 1) begin
                for (b = 0; b < 248; b = b + 1) begin
                    @(negedge clk);
                    in_data[ch*8 +: 8] = pattern(ch,r,b);
                    in_valid[ch] = 1; in_last[ch] = (b == 247);
                    @(posedge clk);
                    while (!in_ready[ch]) @(posedge clk);
                    if (gaps && b == 61) begin
                        @(negedge clk); in_valid[ch] = 0;
                        repeat (9) @(negedge clk);
                    end
                end
            end
            @(negedge clk); in_valid[ch] = 0; in_last[ch] = 0;
        end
    endtask

    task restart;
        begin
            @(negedge clk); reset_n = 0; in_valid = 0; in_last = 0;
            repeat (4) @(negedge clk);
            reset_n = 1;
        end
    endtask

    initial begin
        restart();
        // Lock first byte of CH1, then make higher-priority CH0 valid while stalled.
        fork
            send_records(1,0,2,1);
            begin wait(out_valid); repeat(5) @(negedge clk); send_records(0,0,3,1); end
            begin wait(out_valid); repeat(25) @(negedge clk); mode = 1; end
        join
        repeat (4) @(posedge clk);
        if (delivered_count !== {32'd0,32'd0,32'd2,32'd3}) $fatal(1,"record counts");
        // An idle peer must not prevent repeated delivery.
        send_records(0,3,2,0);
        repeat (4) @(posedge clk);
        if (delivered_count !== {32'd0,32'd0,32'd2,32'd5}) $fatal(1,"idle peer blocked");
        // Continuous simultaneous load; no byte mixing or starvation.
        restart(); mode = 2;
        fork send_records(0,0,8,0); send_records(1,0,8,0); send_records(2,0,8,0); send_records(3,0,8,0); join
        repeat (4) @(posedge clk);
        if (delivered_count !== {32'd8,32'd8,32'd8,32'd8}) $fatal(1,"fairness counts");
        // Reset while output is stalled: old partial record must disappear.
        mode = 0; @(negedge clk); out_ready = 0;
        in_valid = 1; in_data[7:0] = 8'hee;
        wait(out_valid); repeat (3) @(negedge clk);
        restart(); mode = 1;
        fork send_records(0,0,2,0); send_records(1,0,2,0); send_records(2,0,2,0); send_records(3,0,2,0); join
        repeat (4) @(posedge clk);
        if (delivered_count !== {32'd2,32'd2,32'd2,32'd2}) $fatal(1,"reset counts");
        if (!first_stalls || !middle_stalls || !last_stalls) $fatal(1,"missing stall coverage");
        $display("TB_FOUR_CHANNEL_RECORD_MUX_OK stall_lock gaps idle_peer concurrent reset");
        $finish;
    end
    initial begin #10000000; $fatal(1,"mux timeout"); end
endmodule
