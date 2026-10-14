`timescale 1ns/1ps
// Digital v1 two-CS slave model, not Zephyr/DMA or an RF model.
module two_channel_spi_slave_model #(
    parameter integer CHANNEL = 0,
    parameter integer RECORDS = 4,
    parameter integer CORRUPT_FIRST_PEEK = 0
) (
    input wire reset_n, enable, sclk, mosi, cs_n,
    output reg miso = 0,
    output wire drdy,
    output reg [31:0] committed = 0,
    output reg [31:0] bad_peeks = 0,
    output reg [31:0] flushes = 0
);
    reg [7:0] golden[0:RECORDS*248-1];
    reg [7:0] response[0:259];
    reg [7:0] request[0:7];
    reg response_phase = 0, stream_started = 0, transaction_active = 0;
    reg corrupted = 0, commit_allowed = 0;
    reg [7:0] command = 0, shift = 0;
    reg [31:0] argument = 0;
    integer bits = 0, bytes = 0, f, n, i;
    string golden_dir;
    assign drdy = reset_n && enable && stream_started && committed < RECORDS;

    function [31:0] sequence_at(input integer r);
        sequence_at = {golden[r*248+11],golden[r*248+10],golden[r*248+9],golden[r*248+8]};
    endfunction
    task put32(input integer offset, input [31:0] value);
        begin
            response[offset] = value[7:0]; response[offset+1] = value[15:8];
            response[offset+2] = value[23:16]; response[offset+3] = value[31:24];
        end
    endtask
    task prepare;
        integer k;
        begin
            for (k=0;k<260;k=k+1) response[k]=0;
            commit_allowed=0;
            case(command)
                1: put32(12,32'h3149464e);
                2: put32(12,32'h3153464e);
                3: begin
                    if (committed < RECORDS && enable) begin
                        put32(4,sequence_at(committed)); response[8]=1;
                        for(k=0;k<248;k=k+1) response[12+k]=golden[committed*248+k];
                        if(CORRUPT_FIRST_PEEK && !corrupted) begin
                            response[12+80]=response[12+80]^8'h01;
                            corrupted=1; bad_peeks=bad_peeks+1;
                        end
                    end
                end
                5: begin
                    if(committed < RECORDS && argument == sequence_at(committed)) commit_allowed=1;
                    else put32(0,32'hffffff8c);
                end
                8: if(argument != 1) $fatal(1,"unexpected ARM epoch");
                9: begin end
                default: $fatal(1,"unexpected command %0d",command);
            endcase
        end
    endtask

    initial begin
        if(!$value$plusargs("MC_GOLDEN_DIR=%s",golden_dir)) $fatal(1,"MC_GOLDEN_DIR required");
        f=$fopen($sformatf("%s/channel%0d.bin",golden_dir,CHANNEL),"rb");
        if(!f) $fatal(1,"missing channel vectors");
        n=$fread(golden,f); $fclose(f);
        if(n != RECORDS*248) $fatal(1,"vector size %0d",n);
    end
    always @(negedge reset_n) begin
        miso=0; committed=0; bad_peeks=0; flushes=0;
        response_phase=0; stream_started=0; transaction_active=0;
        corrupted=0; commit_allowed=0; command=0; argument=0;
        bits=0; bytes=0; shift=0;
    end
    always @(negedge cs_n) if(reset_n) begin
        transaction_active=1; bits=0; bytes=0; shift=0;
        if(response_phase) begin prepare(); miso=response[0][7]; end
        else miso=0;
    end
    always @(posedge sclk) if(reset_n && !cs_n) begin
        shift={shift[6:0],mosi}; bits=bits+1;
        if(bits==8) begin
            if(!response_phase && bytes<8) request[bytes]=shift;
            if(response_phase && shift!=0) $fatal(1,"nonzero response MOSI");
            bytes=bytes+1; bits=0; shift=0;
        end
    end
    always @(negedge sclk) if(reset_n && !cs_n && response_phase) begin
        if(bytes<260) miso=response[bytes][7-bits]; else miso=0;
    end
    always @(posedge cs_n) if(reset_n && transaction_active) begin
        transaction_active=0;
        if(response_phase) begin
            if(bytes!=260 || bits!=0) $fatal(1,"response length %0d",bytes);
            if(command==5 && commit_allowed) committed=committed+1;
            if(command==9) stream_started=1;
            response_phase=0;
        end else if(bytes==8 && bits==0) begin
            if((request[1]|request[2]|request[3])!=0) $fatal(1,"request reserved bytes");
            command=request[0]; argument={request[7],request[6],request[5],request[4]};
            response_phase=1;
        end else if(bytes==260 && bits==0) begin
            // Recovery flush in request phase is rejected, as in the v1 worker.
            flushes=flushes+1;
        end else $fatal(1,"unexpected request length %0d",bytes);
        miso=0;
    end
endmodule
