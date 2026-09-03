`timescale 1ns/1ps

module tb_ch0_record_aligner;
    localparam integer RECORD_BYTES = 248;
    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg [31:0] expected_epoch;
    reg [39:0] in_data = 40'd0;
    reg [3:0] in_valid = 4'b0000;
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
    reg [7:0] golden [0:RECORD_BYTES-1];
    integer fh;
    integer count;
    integer i;
    integer output_count = 0;
    integer errors = 0;

    always #10 clk = ~clk;

    four_channel_record_aligner #(
        .RECORD_BYTES(RECORD_BYTES), .ACTIVE_CHANNEL_MASK(4'b0001)
    ) dut (
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

    always @(posedge clk) begin
        if (out_valid && out_ready) begin
            if (out_channel != 0 || out_data !== golden[output_count] ||
                out_last !== (output_count == RECORD_BYTES - 1))
                errors = errors + 1;
            output_count = output_count + 1;
        end
    end

    initial begin
        fh = $fopen("../../protocol/golden/nrf_record_valid.bin", "rb");
        if (fh == 0) $finish_and_return(1);
        count = $fread(golden, fh);
        $fclose(fh);
        if (count != RECORD_BYTES) $finish_and_return(1);
        expected_epoch = {golden[15], golden[14], golden[13], golden[12]};
        repeat (5) @(posedge clk);
        reset_n = 1'b1;
        for (i = 0; i < RECORD_BYTES; i = i + 1) begin
            @(negedge clk);
            while (!in_ready[0]) @(negedge clk);
            in_data[9:0] = {1'b0, (i == RECORD_BYTES - 1), golden[i]};
            in_valid = 4'b0001;
            @(negedge clk);
            in_valid = 4'b0000;
        end
        wait (output_count == RECORD_BYTES);
        repeat (3) @(posedge clk);
        if (aligned_group_count != 1 || metadata_error_count != 0 ||
            stale_drop_count != 0 || errors != 0) begin
            $display("TB_CH0_RECORD_ALIGNER_FAIL group=%0d metadata=%0d drops=%0d errors=%0d",
                     aligned_group_count, metadata_error_count,
                     stale_drop_count, errors);
            $finish_and_return(1);
        end
        $display("TB_CH0_RECORD_ALIGNER_OK bytes=%0d", output_count);
        $finish;
    end
endmodule
