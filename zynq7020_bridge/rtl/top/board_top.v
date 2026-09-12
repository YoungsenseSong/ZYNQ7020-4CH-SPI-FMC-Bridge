`include "protocol_defs.vh"

module board_top #(
    parameter PL_CLOCK_HZ = 50000000,
    parameter TICK_DIVIDER = 50,
    parameter [3:0] ACTIVE_CHANNEL_MASK = 4'b0001,
    parameter FIFO_DEPTH = 16384,
    parameter FIFO_ADDR_WIDTH = 14,
    parameter FIFO_HIGH_WATER = 14336
) (
    input  wire        pl_clk,
    input  wire        ext_reset_n,
    output wire [3:0]  spi_sclk,
    output wire [3:0]  spi_mosi,
    input  wire [3:0]  spi_miso,
    output wire [3:0]  spi_cs_n,
    input  wire [3:0]  spi_drdy,
    output wire [3:0]  nrf_reset_n,
    output wire [3:0]  sync_out,
    input  wire [3:0]  nrf_sync_ready,
    inout  wire [15:0] fmc_ad,
    input  wire        fmc_nadv_n,
    input  wire        fmc_ne1_n,
    input  wire        fmc_noe_n,
    input  wire        fmc_nwe_n,
    output wire        fmc_nwait_n,
    output wire        fpga_irq,
    output wire        status_led
);
    wire clk;
    wire reset_n;
    wire soft_reset_pulse;
    wire tick_pulse;
    reg [63:0] fpga_tick;

    wire global_enable;
    wire start_pulse;
    wire stop_pulse;
    reg running;
    wire degraded;
    wire fatal = 1'b0;

    wire sync_arm_pulse;
    wire sync_fire_pulse;
    wire [3:0] sync_channel_mask;
    wire [31:0] sync_epoch;
    wire sync_armed;
    wire sync_sent_pulse;
    wire [3:0] sync_ready_mask;
    wire [3:0] sync_locked_mask;
    wire [31:0] sync_active_epoch;

    wire [3:0] drdy_sync;
    wire [3:0] spi_start;
    wire [3:0] spi_busy;
    wire [3:0] spi_done;
    wire [3:0] spi_timeout;
    wire [31:0] spi_byte_data;
    wire [3:0] spi_byte_valid;
    wire [3:0] spi_byte_ready;

    wire [3:0] parser_busy;
    wire [31:0] parser_out_data;
    wire [3:0] parser_out_valid;
    wire [3:0] parser_out_last;
    wire [3:0] parser_out_ready;
    wire [3:0] parser_done;
    wire [3:0] parser_error;
    wire [127:0] parser_good_count;
    wire [127:0] parser_error_count;

    wire [39:0] fifo_in_data;
    wire [3:0] fifo_in_ready;
    wire [39:0] fifo_out_data;
    wire [3:0] fifo_out_valid;
    wire [3:0] fifo_out_ready;
    wire [3:0] fifo_almost_full;
    wire [63:0] fifo_levels;
    wire [127:0] fifo_drop_count;

    wire [7:0] scheduled_data;
    wire [1:0] scheduled_channel;
    wire scheduled_last;
    wire scheduled_error;
    wire scheduled_valid;
    wire scheduled_ready;
    wire [3:0] alignment_buffered_mask;
    wire alignment_emitting;
    wire [31:0] aligned_group_count;
    wire [127:0] alignment_drop_count;
    wire [31:0] alignment_error_count;
    wire [31:0] last_aligned_epoch;
    wire [63:0] last_aligned_index;

    wire alloc_request;
    wire alloc_grant;
    wire alloc_bank;
    wire block_write_valid;
    wire block_write_bank;
    wire [15:0] block_write_address;
    wire [7:0] block_write_data;
    wire block_seal_valid;
    wire block_seal_bank;
    wire [15:0] block_seal_length;
    wire [31:0] block_seal_sequence;
    wire [31:0] current_block_sequence;

    wire block_ready;
    wire block_ready_bank;
    wire [15:0] block_ready_length;
    wire [31:0] block_ready_sequence;
    wire [2:0] owner_bank0;
    wire [2:0] owner_bank1;
    reg block_ready_d;

    wire bram_read_request;
    wire bram_read_bank;
    wire [14:0] bram_read_word_address;
    wire bram_read_valid;
    wire [15:0] bram_read_data;
    wire bram_claim_valid;
    wire bram_claim_bank;
    wire block_ack_valid;
    wire [15:0] block_ack_value;

    wire fmc_csr_read_enable;
    wire fmc_csr_write_enable;
    wire [15:0] fmc_csr_address;
    wire [15:0] fmc_csr_write_data;
    wire csr_read_valid;
    wire [15:0] csr_read_data;

    wire [15:0] irq_event_set;
    wire [15:0] irq_status;
    wire [15:0] irq_mask;
    wire irq_clear_valid;
    wire [15:0] irq_clear_value;
    wire irq_mask_write_valid;
    wire [15:0] irq_mask_write_value;

    reset_clock_mgr #(.TICK_DIVIDER(TICK_DIVIDER)) clock_mgr (
        .pl_clk(pl_clk), .ext_reset_n(ext_reset_n), .soft_reset(soft_reset_pulse),
        .clk_out(clk), .reset_n(reset_n), .tick_pulse(tick_pulse)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fpga_tick <= 64'd0;
            running <= 1'b0;
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

    cdc_sync #(.WIDTH(4), .RESET_VALUE(0)) drdy_sync_inst (
        .clk(clk), .reset_n(reset_n), .async_in(spi_drdy), .sync_out(drdy_sync)
    );
    cdc_sync #(.WIDTH(4), .RESET_VALUE(0)) sync_ready_sync_inst (
        .clk(clk), .reset_n(reset_n), .async_in(nrf_sync_ready), .sync_out(sync_ready_mask)
    );

    sync_pulse_gen sync_generator (
        .clk(clk), .reset_n(reset_n), .arm_pulse(sync_arm_pulse),
        .fire_pulse(sync_fire_pulse), .channel_mask(sync_channel_mask),
        .epoch_value(sync_epoch), .delay_cycles(32'd0), .width_cycles(16'd10),
        .ready_mask(sync_ready_mask), .sync_out(sync_out), .armed(sync_armed),
        .sent_pulse(sync_sent_pulse), .active_epoch(sync_active_epoch),
        .locked_mask(sync_locked_mask)
    );

    assign spi_start = {4{running}} & ACTIVE_CHANNEL_MASK & drdy_sync &
                       ~spi_busy & ~parser_busy & ~fifo_almost_full;
    assign nrf_reset_n = {4{reset_n}};
    assign status_led = running;

    genvar channel;
    generate
        for (channel = 0; channel < 4; channel = channel + 1) begin : channel_path
            spi_master_ch spi_master (
                .clk(clk), .reset_n(reset_n), .start(spi_start[channel]),
                .command(`SPI_READ_COMMAND), .read_length(`SPI_RECORD_BYTES),
                .sclk_divider(`SPI_SCLK_DIVIDER), .timeout_cycles(`SPI_TIMEOUT_CYCLES),
                .miso(spi_miso[channel]), .sclk(spi_sclk[channel]),
                .mosi(spi_mosi[channel]), .cs_n(spi_cs_n[channel]),
                .busy(spi_busy[channel]), .done_pulse(spi_done[channel]),
                .timeout_pulse(spi_timeout[channel]),
                .byte_data(spi_byte_data[channel*8 +: 8]),
                .byte_valid(spi_byte_valid[channel]),
                .byte_ready(spi_byte_ready[channel])
            );

            spi_record_parser #(
                .MAX_RECORD_BYTES(512), .RECORD_BYTES(`SPI_RECORD_BYTES),
                .CHECK_MAGIC(`SPI_CHECK_MAGIC), .MAGIC_VALUE(`SPI_MAGIC_VALUE),
                .VERSION_VALUE(`SPI_RECORD_VERSION),
                .RECORD_TYPE_VALUE(`SPI_RECORD_TYPE),
                .PAYLOAD_BYTES(`SPI_RECORD_PAYLOAD_BYTES),
                .CHECK_CRC(`SPI_CHECK_CRC),
                .CRC16_POLYNOMIAL(`CRC16_POLYNOMIAL),
                .CRC16_INITIAL(`CRC16_INITIAL),
                .CRC16_FINAL_XOR(`CRC16_FINAL_XOR),
                .CRC32_POLYNOMIAL(`CRC32_POLYNOMIAL),
                .CRC32_INITIAL(`CRC32_INITIAL),
                .CRC32_FINAL_XOR(`CRC32_FINAL_XOR)
            ) parser (
                .clk(clk), .reset_n(reset_n), .start(spi_start[channel]),
                .expected_length(`SPI_RECORD_BYTES),
                .in_data(spi_byte_data[channel*8 +: 8]),
                .in_valid(spi_byte_valid[channel]),
                .in_ready(spi_byte_ready[channel]),
                .out_data(parser_out_data[channel*8 +: 8]),
                .out_valid(parser_out_valid[channel]),
                .out_ready(parser_out_ready[channel]),
                .out_last(parser_out_last[channel]),
                .record_done_pulse(parser_done[channel]),
                .record_error_pulse(parser_error[channel]),
                .good_count(parser_good_count[channel*32 +: 32]),
                .error_count(parser_error_count[channel*32 +: 32]),
                .busy(parser_busy[channel])
            );

            assign fifo_in_data[channel*10 +: 10] =
                {1'b0, parser_out_last[channel], parser_out_data[channel*8 +: 8]};
            assign parser_out_ready[channel] = fifo_in_ready[channel];

            channel_fifo_wrap #(
                .DATA_WIDTH(10), .DEPTH(FIFO_DEPTH),
                .ADDR_WIDTH(FIFO_ADDR_WIDTH), .HIGH_WATER(FIFO_HIGH_WATER)
            ) channel_fifo (
                .clk(clk), .reset_n(reset_n),
                .in_data(fifo_in_data[channel*10 +: 10]),
                .in_valid(parser_out_valid[channel]),
                .in_ready(fifo_in_ready[channel]),
                .out_data(fifo_out_data[channel*10 +: 10]),
                .out_valid(fifo_out_valid[channel]),
                .out_ready(fifo_out_ready[channel]),
                .almost_full(fifo_almost_full[channel]),
                .level(fifo_levels[channel*16 +: 16]),
                .drop_count(fifo_drop_count[channel*32 +: 32])
            );
        end
    endgenerate

    four_channel_record_aligner #(
        .RECORD_BYTES(`SPI_RECORD_BYTES),
        .ACTIVE_CHANNEL_MASK(ACTIVE_CHANNEL_MASK)
    ) record_aligner (
        .clk(clk), .reset_n(reset_n), .in_data(fifo_out_data),
        .expected_epoch(sync_active_epoch), .in_valid(fifo_out_valid),
        .in_ready(fifo_out_ready), .out_data(scheduled_data),
        .out_channel(scheduled_channel), .out_last(scheduled_last),
        .out_error(scheduled_error), .out_valid(scheduled_valid),
        .out_ready(scheduled_ready),
        .buffered_mask(alignment_buffered_mask),
        .emitting(alignment_emitting),
        .aligned_group_count(aligned_group_count),
        .stale_drop_count(alignment_drop_count),
        .metadata_error_count(alignment_error_count),
        .last_aligned_epoch(last_aligned_epoch),
        .last_aligned_index(last_aligned_index)
    );

    block_builder #(
        .BLOCK_MAGIC(`BLOCK_MAGIC_VALUE),
        .PROTOCOL_VERSION(`PROTO_VERSION_VALUE),
        .HEADER_BYTES(`BLOCK_HEADER_BYTES),
        .RECORD_BYTES(`SPI_RECORD_BYTES),
        .TARGET_PAYLOAD_BYTES(`BLOCK_TARGET_PAYLOAD_BYTES),
        .MAX_PAYLOAD_BYTES(`BLOCK_MAX_PAYLOAD_BYTES),
        .TIMEOUT_CYCLES(`BLOCK_TIMEOUT_CYCLES),
        .CRC_POLYNOMIAL(`CRC32_POLYNOMIAL),
        .CRC_INITIAL(`CRC32_INITIAL), .CRC_FINAL_XOR(`CRC32_FINAL_XOR)
    ) block_builder_inst (
        .clk(clk), .reset_n(reset_n), .in_data(scheduled_data),
        .in_channel(scheduled_channel), .in_last(scheduled_last),
        .in_error(scheduled_error), .in_valid(scheduled_valid),
        .in_ready(scheduled_ready), .sync_epoch(sync_active_epoch),
        .fpga_tick(fpga_tick), .flush(stop_pulse),
        .alloc_request(alloc_request), .alloc_grant(alloc_grant),
        .alloc_bank(alloc_bank), .write_valid(block_write_valid),
        .write_bank(block_write_bank), .write_address(block_write_address),
        .write_data(block_write_data), .seal_valid(block_seal_valid),
        .seal_bank(block_seal_bank), .seal_length(block_seal_length),
        .seal_sequence(block_seal_sequence),
        .current_sequence(current_block_sequence)
    );

    bram_pingpong #(
        .TOTAL_BYTES(32800), .WORDS(16400), .ACK_POLICY(`BLOCK_ACK_POLICY)
    ) pingpong (
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

    fmc_mux_slave fmc_slave (
        .clk(clk), .reset_n(reset_n), .fmc_ad(fmc_ad),
        .fmc_nadv_n(fmc_nadv_n), .fmc_ne1_n(fmc_ne1_n),
        .fmc_noe_n(fmc_noe_n), .fmc_nwe_n(fmc_nwe_n),
        .fmc_nwait_n(fmc_nwait_n), .csr_read_enable(fmc_csr_read_enable),
        .csr_write_enable(fmc_csr_write_enable), .csr_address(fmc_csr_address),
        .csr_write_data(fmc_csr_write_data), .csr_read_valid(csr_read_valid),
        .csr_read_data(csr_read_data)
    );

    csr_bank csr (
        .clk(clk), .reset_n(reset_n), .read_enable(fmc_csr_read_enable),
        .write_enable(fmc_csr_write_enable), .address(fmc_csr_address),
        .write_data(fmc_csr_write_data), .read_valid(csr_read_valid),
        .read_data(csr_read_data), .global_enable(global_enable),
        .soft_reset_pulse(soft_reset_pulse), .start_pulse(start_pulse),
        .stop_pulse(stop_pulse), .running(running), .degraded(degraded),
        .fatal(fatal), .sync_arm_pulse(sync_arm_pulse),
        .sync_fire_pulse(sync_fire_pulse), .sync_channel_mask(sync_channel_mask),
        .sync_epoch(sync_epoch), .sync_armed(sync_armed),
        .sync_locked_mask(sync_locked_mask), .block_ready(block_ready),
        .block_bank(block_ready_bank), .block_length(block_ready_length),
        .block_sequence(block_ready_sequence), .owner_bank0(owner_bank0),
        .owner_bank1(owner_bank1), .block_ack_valid(block_ack_valid),
        .block_ack_value(block_ack_value), .fifo_levels(fifo_levels),
        .fifo_drops(fifo_drop_count), .parser_good(parser_good_count),
        .parser_errors(parser_error_count),
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
        .bram_read_request(bram_read_request), .bram_read_bank(bram_read_bank),
        .bram_read_word_address(bram_read_word_address),
        .bram_read_valid(bram_read_valid), .bram_read_data(bram_read_data),
        .bram_claim_valid(bram_claim_valid), .bram_claim_bank(bram_claim_bank)
    );

    assign degraded = (|parser_error_count) || (|fifo_drop_count) ||
                      (|spi_timeout) || (|alignment_drop_count) ||
                      (|alignment_error_count);
    assign irq_event_set = {
        10'h000,
        fatal,
        (|fifo_almost_full),
        ((|parser_error) || (|spi_timeout)),
        1'b0,
        sync_sent_pulse,
        (block_ready && !block_ready_d)
    };

    irq_ctrl irq_controller (
        .clk(clk), .reset_n(reset_n), .event_set(irq_event_set),
        .clear_valid(irq_clear_valid), .clear_w1c(irq_clear_value),
        .mask_write_valid(irq_mask_write_valid),
        .mask_write_data(irq_mask_write_value), .status(irq_status),
        .mask(irq_mask), .irq(fpga_irq)
    );
endmodule
