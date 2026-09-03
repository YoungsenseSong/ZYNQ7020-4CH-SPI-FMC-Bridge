`timescale 1ns/1ps

module tb_ch0_spi_controller;
    localparam integer CLOCK_HZ = 50000000;
    localparam integer CLOCK_PERIOD_NS = 20;
    localparam integer RECORD_BYTES = 248;
    localparam integer AB_GAP_CYCLES = 250000;
    localparam integer B_TO_NEXT_A_GAP_CYCLES = 250000;
    localparam integer B_TO_NEXT_A_GAP_NS =
        B_TO_NEXT_A_GAP_CYCLES * CLOCK_PERIOD_NS;

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg drdy = 1'b0;
    reg miso = 1'b0;
    wire sclk;
    wire mosi;
    wire cs_n;
    wire sync_out;
    wire [7:0] record_data;
    wire record_valid;
    reg record_ready = 1'b1;
    wire record_last;
    wire [5:0] debug_state;
    wire [31:0] request_count;
    wire [31:0] response_count;
    wire [7:0] last_command;
    wire [31:0] last_status;
    wire [31:0] last_transport_seq;
    wire last_record_valid;
    wire [31:0] crc_ok_count;
    wire [31:0] crc_error_count;
    wire [31:0] commit_ok_count;
    wire [31:0] commit_error_count;
    wire [31:0] bad_commit_reject_count;
    wire [31:0] duplicate_commit_reject_count;
    wire [31:0] timeout_count;
    wire [31:0] envelope_error_count;

    reg [7:0] golden [0:RECORD_BYTES-1];
    reg [7:0] response [0:259];
    reg [7:0] request [0:7];
    integer file_handle;
    integer read_count;
    integer i;
    integer request_byte_count = 0;
    integer response_byte_count = 0;
    integer bit_count = 0;
    integer transaction_count = 0;
    integer output_count = 0;
    integer sync_cycles = 0;
    integer errors = 0;
    reg expect_request = 1'b1;
    reg [7:0] rx_shift = 8'h00;
    reg [7:0] active_command = 8'h00;
    reg [31:0] active_argument = 32'h00000000;
    reg record_queued = 1'b1;
    reg committed_once = 1'b0;
    reg inject_bad_info_once = 1'b1;
    reg miss_first_response_once = 1'b1;
    reg current_response_missed = 1'b0;
    reg slave_phase_misaligned = 1'b0;
    integer recovery_flush_count = 0;
    reg [31:0] queue_sequence = 32'd42;
    time cs_fall_time = 0;
    time cs_rise_time = 0;
    time first_sclk_rise = 0;
    time last_sclk_fall = 0;
    time previous_cs_rise = 0;
    reg saw_first_sclk = 1'b0;
    reg cs_active = 1'b0;

    always #(CLOCK_PERIOD_NS / 2) clk = ~clk;

    ch0_spi_controller #(
        .CLOCK_HZ(CLOCK_HZ),
        .SCLK_HZ(1000000),
        .AB_GAP_CYCLES(AB_GAP_CYCLES),
        .CS_INACTIVE_CYCLES(15),
        .B_TO_NEXT_A_GAP_CYCLES(B_TO_NEXT_A_GAP_CYCLES),
        .STARTUP_DELAY_CYCLES(5),
        .RETRY_DELAY_CYCLES(50),
        .SYNC_WIDTH_CYCLES(50),
        .EXERCISE_COMMIT_ERRORS(1)
    ) dut (
        .clk(clk), .reset_n(reset_n), .drdy(drdy), .miso(miso),
        .sclk(sclk), .mosi(mosi), .cs_n(cs_n), .sync_out(sync_out),
        .record_data(record_data), .record_valid(record_valid),
        .record_ready(record_ready), .record_last(record_last),
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

    task set_u32_le;
        input integer offset;
        input [31:0] value;
        begin
            response[offset + 0] = value[7:0];
            response[offset + 1] = value[15:8];
            response[offset + 2] = value[23:16];
            response[offset + 3] = value[31:24];
        end
    endtask

    task prepare_response;
        integer index;
        reg [31:0] status;
        begin
            for (index = 0; index < 260; index = index + 1)
                response[index] = 8'h00;
            status = 32'd0;
            case (active_command)
                8'd1: begin
                    if (inject_bad_info_once) begin
                        set_u32_le(12, 32'h00000000);
                        inject_bad_info_once = 1'b0;
                    end else begin
                        set_u32_le(12, 32'h3149464e);
                    end
                end
                8'd2: set_u32_le(12, 32'h3153464e);
                8'd3: begin
                    set_u32_le(4, queue_sequence);
                    response[8] = record_queued;
                    if (record_queued)
                        for (index = 0; index < RECORD_BYTES; index = index + 1)
                            response[12 + index] = golden[index];
                end
                8'd5: begin
                    if (active_argument != queue_sequence)
                        status = 32'hffffff8c;
                    else if (!record_queued && committed_once)
                        status = 32'hffffff8e;
                    else begin
                        record_queued = 1'b0;
                        committed_once = 1'b1;
                    end
                end
                default: begin end
            endcase
            set_u32_le(0, status);
        end
    endtask

    always @(negedge cs_n) begin
        cs_active = 1'b1;
        cs_fall_time = $time;
        saw_first_sclk = 1'b0;
        bit_count = 0;
        rx_shift = 8'h00;
        if (previous_cs_rise != 0 && ($time - previous_cs_rise) < 300) begin
            $display("ERROR CS inactive %0t ns", $time - previous_cs_rise);
            errors = errors + 1;
        end
        if (expect_request) begin
            if (previous_cs_rise != 0 &&
                ($time - previous_cs_rise) < B_TO_NEXT_A_GAP_NS) begin
                $display("ERROR B/next-A re-arm gap %0t ns", $time - previous_cs_rise);
                errors = errors + 1;
            end
            request_byte_count = 0;
            miso = 1'b0;
        end else begin
            if (($time - previous_cs_rise) <
                (AB_GAP_CYCLES * CLOCK_PERIOD_NS)) begin
                $display("ERROR A/B gap %0t ns", $time - previous_cs_rise);
                errors = errors + 1;
            end
            response_byte_count = 0;
            current_response_missed = miss_first_response_once;
            if (miss_first_response_once) begin
                // Model the real failure: transaction B arrives before the
                // slave has armed its response buffer, so it produces zeros
                // and remains logically in the response phase.
                miss_first_response_once = 1'b0;
                slave_phase_misaligned = 1'b1;
                miso = 1'b0;
            end else begin
                prepare_response();
                miso = response[0][7];
            end
        end
    end

    always @(posedge sclk) begin
        if (!saw_first_sclk) begin
            first_sclk_rise = $time;
            saw_first_sclk = 1'b1;
            if (($time - cs_fall_time) < 1000) begin
                $display("ERROR CS setup %0t ns", $time - cs_fall_time);
                errors = errors + 1;
            end
        end
        rx_shift = {rx_shift[6:0], mosi};
        bit_count = bit_count + 1;
        if (bit_count == 8) begin
            if (expect_request) begin
                if (request_byte_count < 8)
                    request[request_byte_count] = rx_shift;
                request_byte_count = request_byte_count + 1;
            end else begin
                if (rx_shift != 8'h00) begin
                    $display("ERROR response MOSI byte %0d = %02x", response_byte_count, rx_shift);
                    errors = errors + 1;
                end
                response_byte_count = response_byte_count + 1;
            end
            bit_count = 0;
            rx_shift = 8'h00;
        end
    end

    always @(negedge sclk) begin
        last_sclk_fall = $time;
        if (!cs_n && !expect_request && !current_response_missed) begin
            if (bit_count == 0) begin
                if (response_byte_count < 260)
                    miso = response[response_byte_count][7];
                else
                    miso = 1'b0;
            end else begin
                miso = response[response_byte_count][7-bit_count];
            end
        end
    end

    always @(posedge cs_n) begin
        if (cs_active) begin
        cs_active = 1'b0;
        cs_rise_time = $time;
        previous_cs_rise = $time;
        if (($time - last_sclk_fall) < 1000) begin
            $display("ERROR CS hold %0t ns", $time - last_sclk_fall);
            errors = errors + 1;
        end
        if (expect_request) begin
            if (request_byte_count != 8) begin
                $display("ERROR request length %0d", request_byte_count);
                errors = errors + 1;
            end
            active_command = request[0];
            active_argument = {request[7], request[6], request[5], request[4]};
            if ((request[1] | request[2] | request[3]) != 0) begin
                $display("ERROR reserved request bytes not zero");
                errors = errors + 1;
            end
            case (transaction_count)
                0: if ((active_command != 8'd1) || (active_argument != 0)) errors = errors + 1;
                1: if ((active_command != 8'd1) || (active_argument != 0)) errors = errors + 1;
                2: if ((active_command != 8'd2) || (active_argument != 0)) errors = errors + 1;
                3: if ((active_command != 8'd8) || (active_argument != 1)) errors = errors + 1;
                4: if ((active_command != 8'd9) || (active_argument != 0)) errors = errors + 1;
                5: if ((active_command != 8'd3) || (active_argument != 0)) errors = errors + 1;
                6: if ((active_command != 8'd5) || (active_argument != queue_sequence + 1)) errors = errors + 1;
                7: if ((active_command != 8'd5) || (active_argument != queue_sequence)) errors = errors + 1;
                8: if ((active_command != 8'd5) || (active_argument != queue_sequence)) errors = errors + 1;
                default: errors = errors + 1;
            endcase
            expect_request = 1'b0;
        end else begin
            if (!current_response_missed && response_byte_count != 260) begin
                $display("ERROR response length %0d", response_byte_count);
                errors = errors + 1;
            end
            if (current_response_missed) begin
                current_response_missed = 1'b0;
            end else begin
                if (slave_phase_misaligned) begin
                    recovery_flush_count = recovery_flush_count + 1;
                    slave_phase_misaligned = 1'b0;
                end
                transaction_count = transaction_count + 1;
                if (active_command == 8'd9)
                    drdy = 1'b1;
                if ((active_command == 8'd5) &&
                    (active_argument == queue_sequence) &&
                    record_queued == 1'b0)
                    drdy = 1'b0;
                expect_request = 1'b1;
            end
        end
        miso = 1'b0;
        end
    end

    always @(posedge clk) begin
        if (sync_out)
            sync_cycles = sync_cycles + 1;
        if (record_valid && record_ready) begin
            if (record_data !== golden[output_count]) begin
                $display("ERROR output[%0d] expected=%02x actual=%02x",
                         output_count, golden[output_count], record_data);
                errors = errors + 1;
            end
            if (record_last !== (output_count == RECORD_BYTES - 1)) begin
                $display("ERROR record_last at byte %0d", output_count);
                errors = errors + 1;
            end
            output_count = output_count + 1;
        end
    end

    initial begin
        file_handle = $fopen("../../protocol/golden/nrf_record_valid.bin", "rb");
        if (file_handle == 0) begin
            $display("ERROR cannot open golden record");
            $finish_and_return(1);
        end
        read_count = $fread(golden, file_handle);
        $fclose(file_handle);
        if (read_count != RECORD_BYTES) begin
            $display("ERROR golden byte count %0d", read_count);
            $finish_and_return(1);
        end

        repeat (8) @(posedge clk);
        reset_n = 1'b1;

        fork
            begin
                wait (output_count == RECORD_BYTES);
                repeat (20) @(posedge clk);
                if (request_count != 9 || response_count != 9) begin
                    $display("ERROR counts req=%0d resp=%0d", request_count, response_count);
                    errors = errors + 1;
                end
                if (crc_ok_count != 1 || crc_error_count != 0 ||
                    commit_ok_count != 1 || commit_error_count != 0 ||
                    bad_commit_reject_count != 1 ||
                    duplicate_commit_reject_count != 1 ||
                    timeout_count != 0 || envelope_error_count != 1) begin
                    $display("ERROR counters crc=%0d/%0d commit=%0d/%0d bad=%0d dup=%0d timeout=%0d envelope=%0d",
                        crc_ok_count, crc_error_count, commit_ok_count,
                        commit_error_count, bad_commit_reject_count,
                        duplicate_commit_reject_count, timeout_count,
                        envelope_error_count);
                    errors = errors + 1;
                end
                if (sync_cycles != 50) begin
                    $display("ERROR sync width cycles=%0d", sync_cycles);
                    errors = errors + 1;
                end
                if (recovery_flush_count != 1) begin
                    $display("ERROR recovery flush count=%0d", recovery_flush_count);
                    errors = errors + 1;
                end
                if (errors == 0)
                    $display("TB_CH0_SPI_CONTROLLER_OK transactions=%0d bytes=%0d phase_flush=%0d b_to_next_a_ns=%0d",
                             transaction_count, output_count,
                             recovery_flush_count, B_TO_NEXT_A_GAP_NS);
                else
                    $display("TB_CH0_SPI_CONTROLLER_FAIL errors=%0d", errors);
                $finish_and_return(errors != 0);
            end
            begin
                #250000000;
                $display("ERROR timeout state=%0d req=%0d resp=%0d out=%0d", debug_state, request_count, response_count, output_count);
                $finish_and_return(1);
            end
        join_any
    end
endmodule
