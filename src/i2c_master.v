module i2c_master #(
    parameter CLK_FREQ = 50_000_000,
    parameter I2C_FREQ = 100_000
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       i_start,
    input  wire       i_stop,
    input  wire       i_write,
    input  wire [7:0] i_data,
    output reg        o_ack   = 0,
    output reg        o_busy  = 0,
    output reg        o_done  = 0,
    input  wire       sda_i,
    output reg        sda_oe  = 0,
    output reg        scl_oe  = 0
);

// sda_oe=1 -> drive SDA low (open-drain)
// sda_oe=0 -> release SDA (pulled high by external resistor)
// scl_oe=1 -> drive SCL low
// scl_oe=0 -> release SCL (pulled high)

localparam QP = CLK_FREQ / (4 * I2C_FREQ) - 1;

localparam S_IDLE      = 3'd0;
localparam S_START     = 3'd1;
localparam S_WRITE_BIT = 3'd2;
localparam S_READ_ACK  = 3'd3;
localparam S_STOP      = 3'd4;

reg [2:0]  state    = S_IDLE;
reg [15:0] clk_cnt  = 0;
reg [1:0]  phase    = 0;
reg [2:0]  bit_cnt  = 0;
reg [7:0]  data_reg = 0;

wire phase_tick = (clk_cnt == QP[15:0]);

always @(posedge clk) begin
    if (rst) begin
        state    <= S_IDLE;
        clk_cnt  <= 0;
        phase    <= 0;
        bit_cnt  <= 0;
        data_reg <= 0;
        sda_oe   <= 0;
        scl_oe   <= 0;
        o_ack    <= 0;
        o_busy   <= 0;
        o_done   <= 0;
    end else begin
        o_done <= 1'b0;

        case (state)
            S_IDLE: begin
                o_busy <= 1'b0;
                // NO liberar el bus aqui: entre sub-operaciones (START/byte/STOP)
                // el master regresa a IDLE y debe MANTENER SDA/SCL en su ultimo
                // estado. Soltarlas inyectaba un pulso de reloj espurio con SDA=H
                // que corria toda la trama un bit (0x4E -> 0xA7 => "read 0x53").
                // El reset y el final del STOP ya dejan el bus liberado.
                if (i_start) begin
                    state   <= S_START;
                    o_busy  <= 1'b1;
                    clk_cnt <= 0;
                    phase   <= 0;
                end else if (i_write) begin
                    state    <= S_WRITE_BIT;
                    o_busy   <= 1'b1;
                    data_reg <= i_data;
                    bit_cnt  <= 0;
                    clk_cnt  <= 0;
                    phase    <= 0;
                end else if (i_stop) begin
                    state   <= S_STOP;
                    o_busy  <= 1'b1;
                    clk_cnt <= 0;
                    phase   <= 0;
                end
            end

            // START: SDA falls while SCL is high
            S_START: begin
                if (phase_tick) begin
                    clk_cnt <= 0;
                    phase   <= phase + 1;
                    case (phase)
                        2'd0: begin sda_oe <= 0; scl_oe <= 0; end // SDA=H, SCL=H
                        2'd1: begin sda_oe <= 1; end              // SDA=L, SCL=H (START)
                        2'd2: begin scl_oe <= 1; end              // SDA=L, SCL=L
                        2'd3: begin
                            state  <= S_IDLE;
                            o_done <= 1'b1;
                        end
                    endcase
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            // WRITE: clock out 8 bits MSB-first
            S_WRITE_BIT: begin
                if (phase_tick) begin
                    clk_cnt <= 0;
                    phase   <= phase + 1;
                    case (phase)
                        2'd0: begin sda_oe <= ~data_reg[7]; scl_oe <= 1; end // set SDA, SCL=L
                        2'd1: begin scl_oe <= 0; end                        // SCL=H (slave samples)
                        2'd2: begin end                                     // hold SCL=H
                        2'd3: begin
                            scl_oe   <= 1;                                  // SCL=L
                            data_reg <= {data_reg[6:0], 1'b0};
                            if (bit_cnt == 7) begin
                                state   <= S_READ_ACK;
                                bit_cnt <= 0;
                                phase   <= 0;
                            end else begin
                                bit_cnt <= bit_cnt + 1;
                            end
                        end
                    endcase
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            // ACK: release SDA, clock once, sample SDA
            S_READ_ACK: begin
                if (phase_tick) begin
                    clk_cnt <= 0;
                    phase   <= phase + 1;
                    case (phase)
                        2'd0: begin sda_oe <= 0; scl_oe <= 1; end // release SDA, SCL=L
                        2'd1: begin scl_oe <= 0; end              // SCL=H
                        2'd2: begin o_ack <= sda_i; end           // sample ACK (0=ACK)
                        2'd3: begin
                            scl_oe <= 1;                          // SCL=L
                            state  <= S_IDLE;
                            o_done <= 1'b1;
                        end
                    endcase
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            // STOP: SDA rises while SCL is high
            S_STOP: begin
                if (phase_tick) begin
                    clk_cnt <= 0;
                    phase   <= phase + 1;
                    case (phase)
                        2'd0: begin sda_oe <= 1; scl_oe <= 1; end // SDA=L, SCL=L
                        2'd1: begin scl_oe <= 0; end              // SDA=L, SCL=H
                        2'd2: begin sda_oe <= 0; end              // SDA=H, SCL=H (STOP)
                        2'd3: begin
                            state  <= S_IDLE;
                            o_done <= 1'b1;
                        end
                    endcase
                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
