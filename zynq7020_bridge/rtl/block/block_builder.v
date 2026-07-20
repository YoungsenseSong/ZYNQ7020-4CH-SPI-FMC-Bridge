module block_builder #(
    parameter [31:0] BLOCK_MAGIC = 32'h31425046,
    parameter [15:0] PROTOCOL_VERSION = 16'h0000,
    parameter HEADER_BYTES = 64,
    parameter TARGET_PAYLOAD_BYTES = 16384,
    parameter MAX_PAYLOAD_BYTES = 32768,
    parameter [31:0] TIMEOUT_CYCLES = 32'd2000000,
    parameter [31:0] CRC_POLYNOMIAL = 32'h04C11DB7,
    parameter [31:0] CRC_INITIAL = 32'hFFFFFFFF,
    parameter [31:0] CRC_FINAL_XOR = 32'hFFFFFFFF
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [7:0]  in_data,
    input  wire [1:0]  in_channel,
    input  wire        in_last,
    input  wire        in_error,
    input  wire        in_valid,
    output wire        in_ready,
    input  wire [31:0] sync_epoch,
    input  wire [63:0] fpga_tick,
    input  wire        flush,
    output wire        alloc_request,
    input  wire        alloc_grant,
    input  wire        alloc_bank,
    output reg         write_valid,
    output reg         write_bank,
    output reg  [15:0] write_address,
    output reg  [7:0]  write_data,
    output reg         seal_valid,
    output reg         seal_bank,
    output reg  [15:0] seal_length,
    output reg  [31:0] seal_sequence,
    output reg  [31:0] current_sequence
);
    localparam STATE_ALLOC = 3'd0;
    localparam STATE_COLLECT = 3'd1;
    localparam STATE_HEADER = 3'd2;
    localparam STATE_SEAL = 3'd3;

    reg [2:0] state;
    reg active_bank;
    reg [15:0] payload_count;
    reg [31:0] timeout_count;
    reg [5:0] header_index;
    reg [3:0] channel_mask;
    reg [63:0] first_tick;
    reg [63:0] last_tick;
    reg [31:0] record_count0;
    reg [31:0] record_count1;
    reg [31:0] record_count2;
    reg [31:0] record_count3;
    reg [31:0] flags;
    reg [31:0] crc_reg;
    reg at_record_boundary;

    wire stream_accept = in_valid && in_ready;
    wire [31:0] crc_after_byte = crc_next_byte(crc_reg, in_data);
    wire [31:0] final_crc = crc_reg ^ CRC_FINAL_XOR;
    wire target_reached = (payload_count + 1'b1 >= TARGET_PAYLOAD_BYTES);
    wire maximum_reached = (payload_count + 1'b1 >= MAX_PAYLOAD_BYTES);

    function [31:0] crc_next_byte;
        input [31:0] current_crc;
        input [7:0] next_data;
        reg [31:0] value;
        integer index;
        begin
            value = current_crc ^ {next_data, 24'h000000};
            for (index = 0; index < 8; index = index + 1)
                value = value[31] ? ((value << 1) ^ CRC_POLYNOMIAL)
                                  : (value << 1);
            crc_next_byte = value;
        end
    endfunction

    function [7:0] header_byte;
        input [5:0] index;
        begin
            case (index)
                0: header_byte = BLOCK_MAGIC[7:0];
                1: header_byte = BLOCK_MAGIC[15:8];
                2: header_byte = BLOCK_MAGIC[23:16];
                3: header_byte = BLOCK_MAGIC[31:24];
                4: header_byte = PROTOCOL_VERSION[7:0];
                5: header_byte = PROTOCOL_VERSION[15:8];
                6: header_byte = HEADER_BYTES[7:0];
                7: header_byte = HEADER_BYTES[15:8];
                8: header_byte = current_sequence[7:0];
                9: header_byte = current_sequence[15:8];
                10: header_byte = current_sequence[23:16];
                11: header_byte = current_sequence[31:24];
                12: header_byte = sync_epoch[7:0];
                13: header_byte = sync_epoch[15:8];
                14: header_byte = sync_epoch[23:16];
                15: header_byte = sync_epoch[31:24];
                16: header_byte = payload_count[7:0];
                17: header_byte = payload_count[15:8];
                18: header_byte = 8'h00;
                19: header_byte = 8'h00;
                20: header_byte = channel_mask;
                21,22,23: header_byte = 8'h00;
                24: header_byte = first_tick[7:0];
                25: header_byte = first_tick[15:8];
                26: header_byte = first_tick[23:16];
                27: header_byte = first_tick[31:24];
                28: header_byte = first_tick[39:32];
                29: header_byte = first_tick[47:40];
                30: header_byte = first_tick[55:48];
                31: header_byte = first_tick[63:56];
                32: header_byte = last_tick[7:0];
                33: header_byte = last_tick[15:8];
                34: header_byte = last_tick[23:16];
                35: header_byte = last_tick[31:24];
                36: header_byte = last_tick[39:32];
                37: header_byte = last_tick[47:40];
                38: header_byte = last_tick[55:48];
                39: header_byte = last_tick[63:56];
                40: header_byte = record_count0[7:0];
                41: header_byte = record_count0[15:8];
                42: header_byte = record_count0[23:16];
                43: header_byte = record_count0[31:24];
                44: header_byte = record_count1[7:0];
                45: header_byte = record_count1[15:8];
                46: header_byte = record_count1[23:16];
                47: header_byte = record_count1[31:24];
                48: header_byte = record_count2[7:0];
                49: header_byte = record_count2[15:8];
                50: header_byte = record_count2[23:16];
                51: header_byte = record_count2[31:24];
                52: header_byte = record_count3[7:0];
                53: header_byte = record_count3[15:8];
                54: header_byte = record_count3[23:16];
                55: header_byte = record_count3[31:24];
                56: header_byte = flags[7:0];
                57: header_byte = flags[15:8];
                58: header_byte = flags[23:16];
                59: header_byte = flags[31:24];
                60: header_byte = final_crc[7:0];
                61: header_byte = final_crc[15:8];
                62: header_byte = final_crc[23:16];
                63: header_byte = final_crc[31:24];
                default: header_byte = 8'h00;
            endcase
        end
    endfunction

    assign alloc_request = (state == STATE_ALLOC);
    assign in_ready = (state == STATE_COLLECT) && (payload_count < MAX_PAYLOAD_BYTES);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= STATE_ALLOC;
            active_bank <= 1'b0;
            payload_count <= 16'd0;
            timeout_count <= 32'd0;
            header_index <= 6'd0;
            channel_mask <= 4'd0;
            first_tick <= 64'd0;
            last_tick <= 64'd0;
            record_count0 <= 32'd0;
            record_count1 <= 32'd0;
            record_count2 <= 32'd0;
            record_count3 <= 32'd0;
            flags <= 32'd0;
            crc_reg <= CRC_INITIAL;
            at_record_boundary <= 1'b1;
            write_valid <= 1'b0;
            write_bank <= 1'b0;
            write_address <= 16'd0;
            write_data <= 8'd0;
            seal_valid <= 1'b0;
            seal_bank <= 1'b0;
            seal_length <= 16'd0;
            seal_sequence <= 32'd0;
            current_sequence <= 32'd0;
        end else begin
            write_valid <= 1'b0;
            seal_valid <= 1'b0;

            case (state)
                STATE_ALLOC: begin
                    if (alloc_grant) begin
                        active_bank <= alloc_bank;
                        payload_count <= 16'd0;
                        timeout_count <= 32'd0;
                        channel_mask <= 4'd0;
                        first_tick <= 64'd0;
                        last_tick <= 64'd0;
                        record_count0 <= 32'd0;
                        record_count1 <= 32'd0;
                        record_count2 <= 32'd0;
                        record_count3 <= 32'd0;
                        flags <= 32'd0;
                        crc_reg <= CRC_INITIAL;
                        at_record_boundary <= 1'b1;
                        state <= STATE_COLLECT;
                    end
                end
                STATE_COLLECT: begin
                    if (payload_count != 0)
                        timeout_count <= timeout_count + 1'b1;

                    if (stream_accept) begin
                        write_valid <= 1'b1;
                        write_bank <= active_bank;
                        write_address <= HEADER_BYTES + payload_count;
                        write_data <= in_data;
                        payload_count <= payload_count + 1'b1;
                        last_tick <= fpga_tick;
                        crc_reg <= crc_after_byte;
                        channel_mask[in_channel] <= 1'b1;
                        at_record_boundary <= in_last;
                        if (payload_count == 0)
                            first_tick <= fpga_tick;
                        if (in_error)
                            flags[0] <= 1'b1;
                        if (in_last) begin
                            case (in_channel)
                                2'd0: record_count0 <= record_count0 + 1'b1;
                                2'd1: record_count1 <= record_count1 + 1'b1;
                                2'd2: record_count2 <= record_count2 + 1'b1;
                                2'd3: record_count3 <= record_count3 + 1'b1;
                            endcase
                        end
                        if ((in_last && target_reached) || maximum_reached) begin
                            if (maximum_reached && !in_last)
                                flags[1] <= 1'b1;
                            header_index <= 6'd0;
                            state <= STATE_HEADER;
                        end
                    end else if (flush && (payload_count != 0)) begin
                        if (!at_record_boundary)
                            flags[2] <= 1'b1;
                        header_index <= 6'd0;
                        state <= STATE_HEADER;
                    end else if ((TIMEOUT_CYCLES != 0) &&
                                 (timeout_count >= TIMEOUT_CYCLES) &&
                                 at_record_boundary && (payload_count != 0)) begin
                        flags[3] <= 1'b1;
                        header_index <= 6'd0;
                        state <= STATE_HEADER;
                    end
                end
                STATE_HEADER: begin
                    write_valid <= 1'b1;
                    write_bank <= active_bank;
                    write_address <= header_index;
                    write_data <= header_byte(header_index);
                    if (header_index == HEADER_BYTES - 1) begin
                        state <= STATE_SEAL;
                    end else begin
                        header_index <= header_index + 1'b1;
                    end
                end
                STATE_SEAL: begin
                    seal_valid <= 1'b1;
                    seal_bank <= active_bank;
                    seal_length <= HEADER_BYTES + payload_count;
                    seal_sequence <= current_sequence;
                    current_sequence <= current_sequence + 1'b1;
                    state <= STATE_ALLOC;
                end
                default: state <= STATE_ALLOC;
            endcase
        end
    end
endmodule
