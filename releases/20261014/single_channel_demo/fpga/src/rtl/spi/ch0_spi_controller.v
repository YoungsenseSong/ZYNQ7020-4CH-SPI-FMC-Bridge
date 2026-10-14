`timescale 1ns/1ps

`include "protocol_defs.vh"

// CH0 command-oriented master for the nRF54L15 two-CS contract v1.
// The first valid record deliberately exercises bad and duplicate COMMIT once;
// subsequent records use only PEEK -> correct COMMIT.
module ch0_spi_controller #(
    parameter integer CLOCK_HZ = 50000000,
    parameter integer SCLK_HZ = 1000000,
    parameter integer AB_GAP_CYCLES = 250000,
    parameter integer CS_INACTIVE_CYCLES = 15,
    // The electrical CS inactive minimum is not enough for the Zephyr SPIS
    // worker to return from transaction B and arm EasyDMA for the next
    // request.  Keep a separate software re-arm interval before every new A.
    parameter integer B_TO_NEXT_A_GAP_CYCLES = 250000,
    parameter integer STARTUP_DELAY_CYCLES = 250000,
    parameter integer RETRY_DELAY_CYCLES = 50000,
    parameter integer SYNC_WIDTH_CYCLES = 50,
    parameter integer EXERCISE_COMMIT_ERRORS = 1
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        drdy,
    input  wire        miso,
    output wire        sclk,
    output wire        mosi,
    output wire        cs_n,
    output wire        sync_out,

    output wire [7:0]  record_data,
    output wire        record_valid,
    input  wire        record_ready,
    output wire        record_last,

    output wire [5:0]  debug_state,
    output reg  [31:0] request_count,
    output reg  [31:0] response_count,
    output reg  [7:0]  last_command,
    output reg  [31:0] last_status,
    output reg  [31:0] last_transport_seq,
    output reg         last_record_valid,
    output reg  [31:0] crc_ok_count,
    output reg  [31:0] crc_error_count,
    output reg  [31:0] commit_ok_count,
    output reg  [31:0] commit_error_count,
    output reg  [31:0] bad_commit_reject_count,
    output reg  [31:0] duplicate_commit_reject_count,
    output reg  [31:0] timeout_count,
    output reg  [31:0] envelope_error_count
);
    localparam [7:0] CMD_GET_INFO      = 8'd1;
    localparam [7:0] CMD_GET_STATUS    = 8'd2;
    localparam [7:0] CMD_PEEK_RECORD   = 8'd3;
    localparam [7:0] CMD_COMMIT_RECORD = 8'd5;
    localparam [7:0] CMD_ARM_SYNC      = 8'd8;
    localparam [7:0] CMD_START_STREAM  = 8'd9;

    localparam [31:0] INFO_MAGIC = 32'h3149464e;
    localparam [31:0] STATUS_MAGIC = 32'h3153464e;

    localparam [1:0] COMMIT_NORMAL = 2'd0;
    localparam [1:0] COMMIT_BAD    = 2'd1;
    localparam [1:0] COMMIT_GOOD   = 2'd2;
    localparam [1:0] COMMIT_DUP    = 2'd3;

    localparam [5:0] ST_STARTUP       = 6'd0;
    localparam [5:0] ST_START_REQ     = 6'd1;
    localparam [5:0] ST_WAIT_REQ      = 6'd2;
    localparam [5:0] ST_AB_GAP        = 6'd3;
    localparam [5:0] ST_START_RESP    = 6'd4;
    localparam [5:0] ST_WAIT_RESP     = 6'd5;
    localparam [5:0] ST_EVAL_RESP     = 6'd6;
    localparam [5:0] ST_WAIT_PARSER   = 6'd7;
    localparam [5:0] ST_EMIT_RECORD   = 6'd8;
    localparam [5:0] ST_IDLE_DRDY     = 6'd9;
    localparam [5:0] ST_RETRY_WAIT    = 6'd10;
    localparam [5:0] ST_SYNC_PRE      = 6'd11;
    localparam [5:0] ST_SYNC_HIGH     = 6'd12;
    localparam [5:0] ST_SYNC_POST     = 6'd13;
    localparam [5:0] ST_REQ_INACTIVE  = 6'd14;
    localparam [5:0] ST_RECOVERY_WAIT = 6'd15;
    localparam [5:0] ST_START_RECOVERY = 6'd16;
    localparam [5:0] ST_WAIT_RECOVERY = 6'd17;

    localparam integer REQUEST_GAP_CYCLES =
        (B_TO_NEXT_A_GAP_CYCLES > CS_INACTIVE_CYCLES) ?
        B_TO_NEXT_A_GAP_CYCLES : CS_INACTIVE_CYCLES;

    reg [5:0] state;
    reg [31:0] delay_count;
    reg [7:0] active_command;
    reg [31:0] active_argument;
    reg [1:0] commit_phase;
    reg diagnostic_complete;

    wire transaction_is_request =
        (state == ST_START_REQ) || (state == ST_WAIT_REQ);
    wire transaction_start =
        (state == ST_START_REQ) || (state == ST_START_RESP) ||
        (state == ST_START_RECOVERY);
    wire [8:0] transaction_length = transaction_is_request ? 9'd8 : 9'd260;
    wire [8:0] transaction_tx_index;
    wire [7:0] transaction_tx_data;
    wire transaction_busy;
    wire transaction_done;
    wire transaction_timeout;
    wire [8:0] transaction_rx_index;
    wire [7:0] transaction_rx_data;
    wire transaction_rx_valid;

    reg [31:0] response_status;
    reg [31:0] response_transport_seq;
    reg response_record_valid;
    reg [31:0] response_magic;
    reg [31:0] pending_transport_seq;
    reg parser_reset_pulse;
    reg parser_error_seen;
    reg parser_done_seen;

    wire parser_reset_n = reset_n && !parser_reset_pulse;
    wire parser_start = (state == ST_START_RESP) &&
                        (active_command == CMD_PEEK_RECORD);
    wire parser_in_valid = transaction_rx_valid &&
                           (state == ST_WAIT_RESP) &&
                           (active_command == CMD_PEEK_RECORD) &&
                           response_record_valid &&
                           (transaction_rx_index >= 9'd12) &&
                           (transaction_rx_index < 9'd260);
    wire parser_in_ready;
    wire [7:0] parser_out_data;
    wire parser_out_valid;
    wire parser_out_last;
    wire parser_done;
    wire parser_error;
    wire parser_busy;
    wire [31:0] parser_good_count_unused;
    wire [31:0] parser_error_count_unused;

    reg [7:0] record_buffer [0:247];
    reg [7:0] parser_emit_count;
    reg [7:0] record_emit_count;

    function [7:0] request_byte;
        input [8:0] index;
        input [7:0] command;
        input [31:0] argument;
        begin
            case (index)
                9'd0: request_byte = command;
                9'd1, 9'd2, 9'd3: request_byte = 8'h00;
                9'd4: request_byte = argument[7:0];
                9'd5: request_byte = argument[15:8];
                9'd6: request_byte = argument[23:16];
                9'd7: request_byte = argument[31:24];
                default: request_byte = 8'h00;
            endcase
        end
    endfunction

    initial begin
        if ((AB_GAP_CYCLES < 1) || (CS_INACTIVE_CYCLES < 1) ||
            (B_TO_NEXT_A_GAP_CYCLES < 1))
            $error("invalid CH0 SPI inter-transaction gap parameters");
    end

    assign transaction_tx_data = transaction_is_request ?
        request_byte(transaction_tx_index, active_command, active_argument) : 8'h00;

    spi_fixed_transaction_master #(
        .CLOCK_HZ(CLOCK_HZ), .SCLK_HZ(SCLK_HZ),
        .CS_SETUP_CYCLES(CLOCK_HZ / 1000000),
        .CS_HOLD_CYCLES(CLOCK_HZ / 1000000),
        .TIMEOUT_CYCLES(CLOCK_HZ / 100)
    ) transaction_master (
        .clk(clk), .reset_n(reset_n), .start(transaction_start),
        .length(transaction_length), .tx_index(transaction_tx_index),
        .tx_data(transaction_tx_data), .miso(miso), .sclk(sclk),
        .mosi(mosi), .cs_n(cs_n), .busy(transaction_busy),
        .done_pulse(transaction_done), .timeout_pulse(transaction_timeout),
        .rx_index(transaction_rx_index), .rx_data(transaction_rx_data),
        .rx_valid(transaction_rx_valid)
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
    ) record_parser (
        .clk(clk), .reset_n(parser_reset_n), .start(parser_start),
        .expected_length(`SPI_RECORD_BYTES), .in_data(transaction_rx_data),
        .in_valid(parser_in_valid), .in_ready(parser_in_ready),
        .out_data(parser_out_data), .out_valid(parser_out_valid),
        .out_ready(1'b1), .out_last(parser_out_last),
        .record_done_pulse(parser_done),
        .record_error_pulse(parser_error),
        .good_count(parser_good_count_unused),
        .error_count(parser_error_count_unused), .busy(parser_busy)
    );

    assign record_data = record_buffer[record_emit_count];
    assign record_valid = (state == ST_EMIT_RECORD);
    assign record_last = (state == ST_EMIT_RECORD) && (record_emit_count == 8'd247);
    assign sync_out = (state == ST_SYNC_HIGH);
    assign debug_state = state;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= ST_STARTUP;
            delay_count <= 32'd0;
            active_command <= CMD_GET_INFO;
            active_argument <= 32'd0;
            commit_phase <= COMMIT_NORMAL;
            diagnostic_complete <= 1'b0;
            response_status <= 32'd0;
            response_transport_seq <= 32'd0;
            response_record_valid <= 1'b0;
            response_magic <= 32'd0;
            pending_transport_seq <= 32'd0;
            parser_reset_pulse <= 1'b0;
            parser_error_seen <= 1'b0;
            parser_done_seen <= 1'b0;
            parser_emit_count <= 8'd0;
            record_emit_count <= 8'd0;
            request_count <= 32'd0;
            response_count <= 32'd0;
            last_command <= 8'd0;
            last_status <= 32'd0;
            last_transport_seq <= 32'd0;
            last_record_valid <= 1'b0;
            crc_ok_count <= 32'd0;
            crc_error_count <= 32'd0;
            commit_ok_count <= 32'd0;
            commit_error_count <= 32'd0;
            bad_commit_reject_count <= 32'd0;
            duplicate_commit_reject_count <= 32'd0;
            timeout_count <= 32'd0;
            envelope_error_count <= 32'd0;
        end else begin
            parser_reset_pulse <= 1'b0;

            if (parser_out_valid) begin
                record_buffer[parser_emit_count] <= parser_out_data;
                parser_emit_count <= parser_emit_count + 1'b1;
            end
            if (parser_error) begin
                parser_error_seen <= 1'b1;
                crc_error_count <= crc_error_count + 1'b1;
            end
            if (parser_done) begin
                parser_done_seen <= 1'b1;
                crc_ok_count <= crc_ok_count + 1'b1;
            end

            if (transaction_timeout) begin
                timeout_count <= timeout_count + 1'b1;
                parser_reset_pulse <= 1'b1;
                delay_count <= 32'd0;
                state <= ST_RECOVERY_WAIT;
            end else begin
                case (state)
                    ST_STARTUP: begin
                        if (delay_count >= STARTUP_DELAY_CYCLES - 1) begin
                            delay_count <= 32'd0;
                            active_command <= CMD_GET_INFO;
                            active_argument <= 32'd0;
                            state <= ST_REQ_INACTIVE;
                        end else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    ST_START_REQ: begin
                        request_count <= request_count + 1'b1;
                        last_command <= active_command;
                        state <= ST_WAIT_REQ;
                    end

                    ST_WAIT_REQ: begin
                        if (transaction_done) begin
                            delay_count <= 32'd0;
                            state <= ST_AB_GAP;
                        end
                    end

                    ST_AB_GAP: begin
                        if (delay_count >= AB_GAP_CYCLES - 1) begin
                            delay_count <= 32'd0;
                            state <= ST_START_RESP;
                        end else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    ST_START_RESP: begin
                        response_status <= 32'd0;
                        response_transport_seq <= 32'd0;
                        response_record_valid <= 1'b0;
                        response_magic <= 32'd0;
                        parser_error_seen <= 1'b0;
                        parser_done_seen <= 1'b0;
                        parser_emit_count <= 8'd0;
                        state <= ST_WAIT_RESP;
                    end

                    ST_WAIT_RESP: begin
                        if (transaction_rx_valid) begin
                            case (transaction_rx_index)
                                9'd0: response_status[7:0] <= transaction_rx_data;
                                9'd1: response_status[15:8] <= transaction_rx_data;
                                9'd2: response_status[23:16] <= transaction_rx_data;
                                9'd3: response_status[31:24] <= transaction_rx_data;
                                9'd4: response_transport_seq[7:0] <= transaction_rx_data;
                                9'd5: response_transport_seq[15:8] <= transaction_rx_data;
                                9'd6: response_transport_seq[23:16] <= transaction_rx_data;
                                9'd7: response_transport_seq[31:24] <= transaction_rx_data;
                                9'd8: response_record_valid <= transaction_rx_data[0];
                                9'd12: response_magic[7:0] <= transaction_rx_data;
                                9'd13: response_magic[15:8] <= transaction_rx_data;
                                9'd14: response_magic[23:16] <= transaction_rx_data;
                                9'd15: response_magic[31:24] <= transaction_rx_data;
                                default: begin end
                            endcase
                        end
                        if (transaction_done) begin
                            response_count <= response_count + 1'b1;
                            state <= ST_EVAL_RESP;
                        end
                    end

                    ST_EVAL_RESP: begin
                        last_status <= response_status;
                        last_transport_seq <= response_transport_seq;
                        last_record_valid <= response_record_valid;
                        case (active_command)
                            CMD_GET_INFO: begin
                                if ((response_status == 0) &&
                                    (response_magic == INFO_MAGIC)) begin
                                    active_command <= CMD_GET_STATUS;
                                    active_argument <= 32'd0;
                                    state <= ST_REQ_INACTIVE;
                                end else begin
                                    envelope_error_count <= envelope_error_count + 1'b1;
                                    delay_count <= 32'd0;
                                    state <= ST_RECOVERY_WAIT;
                                end
                            end

                            CMD_GET_STATUS: begin
                                if ((response_status == 0) &&
                                    (response_magic == STATUS_MAGIC)) begin
                                    active_command <= CMD_ARM_SYNC;
                                    active_argument <= 32'd1;
                                    state <= ST_REQ_INACTIVE;
                                end else begin
                                    envelope_error_count <= envelope_error_count + 1'b1;
                                    delay_count <= 32'd0;
                                    state <= ST_RECOVERY_WAIT;
                                end
                            end

                            CMD_ARM_SYNC: begin
                                if (response_status == 0) begin
                                    delay_count <= 32'd0;
                                    state <= ST_SYNC_PRE;
                                end else begin
                                    envelope_error_count <= envelope_error_count + 1'b1;
                                    delay_count <= 32'd0;
                                    state <= ST_RECOVERY_WAIT;
                                end
                            end

                            CMD_START_STREAM: begin
                                if (response_status == 0) begin
                                    state <= ST_IDLE_DRDY;
                                end else begin
                                    envelope_error_count <= envelope_error_count + 1'b1;
                                    delay_count <= 32'd0;
                                    state <= ST_RECOVERY_WAIT;
                                end
                            end

                            CMD_PEEK_RECORD: begin
                                if ((response_status != 0) || !response_record_valid) begin
                                    envelope_error_count <= envelope_error_count + 1'b1;
                                    parser_reset_pulse <= 1'b1;
                                    delay_count <= 32'd0;
                                    state <= ST_RECOVERY_WAIT;
                                end else if (parser_error_seen) begin
                                    parser_reset_pulse <= 1'b1;
                                    delay_count <= 32'd0;
                                    state <= ST_RECOVERY_WAIT;
                                end else if (parser_done_seen) begin
                                    pending_transport_seq <= response_transport_seq;
                                    active_command <= CMD_COMMIT_RECORD;
                                    if ((EXERCISE_COMMIT_ERRORS != 0) &&
                                        !diagnostic_complete) begin
                                        active_argument <= response_transport_seq + 1'b1;
                                        commit_phase <= COMMIT_BAD;
                                    end else begin
                                        active_argument <= response_transport_seq;
                                        commit_phase <= COMMIT_GOOD;
                                    end
                                    state <= ST_REQ_INACTIVE;
                                end else begin
                                    pending_transport_seq <= response_transport_seq;
                                    state <= ST_WAIT_PARSER;
                                end
                            end

                            CMD_COMMIT_RECORD: begin
                                case (commit_phase)
                                    COMMIT_BAD: begin
                                        if (response_status != 0) begin
                                            bad_commit_reject_count <=
                                                bad_commit_reject_count + 1'b1;
                                            active_argument <= pending_transport_seq;
                                            commit_phase <= COMMIT_GOOD;
                                            state <= ST_REQ_INACTIVE;
                                        end else begin
                                            commit_error_count <= commit_error_count + 1'b1;
                                            delay_count <= 32'd0;
                                            state <= ST_RECOVERY_WAIT;
                                        end
                                    end

                                    COMMIT_GOOD: begin
                                        if (response_status == 0) begin
                                            commit_ok_count <= commit_ok_count + 1'b1;
                                            if ((EXERCISE_COMMIT_ERRORS != 0) &&
                                                !diagnostic_complete) begin
                                                active_argument <= pending_transport_seq;
                                                commit_phase <= COMMIT_DUP;
                                                state <= ST_REQ_INACTIVE;
                                            end else begin
                                                record_emit_count <= 8'd0;
                                                state <= ST_EMIT_RECORD;
                                            end
                                        end else begin
                                            commit_error_count <= commit_error_count + 1'b1;
                                            delay_count <= 32'd0;
                                            state <= ST_RECOVERY_WAIT;
                                        end
                                    end

                                    COMMIT_DUP: begin
                                        if (response_status != 0)
                                            duplicate_commit_reject_count <=
                                                duplicate_commit_reject_count + 1'b1;
                                        else
                                            commit_error_count <= commit_error_count + 1'b1;
                                        diagnostic_complete <= 1'b1;
                                        record_emit_count <= 8'd0;
                                        state <= ST_EMIT_RECORD;
                                    end

                                    default: begin
                                        commit_error_count <= commit_error_count + 1'b1;
                                        delay_count <= 32'd0;
                                        state <= ST_RECOVERY_WAIT;
                                    end
                                endcase
                            end

                            default: begin
                                envelope_error_count <= envelope_error_count + 1'b1;
                                delay_count <= 32'd0;
                                state <= ST_RECOVERY_WAIT;
                            end
                        endcase
                    end

                    ST_WAIT_PARSER: begin
                        if (parser_error_seen) begin
                            parser_reset_pulse <= 1'b1;
                            delay_count <= 32'd0;
                            state <= ST_RECOVERY_WAIT;
                        end else if (parser_done_seen) begin
                            active_command <= CMD_COMMIT_RECORD;
                            if ((EXERCISE_COMMIT_ERRORS != 0) &&
                                !diagnostic_complete) begin
                                active_argument <= response_transport_seq + 1'b1;
                                commit_phase <= COMMIT_BAD;
                            end else begin
                                active_argument <= response_transport_seq;
                                commit_phase <= COMMIT_GOOD;
                            end
                            state <= ST_REQ_INACTIVE;
                        end
                    end

                    ST_EMIT_RECORD: begin
                        if (record_valid && record_ready) begin
                            if (record_emit_count == 8'd247) begin
                                record_emit_count <= 8'd0;
                                state <= ST_IDLE_DRDY;
                            end else begin
                                record_emit_count <= record_emit_count + 1'b1;
                            end
                        end
                    end

                    ST_IDLE_DRDY: begin
                        if (drdy) begin
                            active_command <= CMD_PEEK_RECORD;
                            active_argument <= 32'd0;
                            commit_phase <= COMMIT_NORMAL;
                            state <= ST_REQ_INACTIVE;
                        end
                    end

                    ST_RETRY_WAIT: begin
                        if (delay_count >= RETRY_DELAY_CYCLES - 1) begin
                            delay_count <= 32'd0;
                            if ((last_command == CMD_GET_INFO) ||
                                (last_command == CMD_GET_STATUS) ||
                                (last_command == CMD_ARM_SYNC) ||
                                (last_command == CMD_START_STREAM)) begin
                                active_command <= CMD_GET_INFO;
                                active_argument <= 32'd0;
                                state <= ST_REQ_INACTIVE;
                            end else begin
                                state <= ST_IDLE_DRDY;
                            end
                        end else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    ST_SYNC_PRE: begin
                        if (delay_count >= AB_GAP_CYCLES - 1) begin
                            delay_count <= 32'd0;
                            state <= ST_SYNC_HIGH;
                        end else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    ST_SYNC_HIGH: begin
                        if (delay_count >= SYNC_WIDTH_CYCLES - 1) begin
                            delay_count <= 32'd0;
                            state <= ST_SYNC_POST;
                        end else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    ST_SYNC_POST: begin
                        if (delay_count >= AB_GAP_CYCLES - 1) begin
                            delay_count <= 32'd0;
                            active_command <= CMD_START_STREAM;
                            active_argument <= 32'd0;
                            state <= ST_REQ_INACTIVE;
                        end else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    ST_REQ_INACTIVE: begin
                        if (delay_count >= REQUEST_GAP_CYCLES - 1) begin
                            delay_count <= 32'd0;
                            state <= ST_START_REQ;
                        end else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    // A 260-byte transfer forces the blocking Zephyr SPIS
                    // worker back to its request phase.  In response phase it
                    // completes B; in request phase it is rejected as a long
                    // request and the worker waits for a request again.
                    ST_RECOVERY_WAIT: begin
                        if (delay_count >= REQUEST_GAP_CYCLES - 1) begin
                            delay_count <= 32'd0;
                            state <= ST_START_RECOVERY;
                        end else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    ST_START_RECOVERY: begin
                        state <= ST_WAIT_RECOVERY;
                    end

                    ST_WAIT_RECOVERY: begin
                        if (transaction_done) begin
                            delay_count <= 32'd0;
                            state <= ST_RETRY_WAIT;
                        end
                    end

                    default: state <= ST_STARTUP;
                endcase
            end
        end
    end
endmodule
