`timescale 1ns/1ps

// Record-preserving signal processing sideband.
// The 248-byte v0 record is passed through unchanged. The RF payload contains
// a 96-sample little-endian int16 vector at record offsets 52..243.
// Statistics are committed only after the complete record has been accepted.
module single_channel_signal_stats #(
    parameter integer SAMPLE_COUNT = 96
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [7:0]  in_data,
    input  wire        in_valid,
    output wire        in_ready,
    input  wire        in_last,
    output wire [7:0]  out_data,
    output wire        out_valid,
    input  wire        out_ready,
    output wire        out_last,
    input  wire        clear_counters,
    input  wire        threshold_enable,
    input  wire [15:0] threshold_abs,
    output reg         stats_valid,
    output reg         threshold_pulse,
    output reg         threshold_sticky,
    output reg [15:0]  peak_abs,
    output reg signed [15:0] mean_signed,
    output reg [39:0]  energy_sum,
    output reg [7:0]   sample_count,
    output reg [31:0]  record_count,
    output reg [31:0]  threshold_count,
    output reg [31:0]  malformed_count
);
    reg [8:0] offset;
    reg [7:0] sample_low;
    reg signed [31:0] sum_work;
    reg [39:0] energy_work;
    reg [15:0] peak_work;

    reg signed [15:0] sample_signed;
    reg [16:0] sample_abs;
    wire accept = in_valid && out_ready;

    assign in_ready = out_ready;
    assign out_data = in_data;
    assign out_valid = in_valid;
    assign out_last = in_last;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            offset <= 9'd0;
            sample_low <= 8'd0;
            sum_work <= 32'sd0;
            energy_work <= 40'd0;
            peak_work <= 16'd0;
            stats_valid <= 1'b0;
            threshold_pulse <= 1'b0;
            threshold_sticky <= 1'b0;
            peak_abs <= 16'd0;
            mean_signed <= 16'sd0;
            energy_sum <= 40'd0;
            sample_count <= 8'd0;
            record_count <= 32'd0;
            threshold_count <= 32'd0;
            malformed_count <= 32'd0;
        end else begin
            threshold_pulse <= 1'b0;

            if (clear_counters) begin
                threshold_sticky <= 1'b0;
                record_count <= 32'd0;
                threshold_count <= 32'd0;
                malformed_count <= 32'd0;
                stats_valid <= 1'b0;
            end

            if (accept) begin
                if (offset == 9'd0) begin
                    sum_work <= 32'sd0;
                    energy_work <= 40'd0;
                    peak_work <= 16'd0;
                    sample_count <= 8'd0;
                end

                if ((offset >= 9'd52) && (offset <= 9'd243)) begin
                    if (!offset[0]) begin
                        sample_low <= in_data;
                    end else begin
                        sample_signed = $signed({in_data, sample_low});
                        sample_abs = sample_signed[15] ?
                                     (~sample_signed + 17'd1) :
                                     {1'b0, sample_signed[15:0]};
                        sum_work <= sum_work + sample_signed;
                        energy_work <= energy_work +
                                       (sample_abs * sample_abs);
                        if (sample_abs[15:0] > peak_work)
                            peak_work <= sample_abs[15:0];
                        sample_count <= sample_count + 1'b1;
                    end
                end

                if (in_last || (offset == 9'd247)) begin
                    if ((offset == 9'd247) &&
                        (sample_count == SAMPLE_COUNT[7:0])) begin
                        stats_valid <= 1'b1;
                        peak_abs <= peak_work;
                        mean_signed <= sum_work / SAMPLE_COUNT;
                        energy_sum <= energy_work;
                        record_count <= record_count + 1'b1;
                        if (threshold_enable && (peak_work >= threshold_abs)) begin
                            threshold_pulse <= 1'b1;
                            threshold_sticky <= 1'b1;
                            threshold_count <= threshold_count + 1'b1;
                        end
                    end else begin
                        malformed_count <= malformed_count + 1'b1;
                    end
                    offset <= 9'd0;
                end else begin
                    offset <= offset + 1'b1;
                end
            end
        end
    end
endmodule
