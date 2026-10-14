`timescale 1ns/1ps
// Four independent nRF v1 command paths. No physical sample-clock alignment.
module four_channel_capture_core #(
    parameter integer CLOCK_HZ=50000000, SCLK_HZ=1000000,
    parameter integer AB_GAP_CYCLES=250000, CS_INACTIVE_CYCLES=15,
    parameter integer B_TO_NEXT_A_GAP_CYCLES=250000, STARTUP_DELAY_CYCLES=250000,
    parameter integer RETRY_DELAY_CYCLES=50000, SYNC_WIDTH_CYCLES=50,
    parameter integer FIFO_DEPTH=16384, FIFO_ADDR_WIDTH=14, FIFO_HIGH_WATER=14336,
    parameter [3:0] ACTIVE_CHANNEL_MASK=4'b1111
) (
    input wire clk, reset_n,
    input wire [3:0] spi_drdy, spi_miso,
    output wire [3:0] spi_sclk, spi_mosi, spi_cs_n, sync_out,
    output wire [7:0] record_data,
    output wire [1:0] record_channel,
    output wire record_valid, record_last,
    input wire record_ready,
    output wire [23:0] debug_state,
    output wire [127:0] crc_error_count, commit_ok_count, commit_error_count,
    output wire [127:0] timeout_count, envelope_error_count, delivered_count,
    output wire [63:0] fifo_levels,
    output wire [3:0] fifo_almost_full,
    output wire [127:0] fifo_blocked_cycles
);
    wire [3:0] drdy_sync, controller_valid, controller_last, controller_ready;
    wire [31:0] controller_data, mux_data;
    wire [3:0] mux_valid, mux_last, mux_ready;
    cdc_sync #(.WIDTH(4)) drdy_cdc(.clk(clk),.reset_n(reset_n),.async_in(spi_drdy),.sync_out(drdy_sync));
    genvar ch;
    generate for(ch=0;ch<4;ch=ch+1) begin: channels
        if(ACTIVE_CHANNEL_MASK[ch]) begin: enabled
            ch0_spi_controller #(
                .CLOCK_HZ(CLOCK_HZ),.SCLK_HZ(SCLK_HZ),.AB_GAP_CYCLES(AB_GAP_CYCLES),
                .CS_INACTIVE_CYCLES(CS_INACTIVE_CYCLES),.B_TO_NEXT_A_GAP_CYCLES(B_TO_NEXT_A_GAP_CYCLES),
                .STARTUP_DELAY_CYCLES(STARTUP_DELAY_CYCLES),.RETRY_DELAY_CYCLES(RETRY_DELAY_CYCLES),
                .SYNC_WIDTH_CYCLES(SYNC_WIDTH_CYCLES),.EXERCISE_COMMIT_ERRORS(0)
            ) controller(
                .clk(clk),.reset_n(reset_n),.drdy(drdy_sync[ch]),.miso(spi_miso[ch]),
                .sclk(spi_sclk[ch]),.mosi(spi_mosi[ch]),.cs_n(spi_cs_n[ch]),.sync_out(sync_out[ch]),
                .record_data(controller_data[ch*8+:8]),.record_valid(controller_valid[ch]),
                .record_last(controller_last[ch]),.record_ready(controller_ready[ch]),
                .debug_state(debug_state[ch*6+:6]),.request_count(),.response_count(),
                .last_command(),.last_status(),.last_transport_seq(),.last_record_valid(),
                .crc_ok_count(),.crc_error_count(crc_error_count[ch*32+:32]),
                .commit_ok_count(commit_ok_count[ch*32+:32]),.commit_error_count(commit_error_count[ch*32+:32]),
                .bad_commit_reject_count(),.duplicate_commit_reject_count(),
                .timeout_count(timeout_count[ch*32+:32]),.envelope_error_count(envelope_error_count[ch*32+:32])
            );
        end else begin: disabled
            assign spi_sclk[ch]=0; assign spi_mosi[ch]=0; assign spi_cs_n[ch]=1; assign sync_out[ch]=0;
            assign controller_data[ch*8+:8]=0; assign controller_valid[ch]=0; assign controller_last[ch]=0;
            assign debug_state[ch*6+:6]=0; assign crc_error_count[ch*32+:32]=0;
            assign commit_ok_count[ch*32+:32]=0; assign commit_error_count[ch*32+:32]=0;
            assign timeout_count[ch*32+:32]=0; assign envelope_error_count[ch*32+:32]=0;
        end
        if(FIFO_DEPTH>0 && ACTIVE_CHANNEL_MASK[ch]) begin: buffered
            wire [8:0] output_word;
            record_fifo_bram #(.DEPTH(FIFO_DEPTH),.ADDR_WIDTH(FIFO_ADDR_WIDTH),.HIGH_WATER(FIFO_HIGH_WATER)) fifo(
                .clk(clk),.reset_n(reset_n),.in_data({controller_last[ch],controller_data[ch*8+:8]}),
                .in_valid(controller_valid[ch]),.in_ready(controller_ready[ch]),.out_data(output_word),
                .out_valid(mux_valid[ch]),.out_ready(mux_ready[ch]),.almost_full(fifo_almost_full[ch]),
                .level(fifo_levels[ch*16+:16]),.blocked_cycles(fifo_blocked_cycles[ch*32+:32])
            );
            assign mux_data[ch*8+:8]=output_word[7:0]; assign mux_last[ch]=output_word[8];
        end else begin: bypass
            assign mux_data[ch*8+:8]=controller_data[ch*8+:8];
            assign mux_valid[ch]=controller_valid[ch]; assign mux_last[ch]=controller_last[ch];
            assign controller_ready[ch]=mux_ready[ch]; assign fifo_levels[ch*16+:16]=0;
            assign fifo_almost_full[ch]=0; assign fifo_blocked_cycles[ch*32+:32]=0;
        end
    end endgenerate
    four_channel_record_mux mux(.clk(clk),.reset_n(reset_n),.in_data(mux_data),.in_valid(mux_valid),
        .in_last(mux_last),.in_ready(mux_ready),.out_data(record_data),.out_channel(record_channel),
        .out_valid(record_valid),.out_last(record_last),.out_ready(record_ready),.delivered_count(delivered_count));
endmodule
