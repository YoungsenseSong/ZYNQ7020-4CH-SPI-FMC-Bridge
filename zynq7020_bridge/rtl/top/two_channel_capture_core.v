`timescale 1ns/1ps

// MC002 integration core; not a board top or a sampling synchronizer.
// Each physical SPI port uses the existing v1 two-CS command protocol.
// clk/reset_n are supplied by the integration wrapper (synchronous deassertion).
module two_channel_capture_core #(
    parameter integer CLOCK_HZ = 50000000,
    parameter integer SCLK_HZ = 1000000,
    parameter integer AB_GAP_CYCLES = 250000,
    parameter integer CS_INACTIVE_CYCLES = 15,
    parameter integer B_TO_NEXT_A_GAP_CYCLES = 250000,
    parameter integer STARTUP_DELAY_CYCLES = 250000,
    parameter integer RETRY_DELAY_CYCLES = 50000,
    parameter integer SYNC_WIDTH_CYCLES = 50
) (
    input wire clk,
    input wire reset_n,
    input wire [1:0] spi_drdy,
    input wire [1:0] spi_miso,
    output wire [1:0] spi_sclk,
    output wire [1:0] spi_mosi,
    output wire [1:0] spi_cs_n,
    output wire [1:0] sync_out,
    output wire [7:0] record_data,
    output wire record_channel,
    output wire record_valid,
    output wire record_last,
    input wire record_ready,
    output wire [11:0] debug_state,
    output wire [63:0] crc_error_count,
    output wire [63:0] commit_ok_count,
    output wire [63:0] commit_error_count,
    output wire [63:0] timeout_count,
    output wire [63:0] envelope_error_count,
    output wire [63:0] delivered_count
);
    wire [1:0] drdy_sync;
    wire [15:0] channel_data;
    wire [1:0] channel_valid, channel_last, channel_ready;
    cdc_sync #(.WIDTH(2)) drdy_cdc (
        .clk(clk), .reset_n(reset_n), .async_in(spi_drdy), .sync_out(drdy_sync)
    );

    genvar ch;
    generate for (ch = 0; ch < 2; ch = ch + 1) begin : channels
        ch0_spi_controller #(
            .CLOCK_HZ(CLOCK_HZ), .SCLK_HZ(SCLK_HZ),
            .AB_GAP_CYCLES(AB_GAP_CYCLES),
            .CS_INACTIVE_CYCLES(CS_INACTIVE_CYCLES),
            .B_TO_NEXT_A_GAP_CYCLES(B_TO_NEXT_A_GAP_CYCLES),
            .STARTUP_DELAY_CYCLES(STARTUP_DELAY_CYCLES),
            .RETRY_DELAY_CYCLES(RETRY_DELAY_CYCLES),
            .SYNC_WIDTH_CYCLES(SYNC_WIDTH_CYCLES),
            .EXERCISE_COMMIT_ERRORS(0)
        ) controller (
            .clk(clk), .reset_n(reset_n), .drdy(drdy_sync[ch]),
            .miso(spi_miso[ch]), .mosi(spi_mosi[ch]), .sclk(spi_sclk[ch]),
            .cs_n(spi_cs_n[ch]), .sync_out(sync_out[ch]),
            .record_data(channel_data[ch*8 +: 8]),
            .record_valid(channel_valid[ch]), .record_last(channel_last[ch]),
            .record_ready(channel_ready[ch]), .debug_state(debug_state[ch*6 +: 6]),
            .request_count(), .response_count(), .last_command(), .last_status(),
            .last_transport_seq(), .last_record_valid(), .crc_ok_count(),
            .crc_error_count(crc_error_count[ch*32 +: 32]),
            .commit_ok_count(commit_ok_count[ch*32 +: 32]),
            .commit_error_count(commit_error_count[ch*32 +: 32]),
            .bad_commit_reject_count(), .duplicate_commit_reject_count(),
            .timeout_count(timeout_count[ch*32 +: 32]),
            .envelope_error_count(envelope_error_count[ch*32 +: 32])
        );
    end endgenerate

    two_channel_record_mux output_mux (
        .clk(clk), .reset_n(reset_n), .in_data(channel_data),
        .in_valid(channel_valid), .in_last(channel_last), .in_ready(channel_ready),
        .out_data(record_data), .out_channel(record_channel),
        .out_valid(record_valid), .out_last(record_last), .out_ready(record_ready),
        .delivered_count(delivered_count)
    );
endmodule
