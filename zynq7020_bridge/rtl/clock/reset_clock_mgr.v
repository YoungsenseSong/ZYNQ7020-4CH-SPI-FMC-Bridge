module reset_clock_mgr #(
    parameter TICK_DIVIDER = 100
) (
    input  wire pl_clk,
    input  wire ext_reset_n,
    input  wire soft_reset,
    output wire clk_out,
    output wire reset_n,
    output reg  tick_pulse
);
    (* ASYNC_REG = "TRUE" *) reg [2:0] reset_sync;
    reg [31:0] tick_count;

    always @(posedge pl_clk or negedge ext_reset_n) begin
        if (!ext_reset_n)
            reset_sync <= 3'b000;
        else if (soft_reset)
            reset_sync <= 3'b000;
        else
            reset_sync <= {reset_sync[1:0], 1'b1};
    end

    always @(posedge pl_clk or negedge reset_sync[2]) begin
        if (!reset_sync[2]) begin
            tick_count <= 32'd0;
            tick_pulse <= 1'b0;
        end else if (TICK_DIVIDER <= 1) begin
            tick_count <= 32'd0;
            tick_pulse <= 1'b1;
        end else if (tick_count == TICK_DIVIDER - 1) begin
            tick_count <= 32'd0;
            tick_pulse <= 1'b1;
        end else begin
            tick_count <= tick_count + 1'b1;
            tick_pulse <= 1'b0;
        end
    end

    assign clk_out = pl_clk;
    assign reset_n = reset_sync[2];
endmodule
