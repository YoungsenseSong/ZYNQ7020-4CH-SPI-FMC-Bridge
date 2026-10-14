`timescale 1ns/1ps
`include "protocol_defs.vh"

// Single-channel CSR/data-window endpoint behind fmc_mux_slave.
// Addresses are byte offsets; fmc_mux_slave converts the external word address.
module single_channel_csr_bank (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        read_enable,
    input  wire        write_enable,
    input  wire [15:0] address,
    input  wire [15:0] write_data,
    output reg         read_valid,
    output reg  [15:0] read_data,
    output reg         global_enable,
    output reg         soft_reset_pulse,
    output reg         start_pulse,
    output reg         stop_pulse,
    input  wire        running,
    input  wire        degraded,
    input  wire        fatal,
    input  wire        block_ready,
    input  wire        block_bank,
    input  wire [15:0] block_length,
    input  wire [31:0] block_sequence,
    input  wire [2:0]  owner_bank0,
    input  wire [2:0]  owner_bank1,
    output reg         block_ack_valid,
    output reg  [15:0] block_ack_value,
    output reg         bram_read_request,
    output reg         bram_read_bank,
    output reg  [14:0] bram_read_word_address,
    input  wire        bram_read_valid,
    input  wire [15:0] bram_read_data,
    output reg         bram_claim_valid,
    output reg         bram_claim_bank,
    input  wire [15:0] irq_status,
    input  wire [15:0] irq_mask,
    output reg         irq_clear_valid,
    output reg  [15:0] irq_clear_value,
    output reg         irq_mask_write_valid,
    output reg  [15:0] irq_mask_write_value,
    output reg         clear_stats_pulse,
    output reg         signal_threshold_enable,
    output reg  [15:0] signal_threshold_abs,
    input  wire        stats_valid,
    input  wire        stats_threshold_sticky,
    input  wire [15:0] stats_peak_abs,
    input  wire signed [15:0] stats_mean_signed,
    input  wire [39:0] stats_energy_sum,
    input  wire [7:0]  stats_sample_count,
    input  wire [31:0] stats_record_count,
    input  wire [31:0] stats_threshold_count,
    input  wire [31:0] stats_malformed_count
);
    localparam REG_FPGA_ID       = 16'h0000;
    localparam REG_PROTO_VERSION = 16'h0002;
    localparam REG_BUILD_WORD    = 16'h0004;
    localparam REG_GLOBAL_CTRL   = 16'h0010;
    localparam REG_GLOBAL_STATUS = 16'h0012;
    localparam REG_IRQ_STATUS    = 16'h0020;
    localparam REG_IRQ_MASK      = 16'h0022;
    localparam REG_BLOCK_STATUS  = 16'h0040;
    localparam REG_BLOCK_LEN     = 16'h0042;
    localparam REG_BLOCK_ACK     = 16'h0044;
    localparam REG_SIGNAL_STATUS = 16'h0080;
    localparam REG_SIGNAL_PEAK   = 16'h0082;
    localparam REG_SIGNAL_MEAN   = 16'h0084;
    localparam REG_SIGNAL_EN_LO  = 16'h0086;
    localparam REG_SIGNAL_EN_HI  = 16'h0088;
    localparam REG_SIGNAL_COUNT  = 16'h008A;
    localparam REG_SIGNAL_CTRL   = 16'h0090;
    localparam REG_SIGNAL_REC_LO = 16'h0092;
    localparam REG_SIGNAL_REC_HI = 16'h0094;
    localparam REG_SIGNAL_AL_LO  = 16'h0096;
    localparam REG_SIGNAL_AL_HI  = 16'h0098;
    localparam REG_SIGNAL_BAD_LO = 16'h009A;
    localparam REG_SIGNAL_BAD_HI = 16'h009C;
    localparam REG_DATA_WINDOW   = 16'h1000;
    localparam DATA_WINDOW_END   = 16'h9020;

    reg bram_read_pending;
    reg [15:0] global_status_word;

    always @* begin
        global_status_word = 16'h0000;
        global_status_word[0] = !running;
        global_status_word[1] = running;
        global_status_word[2] = degraded;
        global_status_word[3] = fatal;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            read_valid <= 1'b0;
            read_data <= 16'h0000;
            global_enable <= 1'b0;
            soft_reset_pulse <= 1'b0;
            start_pulse <= 1'b0;
            stop_pulse <= 1'b0;
            block_ack_valid <= 1'b0;
            block_ack_value <= 16'h0000;
            bram_read_request <= 1'b0;
            bram_read_bank <= 1'b0;
            bram_read_word_address <= 15'd0;
            bram_read_pending <= 1'b0;
            bram_claim_valid <= 1'b0;
            bram_claim_bank <= 1'b0;
            irq_clear_valid <= 1'b0;
            irq_clear_value <= 16'h0000;
            irq_mask_write_valid <= 1'b0;
            irq_mask_write_value <= 16'h0000;
            clear_stats_pulse <= 1'b0;
            signal_threshold_enable <= 1'b0;
            signal_threshold_abs <= 16'h4000;
        end else begin
            read_valid <= 1'b0;
            soft_reset_pulse <= 1'b0;
            start_pulse <= 1'b0;
            stop_pulse <= 1'b0;
            block_ack_valid <= 1'b0;
            bram_read_request <= 1'b0;
            bram_claim_valid <= 1'b0;
            irq_clear_valid <= 1'b0;
            irq_mask_write_valid <= 1'b0;
            clear_stats_pulse <= 1'b0;

            if (write_enable) begin
                case (address)
                    REG_GLOBAL_CTRL: begin
                        global_enable <= write_data[0];
                        soft_reset_pulse <= write_data[1];
                        start_pulse <= write_data[2];
                        stop_pulse <= write_data[3];
                    end
                    REG_IRQ_STATUS: begin
                        irq_clear_valid <= 1'b1;
                        irq_clear_value <= write_data;
                    end
                    REG_IRQ_MASK: begin
                        irq_mask_write_valid <= 1'b1;
                        irq_mask_write_value <= write_data;
                    end
                    REG_BLOCK_ACK: begin
                        block_ack_valid <= 1'b1;
                        block_ack_value <= write_data;
                    end
                    REG_SIGNAL_CTRL: begin
                        signal_threshold_enable <= write_data[0];
                        clear_stats_pulse <= write_data[1];
                        signal_threshold_abs <= {write_data[15:2], 2'b00};
                    end
                    default: begin end
                endcase
            end

            if (read_enable && !bram_read_pending) begin
                if ((address >= REG_DATA_WINDOW) && (address < DATA_WINDOW_END)) begin
                    bram_read_request <= 1'b1;
                    bram_read_bank <= block_bank;
                    bram_read_word_address <= (address - REG_DATA_WINDOW) >> 1;
                    bram_read_pending <= 1'b1;
                    bram_claim_valid <= block_ready;
                    bram_claim_bank <= block_bank;
                end else begin
                    read_valid <= 1'b1;
                    case (address)
                        REG_FPGA_ID: read_data <= 16'h5343;
                        REG_PROTO_VERSION: read_data <= `PROTO_VERSION_VALUE;
                        REG_BUILD_WORD: read_data <= 16'h0501;
                        REG_GLOBAL_CTRL: read_data <= {15'd0, global_enable};
                        REG_GLOBAL_STATUS: read_data <= global_status_word;
                        REG_IRQ_STATUS: read_data <= irq_status;
                        REG_IRQ_MASK: read_data <= irq_mask;
                        REG_BLOCK_STATUS: read_data <= {8'd0, owner_bank1, owner_bank0, block_bank, block_ready};
                        REG_BLOCK_LEN: read_data <= block_length;
                        REG_BLOCK_ACK: read_data <= block_sequence[15:0];
                        REG_SIGNAL_STATUS: read_data <= {6'd0, stats_threshold_sticky,
                                                         stats_valid, stats_sample_count};
                        REG_SIGNAL_PEAK: read_data <= stats_peak_abs;
                        REG_SIGNAL_MEAN: read_data <= stats_mean_signed;
                        REG_SIGNAL_EN_LO: read_data <= stats_energy_sum[15:0];
                        REG_SIGNAL_EN_HI: read_data <= stats_energy_sum[31:16];
                        REG_SIGNAL_COUNT: read_data <= {8'd0, stats_sample_count};
                        REG_SIGNAL_CTRL: read_data <= {signal_threshold_abs[15:2],
                                                       1'b0, 1'b0,
                                                       signal_threshold_enable};
                        REG_SIGNAL_REC_LO: read_data <= stats_record_count[15:0];
                        REG_SIGNAL_REC_HI: read_data <= stats_record_count[31:16];
                        REG_SIGNAL_AL_LO: read_data <= stats_threshold_count[15:0];
                        REG_SIGNAL_AL_HI: read_data <= stats_threshold_count[31:16];
                        REG_SIGNAL_BAD_LO: read_data <= stats_malformed_count[15:0];
                        REG_SIGNAL_BAD_HI: read_data <= stats_malformed_count[31:16];
                        default: read_data <= 16'h0000;
                    endcase
                end
            end

            if (bram_read_pending && bram_read_valid) begin
                read_data <= bram_read_data;
                read_valid <= 1'b1;
                bram_read_pending <= 1'b0;
            end
        end
    end
endmodule
