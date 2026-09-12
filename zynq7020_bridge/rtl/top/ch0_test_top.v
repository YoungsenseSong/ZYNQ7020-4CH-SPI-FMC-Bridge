`timescale 1ns/1ps

// Board-level CH0 acceptance image.  This top intentionally excludes FMC and
// CH1..CH3; received records are checked and counted, not forwarded to F730.
module ch0_test_top #(
    parameter [3:0] ACTIVE_CHANNEL_MASK = 4'b0001
) (
    input  wire pl_clk,
    input  wire ext_reset_n,
    output wire ch0_mosi,
    input  wire ch0_miso,
    output wire ch0_cs_n,
    input  wire ch0_drdy,
    output wire ch0_sclk,
    output wire ch0_sync_out
);
    wire clk;
    wire reset_n;
    wire drdy_sync;

    (* MARK_DEBUG = "TRUE" *) wire [5:0]  debug_state;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] request_count;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] response_count;
    (* MARK_DEBUG = "TRUE" *) wire [7:0]  last_command;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] last_status;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] last_transport_seq;
    (* MARK_DEBUG = "TRUE" *) wire        last_record_valid;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] crc_ok_count;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] crc_error_count;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] commit_ok_count;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] commit_error_count;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] bad_commit_reject_count;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] duplicate_commit_reject_count;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] timeout_count;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] envelope_error_count;
    (* MARK_DEBUG = "TRUE" *) wire [7:0]  record_data;
    (* MARK_DEBUG = "TRUE" *) wire        record_valid;
    (* MARK_DEBUG = "TRUE" *) wire        record_last;
    (* MARK_DEBUG = "TRUE" *) wire        drdy_debug = drdy_sync;
    (* MARK_DEBUG = "TRUE" *) wire        cs_debug = ch0_cs_n;
    (* MARK_DEBUG = "TRUE" *) wire        sync_debug = ch0_sync_out;

    reset_clock_mgr #(.TICK_DIVIDER(50)) clock_mgr (
        .pl_clk(pl_clk), .ext_reset_n(ext_reset_n), .soft_reset(1'b0),
        .clk_out(clk), .reset_n(reset_n), .tick_pulse()
    );

    cdc_sync #(.WIDTH(1), .RESET_VALUE(0)) drdy_synchronizer (
        .clk(clk), .reset_n(reset_n), .async_in(ch0_drdy),
        .sync_out(drdy_sync)
    );

    ch0_spi_controller #(
        .CLOCK_HZ(50000000),
        .SCLK_HZ(1000000),
        .AB_GAP_CYCLES(250000),
        .CS_INACTIVE_CYCLES(15),
        .B_TO_NEXT_A_GAP_CYCLES(250000),
        .STARTUP_DELAY_CYCLES(250000),
        .RETRY_DELAY_CYCLES(50000),
        .SYNC_WIDTH_CYCLES(50),
        .EXERCISE_COMMIT_ERRORS(1)
    ) controller (
        .clk(clk), .reset_n(reset_n && ACTIVE_CHANNEL_MASK[0]),
        .drdy(drdy_sync), .miso(ch0_miso), .sclk(ch0_sclk),
        .mosi(ch0_mosi), .cs_n(ch0_cs_n), .sync_out(ch0_sync_out),
        .record_data(record_data), .record_valid(record_valid),
        .record_ready(1'b1), .record_last(record_last),
        .debug_state(debug_state), .request_count(request_count),
        .response_count(response_count), .last_command(last_command),
        .last_status(last_status), .last_transport_seq(last_transport_seq),
        .last_record_valid(last_record_valid), .crc_ok_count(crc_ok_count),
        .crc_error_count(crc_error_count), .commit_ok_count(commit_ok_count),
        .commit_error_count(commit_error_count),
        .bad_commit_reject_count(bad_commit_reject_count),
        .duplicate_commit_reject_count(duplicate_commit_reject_count),
        .timeout_count(timeout_count), .envelope_error_count(envelope_error_count)
    );

    initial begin
        if (ACTIVE_CHANNEL_MASK != 4'b0001)
            $error("ch0_test_top supports CH0 only");
    end
endmodule
