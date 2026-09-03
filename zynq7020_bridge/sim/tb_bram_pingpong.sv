`timescale 1ns/1ps

module tb_bram_pingpong;
    localparam OWNER_FREE = 3'd0;
    localparam OWNER_FILLING = 3'd1;
    localparam OWNER_READY = 3'd2;
    localparam OWNER_MCU_READING = 3'd3;

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg alloc_request = 1'b0;
    wire alloc_grant;
    wire alloc_bank;
    reg write_valid = 1'b0;
    reg write_bank = 1'b0;
    reg [15:0] write_address = 16'd0;
    reg [7:0] write_data = 8'd0;
    reg seal_valid = 1'b0;
    reg seal_bank = 1'b0;
    reg [15:0] seal_length = 16'd0;
    reg [31:0] seal_sequence = 32'd0;
    reg read_request = 1'b0;
    reg read_bank = 1'b0;
    reg [14:0] read_word_address = 15'd0;
    wire read_valid;
    wire [15:0] read_data;
    reg claim_valid = 1'b0;
    reg claim_bank = 1'b0;
    reg ack_valid = 1'b0;
    reg [15:0] ack_value = 16'd0;
    wire ready_valid;
    wire ready_bank;
    wire [15:0] ready_length;
    wire [31:0] ready_sequence;
    wire [2:0] owner_bank0;
    wire [2:0] owner_bank1;

    always #5 clk = ~clk;

    bram_pingpong #(
        .TOTAL_BYTES(64),
        .WORDS(32),
        .ACK_POLICY(1)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .alloc_request(alloc_request), .alloc_grant(alloc_grant),
        .alloc_bank(alloc_bank), .write_valid(write_valid),
        .write_bank(write_bank), .write_address(write_address),
        .write_data(write_data), .seal_valid(seal_valid),
        .seal_bank(seal_bank), .seal_length(seal_length),
        .seal_sequence(seal_sequence), .read_request(read_request),
        .read_bank(read_bank), .read_word_address(read_word_address),
        .read_valid(read_valid), .read_data(read_data),
        .claim_valid(claim_valid), .claim_bank(claim_bank),
        .ack_valid(ack_valid), .ack_value(ack_value),
        .ready_valid(ready_valid), .ready_bank(ready_bank),
        .ready_length(ready_length), .ready_sequence(ready_sequence),
        .owner_bank0(owner_bank0), .owner_bank1(owner_bank1)
    );

    task automatic allocate(input bit expected_bank);
        begin
            @(negedge clk);
            alloc_request = 1'b1;
            @(posedge clk);
            #1;
            if (!alloc_grant || (alloc_bank != expected_bank))
                $fatal(1, "allocation mismatch grant=%0d bank=%0d expected=%0d",
                       alloc_grant, alloc_bank, expected_bank);
            @(negedge clk);
            alloc_request = 1'b0;
        end
    endtask

    task automatic seal(input bit bank, input [31:0] sequence_value);
        begin
            @(negedge clk);
            seal_bank = bank;
            seal_length = 16'd64;
            seal_sequence = sequence_value;
            seal_valid = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            seal_valid = 1'b0;
        end
    endtask

    task automatic claim(input bit bank);
        begin
            @(negedge clk);
            claim_bank = bank;
            claim_valid = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            claim_valid = 1'b0;
        end
    endtask

    task automatic acknowledge(input [15:0] value);
        begin
            @(negedge clk);
            ack_value = value;
            ack_valid = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            ack_valid = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        repeat (2) @(posedge clk);

        allocate(1'b0);
        if (owner_bank0 != OWNER_FILLING)
            $fatal(1, "bank0 did not enter FILLING");
        seal(1'b0, 32'h12345678);
        if (!ready_valid || ready_bank || (ready_length != 64) ||
            (ready_sequence != 32'h12345678) || (owner_bank0 != OWNER_READY))
            $fatal(1, "bank0 READY metadata mismatch");

        acknowledge(16'h5678);
        if (owner_bank0 != OWNER_READY)
            $fatal(1, "unclaimed bank released by ACK");
        claim(1'b0);
        if (owner_bank0 != OWNER_MCU_READING)
            $fatal(1, "bank0 did not enter MCU_READING");
        acknowledge(16'h5679);
        if (owner_bank0 != OWNER_MCU_READING)
            $fatal(1, "wrong sequence ACK released bank0");
        acknowledge(16'h5678);
        if ((owner_bank0 != OWNER_FREE) || ready_valid)
            $fatal(1, "matching ACK did not release bank0");
        acknowledge(16'h5678);
        if (owner_bank0 != OWNER_FREE)
            $fatal(1, "duplicate ACK changed a free bank");

        allocate(1'b1);
        seal(1'b1, 32'h89ABCDEF);
        claim(1'b0);
        if (owner_bank1 != OWNER_READY)
            $fatal(1, "claim for wrong bank changed bank1");
        claim(1'b1);
        if (owner_bank1 != OWNER_MCU_READING)
            $fatal(1, "bank1 did not enter MCU_READING");
        acknowledge(16'hCDEF);
        if ((owner_bank1 != OWNER_FREE) || ready_valid)
            $fatal(1, "matching ACK did not release bank1");

        $display("TB_BRAM_PINGPONG_OK");
        $finish;
    end
endmodule
