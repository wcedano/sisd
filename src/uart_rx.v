// UART receptor 8N1 (8 datos, sin paridad, 1 stop)
// Muestrea rx en el centro de cada bit a partir del flanco de start.
module uart_rx #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD     = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] o_data  = 0,
    output reg        o_valid = 0
);

localparam integer CLKS = (CLK_FREQ + BAUD/2) / BAUD;   // ciclos por bit (redondeado)
localparam integer HALF = CLKS / 2;                     // medio bit (centro)

localparam S_IDLE  = 2'd0;
localparam S_START = 2'd1;
localparam S_DATA  = 2'd2;
localparam S_STOP  = 2'd3;

reg [1:0]  state  = S_IDLE;
reg [15:0] cnt    = 0;
reg [2:0]  bitidx = 0;
reg [7:0]  shreg  = 0;

// Sincronizador de 2 FF para entrar al dominio de reloj
reg rx_s1 = 1'b1, rx_s2 = 1'b1;
always @(posedge clk) begin
    rx_s1 <= rx;
    rx_s2 <= rx_s1;
end

always @(posedge clk) begin
    if (rst) begin
        state   <= S_IDLE;
        cnt     <= 0;
        bitidx  <= 0;
        o_data  <= 0;
        o_valid <= 0;
    end else begin
        o_valid <= 1'b0;
        case (state)
            S_IDLE: begin
                cnt    <= 0;
                bitidx <= 0;
                if (!rx_s2) state <= S_START;   // flanco de start (linea a 0)
            end

            // Confirmar el start en el centro del bit (descarta glitches)
            S_START: begin
                if (cnt == HALF[15:0]) begin
                    cnt <= 0;
                    if (!rx_s2) state <= S_DATA;
                    else        state <= S_IDLE; // falso start
                end else cnt <= cnt + 1'b1;
            end

            // Muestrear 8 bits, LSB primero, un bit completo entre muestras
            S_DATA: begin
                if (cnt == CLKS[15:0] - 1) begin
                    cnt   <= 0;
                    shreg <= {rx_s2, shreg[7:1]};
                    if (bitidx == 3'd7) state <= S_STOP;
                    else                bitidx <= bitidx + 1'b1;
                end else cnt <= cnt + 1'b1;
            end

            // Bit de stop: validar el byte
            S_STOP: begin
                if (cnt == CLKS[15:0] - 1) begin
                    o_data  <= shreg;
                    o_valid <= 1'b1;
                    state   <= S_IDLE;
                end else cnt <= cnt + 1'b1;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
