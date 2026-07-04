# Sipeed Tang Primer 25K — Referencia de Ejemplos Oficiales

Destilado de https://github.com/sipeed/TangPrimer-25K-example
para uso con toolchain open-source (Yosys + nextpnr + Apicula + openFPGALoader).

---

## 1. Pin Map de la Placa (Dock Board)

Extraido de los .cst oficiales. Todos los pines usan LVCMOS33 / BANK_VCCIO=3.3.

### 1.1 Pines fijos (onboard)

| Senal       | Pin  | Tipo    | Notas                        |
|-------------|------|---------|------------------------------|
| `clk`       | E2   | Input   | Cristal 50 MHz (dock board)  |
| `rst` / key | H11  | Input   | Boton reset, PULL_MODE=DOWN  |
| `uart_rx`   | B3   | Input   | BL616 USB-UART bridge        |
| `uart_tx`   | C3   | Output  | BL616 USB-UART bridge        |

> **IMPORTANTE:** El dock board usa cristal de **50 MHz**, no 27 MHz.
> El modulo SOM tiene 27 MHz, pero el dock board lo reemplaza con 50 MHz.
> Usar `CLK_FRE = 50` y `create_clock -period 20` para el dock board.

### 1.2 LEDs onboard (active-low)

| Senal      | Pin  |
|------------|------|
| `led[0]`   | G11  |
| `led[1]`   | G10  |
| `led[2]`   | D11  |
| `led[3]`   | D10  |
| `led[4]`   | B11  |
| `led[5]`   | B10  |
| `led[6]`   | C11  |
| `led[7]`   | C10  |

### 1.3 Botones onboard (active-low)

| Senal       | Pin  |
|-------------|------|
| `button[0]` | F5   |
| `button[1]` | G7   |
| `button[2]` | H7   |
| `button[3]` | J5   |

### 1.4 DIP Switches

| Senal       | Pin  |
|-------------|------|
| `switch[0]` | G5   |
| `switch[1]` | G8   |
| `switch[2]` | H8   |
| `switch[3]` | H5   |

### 1.5 Display 7-segmentos (2-digit, active-low)

| Senal              | Pin  |
|--------------------|------|
| `digitalTube[0]`   | A10  |
| `digitalTube[1]`   | A11  |
| `digitalTube[2]`   | E11  |
| `digitalTube[3]`   | E10  |
| `digitalTube[4]`   | L5   |
| `digitalTube[5]`   | K11  |
| `digitalTube[6]`   | L11  |
| `sel` (digito)     | K5   |

### 1.6 Conectores PMOD (8 conectores, 64 pines)

```
PMOD0: G5  F5  G7  G8  H7  H8  L5  K5
PMOD1: J5  H5  L9  K9  J8  K8  F6  F7
PMOD2: L2  L1  K1  K2  J4  K4  G2  G1
PMOD3: F1  B2  A1  C2  E1  F2  D1  E3
PMOD4: L4  J1  H1  G4  H2  H4  L3  J2
PMOD5: D11 D10 C10 C11 B11 B10 A10 A11
PMOD6: G10 G11 H10 H11 J10 J11 E11 E10
PMOD7: L11 K11 L10 K10 L8  L7  K7  J7
```

---

## 2. Patrones de Diseno Extraidos

### 2.1 Debounce de boton

Los botones del dock son active-low. Patron de debounce con contador:

```verilog
module debounce #(
    parameter DELAY = 5_000_000  // ~100ms @ 50MHz
)(
    input  wire clk,
    input  wire rst,
    input  wire btn_raw,     // active-low del boton
    output wire btn_pressed  // pulso limpio, 1 ciclo
);

reg [23:0] cnt = 0;
reg        state = 0;
reg        state_d = 0;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        cnt   <= 0;
        state <= 0;
    end else if (btn_raw) begin  // boton no presionado (active-low)
        cnt   <= 0;
        state <= 0;
    end else if (cnt == DELAY - 1) begin
        state <= 1;
    end else begin
        cnt <= cnt + 1;
    end
end

always @(posedge clk) state_d <= state;
assign btn_pressed = state & ~state_d;  // rising edge = single pulse

endmodule
```

### 2.2 Display 7-segmentos (multiplexado 2 digitos)

Multiplexar unidades y decenas con un contador de escaneo:

```verilog
module seven_seg #(
    parameter SCAN_PERIOD = 300_000  // ~6ms @ 50MHz
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [3:0] ones,   // 0-9
    input  wire [3:0] tens,   // 0-9
    output reg  [6:0] segments,
    output reg        sel      // 0=ones, 1=tens
);

// Truth table: segments = ~ABCDEFG (active-low)
function [6:0] decode;
    input [3:0] digit;
    case (digit)
        4'd0: decode = 7'b0000001;
        4'd1: decode = 7'b1111001;
        4'd2: decode = 7'b0010010;
        4'd3: decode = 7'b0110000;
        4'd4: decode = 7'b1101000;
        4'd5: decode = 7'b0100100;
        4'd6: decode = 7'b0000100;
        4'd7: decode = 7'b1110001;
        4'd8: decode = 7'b0000000;
        4'd9: decode = 7'b0100000;
        default: decode = 7'b1111111;  // blank
    endcase
endfunction

reg [23:0] cnt = 0;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        cnt <= 0;
        sel <= 0;
    end else if (cnt == SCAN_PERIOD) begin
        cnt <= 0;
        sel <= ~sel;
    end else begin
        cnt <= cnt + 1;
    end
end

always @(posedge clk)
    segments <= sel ? decode(tens) : decode(ones);

endmodule
```

### 2.3 UART TX/RX (115200 baud)

Patron FSM completo para UART. Parametros clave:

```verilog
parameter CLK_FRE   = 50;      // MHz (dock board)
parameter BAUD_RATE = 115200;
localparam CYCLE    = CLK_FRE * 1_000_000 / BAUD_RATE;  // ciclos por bit
```

**UART TX — FSM de 4 estados:**
```
IDLE → START (bit bajo 1 ciclo) → SEND_BYTE (8 bits LSB-first) → STOP (bit alto) → IDLE
```

```verilog
// Latch dato al iniciar transmision
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        tx_data_latch <= 8'd0;
    else if (state == S_IDLE && tx_data_valid)
        tx_data_latch <= tx_data;
end

// Salida serial
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        tx_reg <= 1'b1;
    else case (state)
        S_IDLE, S_STOP: tx_reg <= 1'b1;
        S_START:        tx_reg <= 1'b0;
        S_SEND_BYTE:    tx_reg <= tx_data_latch[bit_cnt];
        default:        tx_reg <= 1'b1;
    endcase
end
```

**UART RX — Sampling a mitad de bit:**
```verilog
// Deteccion de flanco negativo (start bit)
assign rx_negedge = rx_d1 && ~rx_d0;

// Muestreo a mitad del ciclo para maxima inmunidad al ruido
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rx_bits <= 8'd0;
    else if (state == S_REC_BYTE && cycle_cnt == CYCLE/2 - 1)
        rx_bits[bit_cnt] <= rx_pin;
end
```

**Pinout UART en el dock board:**
```
IO_LOC "uart_rx" B3;  IO_PORT "uart_rx" IO_TYPE=LVCMOS33 PULL_MODE=NONE;
IO_LOC "uart_tx" C3;  IO_PORT "uart_tx" IO_TYPE=LVCMOS33 DRIVE=8;
```

### 2.4 LED shifting (running light)

```verilog
reg [7:0] led_reg = 8'b11111110;  // active-low, 1 LED encendido
reg [27:0] cnt = 0;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        cnt     <= 0;
        led_reg <= 8'b11111110;
    end else if (cnt == 50_000_000) begin  // 1 segundo @ 50MHz
        cnt     <= 0;
        led_reg <= {led_reg[6:0], led_reg[7]};  // rotate left
    end else begin
        cnt <= cnt + 1;
    end
end

assign o_led = led_reg;
```

### 2.5 Oscilador interno (OSCA)

Primitiva Gowin para clock interno sin cristal externo:

```verilog
OSCA osc_inst (
    .OSCOUT(internal_clk),  // salida de clock
    .OSCEN(1'b1)            // siempre habilitado
);
defparam osc_inst.FREQ_DIV = 50;  // 210MHz / 50 = 4.2MHz
```

> Solo util para debug (GAO sample clock). No usar como clock principal.

### 2.6 HDMI output (basico)

Requiere PLL + clock divider. Estructura:
```
PLL (50MHz → pixel_clk × 5) → CLKDIV (/5) → pixel_clk
                                            → serial_clk (5×)
    → 3× HDMI encoder (R, G, B channels)
    → LVDS output pairs
```

Primitivas Gowin usadas: `Gowin_PLL`, `Gowin_CLKDIV`, `svo_hdmi` encoder.

---

## 3. Constraints Template (.cst)

Template base para el dock board con todos los perifericos:

```
// Tang Primer 25K Dock Board — GW5A-LV25MG121NES
// Clock: 50 MHz

IO_LOC  "clk" E2;
IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;

// Reset button
IO_LOC  "rst" H11;
IO_PORT "rst" IO_TYPE=LVCMOS33 PULL_MODE=DOWN BANK_VCCIO=3.3;

// UART (via BL616 USB bridge)
IO_LOC  "uart_rx" B3;
IO_PORT "uart_rx" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC  "uart_tx" C3;
IO_PORT "uart_tx" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;

// LEDs (active-low)
IO_LOC  "led[0]" G11;
IO_PORT "led[0]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "led[1]" G10;
IO_PORT "led[1]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "led[2]" D11;
IO_PORT "led[2]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "led[3]" D10;
IO_PORT "led[3]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "led[4]" B11;
IO_PORT "led[4]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "led[5]" B10;
IO_PORT "led[5]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "led[6]" C11;
IO_PORT "led[6]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "led[7]" C10;
IO_PORT "led[7]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;

// Buttons (active-low)
IO_LOC  "btn[0]" F5;
IO_PORT "btn[0]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=OFF BANK_VCCIO=3.3;
IO_LOC  "btn[1]" G7;
IO_PORT "btn[1]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=OFF BANK_VCCIO=3.3;
IO_LOC  "btn[2]" H7;
IO_PORT "btn[2]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=OFF BANK_VCCIO=3.3;
IO_LOC  "btn[3]" J5;
IO_PORT "btn[3]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=OFF BANK_VCCIO=3.3;

// DIP Switches
IO_LOC  "sw[0]" G5;
IO_PORT "sw[0]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=OFF BANK_VCCIO=3.3;
IO_LOC  "sw[1]" G8;
IO_PORT "sw[1]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=OFF BANK_VCCIO=3.3;
IO_LOC  "sw[2]" H8;
IO_PORT "sw[2]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=OFF BANK_VCCIO=3.3;
IO_LOC  "sw[3]" H5;
IO_PORT "sw[3]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=OFF BANK_VCCIO=3.3;

// 7-Segment Display (2-digit, active-low)
IO_LOC  "seg[0]" A10;
IO_PORT "seg[0]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "seg[1]" A11;
IO_PORT "seg[1]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "seg[2]" E11;
IO_PORT "seg[2]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "seg[3]" E10;
IO_PORT "seg[3]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "seg[4]" L5;
IO_PORT "seg[4]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "seg[5]" K11;
IO_PORT "seg[5]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "seg[6]" L11;
IO_PORT "seg[6]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "seg_sel" K5;
IO_PORT "seg_sel" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
```

---

## 4. SDC Template

```sdc
// Tang Primer 25K Dock Board — 50 MHz clock
create_clock -name sys_clk -period 20 -waveform {0 10} [get_ports {clk}]
```

---

## 5. Diferencias Clave vs Nuestro Setup Actual

| Aspecto | Ejemplos Sipeed | Nuestro proyecto |
|---|---|---|
| Clock | 50 MHz (dock board) | Configurado para cristal directo |
| Reset | H11, PULL_MODE=DOWN, active-high | Depende del diseno |
| LEDs | Active-low (8 LEDs) | Active-low confirmado |
| Botones | Active-low (4 botones) | Active-low confirmado |
| UART | B3/C3 via BL616 | No configurado aun |
| Proyecto | Gowin IDE (.gprj) | Makefile open-source |
| Sintesis | GowinSynthesis | Yosys synth_gowin |

> El clock de 50 MHz es critico: los ejemplos de Sipeed asumen el dock board.
> Si se usa el SOM sin dock, el cristal es 27 MHz.
