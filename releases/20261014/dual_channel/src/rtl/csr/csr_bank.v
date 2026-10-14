`include "protocol_defs.vh"
`include "build_defs.vh"

module csr_bank (
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
    output reg         sync_arm_pulse,
    output reg         sync_fire_pulse,
    output reg  [3:0]  sync_channel_mask,
    output reg  [31:0] sync_epoch,
    input  wire        sync_armed,
    input  wire [3:0]  sync_locked_mask,
    input  wire        block_ready,
    input  wire        block_bank,
    input  wire [15:0] block_length,
    input  wire [31:0] block_sequence,
    input  wire [2:0]  owner_bank0,
    input  wire [2:0]  owner_bank1,
    output reg         block_ack_valid,
    output reg  [15:0] block_ack_value,
    input  wire [63:0] fifo_levels,
    input  wire [127:0] fifo_drops,
    input  wire [127:0] parser_good,
    input  wire [127:0] parser_errors,
    input  wire [3:0]  alignment_buffered_mask,
    input  wire        alignment_emitting,
    input  wire [31:0] aligned_group_count,
    input  wire [127:0] alignment_drop_count,
    input  wire [31:0] alignment_error_count,
    input  wire [31:0] last_aligned_epoch,
    input  wire [63:0] last_aligned_index,
    input  wire [15:0] irq_status,
    input  wire [15:0] irq_mask,
    output reg         irq_clear_valid,
    output reg  [15:0] irq_clear_value,
    output reg         irq_mask_write_valid,
    output reg  [15:0] irq_mask_write_value,
    output reg         bram_read_request,
    output reg         bram_read_bank,
    output reg  [14:0] bram_read_word_address,
    input  wire        bram_read_valid,
    input  wire [15:0] bram_read_data,
    output reg         bram_claim_valid,
    output reg         bram_claim_bank
);
    localparam REG_FPGA_ID = 16'h0000;
    localparam REG_PROTO_VERSION = 16'h0002;
    localparam REG_BUILD_WORD = 16'h0004;
    localparam REG_GLOBAL_CTRL = 16'h0010;
    localparam REG_GLOBAL_STATUS = 16'h0012;
    localparam REG_IRQ_STATUS = 16'h0020;
    localparam REG_IRQ_MASK = 16'h0022;
    localparam REG_SYNC_CTRL = 16'h0030;
    localparam REG_SYNC_STATUS = 16'h0032;
    localparam REG_BLOCK_STATUS = 16'h0040;
    localparam REG_BLOCK_LEN = 16'h0042;
    localparam REG_BLOCK_ACK = 16'h0044;
    localparam REG_ALIGN_STATUS = 16'h0050;
    localparam REG_ALIGN_GROUP_LO = 16'h0052;
    localparam REG_ALIGN_GROUP_HI = 16'h0054;
    localparam REG_ALIGN_ERROR_LO = 16'h0056;
    localparam REG_ALIGN_ERROR_HI = 16'h0058;
    localparam REG_ALIGN_EPOCH_LO = 16'h005A;
    localparam REG_ALIGN_EPOCH_HI = 16'h005C;
    localparam REG_ALIGN_INDEX_0 = 16'h0060;
    localparam REG_ALIGN_INDEX_1 = 16'h0062;
    localparam REG_ALIGN_INDEX_2 = 16'h0064;
    localparam REG_ALIGN_INDEX_3 = 16'h0066;
    localparam REG_ALIGN_DROP0_LO = 16'h0068;
    localparam REG_ALIGN_DROP0_HI = 16'h006A;
    localparam REG_ALIGN_DROP1_LO = 16'h006C;
    localparam REG_ALIGN_DROP1_HI = 16'h006E;
    localparam REG_ALIGN_DROP2_LO = 16'h0070;
    localparam REG_ALIGN_DROP2_HI = 16'h0072;
    localparam REG_ALIGN_DROP3_LO = 16'h0074;
    localparam REG_ALIGN_DROP3_HI = 16'h0076;
    localparam REG_CHANNEL_BASE = 16'h0100;
    localparam REG_DATA_WINDOW = 16'h1000;
    localparam DATA_WINDOW_END = 16'h9020;

    reg bram_read_pending;
    reg [15:0] global_status_word;
    reg [15:0] channel_read_data;

    always @* begin
        global_status_word = 16'h0000;
        global_status_word[`GLOBAL_STATUS_IDLE_BIT] = !running;
        global_status_word[`GLOBAL_STATUS_RUNNING_BIT] = running;
        global_status_word[`GLOBAL_STATUS_DEGRADED_BIT] = degraded;
        global_status_word[`GLOBAL_STATUS_FATAL_BIT] = fatal;

        channel_read_data = 16'h0000;
        case (address[7:4])
            4'h0: begin
                case (address[3:1])
                    3'd0: channel_read_data = fifo_levels[15:0];
                    3'd1: channel_read_data = fifo_drops[15:0];
                    3'd2: channel_read_data = parser_good[15:0];
                    3'd3: channel_read_data = parser_errors[15:0];
                    default: channel_read_data = 16'h0000;
                endcase
            end
            4'h1: begin
                case (address[3:1])
                    3'd0: channel_read_data = fifo_levels[31:16];
                    3'd1: channel_read_data = fifo_drops[47:32];
                    3'd2: channel_read_data = parser_good[47:32];
                    3'd3: channel_read_data = parser_errors[47:32];
                    default: channel_read_data = 16'h0000;
                endcase
            end
            4'h2: begin
                case (address[3:1])
                    3'd0: channel_read_data = fifo_levels[47:32];
                    3'd1: channel_read_data = fifo_drops[79:64];
                    3'd2: channel_read_data = parser_good[79:64];
                    3'd3: channel_read_data = parser_errors[79:64];
                    default: channel_read_data = 16'h0000;
                endcase
            end
            4'h3: begin
                case (address[3:1])
                    3'd0: channel_read_data = fifo_levels[63:48];
                    3'd1: channel_read_data = fifo_drops[111:96];
                    3'd2: channel_read_data = parser_good[111:96];
                    3'd3: channel_read_data = parser_errors[111:96];
                    default: channel_read_data = 16'h0000;
                endcase
            end
            default: channel_read_data = 16'h0000;
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            read_valid <= 1'b0;
            read_data <= 16'h0000;
            global_enable <= 1'b0;
            soft_reset_pulse <= 1'b0;
            start_pulse <= 1'b0;
            stop_pulse <= 1'b0;
            sync_arm_pulse <= 1'b0;
            sync_fire_pulse <= 1'b0;
            sync_channel_mask <= 4'hF;
            sync_epoch <= 32'd0;
            block_ack_valid <= 1'b0;
            block_ack_value <= 16'h0000;
            irq_clear_valid <= 1'b0;
            irq_clear_value <= 16'h0000;
            irq_mask_write_valid <= 1'b0;
            irq_mask_write_value <= 16'h0000;
            bram_read_request <= 1'b0;
            bram_read_bank <= 1'b0;
            bram_read_word_address <= 15'd0;
            bram_read_pending <= 1'b0;
            bram_claim_valid <= 1'b0;
            bram_claim_bank <= 1'b0;
        end else begin
            read_valid <= 1'b0;
            soft_reset_pulse <= 1'b0;
            start_pulse <= 1'b0;
            stop_pulse <= 1'b0;
            sync_arm_pulse <= 1'b0;
            sync_fire_pulse <= 1'b0;
            block_ack_valid <= 1'b0;
            irq_clear_valid <= 1'b0;
            irq_mask_write_valid <= 1'b0;
            bram_read_request <= 1'b0;
            bram_claim_valid <= 1'b0;

            if (write_enable) begin
                case (address)
                    REG_GLOBAL_CTRL: begin
                        global_enable <= write_data[`GLOBAL_CTRL_ENABLE_BIT];
                        soft_reset_pulse <= write_data[`GLOBAL_CTRL_SOFT_RESET_BIT];
                        start_pulse <= write_data[`GLOBAL_CTRL_START_BIT];
                        stop_pulse <= write_data[`GLOBAL_CTRL_STOP_BIT];
                    end
                    REG_IRQ_STATUS: begin
                        irq_clear_valid <= 1'b1;
                        irq_clear_value <= write_data;
                    end
                    REG_IRQ_MASK: begin
                        irq_mask_write_valid <= 1'b1;
                        irq_mask_write_value <= write_data;
                    end
                    REG_SYNC_CTRL: begin
                        sync_channel_mask <= write_data[3:0];
                        sync_arm_pulse <= write_data[8];
                        sync_fire_pulse <= write_data[9];
                        if (write_data[9])
                            sync_epoch <= sync_epoch + 1'b1;
                    end
                    REG_BLOCK_ACK: begin
                        block_ack_valid <= 1'b1;
                        block_ack_value <= write_data;
                    end
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
                        REG_FPGA_ID: read_data <= `FPGA_ID_VALUE;
                        REG_PROTO_VERSION: read_data <= `PROTO_VERSION_VALUE;
                        REG_BUILD_WORD: read_data <= `BUILD_WORD_VALUE;
                        REG_GLOBAL_CTRL: read_data <= {15'd0, global_enable};
                        REG_GLOBAL_STATUS: read_data <= global_status_word;
                        REG_IRQ_STATUS: read_data <= irq_status;
                        REG_IRQ_MASK: read_data <= irq_mask;
                        REG_SYNC_CTRL: read_data <= {6'd0, 2'b00, 4'd0, sync_channel_mask};
                        REG_SYNC_STATUS: read_data <= {7'd0, sync_armed, 4'd0, sync_locked_mask};
                        REG_BLOCK_STATUS: read_data <= {8'd0, owner_bank1, owner_bank0, block_bank, block_ready};
                        REG_BLOCK_LEN: read_data <= block_length;
                        REG_BLOCK_ACK: read_data <= block_ack_value;
                        REG_ALIGN_STATUS: read_data <= {7'd0, alignment_emitting, 4'd0, alignment_buffered_mask};
                        REG_ALIGN_GROUP_LO: read_data <= aligned_group_count[15:0];
                        REG_ALIGN_GROUP_HI: read_data <= aligned_group_count[31:16];
                        REG_ALIGN_ERROR_LO: read_data <= alignment_error_count[15:0];
                        REG_ALIGN_ERROR_HI: read_data <= alignment_error_count[31:16];
                        REG_ALIGN_EPOCH_LO: read_data <= last_aligned_epoch[15:0];
                        REG_ALIGN_EPOCH_HI: read_data <= last_aligned_epoch[31:16];
                        REG_ALIGN_INDEX_0: read_data <= last_aligned_index[15:0];
                        REG_ALIGN_INDEX_1: read_data <= last_aligned_index[31:16];
                        REG_ALIGN_INDEX_2: read_data <= last_aligned_index[47:32];
                        REG_ALIGN_INDEX_3: read_data <= last_aligned_index[63:48];
                        REG_ALIGN_DROP0_LO: read_data <= alignment_drop_count[15:0];
                        REG_ALIGN_DROP0_HI: read_data <= alignment_drop_count[31:16];
                        REG_ALIGN_DROP1_LO: read_data <= alignment_drop_count[47:32];
                        REG_ALIGN_DROP1_HI: read_data <= alignment_drop_count[63:48];
                        REG_ALIGN_DROP2_LO: read_data <= alignment_drop_count[79:64];
                        REG_ALIGN_DROP2_HI: read_data <= alignment_drop_count[95:80];
                        REG_ALIGN_DROP3_LO: read_data <= alignment_drop_count[111:96];
                        REG_ALIGN_DROP3_HI: read_data <= alignment_drop_count[127:112];
                        default: begin
                            if ((address >= REG_CHANNEL_BASE) && (address < 16'h0140))
                                read_data <= channel_read_data;
                            else
                                read_data <= 16'h0000;
                        end
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
