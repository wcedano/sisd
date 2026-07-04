// Controlador de LCD 16x2 (HD44780 via PCF8574).
// Inicializa la pantalla y refresca continuamente ambas lineas leyendo el
// contenido desde una memoria externa (text_buffer) por el puerto o_rd_addr.
//
// Scroll condicional por linea:
//   - longitud <= LCD_COLS  -> linea estatica
//   - longitud >  LCD_COLS  -> esa linea se desplaza (offset propio)
// El offset de scroll de cada linea se reinicia cuando cambia su longitud
// (es decir, cuando llega texto nuevo por UART).
module lcd_controller #(
    parameter CLK_FREQ  = 50_000_000,
    parameter I2C_FREQ  = 50_000,
    parameter I2C_ADDR  = 7'h27,
    parameter SCROLL_MS = 400,
    parameter LINE_MAX  = 40
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       sda_i,
    output wire       sda_oe,
    output wire       scl_oe,
    // puerto de lectura hacia la memoria de video
    output wire [6:0] o_rd_addr,
    input  wire [7:0] i_rd_data,
    input  wire [6:0] i_len1,
    input  wire [6:0] i_len2
);

localparam LCD_COLS      = 16;
localparam DELAY_40MS    = CLK_FREQ / 25;
localparam DELAY_5MS     = CLK_FREQ / 200;
localparam DELAY_2MS     = CLK_FREQ / 500;
localparam DELAY_200US   = CLK_FREQ / 5000;
localparam DELAY_50US    = CLK_FREQ / 20000;
localparam SCROLL_DELAY  = (CLK_FREQ / 1000) * SCROLL_MS;

localparam INIT_STEPS = 9;

localparam S_INIT_DELAY = 3'd0;
localparam S_INIT_CMD   = 3'd1;
localparam S_INIT_WAIT  = 3'd2;
localparam S_LINE_ADDR  = 3'd3;
localparam S_LINE_DATA  = 3'd4;
localparam S_CMD_WAIT   = 3'd5;

reg [2:0]  state      = S_INIT_DELAY;
reg [3:0]  init_step  = 0;
reg [20:0] delay_cnt  = 0;
reg [4:0]  char_idx   = 0;
reg        line_sel   = 0;

// scroll independiente por linea
reg [24:0] scroll_cnt = 0;
reg [6:0]  scroll_off1 = 0;
reg [6:0]  scroll_off2 = 0;
reg [6:0]  prev_len1   = 0;
reg [6:0]  prev_len2   = 0;

reg        lcd_start  = 0;
reg [7:0]  lcd_data   = 0;
reg        lcd_rs     = 0;
reg        lcd_nib    = 0;
wire       lcd_busy;
wire       lcd_done;

lcd_pcf8574 #(
    .CLK_FREQ(CLK_FREQ),
    .I2C_FREQ(I2C_FREQ),
    .I2C_ADDR(I2C_ADDR)
) u_lcd (
    .clk          (clk),
    .rst          (rst),
    .i_data       (lcd_data),
    .i_rs         (lcd_rs),
    .i_nibble_mode(lcd_nib),
    .i_start      (lcd_start),
    .o_busy       (lcd_busy),
    .o_done       (lcd_done),
    .sda_i        (sda_i),
    .sda_oe       (sda_oe),
    .scl_oe       (scl_oe)
);

// Secuencia de inicializacion HD44780 como logica combinacional (case), NO como
// arreglo con initial: GowinSynthesis extrae los arreglos con initial como RAM y
// pierde el contenido -> la LCD no entra en modo 4-bit/2-lineas y muestra
// caracteres ilegibles aunque el dato de cada caracter sea correcto. Un case
// sintetiza a un mux de constantes, identico en Yosys y GowinSynthesis.
reg [7:0]  init_cmd_data;
reg        init_cmd_nib;
reg [20:0] init_cmd_delay;
always @(*) begin
    case (init_step)
        4'd0: begin init_cmd_data = 8'h30; init_cmd_nib = 1'b1; init_cmd_delay = DELAY_5MS[20:0];   end
        4'd1: begin init_cmd_data = 8'h30; init_cmd_nib = 1'b1; init_cmd_delay = DELAY_200US[20:0]; end
        4'd2: begin init_cmd_data = 8'h30; init_cmd_nib = 1'b1; init_cmd_delay = DELAY_200US[20:0]; end
        4'd3: begin init_cmd_data = 8'h20; init_cmd_nib = 1'b1; init_cmd_delay = DELAY_200US[20:0]; end
        4'd4: begin init_cmd_data = 8'h28; init_cmd_nib = 1'b0; init_cmd_delay = DELAY_50US[20:0];  end
        4'd5: begin init_cmd_data = 8'h0C; init_cmd_nib = 1'b0; init_cmd_delay = DELAY_50US[20:0];  end
        4'd6: begin init_cmd_data = 8'h06; init_cmd_nib = 1'b0; init_cmd_delay = DELAY_50US[20:0];  end
        4'd7: begin init_cmd_data = 8'h01; init_cmd_nib = 1'b0; init_cmd_delay = DELAY_2MS[20:0];   end
        4'd8: begin init_cmd_data = 8'h02; init_cmd_nib = 1'b0; init_cmd_delay = DELAY_2MS[20:0];   end
        default: begin init_cmd_data = 8'h00; init_cmd_nib = 1'b0; init_cmd_delay = DELAY_50US[20:0]; end
    endcase
end

// --- Calculo combinacional de la direccion de lectura del caracter actual ---
wire [6:0] cur_base = line_sel ? LINE_MAX[6:0] : 7'd0;
wire [6:0] cur_len  = line_sel ? i_len2 : i_len1;
wire       scroll_on = (cur_len > LCD_COLS[6:0]);
wire [6:0] cur_off  = line_sel ? scroll_off2 : scroll_off1;
wire [7:0] raw_idx  = (scroll_on ? {1'b0, cur_off} : 8'd0) + {3'd0, char_idx};
wire [6:0] sub_idx  = raw_idx[6:0] - cur_len;
wire [6:0] wrap_idx = (scroll_on && (raw_idx >= {1'b0, cur_len})) ?
                      sub_idx : raw_idx[6:0];
assign o_rd_addr = cur_base + wrap_idx;

always @(posedge clk) begin
    if (rst) begin
        state       <= S_INIT_DELAY;
        init_step   <= 0;
        delay_cnt   <= DELAY_40MS[20:0];   // esperar 40ms antes del primer comando
        char_idx    <= 0;
        line_sel    <= 0;
        scroll_cnt  <= 0;
        scroll_off1 <= 0;
        scroll_off2 <= 0;
        prev_len1   <= 0;
        prev_len2   <= 0;
        lcd_start   <= 0;
        lcd_data    <= 0;
        lcd_rs      <= 0;
        lcd_nib     <= 0;
    end else begin
        lcd_start <= 1'b0;

        // ----- Temporizador de scroll (libre, independiente del dibujado) -----
        if (scroll_cnt == SCROLL_DELAY[24:0]) begin
            scroll_cnt <= 0;
            if (i_len1 > LCD_COLS[6:0])
                scroll_off1 <= (scroll_off1 >= i_len1 - 1'b1) ? 7'd0 : scroll_off1 + 1'b1;
            if (i_len2 > LCD_COLS[6:0])
                scroll_off2 <= (scroll_off2 >= i_len2 - 1'b1) ? 7'd0 : scroll_off2 + 1'b1;
        end else begin
            scroll_cnt <= scroll_cnt + 1'b1;
        end

        // Reinicio de offset cuando cambia el texto (prioridad sobre el avance)
        if (i_len1 != prev_len1) begin prev_len1 <= i_len1; scroll_off1 <= 0; end
        if (i_len2 != prev_len2) begin prev_len2 <= i_len2; scroll_off2 <= 0; end

        // ----------------------- FSM de dibujado --------------------------
        case (state)
            S_INIT_DELAY: begin
                if (delay_cnt != 0) begin
                    delay_cnt <= delay_cnt - 1'b1;
                end else if (init_step >= INIT_STEPS) begin
                    line_sel <= 0;
                    char_idx <= 0;
                    state    <= S_LINE_ADDR;
                end else begin
                    state <= S_INIT_CMD;
                end
            end

            S_INIT_CMD: begin
                if (!lcd_busy) begin
                    lcd_data  <= init_cmd_data;
                    lcd_rs    <= 1'b0;
                    lcd_nib   <= init_cmd_nib;
                    lcd_start <= 1'b1;
                    state     <= S_INIT_WAIT;
                end
            end

            S_INIT_WAIT: begin
                if (lcd_done) begin
                    delay_cnt <= init_cmd_delay;
                    init_step <= init_step + 1'b1;
                    state     <= S_INIT_DELAY;
                end
            end

            // Fijar direccion DDRAM al inicio de la linea actual
            S_LINE_ADDR: begin
                if (!lcd_busy) begin
                    lcd_data  <= line_sel ? 8'hC0 : 8'h80;
                    lcd_rs    <= 1'b0;
                    lcd_nib   <= 1'b0;
                    lcd_start <= 1'b1;
                    char_idx  <= 0;
                    state     <= S_CMD_WAIT;
                end
            end

            // S_CMD_WAIT regresa a S_LINE_DATA tras terminar (addr o caracter)
            S_CMD_WAIT: begin
                if (lcd_done) state <= S_LINE_DATA;
            end

            S_LINE_DATA: begin
                if (!lcd_busy) begin
                    if (char_idx < LCD_COLS[4:0]) begin
                        lcd_data  <= i_rd_data;   // o_rd_addr es combinacional (char_idx actual)
                        lcd_rs    <= 1'b1;
                        lcd_nib   <= 1'b0;
                        lcd_start <= 1'b1;
                        char_idx  <= char_idx + 1'b1;
                        state     <= S_CMD_WAIT;  // esperar lcd_done antes del proximo char
                    end else begin
                        if (!line_sel) begin
                            line_sel <= 1'b1;     // pasar a la linea 2
                            state    <= S_LINE_ADDR;
                        end else begin
                            line_sel <= 1'b0;     // ciclo completo: volver a redibujar
                            state    <= S_LINE_ADDR;
                        end
                    end
                end
            end

            default: state <= S_INIT_DELAY;
        endcase
    end
end

endmodule
