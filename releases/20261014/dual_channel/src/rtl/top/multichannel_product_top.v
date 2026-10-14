`timescale 1ns/1ps
`include "protocol_defs.vh"

// Board-facing multi-channel product path. The capture core keeps four fixed
// channel lanes; ACTIVE_CHANNEL_MASK selects the released lanes for this image.
// The same FMC/CSR/block/ILA contract is used by the two- and four-channel
// wrappers so the F730 host software does not need a second register protocol.
module multichannel_product_top #(
    parameter [3:0] ACTIVE_CHANNEL_MASK = 4'b0011,
    parameter integer CLOCK_HZ = 50000000,
    parameter integer SCLK_HZ = 1000000,
    parameter integer FIFO_DEPTH = 16384,
    parameter integer FIFO_ADDR_WIDTH = 14,
    parameter integer FIFO_HIGH_WATER = 14336,
    parameter integer BLOCK_BYTES = 32800,
    parameter integer TARGET_PAYLOAD_BYTES = 16368,
    parameter integer MAX_PAYLOAD_BYTES = 32736,
    parameter [31:0] BLOCK_TIMEOUT_CYCLES = 2000000
) (
    input wire pl_clk,
    input wire ext_reset_n,
    input wire [3:0] spi_drdy,
    input wire [3:0] spi_miso,
    output wire [3:0] spi_sclk,
    output wire [3:0] spi_mosi,
    output wire [3:0] spi_cs_n,
    output wire [3:0] spi_sync_out,
    output wire [3:0] nrf_reset_n,
    inout wire [15:0] fmc_ad,
    input wire fmc_nadv_n,
    input wire fmc_ne1_n,
    input wire fmc_noe_n,
    input wire fmc_nwe_n,
    output wire fmc_nwait_n,
    output wire fpga_irq,
    output wire status_led,
    output reg [287:0] debug_probe
);
    wire clk = pl_clk;
    wire reset_n;
    wire soft_reset_pulse;
    wire start_pulse;
    wire stop_pulse;
    wire global_enable;
    reg running;
    reg sync_armed_reg;
    reg [63:0] fpga_tick;
    reg block_ready_d;

    wire [3:0] sync_channel_mask;
    wire [31:0] sync_epoch;
    wire sync_arm_pulse;
    wire sync_fire_pulse;
    wire capture_reset_n = reset_n && running;

    wire block_ready, block_ready_bank;
    wire [15:0] block_ready_length;
    wire [31:0] block_ready_sequence;
    wire [2:0] owner_bank0, owner_bank1;
    wire host_read_request, host_read_bank, host_read_valid;
    wire [14:0] host_read_word_address;
    wire [15:0] host_read_data;
    wire host_claim_valid, host_claim_bank, host_ack_valid;
    wire [15:0] host_ack_value;
    wire [23:0] debug_state;
    wire [127:0] crc_error_count, commit_ok_count, commit_error_count;
    wire [127:0] timeout_count, envelope_error_count, delivered_count;
    wire [63:0] fifo_levels;
    wire [3:0] fifo_almost_full;
    wire [127:0] fifo_blocked_cycles;
    wire capture_degraded;

    wire fmc_read_enable, fmc_write_enable, csr_read_valid;
    wire [15:0] fmc_address, fmc_write_data, csr_read_data;
    wire [15:0] irq_status, irq_mask;
    wire irq_clear_valid, irq_mask_write_valid;
    wire [15:0] irq_clear_value, irq_mask_write_value;
    wire block_ack_valid;
    wire [15:0] block_ack_value;
    wire [15:0] irq_event_set;
    wire fatal = 1'b0;
    wire degraded = capture_degraded || (|fifo_almost_full);

    // The multichannel CSR exposes alignment fields even before the external
    // sync/aligner is enabled. Zero is an explicit "not active" status.
    wire [127:0] fifo_drops = 128'd0;
    wire [127:0] parser_good = delivered_count;
    wire [127:0] parser_errors = crc_error_count;
    wire [3:0] alignment_buffered_mask = 4'd0;
    wire alignment_emitting = 1'b0;
    wire [31:0] aligned_group_count = 32'd0;
    wire [127:0] alignment_drop_count = 128'd0;
    wire [31:0] alignment_error_count = 32'd0;
    wire [31:0] last_aligned_epoch = 32'd0;
    wire [63:0] last_aligned_index = 64'd0;
    wire [3:0] sync_locked_mask = sync_armed_reg ? (sync_channel_mask & ACTIVE_CHANNEL_MASK) : 4'd0;

    reset_clock_mgr #(.TICK_DIVIDER(1)) clock_mgr (
        .pl_clk(pl_clk), .ext_reset_n(ext_reset_n), .soft_reset(soft_reset_pulse),
        .clk_out(clk), .reset_n(reset_n), .tick_pulse()
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            running <= 1'b0;
            sync_armed_reg <= 1'b0;
            fpga_tick <= 64'd0;
            block_ready_d <= 1'b0;
        end else begin
            fpga_tick <= fpga_tick + 1'b1;
            block_ready_d <= block_ready;
            if (stop_pulse || soft_reset_pulse) begin
                running <= 1'b0;
                sync_armed_reg <= 1'b0;
            end else begin
                if (start_pulse && global_enable)
                    running <= 1'b1;
                if (sync_arm_pulse)
                    sync_armed_reg <= 1'b1;
                if (sync_fire_pulse)
                    sync_armed_reg <= 1'b0;
            end
        end
    end

    four_channel_bridge_core #(
        .CLOCK_HZ(CLOCK_HZ), .SCLK_HZ(SCLK_HZ),
        .FIFO_DEPTH(FIFO_DEPTH), .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .FIFO_HIGH_WATER(FIFO_HIGH_WATER), .BLOCK_BYTES(BLOCK_BYTES),
        .TARGET_PAYLOAD_BYTES(TARGET_PAYLOAD_BYTES),
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES),
        .BLOCK_TIMEOUT_CYCLES(BLOCK_TIMEOUT_CYCLES),
        .ACTIVE_CHANNEL_MASK(ACTIVE_CHANNEL_MASK)
    ) bridge_core (
        .clk(clk), .reset_n(capture_reset_n), .sync_epoch(sync_epoch),
        .spi_drdy(spi_drdy), .spi_miso(spi_miso), .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi), .spi_cs_n(spi_cs_n), .sync_out(spi_sync_out),
        .flush(stop_pulse || soft_reset_pulse),
        .host_read_request(host_read_request), .host_read_bank(host_read_bank),
        .host_read_word_address(host_read_word_address),
        .host_read_valid(host_read_valid), .host_read_data(host_read_data),
        .host_claim_valid(host_claim_valid), .host_claim_bank(host_claim_bank),
        .host_ack_valid(host_ack_valid), .host_ack_value(host_ack_value),
        .block_ready(block_ready), .block_ready_bank(block_ready_bank),
        .block_ready_length(block_ready_length),
        .block_ready_sequence(block_ready_sequence), .owner_bank0(owner_bank0),
        .owner_bank1(owner_bank1), .debug_state(debug_state),
        .crc_error_count(crc_error_count), .commit_ok_count(commit_ok_count),
        .commit_error_count(commit_error_count), .timeout_count(timeout_count),
        .envelope_error_count(envelope_error_count),
        .delivered_count(delivered_count), .fifo_levels(fifo_levels),
        .fifo_almost_full(fifo_almost_full),
        .fifo_blocked_cycles(fifo_blocked_cycles), .degraded(capture_degraded)
    );

    assign nrf_reset_n = {4{capture_reset_n}} & ACTIVE_CHANNEL_MASK;

    fmc_mux_slave fmc (
        .clk(clk), .reset_n(reset_n), .fmc_ad(fmc_ad),
        .fmc_nadv_n(fmc_nadv_n), .fmc_ne1_n(fmc_ne1_n),
        .fmc_noe_n(fmc_noe_n), .fmc_nwe_n(fmc_nwe_n),
        .fmc_nwait_n(fmc_nwait_n), .csr_read_enable(fmc_read_enable),
        .csr_write_enable(fmc_write_enable), .csr_address(fmc_address),
        .csr_write_data(fmc_write_data), .csr_read_valid(csr_read_valid),
        .csr_read_data(csr_read_data)
    );

    csr_bank csr (
        .clk(clk), .reset_n(reset_n), .read_enable(fmc_read_enable),
        .write_enable(fmc_write_enable), .address(fmc_address),
        .write_data(fmc_write_data), .read_valid(csr_read_valid),
        .read_data(csr_read_data), .global_enable(global_enable),
        .soft_reset_pulse(soft_reset_pulse), .start_pulse(start_pulse),
        .stop_pulse(stop_pulse), .running(running), .degraded(degraded),
        .fatal(fatal), .sync_arm_pulse(sync_arm_pulse),
        .sync_fire_pulse(sync_fire_pulse), .sync_channel_mask(sync_channel_mask),
        .sync_epoch(sync_epoch), .sync_armed(sync_armed_reg),
        .sync_locked_mask(sync_locked_mask), .block_ready(block_ready),
        .block_bank(block_ready_bank), .block_length(block_ready_length),
        .block_sequence(block_ready_sequence), .owner_bank0(owner_bank0),
        .owner_bank1(owner_bank1), .block_ack_valid(block_ack_valid),
        .block_ack_value(block_ack_value), .fifo_levels(fifo_levels),
        .fifo_drops(fifo_drops), .parser_good(parser_good),
        .parser_errors(parser_errors),
        .alignment_buffered_mask(alignment_buffered_mask),
        .alignment_emitting(alignment_emitting),
        .aligned_group_count(aligned_group_count),
        .alignment_drop_count(alignment_drop_count),
        .alignment_error_count(alignment_error_count),
        .last_aligned_epoch(last_aligned_epoch),
        .last_aligned_index(last_aligned_index), .irq_status(irq_status),
        .irq_mask(irq_mask), .irq_clear_valid(irq_clear_valid),
        .irq_clear_value(irq_clear_value),
        .irq_mask_write_valid(irq_mask_write_valid),
        .irq_mask_write_value(irq_mask_write_value),
        .bram_read_request(host_read_request), .bram_read_bank(host_read_bank),
        .bram_read_word_address(host_read_word_address),
        .bram_read_valid(host_read_valid), .bram_read_data(host_read_data),
        .bram_claim_valid(host_claim_valid), .bram_claim_bank(host_claim_bank)
    );

    assign host_ack_valid = block_ack_valid;
    assign host_ack_value = block_ack_value;

    assign irq_event_set = {10'd0, fatal, |fifo_almost_full,
                            (|timeout_count) || (|crc_error_count),
                            1'b0, (block_ready && !block_ready_d)};

    irq_ctrl irq (
        .clk(clk), .reset_n(reset_n), .event_set(irq_event_set),
        .clear_valid(irq_clear_valid), .clear_w1c(irq_clear_value),
        .mask_write_valid(irq_mask_write_valid),
        .mask_write_data(irq_mask_write_value), .status(irq_status),
        .mask(irq_mask), .irq(fpga_irq)
    );

    assign status_led = running;

    // Fixed-width probe map. The wrapper marks each bit for Vivado ILA;
    // fields are intentionally stable across dual and four channel images.
    always @* begin
        debug_probe = 288'd0;
        debug_probe[0] = running;
        debug_probe[1] = reset_n;
        debug_probe[5:2] = ACTIVE_CHANNEL_MASK;
        debug_probe[9:6] = spi_drdy;
        debug_probe[13:10] = spi_miso;
        debug_probe[17:14] = spi_sclk;
        debug_probe[21:18] = spi_cs_n;
        debug_probe[25:22] = spi_sync_out;
        debug_probe[29:26] = nrf_reset_n;
        debug_probe[37:30] = debug_state[7:0];
        debug_probe[53:38] = fifo_levels[15:0];
        debug_probe[69:54] = fifo_levels[31:16];
        debug_probe[85:70] = fifo_levels[47:32];
        debug_probe[101:86] = fifo_levels[63:48];
        debug_probe[117:102] = block_ready_length;
        debug_probe[149:118] = block_ready_sequence;
        debug_probe[165:150] = csr_read_data;
        debug_probe[181:166] = fmc_write_data;
        debug_probe[197:182] = fmc_address;
        debug_probe[198] = fmc_read_enable;
        debug_probe[199] = fmc_write_enable;
        debug_probe[200] = block_ready;
        debug_probe[201] = block_ready_bank;
        debug_probe[202] = sync_armed_reg;
        debug_probe[206:203] = sync_locked_mask;
        debug_probe[238:207] = crc_error_count[31:0];
        debug_probe[270:239] = timeout_count[31:0];
        debug_probe[271] = degraded;
        debug_probe[272] = fpga_irq;
        debug_probe[273] = fmc_nwait_n;
        debug_probe[274] = ext_reset_n;
        debug_probe[275] = global_enable;
        debug_probe[276] = sync_arm_pulse;
        debug_probe[277] = sync_fire_pulse;
        debug_probe[278] = start_pulse;
        debug_probe[279] = stop_pulse;
        debug_probe[287:280] = delivered_count[7:0];
    end
endmodule
