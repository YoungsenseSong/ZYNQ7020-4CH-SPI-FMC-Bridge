module spi_record_parser #(
    parameter MAX_RECORD_BYTES = 512,
    parameter CHECK_MAGIC = 0,
    parameter [31:0] MAGIC_VALUE = 32'h00000000,
    parameter CHECK_CRC = 0,
    parameter [31:0] CRC_POLYNOMIAL = 32'h04C11DB7,
    parameter [31:0] CRC_INITIAL = 32'hFFFFFFFF,
    parameter [31:0] CRC_FINAL_XOR = 32'hFFFFFFFF
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

    reg [1:0] state;
    reg [7:0] buffer [0:MAX_RECORD_BYTES-1];
    reg [15:0] capture_count;
    reg [15:0] emit_count;
    reg [15:0] active_length;
    reg magic_error;
    reg [31:0] received_crc;
    reg [31:0] crc_reg;
    wire [7:0] expected_magic_byte =
        (capture_count == 0) ? MAGIC_VALUE[7:0] :
        (capture_count == 1) ? MAGIC_VALUE[15:8] :
        (capture_count == 2) ? MAGIC_VALUE[23:16] : MAGIC_VALUE[31:24];

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
            magic_error <= 1'b0;
            received_crc <= 32'd0;
            crc_reg <= CRC_INITIAL;
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
                        if ((expected_length < 4) || (expected_length > MAX_RECORD_BYTES)) begin
                            record_error_pulse <= 1'b1;
                            error_count <= error_count + 1'b1;
                        end else begin
                            active_length <= expected_length;
                            capture_count <= 16'd0;
                            magic_error <= 1'b0;
                            received_crc <= 32'd0;
                            crc_reg <= CRC_INITIAL;
                            state <= STATE_CAPTURE;
                        end
                    end
                end
                STATE_CAPTURE: begin
                    if (in_valid) begin
                        buffer[capture_count] <= in_data;
                        if (CHECK_MAGIC && (capture_count < 4) && (in_data != expected_magic_byte))
                            magic_error <= 1'b1;

                        if (capture_count < active_length - 4)
                            crc_reg <= crc_next_byte(crc_reg, in_data);
                        else begin
                            case (capture_count - (active_length - 4))
                                0: received_crc[7:0] <= in_data;
                                1: received_crc[15:8] <= in_data;
                                2: received_crc[23:16] <= in_data;
                                3: received_crc[31:24] <= in_data;
                            endcase
                        end

                        if (capture_count == active_length - 1'b1) begin
                            if (magic_error ||
                                (CHECK_MAGIC && (capture_count < 4) && (in_data != expected_magic_byte)) ||
                                (CHECK_CRC && ({in_data, received_crc[23:0]} != (crc_reg ^ CRC_FINAL_XOR)))) begin
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
