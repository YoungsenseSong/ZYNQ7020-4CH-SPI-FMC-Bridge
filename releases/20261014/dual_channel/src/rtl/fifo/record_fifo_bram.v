`timescale 1ns/1ps
// Synchronous RAM plus one prefetched output word. Memory is never reset.
// DEPTH must be a power of two. Capacity is DEPTH RAM words + one output word.
// Producers hold in_valid/data when !in_ready: a stall does not drop data.
module record_fifo_bram #(
    parameter integer DEPTH=16384,
    parameter integer ADDR_WIDTH=14,
    parameter integer HIGH_WATER=14336
) (
    input wire clk, reset_n,
    input wire [8:0] in_data,
    input wire in_valid,
    output wire in_ready,
    output wire [8:0] out_data,
    output wire out_valid,
    input wire out_ready,
    output wire almost_full,
    output wire [15:0] level,
    output reg [31:0] blocked_cycles
);
    (* ram_style="block" *) reg [8:0] memory [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] write_ptr, read_ptr;
    reg [ADDR_WIDTH:0] count;
    reg [8:0] read_word;
    reg head_valid;
    wire write_accept = reset_n && in_valid && in_ready;
    wire fetch = reset_n && (!head_valid || out_ready) && count!=0;
    assign in_ready = reset_n && count<DEPTH;
    assign out_valid = reset_n && head_valid;
    assign out_data = read_word;
    assign level = count + head_valid;
    assign almost_full = level>=HIGH_WATER;
    // Independent clocked RAM process is essential for block-RAM inference.
    always @(posedge clk) begin
        if(write_accept) memory[write_ptr] <= in_data;
        if(fetch) read_word <= memory[read_ptr];
    end
    // Keep RAM addresses/control synchronous. Hold reset low across a clk edge;
    // interface valid/ready are gated immediately while reset is asserted.
    always @(posedge clk) begin
        if(!reset_n) begin
            write_ptr<=0; read_ptr<=0; count<=0; head_valid<=0; blocked_cycles<=0;
        end else begin
            if(write_accept) write_ptr<=write_ptr+1'b1;
            if(fetch) begin read_ptr<=read_ptr+1'b1; head_valid<=1; end
            else if(head_valid && out_ready) head_valid<=0;
            case({write_accept,fetch})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: count<=count;
            endcase
            if(in_valid && !in_ready) blocked_cycles<=blocked_cycles+1'b1;
        end
    end
    initial begin
        if(DEPTH!=(1<<ADDR_WIDTH) || ADDR_WIDTH>14 || HIGH_WATER>DEPTH || HIGH_WATER<1)
            $error("invalid record_fifo_bram parameters");
    end
endmodule
