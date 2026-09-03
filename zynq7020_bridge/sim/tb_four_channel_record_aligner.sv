`timescale 1ns/1ps

module tb_four_channel_record_aligner;
    localparam RECORD_BYTES = 248;

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg [31:0] expected_epoch = 32'd7;
    reg [39:0] in_data = 40'd0;
    reg [3:0] in_valid = 4'd0;
    wire [3:0] in_ready;
    wire [7:0] out_data;
    wire [1:0] out_channel;
    wire out_last;
    wire out_error;
    wire out_valid;
    reg out_ready = 1'b1;
    wire [3:0] buffered_mask;
    wire emitting;
    wire [31:0] aligned_group_count;
    wire [127:0] stale_drop_count;
    wire [31:0] metadata_error_count;
    wire [31:0] last_aligned_epoch;
    wire [63:0] last_aligned_index;

    integer output_byte = 0;
    integer output_record = 0;
    integer output_group = 0;
    reg [7:0] expected_marker;

    always #5 clk = ~clk;

    four_channel_record_aligner #(.RECORD_BYTES(RECORD_BYTES)) dut (
        .clk(clk), .reset_n(reset_n), .expected_epoch(expected_epoch),
        .in_data(in_data), .in_valid(in_valid), .in_ready(in_ready),
        .out_data(out_data), .out_channel(out_channel), .out_last(out_last),
        .out_error(out_error), .out_valid(out_valid), .out_ready(out_ready),
        .buffered_mask(buffered_mask), .emitting(emitting),
        .aligned_group_count(aligned_group_count),
        .stale_drop_count(stale_drop_count),
        .metadata_error_count(metadata_error_count),
        .last_aligned_epoch(last_aligned_epoch),
        .last_aligned_index(last_aligned_index)
    );

    function automatic [7:0] record_byte;
        input integer position;
        input [31:0] epoch;
        input [63:0] sample_index;
        input synced;
        input [7:0] marker;
        begin
            record_byte = 8'h00;
            case (position)
                0: record_byte = 8'h4E;
                1: record_byte = 8'h52;
                2: record_byte = 8'h46;
                3: record_byte = 8'h31;
                4: record_byte = 8'h01;
                12: record_byte = epoch[7:0];
                13: record_byte = epoch[15:8];
                14: record_byte = epoch[23:16];
                15: record_byte = epoch[31:24];
                24: record_byte = sample_index[7:0];
                25: record_byte = sample_index[15:8];
                26: record_byte = sample_index[23:16];
                27: record_byte = sample_index[31:24];
                28: record_byte = sample_index[39:32];
                29: record_byte = sample_index[47:40];
                30: record_byte = sample_index[55:48];
                31: record_byte = sample_index[63:56];
                32: record_byte = synced ? 8'h20 : 8'h00;
                40: record_byte = marker;
                default: record_byte = position[7:0];
            endcase
        end
    endfunction

    task automatic send_record;
        input integer channel;
        input [31:0] epoch;
        input [63:0] sample_index;
        input synced;
        input [7:0] marker;
        integer position;
        reg [9:0] word_value;
        begin
            for (position = 0; position < RECORD_BYTES; position = position + 1) begin
                while (!in_ready[channel])
                    @(posedge clk);
                @(negedge clk);
                word_value = {1'b0, (position == RECORD_BYTES-1),
                              record_byte(position, epoch, sample_index,
                                          synced, marker)};
                in_data[channel*10 +: 10] = word_value;
                in_valid[channel] = 1'b1;
                @(negedge clk);
                in_valid[channel] = 1'b0;
                in_data[channel*10 +: 10] = 10'd0;
            end
        end
    endtask

    task automatic wait_for_group;
        input [31:0] expected_count;
        integer timeout;
        begin
            timeout = 0;
            while ((aligned_group_count != expected_count) && timeout < 10000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (aligned_group_count != expected_count)
                $fatal(1, "timeout waiting for aligned group %0d", expected_count);
        end
    endtask

    task automatic wait_for_drop0;
        input [31:0] expected_count;
        integer timeout;
        begin
            timeout = 0;
            while ((stale_drop_count[31:0] != expected_count) && timeout < 1000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (stale_drop_count[31:0] != expected_count)
                $fatal(1, "timeout waiting for channel 0 drop %0d", expected_count);
        end
    endtask

    task automatic wait_for_drop1;
        input [31:0] expected_count;
        integer timeout;
        begin
            timeout = 0;
            while ((stale_drop_count[63:32] != expected_count) && timeout < 1000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (stale_drop_count[63:32] != expected_count)
                $fatal(1, "timeout waiting for channel 1 drop %0d", expected_count);
        end
    endtask

    always @(posedge clk) begin
        if (out_valid && out_ready) begin
            if (out_error)
                $fatal(1, "aligned output unexpectedly marked error");
            if (out_channel != output_record[1:0])
                $fatal(1, "channel order mismatch got=%0d expected=%0d",
                       out_channel, output_record);
            if (output_byte == 40) begin
                expected_marker = 8'hA0 + output_group*16 + output_record;
                if (out_data != expected_marker)
                    $fatal(1, "marker mismatch group=%0d channel=%0d got=%02x expected=%02x",
                           output_group, output_record, out_data, expected_marker);
            end
            if (out_last != (output_byte == RECORD_BYTES-1))
                $fatal(1, "record boundary mismatch byte=%0d last=%0d",
                       output_byte, out_last);

            if (out_last) begin
                output_byte = 0;
                if (output_record == 3) begin
                    output_record = 0;
                    output_group = output_group + 1;
                end else begin
                    output_record = output_record + 1;
                end
            end else begin
                output_byte = output_byte + 1;
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        reset_n = 1'b1;

        send_record(0, 7, 0, 1'b1, 8'hA0);
        send_record(1, 7, 0, 1'b1, 8'hA1);
        send_record(2, 7, 0, 1'b1, 8'hA2);
        send_record(3, 7, 0, 1'b1, 8'hA3);
        wait_for_group(1);
        if ((last_aligned_epoch != 7) || (last_aligned_index != 0))
            $fatal(1, "first aligned key mismatch");

        send_record(0, 7, 96, 1'b0, 8'hEE);
        send_record(1, 7, 96, 1'b1, 8'hB1);
        send_record(2, 7, 96, 1'b1, 8'hB2);
        send_record(3, 7, 96, 1'b1, 8'hB3);
        wait_for_drop0(1);
        send_record(0, 7, 96, 1'b1, 8'hB0);
        wait_for_group(2);

        send_record(0, 7, 96, 1'b1, 8'hEF);
        send_record(1, 7, 192, 1'b1, 8'hC1);
        send_record(2, 7, 192, 1'b1, 8'hC2);
        send_record(3, 7, 192, 1'b1, 8'hC3);
        wait_for_drop0(2);
        send_record(0, 7, 192, 1'b1, 8'hC0);
        wait_for_group(3);

        send_record(0, 7, 288, 1'b1, 8'hD0);
        send_record(1, 6, 288, 1'b1, 8'hF1);
        send_record(2, 7, 288, 1'b1, 8'hD2);
        send_record(3, 7, 288, 1'b1, 8'hD3);
        wait_for_drop1(1);
        send_record(1, 7, 288, 1'b1, 8'hD1);
        wait_for_group(4);

        if (output_group != 4)
            $fatal(1, "output monitor saw %0d groups", output_group);
        if (metadata_error_count != 3)
            $fatal(1, "metadata error count got=%0d expected=3",
                   metadata_error_count);
        if ((last_aligned_epoch != 7) || (last_aligned_index != 288))
            $fatal(1, "last aligned key mismatch");
        if (buffered_mask != 0 || emitting)
            $fatal(1, "aligner did not return idle");

        $display("TB_FOUR_CHANNEL_RECORD_ALIGNER_OK groups=%0d drops=%0d/%0d/%0d/%0d errors=%0d",
                 aligned_group_count,
                 stale_drop_count[31:0], stale_drop_count[63:32],
                 stale_drop_count[95:64], stale_drop_count[127:96],
                 metadata_error_count);
        $finish;
    end
endmodule
