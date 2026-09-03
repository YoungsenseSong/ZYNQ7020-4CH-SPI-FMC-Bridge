module crc32 #(
    parameter [31:0] POLYNOMIAL = 32'hEDB88320,
    parameter [31:0] INITIAL_VALUE = 32'hFFFFFFFF,
    parameter [31:0] FINAL_XOR = 32'hFFFFFFFF
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        clear,
    input  wire        data_valid,
    input  wire [7:0]  data_in,
    output wire [31:0] crc_value
);
    reg [31:0] crc_reg;
    integer bit_index;
    reg [31:0] next_crc;

    always @* begin
        next_crc = crc_reg ^ {24'h000000, data_in};
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            next_crc = next_crc[0] ? ((next_crc >> 1) ^ POLYNOMIAL)
                                    : (next_crc >> 1);
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
