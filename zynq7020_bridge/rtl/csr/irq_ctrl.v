module irq_ctrl (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [15:0] event_set,
    input  wire        clear_valid,
    input  wire [15:0] clear_w1c,
    input  wire        mask_write_valid,
    input  wire [15:0] mask_write_data,
    output reg  [15:0] status,
    output reg  [15:0] mask,
    output wire        irq
);
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            status <= 16'h0000;
            mask <= 16'h0000;
        end else begin
            status <= (status | event_set) & ~(clear_valid ? clear_w1c : 16'h0000);
            if (mask_write_valid)
                mask <= mask_write_data;
        end
    end

    assign irq = |(status & mask);
endmodule
