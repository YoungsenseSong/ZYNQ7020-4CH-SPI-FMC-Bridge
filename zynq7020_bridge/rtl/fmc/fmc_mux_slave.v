module fmc_mux_slave #(
    parameter ADDRESS_IS_WORD_ADDRESS = 1,
    parameter WAIT_SUPPORTED = 1
) (
    input  wire        clk,
    input  wire        reset_n,
    inout  wire [15:0] fmc_ad,
    input  wire        fmc_nadv_n,
    input  wire        fmc_ne1_n,
    input  wire        fmc_noe_n,
    input  wire        fmc_nwe_n,
    output wire        fmc_nwait_n,
    output reg         csr_read_enable,
    output reg         csr_write_enable,
    output reg  [15:0] csr_address,
    output reg  [15:0] csr_write_data,
    input  wire        csr_read_valid,
    input  wire [15:0] csr_read_data
);
    localparam STATE_IDLE = 3'd0;
    localparam STATE_ADDRESS = 3'd1;
    localparam STATE_READ_WAIT = 3'd2;
    localparam STATE_READ_DRIVE = 3'd3;
    localparam STATE_WRITE_HOLD = 3'd4;

    wire [4:0] async_controls = {fmc_nadv_n, fmc_ne1_n, fmc_noe_n, fmc_nwe_n, 1'b0};
    wire [4:0] sync_controls;
    wire nadv_n = sync_controls[4];
    wire ne1_n = sync_controls[3];
    wire noe_n = sync_controls[2];
    wire nwe_n = sync_controls[1];
    wire [15:0] ad_input = fmc_ad;
    reg [15:0] ad_output;
    reg ad_drive;
    reg wait_n;
    reg [2:0] state;
    reg [15:0] latched_address;

    cdc_sync #(.WIDTH(5), .RESET_VALUE(1)) control_sync (
        .clk(clk), .reset_n(reset_n), .async_in(async_controls), .sync_out(sync_controls)
    );

    assign fmc_ad = ad_drive ? ad_output : 16'hZZZZ;
    assign fmc_nwait_n = WAIT_SUPPORTED ? wait_n : 1'b1;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= STATE_IDLE;
            latched_address <= 16'h0000;
            csr_read_enable <= 1'b0;
            csr_write_enable <= 1'b0;
            csr_address <= 16'h0000;
            csr_write_data <= 16'h0000;
            ad_output <= 16'h0000;
            ad_drive <= 1'b0;
            wait_n <= 1'b1;
        end else begin
            csr_read_enable <= 1'b0;
            csr_write_enable <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    ad_drive <= 1'b0;
                    wait_n <= 1'b1;
                    if (!ne1_n && !nadv_n) begin
                        latched_address <= ADDRESS_IS_WORD_ADDRESS ? {ad_input[14:0], 1'b0} : ad_input;
                        state <= STATE_ADDRESS;
                    end
                end
                STATE_ADDRESS: begin
                    if (ne1_n) begin
                        state <= STATE_IDLE;
                    end else if (!noe_n && nwe_n) begin
                        csr_address <= latched_address;
                        csr_read_enable <= 1'b1;
                        wait_n <= 1'b0;
                        state <= STATE_READ_WAIT;
                    end else if (!nwe_n && noe_n) begin
                        csr_address <= latched_address;
                        csr_write_data <= ad_input;
                        csr_write_enable <= 1'b1;
                        state <= STATE_WRITE_HOLD;
                    end
                end
                STATE_READ_WAIT: begin
                    if (csr_read_valid) begin
                        ad_output <= csr_read_data;
                        ad_drive <= 1'b1;
                        wait_n <= 1'b1;
                        state <= STATE_READ_DRIVE;
                    end else if (ne1_n) begin
                        wait_n <= 1'b1;
                        state <= STATE_IDLE;
                    end
                end
                STATE_READ_DRIVE: begin
                    if (ne1_n || noe_n) begin
                        ad_drive <= 1'b0;
                        state <= STATE_IDLE;
                    end
                end
                STATE_WRITE_HOLD: begin
                    if (ne1_n || nwe_n)
                        state <= STATE_IDLE;
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
