module bram_pingpong #(
    parameter TOTAL_BYTES = 32832,
    parameter WORDS = 16416,
    parameter ACK_POLICY = 0
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        alloc_request,
    output reg         alloc_grant,
    output reg         alloc_bank,
    input  wire        write_valid,
    input  wire        write_bank,
    input  wire [15:0] write_address,
    input  wire [7:0]  write_data,
    input  wire        seal_valid,
    input  wire        seal_bank,
    input  wire [15:0] seal_length,
    input  wire [31:0] seal_sequence,
    input  wire        read_request,
    input  wire        read_bank,
    input  wire [14:0] read_word_address,
    output reg         read_valid,
    output reg  [15:0] read_data,
    input  wire        claim_valid,
    input  wire        claim_bank,
    input  wire        ack_valid,
    input  wire [15:0] ack_value,
    output wire        ready_valid,
    output wire        ready_bank,
    output wire [15:0] ready_length,
    output wire [31:0] ready_sequence,
    output wire [2:0]  owner_bank0,
    output wire [2:0]  owner_bank1
);
    localparam OWNER_FREE = 3'd0;
    localparam OWNER_FILLING = 3'd1;
    localparam OWNER_READY = 3'd2;
    localparam OWNER_MCU_READING = 3'd3;

    reg [15:0] memory0 [0:WORDS-1];
    reg [15:0] memory1 [0:WORDS-1];
    reg [2:0] owner0;
    reg [2:0] owner1;
    reg [15:0] length0;
    reg [15:0] length1;
    reg [31:0] sequence0;
    reg [31:0] sequence1;
    reg last_allocated;

    assign ready_valid = (owner0 == OWNER_READY) || (owner0 == OWNER_MCU_READING) ||
                         (owner1 == OWNER_READY) || (owner1 == OWNER_MCU_READING);
    assign ready_bank = ((owner0 == OWNER_READY) || (owner0 == OWNER_MCU_READING)) ? 1'b0 : 1'b1;
    assign ready_length = ready_bank ? length1 : length0;
    assign ready_sequence = ready_bank ? sequence1 : sequence0;
    assign owner_bank0 = owner0;
    assign owner_bank1 = owner1;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            owner0 <= OWNER_FREE;
            owner1 <= OWNER_FREE;
            length0 <= 16'd0;
            length1 <= 16'd0;
            sequence0 <= 32'd0;
            sequence1 <= 32'd0;
            last_allocated <= 1'b1;
            alloc_grant <= 1'b0;
            alloc_bank <= 1'b0;
            read_valid <= 1'b0;
            read_data <= 16'd0;
        end else begin
            alloc_grant <= 1'b0;
            read_valid <= 1'b0;

            if (alloc_request) begin
                if ((owner0 == OWNER_FREE) && ((owner1 != OWNER_FREE) || last_allocated)) begin
                    owner0 <= OWNER_FILLING;
                    alloc_bank <= 1'b0;
                    alloc_grant <= 1'b1;
                    last_allocated <= 1'b0;
                end else if (owner1 == OWNER_FREE) begin
                    owner1 <= OWNER_FILLING;
                    alloc_bank <= 1'b1;
                    alloc_grant <= 1'b1;
                    last_allocated <= 1'b1;
                end
            end

            if (write_valid && (write_address < TOTAL_BYTES)) begin
                if (write_bank) begin
                    if (write_address[0])
                        memory1[write_address[15:1]][15:8] <= write_data;
                    else
                        memory1[write_address[15:1]][7:0] <= write_data;
                end else begin
                    if (write_address[0])
                        memory0[write_address[15:1]][15:8] <= write_data;
                    else
                        memory0[write_address[15:1]][7:0] <= write_data;
                end
            end

            if (seal_valid) begin
                if (seal_bank) begin
                    owner1 <= OWNER_READY;
                    length1 <= seal_length;
                    sequence1 <= seal_sequence;
                end else begin
                    owner0 <= OWNER_READY;
                    length0 <= seal_length;
                    sequence0 <= seal_sequence;
                end
            end

            if (claim_valid) begin
                if (claim_bank && (owner1 == OWNER_READY))
                    owner1 <= OWNER_MCU_READING;
                else if (!claim_bank && (owner0 == OWNER_READY))
                    owner0 <= OWNER_MCU_READING;
            end

            if (ack_valid && (ACK_POLICY != 0)) begin
                if ((owner0 == OWNER_MCU_READING) &&
                    ((ACK_POLICY == 2) || (ack_value == sequence0[15:0])))
                    owner0 <= OWNER_FREE;
                else if ((owner1 == OWNER_MCU_READING) &&
                         ((ACK_POLICY == 2) || (ack_value == sequence1[15:0])))
                    owner1 <= OWNER_FREE;
            end

            if (read_request) begin
                read_valid <= 1'b1;
                if (read_word_address < WORDS)
                    read_data <= read_bank ? memory1[read_word_address] : memory0[read_word_address];
                else
                    read_data <= 16'h0000;
            end
        end
    end
endmodule
