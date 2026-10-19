`timescale 1ns/1ps

// Digital model of the nRF command endpoint. It models the v1 two-CS contract,
// including 8-byte request and 260-byte response phases. It is not RF or DMA.
module single_channel_spi_sensor_model #(
    parameter integer RECORDS = 4
) (
    input wire reset_n,
    input wire enable,
    input wire sclk,
    input wire mosi,
    input wire cs_n,
    output reg miso = 1'b0,
    output wire drdy,
    output reg [31:0] committed = 0
);
    reg [7:0] golden [0:RECORDS*248-1];
    reg [7:0] response [0:259];
    reg [7:0] request [0:7];
    reg response_phase, transaction_active, stream_started, commit_allowed;
    reg [7:0] command, shift;
    reg [31:0] argument;
    integer bits, bytes, f, n, k;
    string golden_dir;

    assign drdy = reset_n && enable && stream_started && (committed < RECORDS);

    function [31:0] sequence_at(input integer index);
        sequence_at = {golden[index*248+11], golden[index*248+10],
                       golden[index*248+9], golden[index*248+8]};
    endfunction
    task put32(input integer offset, input [31:0] value);
        begin
            response[offset] = value[7:0]; response[offset+1] = value[15:8];
            response[offset+2] = value[23:16]; response[offset+3] = value[31:24];
        end
    endtask
    task prepare_response;
        begin
            for (k=0;k<260;k=k+1) response[k]=0;
            commit_allowed=0;
            case (command)
                8'd1: put32(12,32'h3149464e);
                8'd2: put32(12,32'h3153464e);
                8'd3: begin
                    if (committed < RECORDS) begin
                        put32(4,sequence_at(committed)); response[8]=1;
                        for (k=0;k<248;k=k+1)
                            response[12+k]=golden[committed*248+k];
                    end
                end
                8'd5: begin
                    if (committed < RECORDS && argument == sequence_at(committed))
                        commit_allowed=1;
                    else put32(0,32'hffffff8c);
                end
                8'd8: if (argument != 1) $fatal(1,"unexpected ARM epoch");
                8'd9: begin end
                default: $fatal(1,"unexpected command %0d",command);
            endcase
        end
    endtask
    initial begin
        if (!$value$plusargs("MC_GOLDEN_DIR=%s",golden_dir))
            $fatal(1,"MC_GOLDEN_DIR required");
        f=$fopen($sformatf("%s/channel0.bin",golden_dir),"rb");
        if (!f) $fatal(1,"channel0.bin missing");
        n=$fread(golden,f); $fclose(f);
        if (n != RECORDS*248) $fatal(1,"bad channel vector size %0d",n);
    end
    always @(negedge reset_n) begin
        miso=0; committed=0; response_phase=0; transaction_active=0;
        stream_started=0; commit_allowed=0; command=0; argument=0;
        bits=0; bytes=0; shift=0;
    end
    always @(negedge cs_n) if (reset_n) begin
        transaction_active=1; bits=0; bytes=0; shift=0;
        if (response_phase) begin prepare_response(); miso=response[0][7]; end
        else miso=0;
    end
    always @(posedge sclk) if (reset_n && !cs_n) begin
        shift={shift[6:0],mosi}; bits=bits+1;
        if (bits==8) begin
            if (!response_phase && bytes<8) request[bytes]=shift;
            if (response_phase && shift!=0) $fatal(1,"nonzero response MOSI");
            bytes=bytes+1; bits=0; shift=0;
        end
    end
    always @(negedge sclk) if (reset_n && !cs_n && response_phase) begin
        if (bytes<260) miso=response[bytes][7-bits]; else miso=0;
    end
    always @(posedge cs_n) if (reset_n && transaction_active) begin
        transaction_active=0;
        if (response_phase) begin
            if (bytes!=260 || bits!=0) $fatal(1,"response length %0d",bytes);
            if (command==8'd5 && commit_allowed) committed=committed+1;
            if (command==8'd9) stream_started=1;
            response_phase=0;
        end else if (bytes==8 && bits==0) begin
            command=request[0]; argument={request[7],request[6],request[5],request[4]};
            response_phase=1;
        end else if (bytes==260 && bits==0) begin
            // recovery flush accepted in the request phase
        end else $fatal(1,"unexpected request length %0d",bytes);
        miso=0;
    end
endmodule
