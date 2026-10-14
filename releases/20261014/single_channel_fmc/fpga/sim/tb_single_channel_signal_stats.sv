`timescale 1ns/1ps
module tb_single_channel_signal_stats;
    reg clk=0, reset_n=0; always #5 clk=~clk;
    reg [7:0] data; reg valid=0, last=0; wire ready;
    wire [7:0] out_data; wire out_valid,out_last;
    wire stats_valid, threshold_pulse, threshold_sticky;
    wire [15:0] peak; wire signed [15:0] mean; wire [39:0] energy;
    wire [7:0] samples; wire [31:0] records,alerts,bad;
    integer i;
    single_channel_signal_stats dut(.clk(clk),.reset_n(reset_n),.in_data(data),
        .in_valid(valid),.in_ready(ready),.in_last(last),.out_data(out_data),
        .out_valid(out_valid),.out_ready(1'b1),.out_last(out_last),
        .clear_counters(1'b0),.threshold_enable(1'b1),.threshold_abs(16'd100),
        .stats_valid(stats_valid),.threshold_pulse(threshold_pulse),
        .threshold_sticky(threshold_sticky),.peak_abs(peak),.mean_signed(mean),
        .energy_sum(energy),.sample_count(samples),.record_count(records),
        .threshold_count(alerts),.malformed_count(bad));
    initial begin
        repeat(3) @(posedge clk); reset_n=1;
        for(i=0;i<248;i=i+1) begin
            @(negedge clk); valid=1; data=0; last=(i==247);
            if(i>=52 && i<=243 && i[0]) data=0; // samples are zero except one injected below
            if(i==52) data=8'h2c;
            if(i==53) data=8'h01; // +300
        end
        @(negedge clk); valid=0; last=0;
        repeat(3) @(posedge clk);
        if(!stats_valid || records!=1 || samples!=96 || peak!=16'd300 || alerts!=1)
            $fatal(1,"stats mismatch valid=%b records=%0d samples=%0d peak=%0d alerts=%0d",stats_valid,records,samples,peak,alerts);
        $display("TB_SINGLE_CHANNEL_SIGNAL_STATS_OK peak=%0d mean=%0d energy=%0d",peak,mean,energy);
        $finish;
    end
endmodule
