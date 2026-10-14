`timescale 1ns/1ps

module spi_record_parser #(
    parameter MAX_RECORD_BYTES = 512,
    parameter RECORD_BYTES = 248,
    parameter CHECK_MAGIC = 1,
    parameter [31:0] MAGIC_VALUE = 32'h3146524E,
    parameter [7:0] VERSION_VALUE = 8'd1,
    parameter [15:0] RECORD_TYPE_VALUE = 16'd1,
    parameter [15:0] PAYLOAD_BYTES = 16'd204,
    parameter CHECK_CRC = 1,
    parameter [15:0] CRC16_POLYNOMIAL = 16'h1021,
    parameter [15:0] CRC16_INITIAL = 16'hFFFF,
    parameter [15:0] CRC16_FINAL_XOR = 16'h0000,
    parameter [31:0] CRC32_POLYNOMIAL = 32'hEDB88320,
    parameter [31:0] CRC32_INITIAL = 32'hFFFFFFFF,
    parameter [31:0] CRC32_FINAL_XOR = 32'hFFFFFFFF
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    input  wire [15:0] expected_length,
    input  wire [7:0]  in_data,
    input  wire        in_valid,
    output wire        in_ready,
    output wire [7:0]  out_data,
    output wire        out_valid,
    input  wire        out_ready,
    output wire        out_last,
    output reg         record_done_pulse,
    output reg         record_error_pulse,
    output reg  [31:0] good_count,
    output reg  [31:0] error_count,
    output wire        busy
);
    localparam STATE_IDLE = 2'd0;
    localparam STATE_CAPTURE = 2'd1;
    localparam STATE_EMIT = 2'd2;

    localparam HEADER_CRC_START = 16'd38;
    localparam PAYLOAD_START = 16'd40;
    localparam PAYLOAD_CRC_START = PAYLOAD_START + PAYLOAD_BYTES;

    reg [1:0] state;
    reg [7:0] buffer [0:MAX_RECORD_BYTES-1];
    reg [15:0] capture_count;
    reg [15:0] emit_count;
    reg [15:0] active_length;
    reg format_error;
    reg header_crc_error;
    reg [15:0] received_header_crc;
    reg [31:0] received_payload_crc;
    reg [15:0] header_crc_reg;
    reg [31:0] payload_crc_reg;

    wire [7:0] expected_magic_byte =
        (capture_count == 0) ? MAGIC_VALUE[7:0] :
        (capture_count == 1) ? MAGIC_VALUE[15:8] :
        (capture_count == 2) ? MAGIC_VALUE[23:16] : MAGIC_VALUE[31:24];

    wire current_format_error =
        (CHECK_MAGIC && (capture_count < 4) && (in_data != expected_magic_byte)) ||
        ((capture_count == 4) && (in_data != VERSION_VALUE)) ||
        ((capture_count == 6) && (in_data != RECORD_TYPE_VALUE[7:0])) ||
        ((capture_count == 7) && (in_data != RECORD_TYPE_VALUE[15:8])) ||
        ((capture_count == 36) && (in_data != PAYLOAD_BYTES[7:0])) ||
        ((capture_count == 37) && (in_data != PAYLOAD_BYTES[15:8]));

    function [15:0] crc16_next_byte;
        input [15:0] current_crc;
        input [7:0] next_data;
        reg [15:0] value;
        integer index;
        begin
            value = current_crc ^ {next_data, 8'h00};
            for (index = 0; index < 8; index = index + 1)
                value = value[15] ? ((value << 1) ^ CRC16_POLYNOMIAL)
                                  : (value << 1);
            crc16_next_byte = value;
        end
    endfunction

    function [31:0] crc32_next_byte;
        input [31:0] current_crc;
        input [7:0] next_data;
        reg [31:0] value;
        integer index;
        begin
            value = current_crc ^ {24'h000000, next_data};
            for (index = 0; index < 8; index = index + 1)
                value = value[0] ? ((value >> 1) ^ CRC32_POLYNOMIAL)
                                 : (value >> 1);
            crc32_next_byte = value;
        end
    endfunction

    assign in_ready = (state == STATE_CAPTURE);
    assign out_valid = (state == STATE_EMIT);
    assign out_data = buffer[emit_count];
    assign out_last = (state == STATE_EMIT) && (emit_count == active_length - 1'b1);
    assign busy = (state != STATE_IDLE);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= STATE_IDLE;
            capture_count <= 16'd0;
            emit_count <= 16'd0;
            active_length <= 16'd0;
            format_error <= 1'b0;
            header_crc_error <= 1'b0;
            received_header_crc <= 16'd0;
            received_payload_crc <= 32'd0;
            header_crc_reg <= CRC16_INITIAL;
            payload_crc_reg <= CRC32_INITIAL;
            record_done_pulse <= 1'b0;
            record_error_pulse <= 1'b0;
            good_count <= 32'd0;
            error_count <= 32'd0;
        end else begin
            record_done_pulse <= 1'b0;
            record_error_pulse <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        if ((expected_length != RECORD_BYTES) ||
                            (RECORD_BYTES > MAX_RECORD_BYTES)) begin
                            record_error_pulse <= 1'b1;
                            error_count <= error_count + 1'b1;
                        end else begin
                            active_length <= expected_length;
                            capture_count <= 16'd0;
                            format_error <= 1'b0;
                            header_crc_error <= 1'b0;
                            received_header_crc <= 16'd0;
                            received_payload_crc <= 32'd0;
                            header_crc_reg <= CRC16_INITIAL;
                            payload_crc_reg <= CRC32_INITIAL;
                            state <= STATE_CAPTURE;
                        end
                    end
                end
                STATE_CAPTURE: begin
                    if (in_valid) begin
                        buffer[capture_count] <= in_data;

                        if (current_format_error)
                            format_error <= 1'b1;

                        if (capture_count < HEADER_CRC_START)
                            header_crc_reg <= crc16_next_byte(header_crc_reg, in_data);
                        else if (capture_count == HEADER_CRC_START)
                            received_header_crc[7:0] <= in_data;
                        else if (capture_count == HEADER_CRC_START + 1'b1) begin
                            received_header_crc[15:8] <= in_data;
                            if (CHECK_CRC &&
                                ({in_data, received_header_crc[7:0]} !=
                                 (header_crc_reg ^ CRC16_FINAL_XOR)))
                                header_crc_error <= 1'b1;
                        end

                        if ((capture_count >= PAYLOAD_START) &&
                            (capture_count < PAYLOAD_CRC_START))
                            payload_crc_reg <= crc32_next_byte(payload_crc_reg, in_data);
                        else if (capture_count == PAYLOAD_CRC_START)
                            received_payload_crc[7:0] <= in_data;
                        else if (capture_count == PAYLOAD_CRC_START + 1'b1)
                            received_payload_crc[15:8] <= in_data;
                        else if (capture_count == PAYLOAD_CRC_START + 2'd2)
                            received_payload_crc[23:16] <= in_data;
                        else if (capture_count == PAYLOAD_CRC_START + 2'd3)
                            received_payload_crc[31:24] <= in_data;

                        if (capture_count == active_length - 1'b1) begin
                            if (format_error || current_format_error || header_crc_error ||
                                (CHECK_CRC &&
                                 ({in_data, received_payload_crc[23:0]} !=
                                  (payload_crc_reg ^ CRC32_FINAL_XOR)))) begin
                                record_error_pulse <= 1'b1;
                                error_count <= error_count + 1'b1;
                                state <= STATE_IDLE;
                            end else begin
                                emit_count <= 16'd0;
                                state <= STATE_EMIT;
                            end
                        end else begin
                            capture_count <= capture_count + 1'b1;
                        end
                    end
                end
                STATE_EMIT: begin
                    if (out_ready) begin
                        if (emit_count == active_length - 1'b1) begin
                            record_done_pulse <= 1'b1;
                            good_count <= good_count + 1'b1;
                            state <= STATE_IDLE;
                        end else begin
                            emit_count <= emit_count + 1'b1;
                        end
                    end
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
