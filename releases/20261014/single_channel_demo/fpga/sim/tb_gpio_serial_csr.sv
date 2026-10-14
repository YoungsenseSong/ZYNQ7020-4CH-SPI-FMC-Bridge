`timescale 1ns/1ps
module tb_gpio_serial_csr;
    reg clk=0, rst=0, cs=1, sck=0, data=0, oe=1, allow_read=1;
    always #10 clk=~clk;
    wire [15:0] ad;
    assign ad[7]=sck;
    assign ad[3]=oe ? data : 1'bz;
    wire re,we; wire [15:0] addr,wd;
    reg rv=0; reg [15:0] rd=16'h5343;
    integer writes=0;
    gpio_serial_csr dut(clk,rst,ad,1'b1,cs,1'b1,1'b1,,re,we,addr,wd,rv,rd);
    always @(posedge clk) begin
        rv<=re && allow_read;
        if(we) begin
            writes<=writes+1;
            if(addr!==16'h0010 || wd!==16'h0005) $fatal(1,"bad write addr/data");
        end
        if(oe && dut.drive && !cs) $fatal(1,"half-duplex contention");
    end
    task send(input [39:0] value, input integer n);
        integer i;
        begin oe=1; for(i=n-1;i>=0;i=i-1) begin
            data=value[i]; #200; sck=1; #200; sck=0;
        end end
    endtask
    task get_reply(output [23:0] value);
        integer i;
        begin oe=0;
            for(i=0;i<8;i=i+1) begin #200; sck=1; #200; sck=0; end
            value=0;
            for(i=0;i<24;i=i+1) begin
                #200; sck=1; #200; value={value[22:0],ad[3]}; sck=0;
            end
            #200; cs=1; #200;
            if(ad[3]!==1'bz) $fatal(1,"data not released after CS");
        end
    endtask
    reg [23:0] reply;
    initial begin
        #200; rst=1; #200;
        cs=0; #200; send({16'd0,8'ha5,16'h0000},24); get_reply(reply);
        if(reply!==24'hc35343) $fatal(1,"read reply %h",reply);
        cs=0; #200; send({8'h5a,16'h0010,16'h0005},40); get_reply(reply);
        if(reply!==24'hc30005 || writes!=1) $fatal(1,"write reply/count");
        cs=0; #200; send({16'd0,8'h99,16'h0000},24); get_reply(reply);
        if(reply[23:16]!==8'he2 || writes!=1) $fatal(1,"bad-command acceptance");
        allow_read=0;
        cs=0; #200; send({16'd0,8'ha5,16'h0000},24); get_reply(reply);
        if(reply[23:16]!==8'he1) $fatal(1,"missing read timeout");
        cs=0; #200; send({16'd0,8'h5a,16'h0010},24); send(8'hff,8);
        cs=1; oe=0; #300;
        if(writes!=1 || ad[3]!==1'bz) $fatal(1,"aborted write had effect");
        allow_read=1;
        cs=0; #200; send({16'd0,8'ha5,16'h0000},24); get_reply(reply);
        if(reply!==24'hc35343) $fatal(1,"recovery after abort failed");
        $display("TB_GPIO_SERIAL_CSR_OK read/write/invalid/timeout/abort/recovery/no_contention");
        $finish;
    end
    initial begin #1000000; $fatal(1,"test watchdog"); end
endmodule
