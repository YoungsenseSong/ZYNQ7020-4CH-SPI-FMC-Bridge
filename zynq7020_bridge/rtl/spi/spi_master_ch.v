module spi_master_ch (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    input  wire [7:0]  command,
    input  wire [15:0] read_length,
    input  wire [15:0] sclk_divider,
    input  wire [31:0] timeout_cycles,
    input  wire        miso,
    output reg         sclk,
    output reg         mosi,
    output reg         cs_n,
    output reg         busy,
    output reg         done_pulse,
    output reg         timeout_pulse,
    output reg  [7:0]  byte_data,
    output reg         byte_valid,
    input  wire        byte_ready
);
    localparam STATE_IDLE = 3'd0;
    localparam STATE_SHIFT = 3'd1;
    localparam STATE_HOLD = 3'd2;
    localparam STATE_DONE = 3'd3;

    reg [2:0] state;
    reg [15:0] divider_count;
    reg [15:0] byte_count;
    reg [31:0] timeout_count;
    reg [2:0] bit_count;
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg command_phase;

    wire [15:0] half_period = (sclk_divider < 2) ? 16'd1 : (sclk_divider >> 1);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= STATE_IDLE;
            divider_count <= 16'd0;
            byte_count <= 16'd0;
            timeout_count <= 32'd0;
            bit_count <= 3'd0;
            tx_shift <= 8'd0;
            rx_shift <= 8'd0;
            command_phase <= 1'b0;
            sclk <= 1'b0;
            mosi <= 1'b0;
            cs_n <= 1'b1;
            busy <= 1'b0;
            done_pulse <= 1'b0;
            timeout_pulse <= 1'b0;
            byte_data <= 8'd0;
            byte_valid <= 1'b0;
        end else begin
            done_pulse <= 1'b0;
            timeout_pulse <= 1'b0;

            if (busy && (timeout_count >= timeout_cycles) && (timeout_cycles != 0)) begin
                state <= STATE_IDLE;
                sclk <= 1'b0;
                cs_n <= 1'b1;
                busy <= 1'b0;
                byte_valid <= 1'b0;
                timeout_pulse <= 1'b1;
            end else begin
                if (busy)
                    timeout_count <= timeout_count + 1'b1;

                case (state)
                    STATE_IDLE: begin
                        sclk <= 1'b0;
                        cs_n <= 1'b1;
                        busy <= 1'b0;
                        byte_valid <= 1'b0;
                        timeout_count <= 32'd0;
                        if (start && (read_length != 0)) begin
                            state <= STATE_SHIFT;
                            busy <= 1'b1;
                            cs_n <= 1'b0;
                            command_phase <= 1'b1;
                            tx_shift <= command;
                            mosi <= command[7];
                            bit_count <= 3'd0;
                            byte_count <= 16'd0;
                            divider_count <= 16'd0;
                            rx_shift <= 8'd0;
                        end
                    end
                    STATE_SHIFT: begin
                        if (divider_count >= half_period - 1'b1) begin
                            divider_count <= 16'd0;
                            if (!sclk) begin
                                sclk <= 1'b1;
                                rx_shift <= {rx_shift[6:0], miso};
                            end else begin
                                sclk <= 1'b0;
                                if (bit_count == 3'd7) begin
                                    bit_count <= 3'd0;
                                    if (command_phase) begin
                                        command_phase <= 1'b0;
                                        tx_shift <= 8'h00;
                                        mosi <= 1'b0;
                                        rx_shift <= 8'd0;
                                    end else begin
                                        byte_data <= rx_shift;
                                        byte_valid <= 1'b1;
                                        state <= STATE_HOLD;
                                    end
                                end else begin
                                    bit_count <= bit_count + 1'b1;
                                    tx_shift <= {tx_shift[6:0], 1'b0};
                                    mosi <= tx_shift[6];
                                end
                            end
                        end else begin
                            divider_count <= divider_count + 1'b1;
                        end
                    end
                    STATE_HOLD: begin
                        if (byte_valid && byte_ready) begin
                            byte_valid <= 1'b0;
                            rx_shift <= 8'd0;
                            if (byte_count + 1'b1 >= read_length) begin
                                state <= STATE_DONE;
                            end else begin
                                byte_count <= byte_count + 1'b1;
                                bit_count <= 3'd0;
                                divider_count <= 16'd0;
                                state <= STATE_SHIFT;
                            end
                        end
                    end
                    STATE_DONE: begin
                        sclk <= 1'b0;
                        cs_n <= 1'b1;
                        busy <= 1'b0;
                        done_pulse <= 1'b1;
                        state <= STATE_IDLE;
                    end
                    default: state <= STATE_IDLE;
                endcase
            end
        end
    end
endmodule
