`timescale 1ns/1ps
`include "protocol_defs.vh"

// Complete single-channel digital product path:
// IIM-42352+nRF command SPI -> validated 248-byte records -> signal stats
// sideband -> v0 block builder/ping-pong -> FMC/CSR/IRQ for the F730.
// The record and block wire formats are unchanged.
module single_channel_product_top #(
    parameter integer CLOCK_HZ = 50000000,
    parameter integer DEBUG_AUTONOMOUS = 0,
    parameter integer DEBUG_START_CYCLES = CLOCK_HZ,
    parameter integer SCLK_HZ = 1000000,
    parameter integer AB_GAP_CYCLES = 250000,
    parameter integer CS_INACTIVE_CYCLES = 15,
    parameter integer B_TO_NEXT_A_GAP_CYCLES = 250000,
    parameter integer STARTUP_DELAY_CYCLES = 250000,
    parameter integer RETRY_DELAY_CYCLES = 50000,
    parameter integer SYNC_WIDTH_CYCLES = 50,
    parameter integer FIFO_DEPTH = 16384,
    parameter integer FIFO_ADDR_WIDTH = 14,
    parameter integer FIFO_HIGH_WATER = 14336,
    parameter integer BLOCK_BYTES = 32800,
    parameter integer TARGET_PAYLOAD_BYTES = 16368,
    parameter integer MAX_PAYLOAD_BYTES = 32736,
    parameter [31:0] BLOCK_TIMEOUT_CYCLES = 2000000
) (
    input  wire        pl_clk,
    input  wire        ext_reset_n,
    output wire        nrf_sclk,
    output wire        nrf_mosi,
    input  wire        nrf_miso,
    output wire        nrf_cs_n,
    input  wire        nrf_drdy,
    output wire        nrf_reset_n,
    output wire        nrf_sync_out,
    inout  wire [15:0] fmc_ad,
    input  wire        fmc_nadv_n,
    input  wire        fmc_ne1_n,
    input  wire        fmc_noe_n,
    input  wire        fmc_nwe_n,
    output wire        fmc_nwait_n,
    output wire        fpga_irq,
    output wire        status_led,
    output wire [447:0] debug_probe
);
    wire clk = pl_clk;
    wire reset_n;
    wire soft_reset_pulse;
    wire start_pulse;
    wire stop_pulse;
    wire global_enable;
    reg running;
    reg [63:0] fpga_tick;
    reg block_ready_d;

    wire drdy_sync;
    wire controller_reset_n = reset_n && running;
    wire [7:0] controller_record_data;
    wire controller_record_valid, controller_record_ready, controller_record_last;
    wire [5:0] controller_debug_state;
    wire [31:0] request_count, response_count, last_status, last_transport_seq;
    wire [7:0] last_command;
    wire last_record_valid;
    wire [31:0] crc_ok_count, crc_error_count, commit_ok_count, commit_error_count;
    wire [31:0] bad_commit_reject_count, duplicate_commit_reject_count;
    wire [31:0] timeout_count, envelope_error_count;

    wire [8:0] fifo_in_data = {controller_record_last, controller_record_data};
    wire [8:0] fifo_out_data;
    wire fifo_in_ready, fifo_out_valid, fifo_out_ready;
    wire fifo_almost_full;
    wire [15:0] fifo_level;
    wire [31:0] fifo_blocked_cycles;

    wire proc_out_valid, proc_in_ready, builder_in_ready, proc_out_last;
    wire [7:0] proc_out_data;
    wire stats_valid, stats_threshold_pulse, stats_threshold_sticky;
    wire [15:0] stats_peak_abs;
    wire signed [15:0] stats_mean_signed;
    wire [39:0] stats_energy_sum;
    wire [7:0] stats_sample_count;
    wire [31:0] stats_record_count, stats_threshold_count, stats_malformed_count;
    wire clear_stats_pulse, signal_threshold_enable;
    wire [15:0] signal_threshold_abs;

    wire alloc_request, alloc_grant, alloc_bank;
    wire block_write_valid, block_write_bank;
    wire [15:0] block_write_address;
    wire [7:0] block_write_data;
    wire block_seal_valid, block_seal_bank;
    wire [15:0] block_seal_length;
    wire [31:0] block_seal_sequence, current_block_sequence;

    wire block_ready, block_ready_bank;
    wire [15:0] block_ready_length;
    wire [31:0] block_ready_sequence;
    wire [2:0] owner_bank0, owner_bank1;
    wire bram_read_request, bram_read_bank, bram_read_valid;
    wire [14:0] bram_read_word_address;
    wire [15:0] bram_read_data;
    wire bram_claim_valid, bram_claim_bank;
    wire block_ack_valid;
    wire [15:0] block_ack_value;

    wire fmc_read_enable, fmc_write_enable, csr_read_valid;
    wire [15:0] fmc_address, fmc_write_data, csr_read_data;
    wire irq_clear_valid, irq_mask_write_valid;
    wire [15:0] irq_clear_value, irq_mask_write_value, irq_status, irq_mask;
    wire degraded = (|crc_error_count) || (|commit_error_count) ||
                    (|timeout_count) || (|envelope_error_count) ||
                    (stats_malformed_count != 0);
    wire fatal = 1'b0;
    wire [15:0] irq_event_set = {10'd0, stats_threshold_pulse,
                                 fatal, fifo_almost_full,
                                 ((|timeout_count) || (|crc_error_count)),
                                 1'b0, (block_ready && !block_ready_d)};

    reset_clock_mgr #(.TICK_DIVIDER(1)) clock_mgr (
        .pl_clk(pl_clk), .ext_reset_n(ext_reset_n), .soft_reset(soft_reset_pulse),
        .clk_out(clk), .reset_n(reset_n), .tick_pulse()
    );

    cdc_sync #(.WIDTH(1), .RESET_VALUE(0)) drdy_cdc (
        .clk(clk), .reset_n(reset_n), .async_in(nrf_drdy), .sync_out(drdy_sync)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            running <= 1'b0;
            fpga_tick <= 64'd0;
            block_ready_d <= 1'b0;
        end else begin
            fpga_tick <= fpga_tick + 1'b1;
            block_ready_d <= block_ready;
            if (stop_pulse || soft_reset_pulse)
                running <= 1'b0;
            else if (start_pulse && global_enable)
                running <= 1'b1;
        end
    end

    ch0_spi_controller #(
        .CLOCK_HZ(CLOCK_HZ), .SCLK_HZ(SCLK_HZ),
        .AB_GAP_CYCLES(AB_GAP_CYCLES), .CS_INACTIVE_CYCLES(CS_INACTIVE_CYCLES),
        .B_TO_NEXT_A_GAP_CYCLES(B_TO_NEXT_A_GAP_CYCLES),
        .STARTUP_DELAY_CYCLES(STARTUP_DELAY_CYCLES),
        .RETRY_DELAY_CYCLES(RETRY_DELAY_CYCLES),
        .SYNC_WIDTH_CYCLES(SYNC_WIDTH_CYCLES), .EXERCISE_COMMIT_ERRORS(0)
    ) controller (
        .clk(clk), .reset_n(controller_reset_n), .drdy(drdy_sync),
        .miso(nrf_miso), .sclk(nrf_sclk), .mosi(nrf_mosi), .cs_n(nrf_cs_n),
        .sync_out(nrf_sync_out), .record_data(controller_record_data),
        .record_valid(controller_record_valid), .record_ready(controller_record_ready),
        .record_last(controller_record_last), .debug_state(controller_debug_state),
        .request_count(request_count), .response_count(response_count),
        .last_command(last_command), .last_status(last_status),
        .last_transport_seq(last_transport_seq), .last_record_valid(last_record_valid),
        .crc_ok_count(crc_ok_count), .crc_error_count(crc_error_count),
        .commit_ok_count(commit_ok_count), .commit_error_count(commit_error_count),
        .bad_commit_reject_count(bad_commit_reject_count),
        .duplicate_commit_reject_count(duplicate_commit_reject_count),
        .timeout_count(timeout_count), .envelope_error_count(envelope_error_count)
    );

    record_fifo_bram #(
        .DEPTH(FIFO_DEPTH), .ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .HIGH_WATER(FIFO_HIGH_WATER)
    ) record_fifo (
        .clk(clk), .reset_n(reset_n), .in_data(fifo_in_data),
        .in_valid(controller_record_valid && running), .in_ready(fifo_in_ready),
        .out_data(fifo_out_data), .out_valid(fifo_out_valid),
        .out_ready(fifo_out_ready), .almost_full(fifo_almost_full),
        .level(fifo_level), .blocked_cycles(fifo_blocked_cycles)
    );
    assign controller_record_ready = fifo_in_ready && running;
    assign fifo_out_ready = proc_in_ready;

    single_channel_signal_stats signal_stats (
        .clk(clk), .reset_n(reset_n), .in_data(fifo_out_data[7:0]),
        .in_valid(fifo_out_valid), .in_ready(proc_in_ready),
        .in_last(fifo_out_data[8]), .out_data(proc_out_data),
        .out_valid(proc_out_valid), .out_ready(builder_in_ready),
        .out_last(proc_out_last), .clear_counters(clear_stats_pulse),
        .threshold_enable(signal_threshold_enable),
        .threshold_abs(signal_threshold_abs), .stats_valid(stats_valid),
        .threshold_pulse(stats_threshold_pulse),
        .threshold_sticky(stats_threshold_sticky), .peak_abs(stats_peak_abs),
        .mean_signed(stats_mean_signed), .energy_sum(stats_energy_sum),
        .sample_count(stats_sample_count), .record_count(stats_record_count),
        .threshold_count(stats_threshold_count),
        .malformed_count(stats_malformed_count)
    );

    block_builder #(
        .BLOCK_MAGIC(`BLOCK_MAGIC_VALUE), .PROTOCOL_VERSION(`PROTO_VERSION_VALUE),
        .HEADER_BYTES(`BLOCK_HEADER_BYTES), .RECORD_BYTES(`SPI_RECORD_BYTES),
        .TARGET_PAYLOAD_BYTES(TARGET_PAYLOAD_BYTES), .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES),
        .TIMEOUT_CYCLES(BLOCK_TIMEOUT_CYCLES), .CRC_POLYNOMIAL(`CRC32_POLYNOMIAL),
        .CRC_INITIAL(`CRC32_INITIAL), .CRC_FINAL_XOR(`CRC32_FINAL_XOR)
    ) builder (
        .clk(clk), .reset_n(reset_n), .in_data(proc_out_data), .in_channel(2'd0),
        .in_last(proc_out_last), .in_error(1'b0), .in_valid(proc_out_valid),
        .in_ready(builder_in_ready), .sync_epoch(32'd1), .fpga_tick(fpga_tick),
        .flush(stop_pulse), .alloc_request(alloc_request), .alloc_grant(alloc_grant),
        .alloc_bank(alloc_bank), .write_valid(block_write_valid),
        .write_bank(block_write_bank), .write_address(block_write_address),
        .write_data(block_write_data), .seal_valid(block_seal_valid),
        .seal_bank(block_seal_bank), .seal_length(block_seal_length),
        .seal_sequence(block_seal_sequence), .current_sequence(current_block_sequence)
    );

    block_pingpong_bram #(.TOTAL_BYTES(BLOCK_BYTES), .WORDS(BLOCK_BYTES/2), .ACK_POLICY(1)) storage (
        .clk(clk), .reset_n(reset_n), .alloc_request(alloc_request),
        .alloc_grant(alloc_grant), .alloc_bank(alloc_bank),
        .write_valid(block_write_valid), .write_bank(block_write_bank),
        .write_address(block_write_address), .write_data(block_write_data),
        .seal_valid(block_seal_valid), .seal_bank(block_seal_bank),
        .seal_length(block_seal_length), .seal_sequence(block_seal_sequence),
        .read_request(bram_read_request), .read_bank(bram_read_bank),
        .read_word_address(bram_read_word_address), .read_valid(bram_read_valid),
        .read_data(bram_read_data), .claim_valid(bram_claim_valid),
        .claim_bank(bram_claim_bank), .ack_valid(block_ack_valid),
        .ack_value(block_ack_value), .ready_valid(block_ready),
        .ready_bank(block_ready_bank), .ready_length(block_ready_length),
        .ready_sequence(block_ready_sequence), .owner_bank0(owner_bank0),
        .owner_bank1(owner_bank1)
    );

    gpio_serial_csr fmc (
        .clk(clk), .reset_n(reset_n), .fmc_ad(fmc_ad), .fmc_nadv_n(fmc_nadv_n),
        .fmc_ne1_n(fmc_ne1_n), .fmc_noe_n(fmc_noe_n), .fmc_nwe_n(fmc_nwe_n),
        .fmc_nwait_n(fmc_nwait_n), .csr_read_enable(fmc_read_enable),
        .csr_write_enable(fmc_write_enable), .csr_address(fmc_address),
        .csr_write_data(fmc_write_data), .csr_read_valid(csr_read_valid),
        .csr_read_data(csr_read_data)
    );

    // Diagnostic-only CSR master. It starts via the real CSR contract, claims
    // each sealed block through its data window, then discards it by ACK.
    // External FMC commands are isolated in this mode; no FMC transfer is claimed.
    reg [2:0] dbg_state;
    reg [31:0] dbg_timer, dbg_sequence, dbg_ack_count;
    wire dbg_write = (dbg_state == 1) || (dbg_state == 5);
    wire dbg_read = (dbg_state == 3);
    wire [15:0] dbg_address = (dbg_state == 1) ? 16'h0010 :
                                 (dbg_state == 5) ? 16'h0044 : 16'h1000;
    wire [15:0] dbg_data = (dbg_state == 1) ? 16'h0005 : dbg_sequence[15:0];
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            dbg_state <= 0; dbg_timer <= 0; dbg_sequence <= 0; dbg_ack_count <= 0;
        end else if (DEBUG_AUTONOMOUS) begin
            case (dbg_state)
                0: if (dbg_timer == DEBUG_START_CYCLES-1) dbg_state <= 1;
                   else dbg_timer <= dbg_timer + 1'b1;
                1: dbg_state <= 2;
                2: if (block_ready) begin
                       dbg_sequence <= block_ready_sequence;
                       dbg_state <= 3;
                   end
                3: dbg_state <= 4;
                4: if (csr_read_valid) dbg_state <= 5;
                5: begin dbg_ack_count <= dbg_ack_count + 1'b1; dbg_state <= 6; end
                6: if (!block_ready || block_ready_sequence != dbg_sequence) dbg_state <= 2;
                default: dbg_state <= 0;
            endcase
        end
    end
    single_channel_csr_bank csr (
        .clk(clk), .reset_n(reset_n), .read_enable(DEBUG_AUTONOMOUS ? dbg_read : fmc_read_enable),
        .write_enable(DEBUG_AUTONOMOUS ? dbg_write : fmc_write_enable), .address(DEBUG_AUTONOMOUS ? dbg_address : fmc_address),
        .write_data(DEBUG_AUTONOMOUS ? dbg_data : fmc_write_data), .read_valid(csr_read_valid),
        .read_data(csr_read_data), .global_enable(global_enable),
        .soft_reset_pulse(soft_reset_pulse), .start_pulse(start_pulse),
        .stop_pulse(stop_pulse), .running(running), .degraded(degraded),
        .fatal(fatal), .block_ready(block_ready), .block_bank(block_ready_bank),
        .block_length(block_ready_length), .block_sequence(block_ready_sequence),
        .owner_bank0(owner_bank0), .owner_bank1(owner_bank1),
        .block_ack_valid(block_ack_valid), .block_ack_value(block_ack_value),
        .bram_read_request(bram_read_request), .bram_read_bank(bram_read_bank),
        .bram_read_word_address(bram_read_word_address),
        .bram_read_valid(bram_read_valid), .bram_read_data(bram_read_data),
        .bram_claim_valid(bram_claim_valid), .bram_claim_bank(bram_claim_bank),
        .irq_status(irq_status), .irq_mask(irq_mask),
        .irq_clear_valid(irq_clear_valid), .irq_clear_value(irq_clear_value),
        .irq_mask_write_valid(irq_mask_write_valid),
        .irq_mask_write_value(irq_mask_write_value),
        .clear_stats_pulse(clear_stats_pulse),
        .signal_threshold_enable(signal_threshold_enable),
        .signal_threshold_abs(signal_threshold_abs), .stats_valid(stats_valid),
        .stats_threshold_sticky(stats_threshold_sticky),
        .stats_peak_abs(stats_peak_abs), .stats_mean_signed(stats_mean_signed),
        .stats_energy_sum(stats_energy_sum), .stats_sample_count(stats_sample_count),
        .stats_record_count(stats_record_count),
        .stats_threshold_count(stats_threshold_count),
        .stats_malformed_count(stats_malformed_count)
    );

    irq_ctrl irq (
        .clk(clk), .reset_n(reset_n), .event_set(irq_event_set),
        .clear_valid(irq_clear_valid), .clear_w1c(irq_clear_value),
        .mask_write_valid(irq_mask_write_valid),
        .mask_write_data(irq_mask_write_value), .status(irq_status),
        .mask(irq_mask), .irq(fpga_irq)
    );

    assign nrf_reset_n = controller_reset_n;
    assign status_led = running;

    // Stable, named observability bus for the prototype ILA. The bus contains
    // transport, record/FIFO, block, FMC and error counters; it does not alter
    // the record or block wire formats.
    assign debug_probe = {
        dbg_ack_count[9:0], crc_ok_count, commit_ok_count, stats_record_count,
        last_status, last_command, controller_debug_state, controller_record_data,
        3'd0, fmc_nwait_n, fmc_nwe_n, fmc_noe_n, fmc_ne1_n, fmc_nadv_n, fmc_ad,
        stats_malformed_count[15:0],
        timeout_count[15:0],
        commit_error_count[15:0],
        crc_error_count[15:0],
        response_count,
        request_count,
        block_ready_sequence,
        block_ready_length,
        fifo_level,
        csr_read_data,
        fmc_write_data,
        fmc_address,
        fmc_write_enable, fmc_read_enable,
        bram_claim_valid, bram_read_valid, block_ack_valid,
        block_ready, block_ready_bank,
        builder_in_ready, proc_out_last, proc_out_valid,
        fifo_out_ready, fifo_out_valid,
        drdy_sync, reset_n, running,
        nrf_reset_n, nrf_sync_out, nrf_miso, nrf_mosi, nrf_sclk, nrf_cs_n,
        controller_record_ready, controller_record_last, controller_record_valid
    };
endmodule
