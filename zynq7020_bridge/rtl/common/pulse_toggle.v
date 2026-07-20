module pulse_toggle (
    input  wire src_clk,
    input  wire src_reset_n,
    input  wire src_pulse,
    input  wire dst_clk,
    input  wire dst_reset_n,
    output wire dst_pulse
);
    reg src_toggle;
    (* ASYNC_REG = "TRUE" *) reg dst_sync1;
    (* ASYNC_REG = "TRUE" *) reg dst_sync2;
    reg dst_sync2_d;

    always @(posedge src_clk or negedge src_reset_n) begin
        if (!src_reset_n)
            src_toggle <= 1'b0;
        else if (src_pulse)
            src_toggle <= ~src_toggle;
    end

    always @(posedge dst_clk or negedge dst_reset_n) begin
        if (!dst_reset_n) begin
            dst_sync1 <= 1'b0;
            dst_sync2 <= 1'b0;
            dst_sync2_d <= 1'b0;
        end else begin
            dst_sync1 <= src_toggle;
            dst_sync2 <= dst_sync1;
            dst_sync2_d <= dst_sync2;
        end
    end

    assign dst_pulse = dst_sync2 ^ dst_sync2_d;
endmodule
