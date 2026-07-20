module channel_fifo_wrap #(
    parameter DATA_WIDTH = 10,
    parameter DEPTH = 16384,
    parameter ADDR_WIDTH = 14,
    parameter HIGH_WATER = 14336
) (
    input  wire                  clk,
    input  wire                  reset_n,
    input  wire [DATA_WIDTH-1:0] in_data,
    input  wire                  in_valid,
    output wire                  in_ready,
    output wire [DATA_WIDTH-1:0] out_data,
    output wire                  out_valid,
    input  wire                  out_ready,
    output wire                  almost_full,
    output wire [15:0]           level,
    output reg  [31:0]           drop_count
);
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] write_ptr;
    reg [ADDR_WIDTH-1:0] read_ptr;
    reg [ADDR_WIDTH:0] count;

    wire write_accept = in_valid && in_ready;
    wire read_accept = out_valid && out_ready;

    assign in_ready = (count < DEPTH);
    assign out_valid = (count != 0);
    assign out_data = memory[read_ptr];
    assign almost_full = (count >= HIGH_WATER);
    assign level = count[15:0];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            write_ptr <= {ADDR_WIDTH{1'b0}};
            read_ptr <= {ADDR_WIDTH{1'b0}};
            count <= {(ADDR_WIDTH+1){1'b0}};
            drop_count <= 32'd0;
        end else begin
            if (write_accept) begin
                memory[write_ptr] <= in_data;
                write_ptr <= write_ptr + 1'b1;
            end else if (in_valid && !in_ready) begin
                drop_count <= drop_count + 1'b1;
            end

            if (read_accept)
                read_ptr <= read_ptr + 1'b1;

            case ({write_accept, read_accept})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule
