`timescale 1ns/1ps

module tb_spi_record_parser;
    localparam integer RECORD_BYTES = 248;

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg start = 1'b0;
    reg [15:0] expected_length = RECORD_BYTES;
    reg [7:0] in_data = 8'd0;
    reg in_valid = 1'b0;
    wire in_ready;
    wire [7:0] out_data;
    wire out_valid;
    reg out_ready = 1'b1;
    wire out_last;
    wire record_done_pulse;
    wire record_error_pulse;
    wire [31:0] good_count;
    wire [31:0] error_count;
    wire busy;

    reg [7:0] source [0:RECORD_BYTES-1];
    reg [7:0] emitted [0:RECORD_BYTES-1];
    integer emitted_count = 0;
    reg saw_done = 1'b0;
    reg saw_error = 1'b0;
    string golden_dir;

    always #5 clk = ~clk;

    spi_record_parser #(
        .MAX_RECORD_BYTES(RECORD_BYTES),
        .RECORD_BYTES(RECORD_BYTES),
        .CHECK_MAGIC(1),
        .MAGIC_VALUE(32'h3146524E),
        .VERSION_VALUE(8'd1),
        .RECORD_TYPE_VALUE(16'd1),
        .PAYLOAD_BYTES(16'd204),
        .CHECK_CRC(1)
    ) dut (
        .clk(clk), .reset_n(reset_n), .start(start),
        .expected_length(expected_length), .in_data(in_data),
        .in_valid(in_valid), .in_ready(in_ready), .out_data(out_data),
        .out_valid(out_valid), .out_ready(out_ready), .out_last(out_last),
        .record_done_pulse(record_done_pulse),
        .record_error_pulse(record_error_pulse), .good_count(good_count),
        .error_count(error_count), .busy(busy)
    );

    always @(posedge clk) begin
        if (!reset_n) begin
            emitted_count <= 0;
            saw_done <= 1'b0;
            saw_error <= 1'b0;
        end else begin
            if (out_valid && out_ready) begin
                if (emitted_count >= RECORD_BYTES)
                    $fatal(1, "parser emitted too many bytes");
                emitted[emitted_count] <= out_data;
                emitted_count <= emitted_count + 1;
                if (out_last != (emitted_count == RECORD_BYTES - 1))
                    $fatal(1, "out_last at wrong byte %0d", emitted_count);
            end
            if (record_done_pulse)
                saw_done <= 1'b1;
            if (record_error_pulse)
                saw_error <= 1'b1;
        end
    end

    task automatic reset_dut;
        begin
            reset_n = 1'b0;
            start = 1'b0;
            in_valid = 1'b0;
            in_data = 8'd0;
            expected_length = RECORD_BYTES;
            repeat (3) @(posedge clk);
            @(negedge clk);
            reset_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic load_vector(input string vector_path);
        integer fd;
        integer bytes_read;
        begin
            fd = $fopen(vector_path, "rb");
            if (fd == 0)
                $fatal(1, "cannot open %s", vector_path);
            bytes_read = $fread(source, fd);
            $fclose(fd);
            if (bytes_read != RECORD_BYTES)
                $fatal(1, "%s: expected %0d bytes, read %0d",
                       vector_path, RECORD_BYTES, bytes_read);
        end
    endtask

    task automatic run_case(input string filename, input bit expect_good);
        integer source_index;
        integer wait_cycles;
        integer compare_index;
        begin
            reset_dut();
            load_vector({golden_dir, "/", filename});

            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            source_index = 0;
            while (source_index < RECORD_BYTES) begin
                @(negedge clk);
                if (in_ready) begin
                    in_data = source[source_index];
                    in_valid = 1'b1;
                    source_index = source_index + 1;
                end else begin
                    in_valid = 1'b0;
                end
            end
            @(negedge clk);
            in_valid = 1'b0;

            wait_cycles = 0;
            while (busy && (wait_cycles < 2000)) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (wait_cycles >= 2000)
                $fatal(1, "%s: parser timeout", filename);
            repeat (3) @(posedge clk);

            if (expect_good) begin
                if (!saw_done || saw_error || (good_count != 1) ||
                    (error_count != 0) || (emitted_count != RECORD_BYTES))
                    $fatal(1, "%s: expected success done=%0d error=%0d good=%0d bad=%0d emitted=%0d",
                           filename, saw_done, saw_error, good_count,
                           error_count, emitted_count);
                for (compare_index = 0; compare_index < RECORD_BYTES;
                     compare_index = compare_index + 1)
                    if (emitted[compare_index] !== source[compare_index])
                        $fatal(1, "%s: emitted mismatch at byte %0d",
                               filename, compare_index);
            end else begin
                if (saw_done || !saw_error || (good_count != 0) ||
                    (error_count != 1) || (emitted_count != 0))
                    $fatal(1, "%s: expected rejection done=%0d error=%0d good=%0d bad=%0d emitted=%0d",
                           filename, saw_done, saw_error, good_count,
                           error_count, emitted_count);
            end
            $display("PASS parser %s", filename);
        end
    endtask

    task automatic run_length_rejection;
        begin
            reset_dut();
            expected_length = RECORD_BYTES - 1;
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            repeat (3) @(posedge clk);
            if (!saw_error || busy || (error_count != 1) || (emitted_count != 0))
                $fatal(1, "record length mismatch was not rejected");
            $display("PASS parser record-length rejection");
        end
    endtask

    initial begin
        if (!$value$plusargs("GOLDEN_DIR=%s", golden_dir))
            golden_dir = "../../protocol/golden";

        run_case("nrf_record_valid.bin", 1'b1);
        run_case("nrf_record_header_crc_bad.bin", 1'b0);
        run_case("nrf_record_payload_crc_bad.bin", 1'b0);
        run_length_rejection();
        $display("TB_SPI_RECORD_PARSER_OK");
        $finish;
    end
endmodule
