module sync_pulse_gen (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        arm_pulse,
    input  wire        fire_pulse,
    input  wire [3:0]  channel_mask,
    input  wire [31:0] epoch_value,
    input  wire [31:0] delay_cycles,
    input  wire [15:0] width_cycles,
    input  wire [3:0]  ready_mask,
    output reg  [3:0]  sync_out,
    output reg          armed,
    output reg          sent_pulse,
    output reg  [31:0] active_epoch,
    output reg  [3:0]  locked_mask
);
    localparam STATE_IDLE  = 2'd0;
    localparam STATE_DELAY = 2'd1;
    localparam STATE_HIGH  = 2'd2;

    reg [1:0] state;
    reg [31:0] delay_count;
    reg [15:0] width_count;
    reg [3:0] active_mask;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= STATE_IDLE;
            sync_out <= 4'b0000;
            armed <= 1'b0;
            sent_pulse <= 1'b0;
            active_epoch <= 32'd0;
            locked_mask <= 4'b0000;
            delay_count <= 32'd0;
            width_count <= 16'd0;
            active_mask <= 4'b0000;
        end else begin
            sent_pulse <= 1'b0;
            locked_mask <= ready_mask & active_mask;

            if (arm_pulse) begin
                armed <= 1'b1;
                active_epoch <= epoch_value;
                active_mask <= channel_mask;
            end

            case (state)
                STATE_IDLE: begin
                    sync_out <= 4'b0000;
                    if (fire_pulse && armed) begin
                        delay_count <= delay_cycles;
                        state <= (delay_cycles == 0) ? STATE_HIGH : STATE_DELAY;
                        if (delay_cycles == 0) begin
                            sync_out <= active_mask;
                            width_count <= (width_cycles == 0) ? 16'd1 : width_cycles;
                        end
                    end
                end
                STATE_DELAY: begin
                    if (delay_count <= 1) begin
                        sync_out <= active_mask;
                        width_count <= (width_cycles == 0) ? 16'd1 : width_cycles;
                        state <= STATE_HIGH;
                    end else begin
                        delay_count <= delay_count - 1'b1;
                    end
                end
                STATE_HIGH: begin
                    if (width_count <= 1) begin
                        sync_out <= 4'b0000;
                        sent_pulse <= 1'b1;
                        state <= STATE_IDLE;
                    end else begin
                        width_count <= width_count - 1'b1;
                    end
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
