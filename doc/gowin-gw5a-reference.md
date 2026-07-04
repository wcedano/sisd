# Gowin GW5A-25A Reference — Tang Primer 25K (MG121)

Referencia destilada de las guias oficiales Gowin, filtrada para el toolchain
open-source (Yosys + nextpnr-himbaechel + Apicula + openFPGALoader).

> Fuentes: SUG100-4.4.1E, SUG949-1.8E, UG286-1.9.9E, SUG940-1.9E,
> SUG502-2.0E, SUG114-3.3E

---

## 1. Dispositivo

| Parametro          | Valor                        |
|--------------------|------------------------------|
| Serie              | GW5A (Arora V)               |
| Part Number        | GW5A-LV25MG121NES            |
| Device             | GW5A-25A                     |
| Package            | MG121 (121 pines)            |
| Core Voltage       | 0.9V (LV)                    |
| I/O Voltage        | 3.3V (VCCX default)          |
| Cristal onboard    | 27 MHz                       |
| SSPI pins          | Usados como GPIO por defecto |
| Embedded Flash     | NO (solo LittleBee)          |
| Flash externo      | SI (SPI flash en la placa)   |

---

## 2. HDL Coding Style (SUG949)

### 2.1 Flip-Flops disponibles (Arora V CLU)

| Primitiva | Tipo                              | Patron recomendado        |
|-----------|-----------------------------------|---------------------------|
| DFFRE     | Sync reset + clock enable         | Default recomendado       |
| DFFSE     | Sync set + clock enable           | Para set sincrono         |
| DFFCE     | Async clear + clock enable        | Para clear asincrono      |
| DFFPE     | Async preset + clock enable       | Para preset asincrono     |

**DFFRE (sync reset, recomendado):**
```verilog
output reg q = 1'b0;
always @(posedge clk) begin
    if (rst)
        q <= 1'b0;
    else if (ce)
        q <= d;
end
```

**DFFCE (async clear):**
```verilog
output reg q = 1'b0;
always @(posedge clk or posedge clear) begin
    if (clear)
        q <= 1'b0;
    else if (ce)
        q <= d;
end
```

> Regla: siempre inicializar registros (`reg q = 1'b0;`).

### 2.2 Evitar latches

Asignar todas las salidas en cada rama de bloques combinacionales.
Usar `default` en `case`. Gowin/Yosys infieren latches de if/case incompletos.

### 2.3 Logica combinacional

```verilog
// MUX (infiere LUT3)
assign f = sel ? a : b;

// ALU adder (infiere cadena ADD)
assign {cout, sum} = a + b + cin;

// ALU ADDSUB
assign sum = c ? (a - b) : (a + b);
```

### 2.4 BSRAM (Block SRAM) — 16Kbit/18Kbit por bloque

Se infiere automaticamente cuando `data_width * depth >= 1024`.

**Single-port:**
```verilog
reg [7:0] mem [2047:0];
reg [10:0] addr_reg;

always @(posedge clk) begin
    addr_reg <= addr;
    if (we) mem[addr] <= din;
end
assign dout = mem[addr_reg]; // read-after-write
```

**Dual-port:**
```verilog
reg [7:0] mem [2047:0];
reg [10:0] addra_reg, addrb_reg;

always @(posedge clka) begin
    addra_reg <= addra;
    if (cea & wrea) mem[addra] <= data_ina;
end
assign data_outa = mem[addra_reg];

always @(posedge clkb) begin
    addrb_reg <= addrb;
    if (ceb & wreb) mem[addrb] <= data_inb;
end
assign data_outb = mem[addrb_reg];
```

**Byte-enable (solo Arora V):**
```verilog
always @(posedge clka) begin
    if (cea & wrea) begin
        if (byte_ena[0]) mem[ada][7:0]  <= dina[7:0];
        if (byte_ena[1]) mem[ada][15:8] <= dina[15:8];
    end
end
```

**Inicializacion de memoria:**
```verilog
initial $readmemh("data.hex", mem);  // funciona en Yosys y Gowin
```

### 2.5 Distributed RAM (SSRAM / LUT RAM)

Se infiere con lectura asincrona + escritura sincrona:
```verilog
reg [3:0] mem [15:0];
always @(posedge clk)
    if (wre) mem[addr] <= data_in;
assign data_out = mem[addr];  // lectura combinacional = distributed RAM
```

### 2.6 DSP / Multiplicadores

Sizes: 9x9, 18x18, 36x36. Usar `signed` para multiplicacion con signo.

```verilog
input signed [17:0] a, b;
reg signed [17:0] ina, inb;
reg signed [35:0] result;

always @(posedge clk or posedge rst)
    if (rst) begin ina <= 0; inb <= 0; end
    else if (ce) begin ina <= a; inb <= b; end

wire signed [35:0] mult_out = ina * inb;  // infiere MULT18X18

always @(posedge clk or posedge rst)
    if (rst) result <= 0;
    else if (ce) result <= mult_out;
```

**Pre-adder + multiplicador (DSP macro):**
```verilog
p_add_reg <= b0_reg + b1_reg;    // pre-add
pipe_reg  <= a0_reg * p_add_reg; // multiply
s_reg     <= pipe_reg;           // output register
```

### 2.7 I/O Buffers

```verilog
// Tri-state (OEN activo-bajo)
assign io = ~oen ? i : 1'bz;
assign o = io;

// LVDS (Yosys: instanciar primitivas directamente)
TLVDS_IBUF lvds_in (.I(in_p), .IB(in_n), .O(sig));
TLVDS_OBUF lvds_out (.I(sig), .O(out_p), .OB(out_n));
```

### 2.8 Pragmas Gowin vs Yosys

| Pragma                          | Gowin | Yosys |
|---------------------------------|-------|-------|
| `syn_ramstyle = "block_ram"`    | SI    | NO    |
| `syn_ramstyle = "distributed_ram"` | SI | NO   |
| `syn_romstyle = "block_rom"`    | SI    | NO    |
| `syn_dspstyle = "dsp"`         | SI    | NO    |
| `syn_tlvds_io = 1`             | SI    | NO    |
| `(* keep *)` attribute         | SI    | SI    |

> En Yosys la inferencia depende del patron de codigo, no de pragmas.
> BRAM se infiere automaticamente por tamano. LVDS requiere instanciacion directa.

---

## 3. Clock Resources (UG286)

### 3.1 PLL — rPLL

Disponible en todos los Gowin. Formula:
```
f_CLKOUT  = (f_CLKIN * FBDIV) / IDIV
f_VCO     = f_CLKOUT * ODIV
f_CLKOUTD = f_CLKOUT / SDIV
```

Rangos: IDIV 1-64, FBDIV 1-64, ODIV {2,4,8,16,32,48,64,80,96,112,128}, SDIV 2-128 (par).

**Ejemplo: 27 MHz a 108 MHz:**
```verilog
rPLL rpll_inst (
    .CLKOUT(clk_108m),
    .LOCK(pll_locked),
    .CLKOUTP(),
    .CLKOUTD(),
    .CLKOUTD3(),
    .RESET(1'b0),
    .RESET_P(1'b0),
    .CLKIN(clk_27m),        // cristal onboard 27 MHz
    .CLKFB(1'b0),
    .FBDSEL(6'b0),
    .IDSEL(6'b0),
    .ODSEL(6'b0),
    .PSDA(4'b0),
    .DUTYDA(4'b0),
    .FDLY(4'b0)
);
defparam rpll_inst.FCLKIN        = "27";
defparam rpll_inst.IDIV_SEL      = 0;       // IDIV = 1
defparam rpll_inst.FBDIV_SEL     = 3;       // FBDIV = 4 -> 27*4/1 = 108 MHz
defparam rpll_inst.ODIV_SEL      = 8;       // VCO = 108*8 = 864 MHz
defparam rpll_inst.DYN_IDIV_SEL  = "false";
defparam rpll_inst.DYN_FBDIV_SEL = "false";
defparam rpll_inst.DYN_ODIV_SEL  = "false";
defparam rpll_inst.DYN_DA_EN     = "false";
defparam rpll_inst.PSDA_SEL      = "0000";
defparam rpll_inst.DUTYDA_SEL    = "1000";  // 50% duty
defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL    = "internal";
defparam rpll_inst.CLKOUT_BYPASS = "false";
defparam rpll_inst.CLKOUTP_BYPASS = "false";
defparam rpll_inst.CLKOUTD_BYPASS = "false";
defparam rpll_inst.DYN_SDIV_SEL = 2;
defparam rpll_inst.CLKOUTD_SRC  = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
defparam rpll_inst.DEVICE        = "GW5A-25";
```

### 3.2 Red de clocks globales

- 4 cuadrantes (TL, TR, BL, BR), 8 GCLKs por cuadrante = 32 redes
- GCLK0-5: con **DQCE** (clock gating dinamico)
- GCLK6-7: con **DCS** (mux de clock glitch-free, 4 entradas)
- HCLK: red de alta velocidad para I/O source-synchronous

**Clock gating (DQCE):**
```verilog
DQCE dqce_inst (
    .CLKIN(clk_in),
    .CE(clock_enable),
    .CLKOUT(clk_gated)
);
```

**Clock mux glitch-free (DCS):**
```verilog
DCS dcs_inst (
    .CLK0(clk_a), .CLK1(clk_b),
    .CLK2(clk_c), .CLK3(clk_d),
    .CLKSEL(sel[3:0]),    // one-hot
    .SELFORCE(1'b0),      // 0 = glitchless
    .CLKOUT(clk_selected)
);
defparam dcs_inst.DCS_MODE = "RISING";
```

### 3.3 Clock Domain Crossing

- 2-stage synchronizer para bits individuales
- Async FIFO (dual-clock) para datos multi-bit
- Gray-code para punteros
- No usar salidas de PLL hasta que `LOCK == 1`
- Mantener reset mientras PLL esta desbloqueado

---

## 4. Timing Constraints (SUG940)

Formato: **SDC** (archivos `.sdc`).

### 4.1 Lo que funciona con nextpnr-himbaechel

| Constraint              | nextpnr | Gowin IDE |
|-------------------------|---------|-----------|
| `create_clock`          | **SI**  | SI        |
| `create_generated_clock`| Parcial | SI        |
| `set_input_delay`       | NO      | SI        |
| `set_output_delay`      | NO      | SI        |
| `set_false_path`        | NO      | SI        |
| `set_multicycle_path`   | NO      | SI        |
| `set_max/min_delay`     | NO      | SI        |
| `set_clock_groups`      | NO      | SI        |

> nextpnr solo usa `create_clock` para P&R timing-driven.
> Escribir el SDC completo de todas formas para documentacion y compatibilidad futura.

### 4.2 Ejemplos practicos

```sdc
# Clock primario (cristal 27 MHz en la Tang Primer 25K)
create_clock -name sys_clk -period 37.037 [get_ports {clk}]

# PLL output (si se usa)
create_generated_clock -name clk_108m -source [get_ports {clk}] \
    -multiply_by 4 [get_pins {rpll_inst/CLKOUT}]

# I/O delays (solo Gowin IDE, ignorados por nextpnr)
set_input_delay -clock sys_clk -max 2.0 [get_ports {btn_raw}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {led}]

# False path entre dominios (solo Gowin IDE)
set_false_path -from [get_clocks {clk_a}] -to [get_clocks {clk_b}]

# Multicycle (solo Gowin IDE)
set_multicycle_path -from [get_clocks {slow_clk}] -setup -end 3
```

---

## 5. Programacion (SUG502)

### 5.1 Modos disponibles para GW5A-25A

| Modo           | Volatil | openFPGALoader | Comando                                     |
|----------------|---------|----------------|----------------------------------------------|
| SRAM           | SI      | **SI**         | `openFPGALoader -b tangprimer25k top.fs`     |
| External Flash | NO      | **SI**         | `openFPGALoader -b tangprimer25k -f top.fs`  |
| Embedded Flash | N/A     | N/A            | No disponible en GW5A                        |
| SSPI (Slave)   | -       | NO             | Requiere control de pines SSPI               |

### 5.2 Archivos

| Extension | Uso                          |
|-----------|------------------------------|
| `.fs`     | Bitstream FPGA (principal)   |
| `.bin`    | Imagen binaria (RISC-V/MCU)  |
| `.fi`     | User flash init              |

### 5.3 Interfaz

JTAG via USB. La Tang Primer 25K usa un BL616 como puente USB-JTAG.
openFPGALoader lo detecta automaticamente.

### 5.4 Seguridad

AES key write/read/lock via JTAG (OTP, irreversible).
**No soportado por openFPGALoader.**

### 5.5 SSPI_AS_GPIO

Las patitas SSPI se usan como GPIO por defecto en MG121.
Requiere flag `--sspi_as_gpio` en gowin_pack y `--vopt sspi_as_gpio` en nextpnr
(ya configurado en el Makefile).

---

## 6. Logic Analyzer / Debug On-Chip (SUG114)

### 6.1 GAO (Gowin Analyzer Oscilloscope)

Analizador logico embebido (como Xilinx ILA). **Solo funciona con Gowin IDE,
NO compatible con el toolchain open-source.**

Capacidades:
- Hasta 16 cores, cada uno con trigger ports y match units configurables
- 6 tipos de match: Basic, con edges, Extended, Range
- Hasta 16 match units combinables con operadores logicos
- Almacena en BSRAM/SSRAM/REG (4 a 65536 muestras)
- Modo Lite: captura inmediata sin trigger (power-on analysis)

### 6.2 Alternativas open-source para debug

1. **UART/SPI logic analyzer custom** — ring buffer en HDL que captura senales
   y las envia por UART a la PC
2. **Sacar senales a GPIO** — capturar con analizador logico externo
3. **LiteScope (LiteX)** — analizador logico open-source embebido
4. **Usar Gowin IDE solo para GAO** — mantener el build principal en Yosys/nextpnr,
   usar Gowin IDE unicamente para sesiones de debug

---

## 7. Physical Constraints (.cst)

Formato Gowin para pin assignment:
```
IO_LOC  "signal_name" pin;
IO_PORT "signal_name" PULL_MODE=NONE DRIVE=8;
```

Opciones de IO_PORT:
- `PULL_MODE`: NONE, UP, DOWN, KEEPER
- `DRIVE`: 4, 8, 12, 16, 24 (mA)
- `IO_TYPE`: LVCMOS33 (default), LVCMOS25, LVCMOS18, LVDS25, etc.
- `SLEW_RATE`: SLOW, FAST
- `BANK_VCCIO`: 3.3, 2.5, 1.8, 1.5, 1.2

Ejemplo completo:
```
IO_LOC  "clk" E2;
IO_PORT "clk" PULL_MODE=NONE IO_TYPE=LVCMOS33;

IO_LOC  "led[0]" G11;
IO_PORT "led[0]" PULL_MODE=NONE DRIVE=8 SLEW_RATE=SLOW;

IO_LOC  "uart_tx" K11;
IO_PORT "uart_tx" PULL_MODE=NONE DRIVE=8 IO_TYPE=LVCMOS33;
```
