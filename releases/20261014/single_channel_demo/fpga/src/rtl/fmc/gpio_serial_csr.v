`timescale 1ns/1ps
// Mode-0 half-duplex CSR transport over existing AD3/AD7/NE1 wires.
// Header: command A5(read)/5A(write), then 16-bit BYTE address, MSB first.
// Write adds 16 data bits. Both directions then have 8 turnaround clocks.
// Response is C3 + 16-bit data (E1 timeout, E2 invalid command).
// A transaction ends at CS high; aborting before write data completes has no effect.
module gpio_serial_csr (
    input wire clk, reset_n,
    inout wire [15:0] fmc_ad,
    input wire fmc_nadv_n, fmc_ne1_n, fmc_noe_n, fmc_nwe_n,
    output wire fmc_nwait_n,
    output reg csr_read_enable, csr_write_enable,
    output reg [15:0] csr_address, csr_write_data,
    input wire csr_read_valid,
    input wire [15:0] csr_read_data
);
    localparam HEADER=0, WRITE=1, TURN=2, RESPONSE=3, DONE=4;
    reg [2:0] phase;
    (* ASYNC_REG="TRUE" *) reg [2:0] sync1, sync2;
    reg last_sck;
    wire cs_n=sync2[2], sck=sync2[1], di=sync2[0];
    wire rise=sck && !last_sck, fall=!sck && last_sck;
    reg [5:0] bits;
    reg [23:0] rx, tx;
    wire [23:0] incoming={rx[22:0],di};
    reg [15:0] reply_word;
    reg [7:0] status;
    reg drive, dout;
    assign fmc_ad[3]=(!fmc_ne1_n && drive) ? dout : 1'bz;
    assign fmc_nwait_n=1'b1;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin sync1<=3'b100; sync2<=3'b100; end
        else begin sync1<={fmc_ne1_n,fmc_ad[7],fmc_ad[3]}; sync2<=sync1; end
    end
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            phase<=HEADER; bits<=0; rx<=0; tx<=0; last_sck<=0;
            reply_word<=0; status<=8'he1; drive<=0; dout<=0;
            csr_read_enable<=0; csr_write_enable<=0; csr_address<=0; csr_write_data<=0;
        end else begin
            last_sck<=sck;
            csr_read_enable<=0; csr_write_enable<=0;
            if (cs_n) begin
                phase<=HEADER; bits<=0; rx<=0; drive<=0; status<=8'he1;
            end else begin
                if (csr_read_valid && phase==TURN) begin
                    reply_word<=csr_read_data; status<=8'hc3;
                end
                if (rise) begin
                    case (phase)
                        HEADER: begin
                            rx<=incoming;
                            if (bits==23) begin
                                csr_address<=incoming[15:0]; bits<=0;
                                if (incoming[23:16]==8'ha5) begin
                                    csr_read_enable<=1; phase<=TURN;
                                end else if (incoming[23:16]==8'h5a) begin
                                    phase<=WRITE;
                                end else begin
                                    status<=8'he2; reply_word<=0; phase<=TURN;
                                end
                            end else bits<=bits+1'b1;
                        end
                        WRITE: begin
                            rx<=incoming;
                            if (bits==15) begin
                                csr_write_data<=incoming[15:0]; csr_write_enable<=1;
                                reply_word<=incoming[15:0]; status<=8'hc3;
                                bits<=0; phase<=TURN;
                            end else bits<=bits+1'b1;
                        end
                        // The data-window BRAM has a synchronous read-valid
                        // response. Allow a longer turnaround than the
                        // identity CSR so the reply word is captured before
                        // the FPGA drives the response bits.
                        TURN: if (bits==7) begin bits<=0; phase<=RESPONSE; end
                              else bits<=bits+1'b1;
                        RESPONSE: if (bits==23) phase<=DONE;
                                  else bits<=bits+1'b1;
                    endcase
                end
                if (fall && phase==RESPONSE) begin
                    if (!drive) begin
                        drive<=1; dout<=status[7]; tx<={status[6:0],reply_word,1'b0};
                    end else begin dout<=tx[23]; tx<={tx[22:0],1'b0}; end
                end
            end
        end
    end
endmodule
