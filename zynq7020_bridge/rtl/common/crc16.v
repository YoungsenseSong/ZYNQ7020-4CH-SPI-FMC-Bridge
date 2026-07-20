module crc16 #(
    parameter [15:0] POLYNOMIAL = 16'h1021,
    parameter [15:0] INITIAL_VALUE = 16'hFFFF,
    parameter [15:0] FINAL_XOR = 16'h0000
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        clear,
    input  wire        data_valid,
    input  wire [7:0]  data_in,
    output wire [15:0] crc_value
);
    reg [15:0] crc_reg;
    integer bit_index;
    reg [15:0] next_crc;

    always @* begin
        next_crc = crc_reg ^ {data_in, 8'h00};
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            next_crc = next_crc[15] ? ((next_crc << 1) ^ POLYNOMIAL)
                                     : (next_crc << 1);
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            crc_reg <= INITIAL_VALUE;
        else if (clear)
            crc_reg <= INITIAL_VALUE;
        else if (data_valid)
            crc_reg <= next_crc;
    end

    assign crc_value = crc_reg ^ FINAL_XOR;
endmodule
