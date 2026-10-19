`timescale 1ns/1ps
module tb_record_fifo_bram;
    reg clk=0,reset_n=0; always #5 clk=~clk;
    reg [8:0] in_data=0; reg in_valid=0,out_ready=0;
    wire [8:0] out_data; wire in_ready,out_valid,almost_full;
    wire [15:0] level; wire [31:0] blocked_cycles;
    record_fifo_bram #(.DEPTH(8),.ADDR_WIDTH(3),.HIGH_WATER(6)) dut(.*);
    integer writes=0,reads=0,cycles=0;
    reg stalled=0; reg [8:0] held;
    function [8:0] pattern(input integer n); pattern=(n*173+19)&511; endfunction
    always @(posedge clk) if(reset_n) begin
        if(stalled && (!out_valid || out_data!==held)) $fatal(1,"FIFO changed during stall");
        stalled=out_valid&&!out_ready; held=out_data;
        if(in_valid&&in_ready) writes=writes+1;
        if(out_valid&&out_ready) begin
            if(reads>=writes || out_data!==pattern(reads)) $fatal(1,"FIFO order/duplication failure");
            reads=reads+1;
        end
    end else begin writes=0;reads=0;stalled=0; end
    initial begin
        repeat(3) @(negedge clk); reset_n=1;
        // Fill RAM + prefetch output, then hold the producer at full.
        repeat(30) begin
            @(negedge clk); in_valid=1; in_data=pattern(writes);
        end
        if(writes!=9 || level!=9 || !almost_full || blocked_cycles<1) $fatal(1,"FIFO full accounting");
        for(cycles=0;cycles<450;cycles=cycles+1) begin
            @(negedge clk); out_ready=(cycles%5!=0); in_valid=writes<180; in_data=pattern(writes);
        end
        @(negedge clk); in_valid=0;out_ready=1;
        wait(reads==writes); repeat(4) @(negedge clk);
        if(out_valid || level!=0 || reads!=180) $fatal(1,"FIFO wrap/drain");
        // Reset discards occupancy without clearing RAM contents.
        out_ready=0; in_valid=1;in_data=pattern(writes);repeat(4) @(negedge clk);
        reset_n=0; in_valid=0; repeat(3) @(negedge clk);reset_n=1;
        repeat(3) @(negedge clk);
        if(out_valid || level!=0 || blocked_cycles!=0) $fatal(1,"FIFO reset leak");
        $display("TB_RECORD_FIFO_BRAM_OK full backpressure wrap simultaneous reset");$finish;
    end
    initial begin #100000;$fatal(1,"FIFO watchdog");end
endmodule
