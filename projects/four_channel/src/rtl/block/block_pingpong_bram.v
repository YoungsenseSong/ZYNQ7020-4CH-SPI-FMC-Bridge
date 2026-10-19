`timescale 1ns/1ps
// v0 block storage with byte-lane synchronous RAM and claim/sequence ACK.
// RAM processes have no reset. Repeated alloc_request grants only once.
module block_pingpong_bram #(
    parameter integer TOTAL_BYTES=32800, WORDS=16400,
    parameter integer ACK_POLICY=1
) (
    input wire clk, reset_n, alloc_request,
    output reg alloc_grant, alloc_bank,
    input wire write_valid, write_bank,
    input wire [15:0] write_address,
    input wire [7:0] write_data,
    input wire seal_valid, seal_bank,
    input wire [15:0] seal_length,
    input wire [31:0] seal_sequence,
    input wire read_request, read_bank,
    input wire [14:0] read_word_address,
    output reg read_valid,
    output wire [15:0] read_data,
    input wire claim_valid, claim_bank, ack_valid,
    input wire [15:0] ack_value,
    output wire ready_valid, ready_bank,
    output wire [15:0] ready_length,
    output wire [31:0] ready_sequence,
    output wire [2:0] owner_bank0, owner_bank1
);
    localparam FREE=3'd0, FILLING=3'd1, READY=3'd2, READING=3'd3;
    (* ram_style="block" *) reg [7:0] low0[0:WORDS-1], high0[0:WORDS-1];
    (* ram_style="block" *) reg [7:0] low1[0:WORDS-1], high1[0:WORDS-1];
    reg [7:0] read_low0,read_high0,read_low1,read_high1;
    reg read_bank_d, read_in_range;
    reg [2:0] owner0,owner1;
    reg [15:0] length0,length1;
    reg [31:0] sequence0,sequence1;
    reg last_allocated, request_seen;
    wire available0=(owner0==READY || owner0==READING);
    wire available1=(owner1==READY || owner1==READING);
    // At most two outstanding consecutive blocks; signed subtraction handles wrap.
    assign ready_bank=available1 && (!available0 || $signed(sequence1-sequence0)<0);
    assign ready_valid=reset_n && (available0 || available1);
    assign ready_length=ready_bank?length1:length0;
    assign ready_sequence=ready_bank?sequence1:sequence0;
    assign owner_bank0=owner0; assign owner_bank1=owner1;
    assign read_data=!read_in_range ? 16'd0 :
        (read_bank_d?{read_high1,read_low1}:{read_high0,read_low0});
    wire write0=reset_n && write_valid && !write_bank && owner0==FILLING && write_address<TOTAL_BYTES;
    wire write1=reset_n && write_valid && write_bank && owner1==FILLING && write_address<TOTAL_BYTES;
    always @(posedge clk) begin
        if(write0 && !write_address[0]) low0[write_address[15:1]]<=write_data;
        if(write0 && write_address[0]) high0[write_address[15:1]]<=write_data;
        if(write1 && !write_address[0]) low1[write_address[15:1]]<=write_data;
        if(write1 && write_address[0]) high1[write_address[15:1]]<=write_data;
        if(reset_n && read_request) begin
            read_bank_d<=read_bank; read_in_range<=read_word_address<WORDS;
            if(read_word_address<WORDS) begin
                read_low0<=low0[read_word_address]; read_high0<=high0[read_word_address];
                read_low1<=low1[read_word_address]; read_high1<=high1[read_word_address];
            end
        end
    end
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            owner0<=FREE; owner1<=FREE; length0<=0; length1<=0; sequence0<=0; sequence1<=0;
            last_allocated<=1; request_seen<=0; alloc_grant<=0; alloc_bank<=0; read_valid<=0;
        end else begin
            alloc_grant<=0; read_valid<=read_request;
            if(!alloc_request) request_seen<=0;
            if(alloc_request && !request_seen) begin
                if(owner0==FREE && (owner1!=FREE || last_allocated)) begin
                    owner0<=FILLING; alloc_bank<=0; alloc_grant<=1; last_allocated<=0; request_seen<=1;
                end else if(owner1==FREE) begin
                    owner1<=FILLING; alloc_bank<=1; alloc_grant<=1; last_allocated<=1; request_seen<=1;
                end
            end
            if(seal_valid && seal_length<=TOTAL_BYTES) begin
                if(seal_bank && owner1==FILLING) begin owner1<=READY; length1<=seal_length; sequence1<=seal_sequence; end
                else if(!seal_bank && owner0==FILLING) begin owner0<=READY; length0<=seal_length; sequence0<=seal_sequence; end
            end
            if(claim_valid) begin
                if(claim_bank && owner1==READY) owner1<=READING;
                else if(!claim_bank && owner0==READY) owner0<=READING;
            end
            if(ack_valid && ACK_POLICY!=0) begin
                if(owner0==READING && (ACK_POLICY==2 || ack_value==sequence0[15:0])) owner0<=FREE;
                else if(owner1==READING && (ACK_POLICY==2 || ack_value==sequence1[15:0])) owner1<=FREE;
            end
        end
    end
    initial begin
        if(TOTAL_BYTES!=WORDS*2 || TOTAL_BYTES>65534 || TOTAL_BYTES<64)
            $error("invalid block_pingpong_bram capacity");
    end
endmodule
