module rr_watermark_scheduler #(
    parameter HIGH_WATER = 14336,
    parameter MAX_BURST_RECORDS = 4
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [39:0] in_data,
    input  wire [3:0]  in_valid,
    input  wire [63:0] in_level,
    output reg  [3:0]  in_ready,
    output reg  [7:0]  out_data,
    output reg  [1:0]  out_channel,
    output reg         out_last,
    output reg         out_error,
    output reg         out_valid,
    input  wire        out_ready
);
    reg active;
    reg [1:0] active_channel;
    reg [1:0] last_grant;
    reg [15:0] burst_records;
    reg [3:0] urgent_mask;
    reg [3:0] eligible_mask;
    reg [1:0] selected_channel;
    reg selected_valid;

    function [1:0] pick_after;
        input [1:0] previous;
        input [3:0] mask;
        begin
            pick_after = previous;
            case (previous)
                2'd0: begin
                    if (mask[1]) pick_after = 2'd1;
                    else if (mask[2]) pick_after = 2'd2;
                    else if (mask[3]) pick_after = 2'd3;
                    else if (mask[0]) pick_after = 2'd0;
                end
                2'd1: begin
                    if (mask[2]) pick_after = 2'd2;
                    else if (mask[3]) pick_after = 2'd3;
                    else if (mask[0]) pick_after = 2'd0;
                    else if (mask[1]) pick_after = 2'd1;
                end
                2'd2: begin
                    if (mask[3]) pick_after = 2'd3;
                    else if (mask[0]) pick_after = 2'd0;
                    else if (mask[1]) pick_after = 2'd1;
                    else if (mask[2]) pick_after = 2'd2;
                end
                default: begin
                    if (mask[0]) pick_after = 2'd0;
                    else if (mask[1]) pick_after = 2'd1;
                    else if (mask[2]) pick_after = 2'd2;
                    else if (mask[3]) pick_after = 2'd3;
                end
            endcase
        end
    endfunction

    always @* begin
        urgent_mask[0] = in_valid[0] && (in_level[15:0] >= HIGH_WATER);
        urgent_mask[1] = in_valid[1] && (in_level[31:16] >= HIGH_WATER);
        urgent_mask[2] = in_valid[2] && (in_level[47:32] >= HIGH_WATER);
        urgent_mask[3] = in_valid[3] && (in_level[63:48] >= HIGH_WATER);
        eligible_mask = (urgent_mask != 0) ? urgent_mask : in_valid;

        selected_valid = active ? in_valid[active_channel] : (eligible_mask != 0);
        selected_channel = active ? active_channel : pick_after(last_grant, eligible_mask);
        in_ready = 4'b0000;
        out_data = 8'd0;
        out_last = 1'b0;
        out_error = 1'b0;
        out_channel = selected_channel;
        out_valid = selected_valid;

        case (selected_channel)
            2'd0: begin out_data = in_data[7:0];   out_last = in_data[8];  out_error = in_data[9];  end
            2'd1: begin out_data = in_data[17:10]; out_last = in_data[18]; out_error = in_data[19]; end
            2'd2: begin out_data = in_data[27:20]; out_last = in_data[28]; out_error = in_data[29]; end
            2'd3: begin out_data = in_data[37:30]; out_last = in_data[38]; out_error = in_data[39]; end
        endcase

        if (out_valid && out_ready)
            in_ready[selected_channel] = 1'b1;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active <= 1'b0;
            active_channel <= 2'd0;
            last_grant <= 2'd3;
            burst_records <= 16'd0;
        end else if (out_valid && out_ready) begin
            if (!active) begin
                active_channel <= selected_channel;
                burst_records <= out_last ? 16'd0 : 16'd0;
                if (!out_last)
                    active <= 1'b1;
                else
                    last_grant <= selected_channel;
            end else if (out_last) begin
                last_grant <= active_channel;
                if ((burst_records + 1'b1) >= MAX_BURST_RECORDS) begin
                    active <= 1'b0;
                    burst_records <= 16'd0;
                end else begin
                    // End of a record is also a legal preemption point. Release
                    // the channel so urgent peers can be reconsidered.
                    active <= 1'b0;
                    burst_records <= burst_records + 1'b1;
                end
            end
        end else if (active && !in_valid[active_channel]) begin
            active <= 1'b0;
            last_grant <= active_channel;
        end
    end
endmodule
