module top (
    input  wire clk,
    input  wire rst,
    inout  wire io_sda,
    inout  wire io_scl,
    input  wire rxd,        // UART RX (desde PC, via puente BL616)
    output wire txd         // UART TX (eco hacia PC)
);

localparam CLK_HZ   = 50_000_000;   // reloj del dock por E2 (la LCD funciona con este valor)
localparam UART_BAUD = 115_200;
localparam LINE_MAX  = 40;   // capacidad por linea (scroll si excede 16)

// Power-on reset: ~21ms a 50MHz antes de iniciar la LCD
reg [19:0] por_cnt = 0;
wire       por_rst = (por_cnt != 20'hFFFFF);
wire       sys_rst = por_rst | rst;

always @(posedge clk)
    if (por_cnt != 20'hFFFFF)
        por_cnt <= por_cnt + 1;

wire sda_oe;
wire scl_oe;
wire sda_in = io_sda;

// Open-drain: oe=1 -> pull low, oe=0 -> release (pull-up externo)
assign io_sda = sda_oe ? 1'b0 : 1'bz;
assign io_scl = scl_oe ? 1'b0 : 1'bz;

// ---------------------------- UART RX ----------------------------
wire [7:0] rx_data;
wire       rx_valid;

uart_rx #(
    .CLK_FREQ(CLK_HZ),
    .BAUD    (UART_BAUD)
) u_rx (
    .clk    (clk),
    .rst    (sys_rst),
    .rx     (rxd),
    .o_data (rx_data),
    .o_valid(rx_valid)
);

// ----------------------- Memoria de video ------------------------
wire [6:0] rd_addr;
wire [7:0] rd_data;
wire [6:0] len1;
wire [6:0] len2;

text_buffer #(
    .LINE_MAX(LINE_MAX)
) u_buf (
    .clk      (clk),
    .rst      (sys_rst),
    .i_data   (rx_data),
    .i_valid  (rx_valid),
    .i_rd_addr(rd_addr),
    .o_rd_data(rd_data),
    .o_len1   (len1),
    .o_len2   (len2)
);

// --------------------- Controlador de LCD ------------------------
// I2C_ADDR: PCF8574T (azul comun) = 7'h27 | PCF8574AT (algunos) = 7'h3F
lcd_controller #(
    .CLK_FREQ  (CLK_HZ),
    .I2C_FREQ  (50_000),
    .I2C_ADDR  (7'h27),
    .SCROLL_MS (400),
    .LINE_MAX  (LINE_MAX)
) u_ctrl (
    .clk      (clk),
    .rst      (sys_rst),
    .sda_i    (sda_in),
    .sda_oe   (sda_oe),
    .scl_oe   (scl_oe),
    .o_rd_addr(rd_addr),
    .i_rd_data(rd_data),
    .i_len1   (len1),
    .i_len2   (len2)
);

// ------------------------- Eco por TX ----------------------------
// Reenvia cada byte recibido. A misma velocidad RX/TX no se solapan.
reg [7:0] tx_data = 0;
reg       tx_send = 0;
wire      tx_busy;

always @(posedge clk) begin
    if (sys_rst) begin
        tx_send <= 1'b0;
        tx_data <= 8'd0;
    end else begin
        tx_send <= 1'b0;
        if (rx_valid && !tx_busy) begin
            tx_data <= rx_data;   // eco del byte recibido
            tx_send <= 1'b1;
        end
    end
end

uart_tx #(
    .CLK_FREQ(CLK_HZ),
    .BAUD    (UART_BAUD)
) u_tx (
    .clk   (clk),
    .rst   (sys_rst),
    .i_data(tx_data),
    .i_send(tx_send),
    .o_busy(tx_busy),
    .tx    (txd)
);

endmodule
