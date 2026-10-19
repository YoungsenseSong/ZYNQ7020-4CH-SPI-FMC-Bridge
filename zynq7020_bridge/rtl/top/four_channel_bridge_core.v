`timescale 1ns/1ps
`include "protocol_defs.vh"
// Portable digital bridge. host_* are synchronous internal interfaces, NOT pins.
// The physical WCH FSMC/CSR adapter, board clocks/pins and wireless timing are separate.
module four_channel_bridge_core #(
    parameter integer CLOCK_HZ=50000000, SCLK_HZ=1000000,
    parameter integer AB_GAP_CYCLES=250000, CS_INACTIVE_CYCLES=15,
    parameter integer B_TO_NEXT_A_GAP_CYCLES=250000, STARTUP_DELAY_CYCLES=250000,
    parameter integer RETRY_DELAY_CYCLES=50000, SYNC_WIDTH_CYCLES=50,
    parameter integer FIFO_DEPTH=16384, FIFO_ADDR_WIDTH=14, FIFO_HIGH_WATER=14336,
    parameter integer BLOCK_BYTES=32800,
    parameter integer TARGET_PAYLOAD_BYTES=16368,
    parameter integer MAX_PAYLOAD_BYTES=32736,
    parameter [31:0] BLOCK_TIMEOUT_CYCLES=2000000,
    parameter [3:0] ACTIVE_CHANNEL_MASK=4'b1111
) (
    input wire clk, reset_n,
    input wire [3:0] spi_drdy, spi_miso,
    output wire [3:0] spi_sclk, spi_mosi, spi_cs_n, sync_out,
    input wire flush,
    input wire host_read_request, host_read_bank,
    input wire [14:0] host_read_word_address,
    output wire host_read_valid,
    output wire [15:0] host_read_data,
    input wire host_claim_valid, host_claim_bank, host_ack_valid,
    input wire [15:0] host_ack_value,
    output wire block_ready, block_ready_bank,
    output wire [15:0] block_ready_length,
    output wire [31:0] block_ready_sequence,
    output wire [2:0] owner_bank0, owner_bank1,
    output wire [23:0] debug_state,
    output wire [127:0] crc_error_count, commit_ok_count, commit_error_count,
    output wire [127:0] timeout_count, envelope_error_count, delivered_count,
    output wire [63:0] fifo_levels,
    output wire [3:0] fifo_almost_full,
    output wire [127:0] fifo_blocked_cycles,
    output wire degraded
);
    wire [7:0] record_data;
    wire [1:0] record_channel;
    wire record_valid, record_last, record_ready;
    four_channel_capture_core #(
        .CLOCK_HZ(CLOCK_HZ),.SCLK_HZ(SCLK_HZ),.AB_GAP_CYCLES(AB_GAP_CYCLES),
        .CS_INACTIVE_CYCLES(CS_INACTIVE_CYCLES),.B_TO_NEXT_A_GAP_CYCLES(B_TO_NEXT_A_GAP_CYCLES),
        .STARTUP_DELAY_CYCLES(STARTUP_DELAY_CYCLES),.RETRY_DELAY_CYCLES(RETRY_DELAY_CYCLES),
        .SYNC_WIDTH_CYCLES(SYNC_WIDTH_CYCLES),.FIFO_DEPTH(FIFO_DEPTH),.FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .FIFO_HIGH_WATER(FIFO_HIGH_WATER),.ACTIVE_CHANNEL_MASK(ACTIVE_CHANNEL_MASK)
    ) capture(.clk(clk),.reset_n(reset_n),.spi_drdy(spi_drdy),.spi_miso(spi_miso),
        .spi_sclk(spi_sclk),.spi_mosi(spi_mosi),.spi_cs_n(spi_cs_n),.sync_out(sync_out),
        .record_data(record_data),.record_channel(record_channel),.record_valid(record_valid),
        .record_last(record_last),.record_ready(record_ready),.debug_state(debug_state),
        .crc_error_count(crc_error_count),.commit_ok_count(commit_ok_count),.commit_error_count(commit_error_count),
        .timeout_count(timeout_count),.envelope_error_count(envelope_error_count),.delivered_count(delivered_count),
        .fifo_levels(fifo_levels),.fifo_almost_full(fifo_almost_full),.fifo_blocked_cycles(fifo_blocked_cycles));
    reg [63:0] fpga_tick;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) fpga_tick<=0; else fpga_tick<=fpga_tick+1'b1;
    end
    wire alloc_request,alloc_grant,alloc_bank,write_valid,write_bank,seal_valid,seal_bank;
    wire [15:0] write_address,seal_length;
    wire [7:0] write_data;
    wire [31:0] seal_sequence,current_sequence;
    // Header epoch=1 matches the inherited controller's ARM_SYNC epoch.
    // It is not a globally unique restart/session identity or a sample timestamp.
    block_builder #(.BLOCK_MAGIC(`BLOCK_MAGIC_VALUE),.PROTOCOL_VERSION(`PROTO_VERSION_VALUE),
        .TARGET_PAYLOAD_BYTES(TARGET_PAYLOAD_BYTES),.MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES),
        .TIMEOUT_CYCLES(BLOCK_TIMEOUT_CYCLES)) builder(
        .clk(clk),.reset_n(reset_n),.in_data(record_data),.in_channel(record_channel),.in_last(record_last),
        .in_error(1'b0),.in_valid(record_valid),.in_ready(record_ready),.sync_epoch(32'd1),
        .fpga_tick(fpga_tick),.flush(flush),.alloc_request(alloc_request),.alloc_grant(alloc_grant),
        .alloc_bank(alloc_bank),.write_valid(write_valid),.write_bank(write_bank),.write_address(write_address),
        .write_data(write_data),.seal_valid(seal_valid),.seal_bank(seal_bank),.seal_length(seal_length),
        .seal_sequence(seal_sequence),.current_sequence(current_sequence));
    block_pingpong_bram #(.TOTAL_BYTES(BLOCK_BYTES),.WORDS(BLOCK_BYTES/2),.ACK_POLICY(`BLOCK_ACK_POLICY)) storage(
        .clk(clk),.reset_n(reset_n),.alloc_request(alloc_request),.alloc_grant(alloc_grant),.alloc_bank(alloc_bank),
        .write_valid(write_valid),.write_bank(write_bank),.write_address(write_address),.write_data(write_data),
        .seal_valid(seal_valid),.seal_bank(seal_bank),.seal_length(seal_length),.seal_sequence(seal_sequence),
        .read_request(host_read_request),.read_bank(host_read_bank),.read_word_address(host_read_word_address),
        .read_valid(host_read_valid),.read_data(host_read_data),.claim_valid(host_claim_valid),
        .claim_bank(host_claim_bank),.ack_valid(host_ack_valid),.ack_value(host_ack_value),
        .ready_valid(block_ready),.ready_bank(block_ready_bank),.ready_length(block_ready_length),
        .ready_sequence(block_ready_sequence),.owner_bank0(owner_bank0),.owner_bank1(owner_bank1));
    assign degraded=(|crc_error_count) || (|commit_error_count) || (|timeout_count) || (|envelope_error_count);
    initial begin
        if(TARGET_PAYLOAD_BYTES%248!=0 || MAX_PAYLOAD_BYTES%248!=0 ||
           TARGET_PAYLOAD_BYTES>MAX_PAYLOAD_BYTES || MAX_PAYLOAD_BYTES+64>BLOCK_BYTES)
            $error("invalid four_channel_bridge_core block parameters");
    end
endmodule
