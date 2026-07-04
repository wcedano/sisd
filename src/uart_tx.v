// UART transmisor 8N1 (8 datos, sin paridad, 1 stop)
// Pulsa i_send (1 ciclo) con i_data valido para enviar un byte.
module uart_tx #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD     = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] i_data,
    input  wire       i_send,
    output reg        o_busy = 0,
    output reg        tx     = 1   // linea en reposo a 1
);

localparam integer CLKS = (CLK_FREQ + BAUD/2) / BAUD;   // ciclos por bit (redondeado)

localparam S_IDLE  = 2'd0;
localparam S_START = 2'd1;
localparam S_DATA  = 2'd2;
localparam S_STOP  = 2'd3;

reg [1:0]  state  = S_IDLE;
reg [15:0] cnt    = 0;
reg [2:0]  bitidx = 0;
reg [7:0]  shreg  = 0;

always @(posedge clk) begin
    if (rst) begin
        state  <= S_IDLE;
        cnt    <= 0;
        bitidx <= 0;
        shreg  <= 0;
        o_busy <= 0;
        tx     <= 1'b1;
    end else begin
        case (state)
            S_IDLE: begin
                tx     <= 1'b1;
                o_busy <= 1'b0;
                if (i_send) begin
                    shreg  <= i_data;
                    o_busy <= 1'b1;
                    cnt    <= 0;
                    tx     <= 1'b0;     // bit de start
                    state  <= S_START;
                end
            end

            S_START: begin
                if (cnt == CLKS[15:0] - 1) begin
                    cnt    <= 0;
                    bitidx <= 0;
                    tx     <= shreg[0]; // primer bit de datos (LSB)
                    state  <= S_DATA;
                end else cnt <= cnt + 1'b1;
            end

            S_DATA: begin
                if (cnt == CLKS[15:0] - 1) begin
                    cnt <= 0;
                    if (bitidx == 3'd7) begin
                        tx    <= 1'b1;  // bit de stop
                        state <= S_STOP;
                    end else begin
                        bitidx <= bitidx + 1'b1;
                        tx     <= shreg[bitidx + 1];
                    end
                end else cnt <= cnt + 1'b1;
            end

            S_STOP: begin
                if (cnt == CLKS[15:0] - 1) begin
                    o_busy <= 1'b0;
                    state  <= S_IDLE;
                end else cnt <= cnt + 1'b1;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
