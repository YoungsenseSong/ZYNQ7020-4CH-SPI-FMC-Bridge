module cdc_sync #(
    parameter WIDTH = 1,
    parameter RESET_VALUE = 0
) (
    input  wire             clk,
    input  wire             reset_n,
    input  wire [WIDTH-1:0] async_in,
    output wire [WIDTH-1:0] sync_out
);
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync_ff1;
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync_ff2;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sync_ff1 <= {WIDTH{RESET_VALUE[0]}};
            sync_ff2 <= {WIDTH{RESET_VALUE[0]}};
        end else begin
            sync_ff1 <= async_in;
            sync_ff2 <= sync_ff1;
        end
    end

    assign sync_out = sync_ff2;
endmodule
