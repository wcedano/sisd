# Tang Primer 25K — Toolchain FPGA Open-Source + Flujo GOWIN CLI

Proyecto educativo (ITLA — Sistemas Digitales) para la placa **Sipeed Tang Primer 25K**
(FPGA **Gowin GW5A-LV25MG121NES**, familia GW5A-25A). Implementa un display **LCD 16×2
por I²C (PCF8574)** controlado por FPGA, con recepción de texto por **UART** y scroll
automático, construido íntegramente con una **cadena de herramientas open-source**
(Yosys + nextpnr + Apicula) y, opcionalmente, con el **toolchain propietario GOWIN CLI**
para comparación.

---

## 📋 Tabla de contenido
- [Hardware](#-hardware)
- [Funcionalidad del diseño](#-funcionalidad-del-diseño)
- [Arquitectura RTL](#-arquitectura-rtl)
- [Mapa de pines](#-mapa-de-pines)
- [Estructura del proyecto](#-estructura-del-proyecto)
- [Cadena de herramientas](#-cadena-de-herramientas)
- [Requisitos e instalación](#-requisitos-e-instalación)
- [Uso — comandos make](#-uso--comandos-make)
- [Flujo abierto vs. flujo GOWIN](#-flujo-abierto-vs-flujo-gowin)
- [Uso de la LCD y UART](#-uso-de-la-lcd-y-uart)
- [Convenciones de diseño](#-convenciones-de-diseño)
- [Solución de problemas](#-solución-de-problemas)
- [Documentación de referencia](#-documentación-de-referencia)

---

## 🔧 Hardware

| Elemento | Detalle |
|---|---|
| **Placa** | Sipeed Tang Primer 25K (con Dock) |
| **FPGA** | Gowin GW5A-LV25MG121NES (familia GW5A-25A) |
| **Recursos** | ~23K LUT, 1008 Kb BSRAM, 6 PLLs, encapsulado MBGA121N |
| **Reloj de diseño** | 50 MHz por el pin **E2** (proviene del Dock) |
| **Display** | LCD 16×2 HD44780 vía expansor I²C **PCF8574** (dirección `0x27`) |
| **UART** | 115200 8N1 (puente USB BL616 o adaptador USB-TTL externo) |

> La SOM tiene un cristal propio de 26/27 MHz, pero **el reloj de diseño en E2 es 50 MHz**
> (del Dock). Todos los parámetros `CLK_FREQ`/`CLK_HZ` usan `50_000_000`.

---

## ✨ Funcionalidad del diseño

- Inicializa la LCD HD44780 en **modo 4-bit / 2 líneas** vía PCF8574.
- Muestra un mensaje por defecto al arrancar: **`Hola Alumnos` / `Envia texto UART`**.
- Recibe texto por **UART** y lo escribe en la memoria de video (VRAM):
  - `0x20–0x7E` → carácter imprimible (avanza el cursor).
  - `\n` (0x0A) → salta a la línea 2.
  - `\r` (0x0D) → regresa al inicio de la línea actual.
  - `\f` (0x0C) → limpia ambas líneas.
- **Scroll automático** por línea cuando el texto supera 16 caracteres (offset independiente
  por línea, reiniciado al llegar texto nuevo).
- **Eco por UART TX**: reenvía cada byte recibido al PC.

---

## 🧩 Arquitectura RTL

```
                 ┌──────────────┐
   rxd  ───────► │   uart_rx    │──rx_data/valid──┐
                 └──────────────┘                 │
                                                  ▼
                 ┌──────────────┐        ┌──────────────────┐
   txd  ◄─────── │   uart_tx    │◄──eco──│       top        │
                 └──────────────┘        │  (POR + glue)    │
                                         └───────┬──────────┘
                                                 │ rx_data
                                                 ▼
                 ┌──────────────────┐    ┌──────────────────┐
                 │   text_buffer    │◄───┤  (escritura UART)│
                 │  VRAM 2×40 chars │    └──────────────────┘
                 │  + longitudes    │
                 └───────┬──────────┘
                    rd_addr│ rd_data
                           ▼
                 ┌──────────────────┐    ┌──────────────┐    ┌──────────────┐
                 │  lcd_controller  │───►│  lcd_pcf8574 │───►│  i2c_master  │──► SDA/SCL
                 │  (init + scroll) │    │ (nibbles+EN) │    │  (open-drain)│
                 └──────────────────┘    └──────────────┘    └──────────────┘
```

| Módulo | Función |
|---|---|
| `top.v` | Top-level: power-on reset (~21 ms), glue, instancias, eco UART |
| `text_buffer.v` | VRAM 2×40 caracteres, escritura por UART, lectura combinacional con relleno de espacios |
| `lcd_controller.v` | FSM: secuencia de init HD44780 + refresco continuo + scroll condicional |
| `lcd_pcf8574.v` | Traduce byte/comando LCD a nibbles PCF8574 con pulsos de Enable |
| `i2c_master.v` | Maestro I²C open-drain (start/stop/write/ack) |
| `uart_rx.v` / `uart_tx.v` | UART 8N1 receptor / transmisor |

---

## 📌 Mapa de pines

| Señal | Pin | Tipo | Notas |
|---|---|---|---|
| `clk` | **E2** | LVCMOS33 | 50 MHz del Dock (pin dual CPU/SSPI → liberado como GPIO) |
| `rst` | **H11** | LVCMOS33, PULL_DOWN | Botón de reset, activo-alto |
| `io_sda` | **K1** | LVCMOS33, PULL_UP, DRIVE=8 | I²C SDA (open-drain) |
| `io_scl` | **K2** | LVCMOS33, PULL_UP, DRIVE=8 | I²C SCL (open-drain) |
| `rxd` | **J10** | LVCMOS33, PULL_UP | UART RX (← TX del adaptador) |
| `txd` | **J11** | LVCMOS33, DRIVE=8 | UART TX (→ RX del adaptador) |

> Constraints en [`constraints/board.cst`](constraints/board.cst) (formato nativo Gowin,
> usado por **ambos** flujos).

---

## 📁 Estructura del proyecto

```
src/            Módulos Verilog (top module = top.v)
tb/             Testbenches (tb_*.v para Icarus Verilog)
constraints/    Restricciones de pines (board.cst)
scripts/        gowin_flow.tcl (gw_sh) + compare_flows.sh
doc/            Datasheets, esquemáticos, referencias e informe didáctico
build/          Artefactos generados (gitignored)
.vscode/        Tareas y settings de VSCode
Makefile        Reglas de build (GNUmakefile es un wrapper que lo incluye)
```

---

## 🛠 Cadena de herramientas

### Flujo abierto (principal)
| Etapa | Herramienta | Comando |
|---|---|---|
| Síntesis | Yosys (`synth_gowin`) | `make synth` |
| Place & Route | nextpnr-himbaechel | `make pnr` |
| Bitstream | gowin_pack (Apicula) | `make pack` |
| Programación | openFPGALoader | `make program` |
| Lint | Verilator | `make lint` |
| Simulación | Icarus Verilog | `make sim TB=...` |
| Waveform | GTKWave | `make wave` |
| Esquemático | netlistsvg | `make schematic` |

### Flujo propietario (opcional, comparación)
| Etapa | Herramienta | Comando |
|---|---|---|
| Síntesis + P&R + Bitstream | GOWIN CLI (`gw_sh`) | `make pnr-gowin` |
| Programación (GOWIN) | openFPGALoader | `make program-gowin` |
| Comparar ambos flujos | shell (parsea reportes) | `make compare` |

---

## 📦 Requisitos e instalación

### Flujo abierto
- **Yosys** (con `synth_gowin`)
- **nextpnr-himbaechel** compilado con las chipdb de Gowin (por defecto se busca en
  `~/nextpnr/build/nextpnr-himbaechel`; ajustable con `NEXTPNR`/`CHIPDB`)
- **Apicula** (`gowin_pack`, vía pipx/venv)
- **openFPGALoader**, **Verilator**, **Icarus Verilog**, **GTKWave**, **netlistsvg**

Verifica las versiones instaladas:
```bash
make tools
```

### Flujo GOWIN (opcional)
- **GOWIN EDA** instalado (Standard o Education con soporte GW5A-25). Ruta autodetectada
  vía `GOWIN_HOME` (por defecto `~/programas/Gowin_V1.9.11.02_linux`).

### Permisos USB (Linux)
Si `openFPGALoader` solo funciona con `sudo`, instala las reglas udev del puente FTDI:
```bash
sudo tee /etc/udev/rules.d/99-ftdi.rules >/dev/null <<'EOF_UDEV'
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6010", MODE="0666", GROUP="plugdev"
EOF_UDEV
sudo udevadm control --reload-rules
sudo udevadm trigger
```

---

## ▶ Uso — comandos make

```bash
make              # build completo (synth → pnr → pack) → build/top.fs
make program      # flashea el bitstream a la placa
make lint         # chequeos de Verilator
make sim TB=tb_text_buffer   # simula un testbench
make wave         # abre el último waveform en GTKWave
make schematic    # genera SVG del netlist
make check        # lint + sim (quality gate)
make detect       # detecta dispositivos JTAG
make tools        # muestra versiones de herramientas
make clean        # limpia build/

# Flujo GOWIN (opcional)
make pnr-gowin    # build completo con GOWIN CLI → build/gowin/impl/pnr/top.fs
make program-gowin
make compare      # corre ambos flujos e imprime tabla comparativa
```

---

## ⚖ Flujo abierto vs. flujo GOWIN

El target `make compare` corre ambos flujos y produce una tabla (recursos, Fmax, tamaño de
bitstream). Ejemplo con este diseño:

| Métrica | Abierto (nextpnr) | Propietario (GOWIN) |
|---|---|---|
| Síntesis | Yosys `synth_gowin` | GowinSynthesis |
| LUT / Logic | ~3500 | ~600 |
| Flip-Flops | ~940 | ~310 |
| Fmax | ~135 MHz* | ~82 MHz |
| Bitstream | ~5.7 MB | ~5.8 MB |

\* El Fmax de nextpnr usa un modelo de timing reconstruido (optimista); el de GOWIN usa los
modelos oficiales y es más conservador/confiable para cierre de timing. Los conteos de
primitivas **no son directamente comparables** (mapeo tecnológico distinto).

**Detalles técnicos del flujo GOWIN** (ver [`scripts/gowin_flow.tcl`](scripts/gowin_flow.tcl)):
- Reutiliza el mismo `constraints/board.cst`.
- Aísla el Qt embebido de GOWIN (`LD_LIBRARY_PATH` + `QT_QPA_PLATFORM=offscreen`) para evitar
  el error *"Cannot mix incompatible Qt library"* en Ubuntu reciente.
- Libera el pin dual **CPU/SSPI** del `clk` (E2) con `use_cpu_as_gpio` / `use_sspi_as_gpio` /
  `use_mspi_as_gpio` (equivalente al `--sspi_as_gpio` de nextpnr/gowin_pack).

---

## 💬 Uso de la LCD y UART

Conecta un terminal serie a **115200 8N1**:
```bash
# ejemplo con picocom
picocom -b 115200 /dev/ttyUSB0
```
- Escribe texto → aparece en la LCD.
- `Enter` (`\r`) reposiciona; `Ctrl+J` (`\n`) salta a la línea 2; `Ctrl+L` (`\f`) limpia.
- Textos de más de 16 caracteres hacen **scroll** automático.

---

## 📐 Convenciones de diseño

- Top module siempre `top` en `src/top.v`.
- HDL: **Verilog-2005**, señales `snake_case`, parámetros `UPPER_CASE`.
- Inicializar siempre los registros (`reg q = 1'b0;`).
- Patrón de flip-flop por defecto: DFFRE (reset síncrono + CE).
- BRAM se infiere automáticamente cuando `data_width * depth >= 1024`.
- **PLL**: instanciar `rPLL` con `DEVICE="GW5A-25"`, `FCLKIN="27"`.
- Solo la restricción SDC `create_clock` afecta el P&R de nextpnr.

---

## 🩺 Solución de problemas

### La LCD muestra caracteres ilegibles con el flujo GOWIN
**Causa:** GowinSynthesis extrae como **RAM** cualquier arreglo con bloque `initial` y
**descarta su contenido** (mensaje `Extracting RAM for identifier '...'` en
`build/gowin/impl/gwsynthesis/top.log`). Esto vaciaba la secuencia de init HD44780 → la LCD
nunca entraba en modo 4-bit → todo ilegible aunque el I²C y los datos fueran correctos.

**Solución aplicada (regla del proyecto):**
- **ROMs de solo lectura** (p. ej. la secuencia de init en `lcd_controller.v`) → escribirlas
  como un **`case` combinacional** (mux de constantes, idéntico en Yosys y GowinSynthesis).
- **Arreglos escribibles con init** (p. ej. la `vram` en `text_buffer.v`) → añadir el atributo
  `(* syn_ramstyle = "registers" *)` (Yosys usa `mem2reg`; GowinSynthesis honra `syn_ramstyle`).

> Tras cualquier cambio de RTL, revisa `Extracting RAM for identifier` en el log de síntesis
> de GOWIN para detectar arreglos que perderían su `initial`.

### `gw_sh` aborta con error de Qt
El target ya aísla el Qt embebido. Si persiste, exporta `QT_QPA_PLATFORM=offscreen`.

### `nextpnr` no encontrado / chipdb faltante
Ajusta `NEXTPNR`, `CHIPDB_DIR` o `CHIPDB` en el `Makefile`, o compila nextpnr-himbaechel con
las chipdb de Gowin.

---

## 📚 Documentación de referencia

- [`doc/gowin-gw5a-reference.md`](doc/gowin-gw5a-reference.md) — HDL, clock/PLL, timing, programación
- [`doc/sipeed-examples-reference.md`](doc/sipeed-examples-reference.md) — mapa de pines, patrones (debounce, 7-seg, UART, HDMI)
- [`doc/Informe_Didactico.md`](doc/Informe_Didactico.md) — informe didáctico del proyecto
- `doc/*.pdf` — datasheets y esquemáticos de la Tang Primer 25K / GW5A

---

## 📄 Licencia y créditos

Proyecto educativo — ITLA, Sistemas Digitales. Herramientas open-source: Yosys, nextpnr,
Project Apicula, openFPGALoader, Verilator, Icarus Verilog, GTKWave.
