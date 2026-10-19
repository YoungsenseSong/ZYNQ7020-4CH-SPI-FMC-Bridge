`timescale 1ns/1ps

// Fixed-length SPI mode-0 master transaction engine.  CS remains asserted for
// the complete transaction and setup/hold timing is counted in input clocks.
module spi_fixed_transaction_master #(
    parameter integer CLOCK_HZ = 50000000,
    parameter integer SCLK_HZ = 1000000,
    parameter integer CS_SETUP_CYCLES = 50,
    parameter integer CS_HOLD_CYCLES = 50,
    parameter integer TIMEOUT_CYCLES = 500000
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    input  wire [8:0]  length,
    output reg  [8:0]  tx_index,
    input  wire [7:0]  tx_data,
    input  wire        miso,
    output reg         sclk,
    output reg         mosi,
    output reg         cs_n,
    output reg         busy,
    output reg         done_pulse,
    output reg         timeout_pulse,
    output reg  [8:0]  rx_index,
    output reg  [7:0]  rx_data,
    output reg         rx_valid
);
    localparam integer HALF_PERIOD_RAW = CLOCK_HZ / (2 * SCLK_HZ);
    localparam integer HALF_PERIOD_CYCLES =
        (HALF_PERIOD_RAW < 1) ? 1 : HALF_PERIOD_RAW;
    localparam integer SETUP_CYCLES =
        (CS_SETUP_CYCLES < 1) ? 1 : CS_SETUP_CYCLES;
    localparam integer HOLD_CYCLES =
        (CS_HOLD_CYCLES < 1) ? 1 : CS_HOLD_CYCLES;

    localparam [2:0] STATE_IDLE  = 3'd0;
    localparam [2:0] STATE_SETUP = 3'd1;
    localparam [2:0] STATE_SHIFT = 3'd2;
    localparam [2:0] STATE_LOAD  = 3'd3;
    localparam [2:0] STATE_HOLD  = 3'd4;

    reg [2:0] state;
    reg [31:0] phase_count;
    reg [31:0] timeout_count;
    reg [8:0] active_length;
    reg [2:0] bit_count;
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;

    initial begin
        if (CLOCK_HZ <= 0 || SCLK_HZ <= 0 || SCLK_HZ > (CLOCK_HZ / 2))
            $error("invalid SPI clock parameters");
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= STATE_IDLE;
            phase_count <= 32'd0;
            timeout_count <= 32'd0;
            active_length <= 9'd0;
            bit_count <= 3'd0;
            tx_shift <= 8'd0;
            rx_shift <= 8'd0;
            tx_index <= 9'd0;
            rx_index <= 9'd0;
            rx_data <= 8'd0;
            rx_valid <= 1'b0;
            sclk <= 1'b0;
            mosi <= 1'b0;
            cs_n <= 1'b1;
            busy <= 1'b0;
            done_pulse <= 1'b0;
            timeout_pulse <= 1'b0;
        end else begin
            done_pulse <= 1'b0;
            timeout_pulse <= 1'b0;
            rx_valid <= 1'b0;

            if (busy && (TIMEOUT_CYCLES != 0) &&
                (timeout_count >= TIMEOUT_CYCLES - 1)) begin
                state <= STATE_IDLE;
                busy <= 1'b0;
                cs_n <= 1'b1;
                sclk <= 1'b0;
                mosi <= 1'b0;
                timeout_pulse <= 1'b1;
                timeout_count <= 32'd0;
            end else begin
                if (busy)
                    timeout_count <= timeout_count + 1'b1;

                case (state)
                    STATE_IDLE: begin
                        busy <= 1'b0;
                        cs_n <= 1'b1;
                        sclk <= 1'b0;
                        mosi <= 1'b0;
                        tx_index <= 9'd0;
                        phase_count <= 32'd0;
                        timeout_count <= 32'd0;
                        if (start && (length != 0)) begin
                            active_length <= length;
                            tx_shift <= tx_data;
                            rx_shift <= 8'd0;
                            bit_count <= 3'd0;
                            mosi <= tx_data[7];
                            cs_n <= 1'b0;
                            busy <= 1'b1;
                            state <= STATE_SETUP;
                        end
                    end

                    STATE_SETUP: begin
                        if (phase_count >= SETUP_CYCLES - 1) begin
                            phase_count <= 32'd0;
                            state <= STATE_SHIFT;
                        end else begin
                            phase_count <= phase_count + 1'b1;
                        end
                    end

                    STATE_SHIFT: begin
                        if (phase_count >= HALF_PERIOD_CYCLES - 1) begin
                            phase_count <= 32'd0;
                            if (!sclk) begin
                                sclk <= 1'b1;
                                rx_shift <= {rx_shift[6:0], miso};
                            end else begin
                                sclk <= 1'b0;
                                if (bit_count == 3'd7) begin
                                    rx_index <= tx_index;
                                    rx_data <= rx_shift;
                                    rx_valid <= 1'b1;
                                    bit_count <= 3'd0;
                                    if (tx_index + 1'b1 >= active_length) begin
                                        state <= STATE_HOLD;
                                    end else begin
                                        tx_index <= tx_index + 1'b1;
                                        state <= STATE_LOAD;
                                    end
                                end else begin
                                    bit_count <= bit_count + 1'b1;
                                    tx_shift <= {tx_shift[6:0], 1'b0};
                                    mosi <= tx_shift[6];
                                end
                            end
                        end else begin
                            phase_count <= phase_count + 1'b1;
                        end
                    end

                    STATE_LOAD: begin
                        tx_shift <= tx_data;
                        rx_shift <= 8'd0;
                        mosi <= tx_data[7];
                        phase_count <= 32'd0;
                        state <= STATE_SHIFT;
                    end

                    STATE_HOLD: begin
                        if (phase_count >= HOLD_CYCLES - 1) begin
                            phase_count <= 32'd0;
                            cs_n <= 1'b1;
                            sclk <= 1'b0;
                            mosi <= 1'b0;
                            busy <= 1'b0;
                            done_pulse <= 1'b1;
                            state <= STATE_IDLE;
                        end else begin
                            phase_count <= phase_count + 1'b1;
                        end
                    end

                    default: state <= STATE_IDLE;
                endcase
            end
        end
    end
endmodule
