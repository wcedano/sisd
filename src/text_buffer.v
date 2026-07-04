// Memoria de video para la LCD, escrita por UART.
//
// Dos lineas de LINE_MAX caracteres -> vram[0..2*LINE_MAX-1].
//   linea 1: vram[0 .. LINE_MAX-1]
//   linea 2: vram[LINE_MAX .. 2*LINE_MAX-1]
//
// Protocolo (control bytes):
//   0x20..0x7E  caracter imprimible -> escribe en el cursor y avanza
//   0x0A '\n'   salta al inicio de la linea 2 (reinicia su contenido)
//   0x0D '\r'   vuelve el cursor al inicio de la linea actual
//   0x0C '\f'   limpia ambas lineas y cursor al inicio de la linea 1
//
// La longitud real escrita por linea se expone en o_len1/o_len2; el puerto de
// lectura rellena con espacios mas alla de esa longitud (no hace falta borrar
// fisicamente la vram). El lcd_controller usa la longitud para decidir si una
// linea es estatica (<=16) o hace scroll (>16).
module text_buffer #(
    parameter LINE_MAX = 40
)(
    input  wire       clk,
    input  wire       rst,
    // escritura desde UART
    input  wire [7:0] i_data,
    input  wire       i_valid,
    // lectura desde la LCD (combinacional)
    input  wire [6:0] i_rd_addr,
    output wire [7:0] o_rd_data,
    output reg  [6:0] o_len1 = 0,
    output reg  [6:0] o_len2 = 0
);

localparam integer DEPTH = 2 * LINE_MAX;

// Fuerza implementacion con flip-flops (no LUTRAM/BRAM): el placer del GW5A no
// tiene BELs de RAM16SDP4, y 640 bits caben de sobra como registros con lectura
// combinacional. Ademas, como registros se respeta el contenido del initial.
//   (* mem2reg *)     -> lo honra Yosys (flujo abierto)
//   syn_ramstyle="registers" -> lo honra GowinSynthesis (flujo propietario);
//     sin el, gw_sh hace "Extracting RAM for identifier 'vram'" (BSRAM), pierde
//     el initial y vuelve sincrona la lectura -> LCD con caracteres ilegibles.
(* mem2reg, syn_ramstyle = "registers" *)
reg [7:0] vram [0:DEPTH-1];

reg        cur_line = 0;   // 0 = linea 1, 1 = linea 2
reg [6:0]  wptr     = 0;   // direccion absoluta de escritura
reg [6:0]  col      = 0;   // columna dentro de la linea actual

integer k;
initial begin
    for (k = 0; k < DEPTH; k = k + 1) vram[k] = 8'h20;  // todo espacios
    // Mensaje por defecto al arrancar (antes de recibir UART)
    vram[0]="H"; vram[1]="o"; vram[2]="l"; vram[3]="a"; vram[4]=" ";
    vram[5]="A"; vram[6]="l"; vram[7]="u"; vram[8]="m"; vram[9]="n";
    vram[10]="o"; vram[11]="s";
    vram[LINE_MAX+0]="E"; vram[LINE_MAX+1]="n"; vram[LINE_MAX+2]="v";
    vram[LINE_MAX+3]="i"; vram[LINE_MAX+4]="a"; vram[LINE_MAX+5]=" ";
    vram[LINE_MAX+6]="t"; vram[LINE_MAX+7]="e"; vram[LINE_MAX+8]="x";
    vram[LINE_MAX+9]="t"; vram[LINE_MAX+10]="o"; vram[LINE_MAX+11]=" ";
    vram[LINE_MAX+12]="U"; vram[LINE_MAX+13]="A"; vram[LINE_MAX+14]="R";
    vram[LINE_MAX+15]="T";
end

// Lectura combinacional con relleno de espacios fuera de la longitud escrita
wire        rd_line2 = (i_rd_addr >= LINE_MAX[6:0]);
wire [6:0]  rd_col   = rd_line2 ? (i_rd_addr - LINE_MAX[6:0]) : i_rd_addr;
wire [6:0]  rd_len   = rd_line2 ? o_len2 : o_len1;
assign o_rd_data = (rd_col < rd_len) ? vram[i_rd_addr] : 8'h20;

always @(posedge clk) begin
    if (rst) begin
        cur_line <= 1'b0;
        wptr     <= 7'd0;
        col      <= 7'd0;
        o_len1   <= 7'd12;   // coincide con el mensaje por defecto "Hola Alumnos"
        o_len2   <= 7'd16;   // "Envia texto UART"
    end else if (i_valid) begin
        case (i_data)
            8'h0C: begin                 // form-feed: limpiar todo
                o_len1   <= 7'd0;
                o_len2   <= 7'd0;
                cur_line <= 1'b0;
                wptr     <= 7'd0;
                col      <= 7'd0;
            end
            8'h0A: begin                 // newline: ir a linea 2 (contenido nuevo)
                cur_line <= 1'b1;
                wptr     <= LINE_MAX[6:0];
                col      <= 7'd0;
                o_len2   <= 7'd0;
            end
            8'h0D: begin                 // carriage return: inicio de linea actual
                col  <= 7'd0;
                wptr <= cur_line ? LINE_MAX[6:0] : 7'd0;
            end
            default: begin               // imprimible -> escribir y avanzar
                if ((i_data >= 8'h20) && (col < LINE_MAX[6:0])) begin
                    vram[wptr] <= i_data;
                    wptr       <= wptr + 1'b1;
                    col        <= col + 1'b1;
                    if (cur_line) o_len2 <= col + 1'b1;
                    else          o_len1 <= col + 1'b1;
                end
            end
        endcase
    end
end

endmodule
