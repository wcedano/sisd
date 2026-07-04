module lcd_pcf8574 #(
    parameter CLK_FREQ = 50_000_000,
    parameter I2C_FREQ = 100_000,
    parameter I2C_ADDR = 7'h27
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] i_data,
    input  wire       i_rs,
    input  wire       i_nibble_mode,
    input  wire       i_start,
    output reg        o_busy = 0,
    output reg        o_done = 0,
    input  wire       sda_i,
    output wire       sda_oe,
    output wire       scl_oe
);

localparam EN_DELAY = 50;

localparam STEP_START1    = 4'd0;
localparam STEP_ADDR1     = 4'd1;
localparam STEP_DATA_HI   = 4'd2;
localparam STEP_STOP1     = 4'd3;
localparam STEP_EN_WAIT   = 4'd4;
localparam STEP_START2    = 4'd5;
localparam STEP_ADDR2     = 4'd6;
localparam STEP_DATA_LO   = 4'd7;
localparam STEP_STOP2     = 4'd8;
localparam STEP_NEXT      = 4'd9;
localparam STEP_DONE      = 4'd10;

localparam S_IDLE    = 2'd0;
localparam S_EXEC    = 2'd1;
localparam S_WAIT    = 2'd2;
localparam S_DELAY   = 2'd3;

reg [1:0]  state     = S_IDLE;
reg [3:0]  step      = 0;
reg [3:0]  lo_nib    = 0;
reg        rs_lat    = 0;
reg        nib_mode  = 0;
reg        nib_phase = 0;
reg [3:0]  cur_nib   = 0;
reg [7:0]  delay_cnt = 0;

reg        i2c_start = 0;
reg        i2c_stop  = 0;
reg        i2c_write = 0;
reg [7:0]  i2c_wdata = 0;
wire       i2c_done;

i2c_master #(
    .CLK_FREQ(CLK_FREQ),
    .I2C_FREQ(I2C_FREQ)
) u_i2c (
    .clk    (clk),
    .rst    (rst),
    .i_start(i2c_start),
    .i_stop (i2c_stop),
    .i_write(i2c_write),
    .i_data (i2c_wdata),
    /* verilator lint_off PINCONNECTEMPTY */
    .o_ack  (),
    .o_busy (),
    /* verilator lint_on PINCONNECTEMPTY */
    .o_done (i2c_done),
    .sda_i  (sda_i),
    .sda_oe (sda_oe),
    .scl_oe (scl_oe)
);

wire [7:0] pcf_byte_en_hi = {cur_nib, 1'b1, 1'b1, 1'b0, rs_lat};
wire [7:0] pcf_byte_en_lo = {cur_nib, 1'b1, 1'b0, 1'b0, rs_lat};
wire [7:0] addr_byte      = {I2C_ADDR, 1'b0};

always @(posedge clk) begin
    if (rst) begin
        state     <= S_IDLE;
        step      <= 0;
        o_busy    <= 0;
        o_done    <= 0;
        i2c_start <= 0;
        i2c_stop  <= 0;
        i2c_write <= 0;
        i2c_wdata <= 0;
        nib_phase <= 0;
        delay_cnt <= 0;
    end else begin
        o_done    <= 1'b0;
        i2c_start <= 1'b0;
        i2c_stop  <= 1'b0;
        i2c_write <= 1'b0;

        case (state)
            S_IDLE: begin
                o_busy <= 1'b0;
                if (i_start) begin
                    state     <= S_EXEC;
                    o_busy    <= 1'b1;
                    lo_nib    <= i_data[3:0];
                    rs_lat    <= i_rs;
                    nib_mode  <= i_nibble_mode;
                    nib_phase <= 0;
                    cur_nib   <= i_data[7:4];
                    step      <= STEP_START1;
                end
            end

            S_EXEC: begin
                case (step)
                    STEP_START1, STEP_START2: begin
                        i2c_start <= 1'b1;
                        state     <= S_WAIT;
                    end
                    STEP_ADDR1, STEP_ADDR2: begin
                        i2c_write <= 1'b1;
                        i2c_wdata <= addr_byte;
                        state     <= S_WAIT;
                    end
                    STEP_DATA_HI: begin
                        i2c_write <= 1'b1;
                        i2c_wdata <= pcf_byte_en_hi;
                        state     <= S_WAIT;
                    end
                    STEP_DATA_LO: begin
                        i2c_write <= 1'b1;
                        i2c_wdata <= pcf_byte_en_lo;
                        state     <= S_WAIT;
                    end
                    STEP_STOP1, STEP_STOP2: begin
                        i2c_stop <= 1'b1;
                        state    <= S_WAIT;
                    end
                    STEP_EN_WAIT: begin
                        delay_cnt <= 0;
                        state     <= S_DELAY;
                    end
                    STEP_NEXT: begin
                        if (nib_mode || nib_phase) begin
                            step  <= STEP_DONE;
                            state <= S_EXEC;
                        end else begin
                            nib_phase <= 1;
                            cur_nib   <= lo_nib;
                            step      <= STEP_START1;
                            state     <= S_EXEC;
                        end
                    end
                    STEP_DONE: begin
                        o_done <= 1'b1;
                        state  <= S_IDLE;
                    end
                    default: state <= S_IDLE;
                endcase
            end

            S_WAIT: begin
                if (i2c_done) begin
                    step  <= step + 1;
                    state <= S_EXEC;
                end
            end

            S_DELAY: begin
                if (delay_cnt == EN_DELAY - 1) begin
                    step  <= step + 1;
                    state <= S_EXEC;
                end else begin
                    delay_cnt <= delay_cnt + 1;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
