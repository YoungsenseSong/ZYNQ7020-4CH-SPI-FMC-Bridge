`timescale 1ns/1ps

module tb_block_builder;
    localparam integer RECORD_BYTES = 248;
    localparam integer TWO_RECORD_PAYLOAD_BYTES = 496;
    localparam integer HEADER_BYTES = 64;
    localparam integer GOLDEN_BLOCK_BYTES = 560;

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg [7:0] in_data = 8'd0;
    reg [1:0] in_channel = 2'd0;
    reg in_last = 1'b0;
    reg in_error = 1'b0;
    reg in_valid = 1'b0;
    wire in_ready;
    reg [31:0] sync_epoch = 32'h10203040;
    reg [63:0] fpga_tick = 64'd0;
    reg flush = 1'b0;
    wire alloc_request;
    wire alloc_grant = alloc_request;
    wire alloc_bank = 1'b0;
    wire write_valid;
    wire write_bank;
    wire [15:0] write_address;
    wire [7:0] write_data;
    wire seal_valid;
    wire seal_bank;
    wire [15:0] seal_length;
    wire [31:0] seal_sequence;
    wire [31:0] current_sequence;

    reg [7:0] golden [0:GOLDEN_BLOCK_BYTES-1];
    reg [7:0] observed [0:GOLDEN_BLOCK_BYTES-1];
    integer write_count = 0;
    reg saw_seal = 1'b0;
    string golden_dir;

    always #5 clk = ~clk;

    block_builder #(
        .BLOCK_MAGIC(32'h31425046),
        .PROTOCOL_VERSION(16'd1),
        .HEADER_BYTES(HEADER_BYTES),
        .RECORD_BYTES(RECORD_BYTES),
        .TARGET_PAYLOAD_BYTES(TWO_RECORD_PAYLOAD_BYTES),
        .MAX_PAYLOAD_BYTES(TWO_RECORD_PAYLOAD_BYTES),
        .TIMEOUT_CYCLES(0),
        .INITIAL_SEQUENCE(32'h89ABCDEF)
    ) dut (
        .clk(clk), .reset_n(reset_n), .in_data(in_data),
        .in_channel(in_channel), .in_last(in_last), .in_error(in_error),
        .in_valid(in_valid), .in_ready(in_ready), .sync_epoch(sync_epoch),
        .fpga_tick(fpga_tick), .flush(flush), .alloc_request(alloc_request),
        .alloc_grant(alloc_grant), .alloc_bank(alloc_bank),
        .write_valid(write_valid), .write_bank(write_bank),
        .write_address(write_address), .write_data(write_data),
        .seal_valid(seal_valid), .seal_bank(seal_bank),
        .seal_length(seal_length), .seal_sequence(seal_sequence),
        .current_sequence(current_sequence)
    );

    always @(posedge clk) begin
        if (!reset_n) begin
            write_count <= 0;
            saw_seal <= 1'b0;
        end else begin
            if (write_valid) begin
                if (write_address >= GOLDEN_BLOCK_BYTES)
                    $fatal(1, "write address out of range: %0d", write_address);
                observed[write_address] <= write_data;
                write_count <= write_count + 1;
            end
            if (seal_valid)
                saw_seal <= 1'b1;
        end
    end

    task automatic reset_dut;
        integer clear_index;
        begin
            reset_n = 1'b0;
            in_valid = 1'b0;
            in_last = 1'b0;
            in_error = 1'b0;
            flush = 1'b0;
            for (clear_index = 0; clear_index < GOLDEN_BLOCK_BYTES;
                 clear_index = clear_index + 1)
                observed[clear_index] = 8'd0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            reset_n = 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask

    task automatic load_golden;
        integer fd;
        integer bytes_read;
        begin
            fd = $fopen({golden_dir, "/fpga_block_two_records.bin"}, "rb");
            if (fd == 0)
                $fatal(1, "cannot open golden block in %s", golden_dir);
            bytes_read = $fread(golden, fd);
            $fclose(fd);
            if (bytes_read != GOLDEN_BLOCK_BYTES)
                $fatal(1, "golden block: expected %0d bytes, read %0d",
                       GOLDEN_BLOCK_BYTES, bytes_read);
        end
    endtask

    task automatic feed_payload(input integer byte_count, input integer flush_at);
        integer payload_index;
        begin
            payload_index = 0;
            while (payload_index < byte_count) begin
                @(negedge clk);
                if (in_ready) begin
                    in_data = golden[HEADER_BYTES + payload_index];
                    in_channel = (payload_index < RECORD_BYTES) ? 2'd2 : 2'd3;
                    fpga_tick = (payload_index < RECORD_BYTES) ?
                        64'h0102030405060708 : 64'h2122232425262728;
                    in_last = ((payload_index % RECORD_BYTES) == RECORD_BYTES - 1);
                    flush = (payload_index == flush_at);
                    in_valid = 1'b1;
                    payload_index = payload_index + 1;
                end else begin
                    in_valid = 1'b0;
                    in_last = 1'b0;
                    flush = 1'b0;
                end
                if (seal_valid && (payload_index < byte_count))
                    $fatal(1, "block sealed in the middle of a record");
            end
            @(negedge clk);
            in_valid = 1'b0;
            in_last = 1'b0;
            flush = 1'b0;
        end
    endtask

    task automatic wait_for_seal;
        integer wait_cycles;
        begin
            wait_cycles = 0;
            while (!saw_seal && (wait_cycles < 1000)) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (wait_cycles >= 1000)
                $fatal(1, "block builder timeout");
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic run_exact_golden;
        integer compare_index;
        begin
            reset_dut();
            feed_payload(TWO_RECORD_PAYLOAD_BYTES, -1);
            wait_for_seal();
            if ((seal_length != GOLDEN_BLOCK_BYTES) ||
                (seal_sequence != 32'h89ABCDEF) || (write_count != GOLDEN_BLOCK_BYTES))
                $fatal(1, "golden block metadata mismatch len=%0d seq=%08x writes=%0d",
                       seal_length, seal_sequence, write_count);
            for (compare_index = 0; compare_index < GOLDEN_BLOCK_BYTES;
                 compare_index = compare_index + 1)
                if (observed[compare_index] !== golden[compare_index])
                    $fatal(1, "golden block mismatch at byte %0d got=%02x expected=%02x",
                           compare_index, observed[compare_index], golden[compare_index]);
            $display("PASS block builder exact shared golden vector");
        end
    endtask

    task automatic run_mid_record_flush;
        integer compare_index;
        begin
            reset_dut();
            feed_payload(RECORD_BYTES, 100);
            wait_for_seal();
            if ((seal_length != HEADER_BYTES + RECORD_BYTES) ||
                (write_count != HEADER_BYTES + RECORD_BYTES))
                $fatal(1, "mid-record flush split payload len=%0d writes=%0d",
                       seal_length, write_count);
            if ((observed[56] & 8'h04) == 0)
                $fatal(1, "mid-record flush did not set boundary warning flag");
            for (compare_index = 0; compare_index < RECORD_BYTES;
                 compare_index = compare_index + 1)
                if (observed[HEADER_BYTES + compare_index] !==
                    golden[HEADER_BYTES + compare_index])
                    $fatal(1, "flush payload mismatch at byte %0d", compare_index);
            $display("PASS block builder defers mid-record flush to record boundary");
        end
    endtask

    task automatic run_first_byte_flush;
        begin
            reset_dut();
            // A one-cycle flush coincident with the first byte of a record
            // must be remembered until that record's last byte.
            feed_payload(RECORD_BYTES, 0);
            wait_for_seal();
            if ((seal_length != HEADER_BYTES + RECORD_BYTES) ||
                (write_count != HEADER_BYTES + RECORD_BYTES))
                $fatal(1, "first-byte flush split payload len=%0d writes=%0d",
                       seal_length, write_count);
            if ((observed[56] & 8'h04) == 0)
                $fatal(1, "first-byte flush was not latched");
            $display("PASS block builder latches first-byte flush to boundary");
        end
    endtask

    initial begin
        if (!$value$plusargs("GOLDEN_DIR=%s", golden_dir))
            golden_dir = "../../protocol/golden";
        load_golden();
        run_exact_golden();
        run_mid_record_flush();
        run_first_byte_flush();
        $display("TB_BLOCK_BUILDER_OK");
        $finish;
    end
endmodule
