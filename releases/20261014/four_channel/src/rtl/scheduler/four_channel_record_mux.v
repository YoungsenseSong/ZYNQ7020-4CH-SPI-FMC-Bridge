`timescale 1ns/1ps
// Registered whole-record grant. All inputs must be complete buffered records.
// A stalled first byte cannot be replaced when another source becomes valid.
module four_channel_record_mux (
    input wire clk, reset_n,
    input wire [31:0] in_data,
    input wire [3:0] in_valid, in_last,
    output wire [3:0] in_ready,
    output wire [7:0] out_data,
    output wire [1:0] out_channel,
    output wire out_valid, out_last,
    input wire out_ready,
    output wire [127:0] delivered_count
);
    reg active;
    reg [1:0] selected, next_priority;
    reg [31:0] counts [0:3];
    reg found;
    reg [1:0] candidate, scan_channel;
    integer offset, i;
    always @* begin
        found = 0; candidate = next_priority; scan_channel = 0;
        for (offset=0; offset<4; offset=offset+1) begin
            scan_channel = next_priority + offset;
            if (!found && in_valid[scan_channel]) begin
                candidate = scan_channel; found = 1;
            end
        end
    end
    assign out_valid = reset_n && active && in_valid[selected];
    assign out_data = in_data[selected*8 +: 8];
    assign out_channel = selected;
    assign out_last = out_valid && in_last[selected];
    assign in_ready = (reset_n && active && out_ready) ? (4'b0001 << selected) : 4'b0000;
    assign delivered_count = {counts[3],counts[2],counts[1],counts[0]};
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active <= 0; selected <= 0; next_priority <= 0;
            for(i=0;i<4;i=i+1) counts[i] <= 0;
        end else if (!active) begin
            if(found) begin selected <= candidate; active <= 1; end
        end else if(out_valid && out_ready && out_last) begin
            active <= 0; next_priority <= selected + 2'd1;
            counts[selected] <= counts[selected] + 1'b1;
        end
    end
endmodule
