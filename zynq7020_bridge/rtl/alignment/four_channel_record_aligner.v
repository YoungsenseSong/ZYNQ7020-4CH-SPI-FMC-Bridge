`timescale 1ns/1ps

module four_channel_record_aligner #(
    parameter RECORD_BYTES = 248,
    parameter [3:0] ACTIVE_CHANNEL_MASK = 4'b1111
) (
    input  wire         clk,
    input  wire         reset_n,
    input  wire [31:0]  expected_epoch,
    input  wire [39:0]  in_data,
    input  wire [3:0]   in_valid,
    output reg  [3:0]   in_ready,
    output reg  [7:0]   out_data,
    output reg  [1:0]   out_channel,
    output reg          out_last,
    output wire         out_error,
    output reg          out_valid,
    input  wire         out_ready,
    output wire [3:0]   buffered_mask,
    output wire         emitting,
    output reg  [31:0]  aligned_group_count,
    output wire [127:0] stale_drop_count,
    output reg  [31:0]  metadata_error_count,
    output reg  [31:0]  last_aligned_epoch,
    output reg  [63:0]  last_aligned_index
);
    localparam [15:0] LAST_BYTE = RECORD_BYTES - 1;

    reg [7:0] record0 [0:RECORD_BYTES-1];
    reg [7:0] record1 [0:RECORD_BYTES-1];
    reg [7:0] record2 [0:RECORD_BYTES-1];
    reg [7:0] record3 [0:RECORD_BYTES-1];

    reg [15:0] load_count0;
    reg [15:0] load_count1;
    reg [15:0] load_count2;
    reg [15:0] load_count3;
    reg slot_valid0;
    reg slot_valid1;
    reg slot_valid2;
    reg slot_valid3;
    reg slot_synced0;
    reg slot_synced1;
    reg slot_synced2;
    reg slot_synced3;
    reg [31:0] slot_epoch0;
    reg [31:0] slot_epoch1;
    reg [31:0] slot_epoch2;
    reg [31:0] slot_epoch3;
    reg [63:0] slot_index0;
    reg [63:0] slot_index1;
    reg [63:0] slot_index2;
    reg [63:0] slot_index3;
    reg [31:0] drop_count0;
    reg [31:0] drop_count1;
    reg [31:0] drop_count2;
    reg [31:0] drop_count3;

    reg emit_active;
    reg [1:0] emit_channel;
    reg [15:0] emit_count;

    wire [9:0] word0 = in_data[9:0];
    wire [9:0] word1 = in_data[19:10];
    wire [9:0] word2 = in_data[29:20];
    wire [9:0] word3 = in_data[39:30];
    wire accept0 = in_valid[0] && in_ready[0];
    wire accept1 = in_valid[1] && in_ready[1];
    wire accept2 = in_valid[2] && in_ready[2];
    wire accept3 = in_valid[3] && in_ready[3];
    wire frame_error0 = accept0 &&
        (word0[9] || (word0[8] != (load_count0 == LAST_BYTE)));
    wire frame_error1 = accept1 &&
        (word1[9] || (word1[8] != (load_count1 == LAST_BYTE)));
    wire frame_error2 = accept2 &&
        (word2[9] || (word2[8] != (load_count2 == LAST_BYTE)));
    wire frame_error3 = accept3 &&
        (word3[9] || (word3[8] != (load_count3 == LAST_BYTE)));
    wire [2:0] frame_error_events = {2'b00, frame_error0} +
                                    {2'b00, frame_error1} +
                                    {2'b00, frame_error2} +
                                    {2'b00, frame_error3};
    localparam [1:0] FIRST_ACTIVE_CHANNEL = ACTIVE_CHANNEL_MASK[0] ? 2'd0 :
                                            ACTIVE_CHANNEL_MASK[1] ? 2'd1 :
                                            ACTIVE_CHANNEL_MASK[2] ? 2'd2 : 2'd3;
    wire [3:0] slot_valid_mask =
        {slot_valid3, slot_valid2, slot_valid1, slot_valid0};
    wire [3:0] slot_synced_mask =
        {slot_synced3, slot_synced2, slot_synced1, slot_synced0};
    wire all_valid = (slot_valid_mask & ACTIVE_CHANNEL_MASK) ==
                     ACTIVE_CHANNEL_MASK;
    wire all_synced = (slot_synced_mask & ACTIVE_CHANNEL_MASK) ==
                      ACTIVE_CHANNEL_MASK;
    wire [31:0] reference_epoch =
        (FIRST_ACTIVE_CHANNEL == 2'd0) ? slot_epoch0 :
        (FIRST_ACTIVE_CHANNEL == 2'd1) ? slot_epoch1 :
        (FIRST_ACTIVE_CHANNEL == 2'd2) ? slot_epoch2 : slot_epoch3;
    wire [63:0] reference_index =
        (FIRST_ACTIVE_CHANNEL == 2'd0) ? slot_index0 :
        (FIRST_ACTIVE_CHANNEL == 2'd1) ? slot_index1 :
        (FIRST_ACTIVE_CHANNEL == 2'd2) ? slot_index2 : slot_index3;
    wire epochs_equal = (!ACTIVE_CHANNEL_MASK[0] || (slot_epoch0 == reference_epoch)) &&
                        (!ACTIVE_CHANNEL_MASK[1] || (slot_epoch1 == reference_epoch)) &&
                        (!ACTIVE_CHANNEL_MASK[2] || (slot_epoch2 == reference_epoch)) &&
                        (!ACTIVE_CHANNEL_MASK[3] || (slot_epoch3 == reference_epoch));
    wire indexes_equal = (!ACTIVE_CHANNEL_MASK[0] || (slot_index0 == reference_index)) &&
                         (!ACTIVE_CHANNEL_MASK[1] || (slot_index1 == reference_index)) &&
                         (!ACTIVE_CHANNEL_MASK[2] || (slot_index2 == reference_index)) &&
                         (!ACTIVE_CHANNEL_MASK[3] || (slot_index3 == reference_index));

    reg [31:0] newest_epoch;
    reg [63:0] newest_index;

    function epoch_before;
        input [31:0] left;
        input [31:0] right;
        reg [31:0] difference;
        begin
            difference = left - right;
            epoch_before = difference[31] && (difference != 32'h80000000);
        end
    endfunction

    function has_next_active;
        input [1:0] current;
        begin
            case (current)
                2'd0: has_next_active = |ACTIVE_CHANNEL_MASK[3:1];
                2'd1: has_next_active = |ACTIVE_CHANNEL_MASK[3:2];
                2'd2: has_next_active = ACTIVE_CHANNEL_MASK[3];
                default: has_next_active = 1'b0;
            endcase
        end
    endfunction

    function [1:0] next_active_channel;
        input [1:0] current;
        begin
            case (current)
                2'd0: next_active_channel = ACTIVE_CHANNEL_MASK[1] ? 2'd1 :
                                             ACTIVE_CHANNEL_MASK[2] ? 2'd2 : 2'd3;
                2'd1: next_active_channel = ACTIVE_CHANNEL_MASK[2] ? 2'd2 : 2'd3;
                2'd2: next_active_channel = 2'd3;
                default: next_active_channel = FIRST_ACTIVE_CHANNEL;
            endcase
        end
    endfunction

    always @* begin
        newest_epoch = reference_epoch;
        if (ACTIVE_CHANNEL_MASK[1] && epoch_before(newest_epoch, slot_epoch1))
            newest_epoch = slot_epoch1;
        if (ACTIVE_CHANNEL_MASK[2] && epoch_before(newest_epoch, slot_epoch2))
            newest_epoch = slot_epoch2;
        if (ACTIVE_CHANNEL_MASK[3] && epoch_before(newest_epoch, slot_epoch3))
            newest_epoch = slot_epoch3;

        newest_index = reference_index;
        if (ACTIVE_CHANNEL_MASK[1] && (slot_index1 > newest_index))
            newest_index = slot_index1;
        if (ACTIVE_CHANNEL_MASK[2] && (slot_index2 > newest_index))
            newest_index = slot_index2;
        if (ACTIVE_CHANNEL_MASK[3] && (slot_index3 > newest_index))
            newest_index = slot_index3;
    end

    assign buffered_mask = {slot_valid3, slot_valid2, slot_valid1, slot_valid0};
    assign emitting = emit_active;
    assign stale_drop_count = {drop_count3, drop_count2, drop_count1, drop_count0};
    assign out_error = 1'b0;

    always @* begin
        in_ready = 4'b0000;
        if (!emit_active) begin
            in_ready[0] = ACTIVE_CHANNEL_MASK[0] && !slot_valid0;
            in_ready[1] = ACTIVE_CHANNEL_MASK[1] && !slot_valid1;
            in_ready[2] = ACTIVE_CHANNEL_MASK[2] && !slot_valid2;
            in_ready[3] = ACTIVE_CHANNEL_MASK[3] && !slot_valid3;
        end

        out_data = 8'h00;
        out_channel = emit_channel;
        out_last = emit_active && (emit_count == LAST_BYTE);
        out_valid = emit_active;
        case (emit_channel)
            2'd0: out_data = record0[emit_count];
            2'd1: out_data = record1[emit_count];
            2'd2: out_data = record2[emit_count];
            default: out_data = record3[emit_count];
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            load_count0 <= 16'd0;
            load_count1 <= 16'd0;
            load_count2 <= 16'd0;
            load_count3 <= 16'd0;
            slot_valid0 <= 1'b0;
            slot_valid1 <= 1'b0;
            slot_valid2 <= 1'b0;
            slot_valid3 <= 1'b0;
            slot_synced0 <= 1'b0;
            slot_synced1 <= 1'b0;
            slot_synced2 <= 1'b0;
            slot_synced3 <= 1'b0;
            slot_epoch0 <= 32'd0;
            slot_epoch1 <= 32'd0;
            slot_epoch2 <= 32'd0;
            slot_epoch3 <= 32'd0;
            slot_index0 <= 64'd0;
            slot_index1 <= 64'd0;
            slot_index2 <= 64'd0;
            slot_index3 <= 64'd0;
            drop_count0 <= 32'd0;
            drop_count1 <= 32'd0;
            drop_count2 <= 32'd0;
            drop_count3 <= 32'd0;
            emit_active <= 1'b0;
            emit_channel <= 2'd0;
            emit_count <= 16'd0;
            aligned_group_count <= 32'd0;
            metadata_error_count <= 32'd0;
            last_aligned_epoch <= 32'd0;
            last_aligned_index <= 64'd0;
        end else begin
            if (frame_error_events != 0)
                metadata_error_count <= metadata_error_count + frame_error_events;

            if (accept0) begin
                if (frame_error0) begin
                    load_count0 <= 16'd0;
                    slot_synced0 <= 1'b0;
                end else begin
                    record0[load_count0] <= word0[7:0];
                    case (load_count0)
                        16'd12: slot_epoch0[7:0] <= word0[7:0];
                        16'd13: slot_epoch0[15:8] <= word0[7:0];
                        16'd14: slot_epoch0[23:16] <= word0[7:0];
                        16'd15: slot_epoch0[31:24] <= word0[7:0];
                        16'd24: slot_index0[7:0] <= word0[7:0];
                        16'd25: slot_index0[15:8] <= word0[7:0];
                        16'd26: slot_index0[23:16] <= word0[7:0];
                        16'd27: slot_index0[31:24] <= word0[7:0];
                        16'd28: slot_index0[39:32] <= word0[7:0];
                        16'd29: slot_index0[47:40] <= word0[7:0];
                        16'd30: slot_index0[55:48] <= word0[7:0];
                        16'd31: slot_index0[63:56] <= word0[7:0];
                        16'd32: slot_synced0 <= word0[5] && !word0[6];
                    endcase
                    if (word0[8]) begin
                        slot_valid0 <= 1'b1;
                        load_count0 <= 16'd0;
                    end else begin
                        load_count0 <= load_count0 + 1'b1;
                    end
                end
            end

            if (accept1) begin
                if (frame_error1) begin
                    load_count1 <= 16'd0;
                    slot_synced1 <= 1'b0;
                end else begin
                    record1[load_count1] <= word1[7:0];
                    case (load_count1)
                        16'd12: slot_epoch1[7:0] <= word1[7:0];
                        16'd13: slot_epoch1[15:8] <= word1[7:0];
                        16'd14: slot_epoch1[23:16] <= word1[7:0];
                        16'd15: slot_epoch1[31:24] <= word1[7:0];
                        16'd24: slot_index1[7:0] <= word1[7:0];
                        16'd25: slot_index1[15:8] <= word1[7:0];
                        16'd26: slot_index1[23:16] <= word1[7:0];
                        16'd27: slot_index1[31:24] <= word1[7:0];
                        16'd28: slot_index1[39:32] <= word1[7:0];
                        16'd29: slot_index1[47:40] <= word1[7:0];
                        16'd30: slot_index1[55:48] <= word1[7:0];
                        16'd31: slot_index1[63:56] <= word1[7:0];
                        16'd32: slot_synced1 <= word1[5] && !word1[6];
                    endcase
                    if (word1[8]) begin
                        slot_valid1 <= 1'b1;
                        load_count1 <= 16'd0;
                    end else begin
                        load_count1 <= load_count1 + 1'b1;
                    end
                end
            end

            if (accept2) begin
                if (frame_error2) begin
                    load_count2 <= 16'd0;
                    slot_synced2 <= 1'b0;
                end else begin
                    record2[load_count2] <= word2[7:0];
                    case (load_count2)
                        16'd12: slot_epoch2[7:0] <= word2[7:0];
                        16'd13: slot_epoch2[15:8] <= word2[7:0];
                        16'd14: slot_epoch2[23:16] <= word2[7:0];
                        16'd15: slot_epoch2[31:24] <= word2[7:0];
                        16'd24: slot_index2[7:0] <= word2[7:0];
                        16'd25: slot_index2[15:8] <= word2[7:0];
                        16'd26: slot_index2[23:16] <= word2[7:0];
                        16'd27: slot_index2[31:24] <= word2[7:0];
                        16'd28: slot_index2[39:32] <= word2[7:0];
                        16'd29: slot_index2[47:40] <= word2[7:0];
                        16'd30: slot_index2[55:48] <= word2[7:0];
                        16'd31: slot_index2[63:56] <= word2[7:0];
                        16'd32: slot_synced2 <= word2[5] && !word2[6];
                    endcase
                    if (word2[8]) begin
                        slot_valid2 <= 1'b1;
                        load_count2 <= 16'd0;
                    end else begin
                        load_count2 <= load_count2 + 1'b1;
                    end
                end
            end

            if (accept3) begin
                if (frame_error3) begin
                    load_count3 <= 16'd0;
                    slot_synced3 <= 1'b0;
                end else begin
                    record3[load_count3] <= word3[7:0];
                    case (load_count3)
                        16'd12: slot_epoch3[7:0] <= word3[7:0];
                        16'd13: slot_epoch3[15:8] <= word3[7:0];
                        16'd14: slot_epoch3[23:16] <= word3[7:0];
                        16'd15: slot_epoch3[31:24] <= word3[7:0];
                        16'd24: slot_index3[7:0] <= word3[7:0];
                        16'd25: slot_index3[15:8] <= word3[7:0];
                        16'd26: slot_index3[23:16] <= word3[7:0];
                        16'd27: slot_index3[31:24] <= word3[7:0];
                        16'd28: slot_index3[39:32] <= word3[7:0];
                        16'd29: slot_index3[47:40] <= word3[7:0];
                        16'd30: slot_index3[55:48] <= word3[7:0];
                        16'd31: slot_index3[63:56] <= word3[7:0];
                        16'd32: slot_synced3 <= word3[5] && !word3[6];
                    endcase
                    if (word3[8]) begin
                        slot_valid3 <= 1'b1;
                        load_count3 <= 16'd0;
                    end else begin
                        load_count3 <= load_count3 + 1'b1;
                    end
                end
            end

            if (!emit_active && all_valid) begin
                if (!all_synced) begin
                    if (ACTIVE_CHANNEL_MASK[0] && !slot_synced0) begin slot_valid0 <= 1'b0; drop_count0 <= drop_count0 + 1'b1; end
                    if (ACTIVE_CHANNEL_MASK[1] && !slot_synced1) begin slot_valid1 <= 1'b0; drop_count1 <= drop_count1 + 1'b1; end
                    if (ACTIVE_CHANNEL_MASK[2] && !slot_synced2) begin slot_valid2 <= 1'b0; drop_count2 <= drop_count2 + 1'b1; end
                    if (ACTIVE_CHANNEL_MASK[3] && !slot_synced3) begin slot_valid3 <= 1'b0; drop_count3 <= drop_count3 + 1'b1; end
                    metadata_error_count <= metadata_error_count + 1'b1;
                end else if (!epochs_equal) begin
                    if (ACTIVE_CHANNEL_MASK[0] && (slot_epoch0 != newest_epoch)) begin slot_valid0 <= 1'b0; drop_count0 <= drop_count0 + 1'b1; end
                    if (ACTIVE_CHANNEL_MASK[1] && (slot_epoch1 != newest_epoch)) begin slot_valid1 <= 1'b0; drop_count1 <= drop_count1 + 1'b1; end
                    if (ACTIVE_CHANNEL_MASK[2] && (slot_epoch2 != newest_epoch)) begin slot_valid2 <= 1'b0; drop_count2 <= drop_count2 + 1'b1; end
                    if (ACTIVE_CHANNEL_MASK[3] && (slot_epoch3 != newest_epoch)) begin slot_valid3 <= 1'b0; drop_count3 <= drop_count3 + 1'b1; end
                    metadata_error_count <= metadata_error_count + 1'b1;
                end else if (reference_epoch != expected_epoch) begin
                    if (ACTIVE_CHANNEL_MASK[0]) begin slot_valid0 <= 1'b0; drop_count0 <= drop_count0 + 1'b1; end
                    if (ACTIVE_CHANNEL_MASK[1]) begin slot_valid1 <= 1'b0; drop_count1 <= drop_count1 + 1'b1; end
                    if (ACTIVE_CHANNEL_MASK[2]) begin slot_valid2 <= 1'b0; drop_count2 <= drop_count2 + 1'b1; end
                    if (ACTIVE_CHANNEL_MASK[3]) begin slot_valid3 <= 1'b0; drop_count3 <= drop_count3 + 1'b1; end
                    metadata_error_count <= metadata_error_count + 1'b1;
                end else if (!indexes_equal) begin
                    if (ACTIVE_CHANNEL_MASK[0] && (slot_index0 != newest_index)) begin slot_valid0 <= 1'b0; drop_count0 <= drop_count0 + 1'b1; end
                    if (ACTIVE_CHANNEL_MASK[1] && (slot_index1 != newest_index)) begin slot_valid1 <= 1'b0; drop_count1 <= drop_count1 + 1'b1; end
                    if (ACTIVE_CHANNEL_MASK[2] && (slot_index2 != newest_index)) begin slot_valid2 <= 1'b0; drop_count2 <= drop_count2 + 1'b1; end
                    if (ACTIVE_CHANNEL_MASK[3] && (slot_index3 != newest_index)) begin slot_valid3 <= 1'b0; drop_count3 <= drop_count3 + 1'b1; end
                    metadata_error_count <= metadata_error_count + 1'b1;
                end else begin
                    emit_active <= 1'b1;
                    emit_channel <= FIRST_ACTIVE_CHANNEL;
                    emit_count <= 16'd0;
                end
            end

            if (emit_active && out_ready) begin
                if (emit_count == LAST_BYTE) begin
                    emit_count <= 16'd0;
                    if (!has_next_active(emit_channel)) begin
                        emit_active <= 1'b0;
                        emit_channel <= 2'd0;
                        slot_valid0 <= 1'b0;
                        slot_valid1 <= 1'b0;
                        slot_valid2 <= 1'b0;
                        slot_valid3 <= 1'b0;
                        aligned_group_count <= aligned_group_count + 1'b1;
                        last_aligned_epoch <= reference_epoch;
                        last_aligned_index <= reference_index;
                    end else begin
                        emit_channel <= next_active_channel(emit_channel);
                    end
                end else begin
                    emit_count <= emit_count + 1'b1;
                end
            end
        end
    end
endmodule
