`timescale 1ns/1ps

// Whole-record round robin. Inputs are already checked, fully buffered records
// from ch0_spi_controller. Sources must hold valid/data/last until accepted.
// A selected record owns the output until its last handshake, including stalls.
module two_channel_record_mux (
    input wire clk,
    input wire reset_n,
    input wire [15:0] in_data,
    input wire [1:0] in_valid,
    input wire [1:0] in_last,
    output wire [1:0] in_ready,
    output wire [7:0] out_data,
    output wire out_channel,
    output wire out_valid,
    output wire out_last,
    input wire out_ready,
    output wire [63:0] delivered_count
);
    reg active;
    reg selected;
    reg next_priority;
    reg [31:0] count0, count1;

    // Register the grant BEFORE asserting valid. A peer becoming valid while
    // the first byte is stalled must not change the externally visible record.
    assign out_valid = reset_n && active && in_valid[selected];
    assign out_channel = selected;
    assign out_data = selected ? in_data[15:8] : in_data[7:0];
    assign out_last = out_valid && in_last[selected];
    assign in_ready = (reset_n && active && out_ready) ?
                      (selected ? 2'b10 : 2'b01) : 2'b00;
    assign delivered_count = {count1, count0};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active <= 1'b0;
            selected <= 1'b0;
            next_priority <= 1'b0;
            count0 <= 0;
            count1 <= 0;
        end else if (!active) begin
            if (|in_valid) begin
                selected <= in_valid[next_priority] ? next_priority : ~next_priority;
                active <= 1'b1;
            end
        end else if (out_valid && out_ready && out_last) begin
            active <= 1'b0;
            next_priority <= ~selected;
            if (selected) count1 <= count1 + 1'b1;
            else count0 <= count0 + 1'b1;
        end
    end
endmodule
