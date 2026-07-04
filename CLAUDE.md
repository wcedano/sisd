# Tang Primer 25K — Open-Source FPGA Toolchain

## Target
- **Board:** Sipeed Tang Primer 25K
- **FPGA:** Gowin GW5A-LV25MG121NES (GW5A-25A family)

## Toolchain
| Stage       | Tool                    | Command          |
|-------------|-------------------------|------------------|
| Synthesis   | Yosys (`synth_gowin`)   | `make synth`     |
| Place&Route | nextpnr-himbaechel      | `make pnr`       |
| Bitstream   | gowin_pack (Apicula)    | `make pack`      |
| Program     | openFPGALoader          | `make program`   |
| Lint        | Verilator               | `make lint`      |
| Simulate    | Icarus Verilog          | `make sim`       |
| Waveform    | GTKWave                 | `make wave`      |
| Schematic   | netlistsvg              | `make schematic` |

### Optional proprietary flow (comparison)
| Stage           | Tool                  | Command            |
|-----------------|-----------------------|--------------------|
| Synth+P&R+Pack  | GOWIN CLI (`gw_sh`)   | `make pnr-gowin`   |
| Program (GOWIN) | openFPGALoader        | `make program-gowin` |
| Compare flows   | shell (parse reports) | `make compare`     |

## Project Structure
```
src/            Verilog source modules
tb/             Testbenches (tb_*.v for iverilog, test_*.py for cocotb)
constraints/    Pin constraint files (.cst)
build/          Generated artifacts (gitignored)
.vscode/        VSCode tasks and settings
```

## Make Targets
- `make` / `make bitstream` — full build (synth → pnr → pack)
- `make program` — flash bitstream to board
- `make lint` — run Verilator lint checks
- `make sim TB=tb_name` — simulate a testbench
- `make wave` — open last waveform in GTKWave
- `make schematic` — generate SVG schematic via netlistsvg
- `make check` — lint + simulate (quality gate)
- `make clean` — remove build artifacts
- `make detect` — detect JTAG devices
- `make tools` — show installed tool versions
- `make pnr-gowin` — full build with the proprietary GOWIN CLI (`gw_sh`); output in `build/gowin/impl/pnr/top.fs`. Override install path with `GOWIN_HOME=...`
- `make program-gowin` — flash the GOWIN-generated bitstream
- `make compare` — run both flows and print a side-by-side table (resources, Fmax, bitstream size)

### GOWIN CLI notes
- Script: `scripts/gowin_flow.tcl` (driven by `gw_sh`); comparison parser: `scripts/compare_flows.sh`
- Reuses the same `constraints/board.cst` (native Gowin format)
- Must isolate GOWIN's bundled Qt (`LD_LIBRARY_PATH` + `QT_QPA_PLATFORM=offscreen`) to avoid the "Cannot mix incompatible Qt library" error on recent Ubuntu
- `clk` (E2) is a dual-purpose CPU/SSPI pin — freed via `set_option -use_cpu_as_gpio/-use_sspi_as_gpio/-use_mspi_as_gpio` (equivalent to nextpnr's `--sspi_as_gpio`)
- `gw_sh` always writes artifacts to `./impl/` relative to cwd, so the target runs it inside `build/gowin/` with absolute source paths via `GW_ROOT`
- Yosys and GowinSynthesis produce different netlists → primitive counts (LUT/FF) are NOT directly comparable; Fmax and bitstream size are the meaningful comparison metrics

## Conventions
- Top module is always `top` in `src/top.v`
- Testbenches are prefixed `tb_` and live in `tb/`
- Constraints file: `constraints/board.cst`
- HDL style: Verilog-2005, snake_case signals, UPPER_CASE parameters
- Always initialize registers (`reg q = 1'b0;`)
- Use DFFRE (sync reset + CE) as default flip-flop pattern
- BRAM inferred automatically when `data_width * depth >= 1024`
- Gowin pragmas (syn_ramstyle, etc.) do NOT work with Yosys — rely on code patterns
- PLL: instantiate `rPLL` directly with `DEVICE = "GW5A-25"`, `FCLKIN = "27"`
- Only `create_clock` SDC constraint affects nextpnr P&R

## Reference Documentation
- `doc/gowin-gw5a-reference.md` — HDL coding, clock/PLL, timing constraints, programming reference
- `doc/sipeed-examples-reference.md` — Pin map, design patterns (debounce, 7-seg, UART, HDMI), constraint templates
- `doc/` — Gowin datasheets and Tang Primer 25K schematics (PDFs)

## Board Notes
- Design clock (E2) = **50 MHz** from the dock — the LCD/I2C work with `CLK_HZ/CLK_FREQ = 50_000_000`. (The SOM has a separate 26 MHz crystal, but that is NOT what drives the design clock on E2.)
- SOM standalone clock: 27 MHz — use `create_clock -period 37.037`
- LEDs and buttons are **active-low**
- UART: RX=B3, TX=C3 (via BL616 USB bridge, 115200 baud)
- Reset button: H11 (active-high, PULL_MODE=DOWN)
