# Tang Primer 25K (GW5A) Open Toolchain

## Build

```bash
make tools
make
```

Output: `build/top.fs`

## Program

```bash
make program
```

## Detect JTAG

```bash
make detect
```

## Flujo propietario GOWIN (opcional, para comparación)

Además del flujo abierto (Yosys + nextpnr + Apicula), el proyecto puede correr
el toolchain propietario de **GOWIN EDA** por línea de comandos (`gw_sh`) para
comparar resultados. Reutiliza el mismo `constraints/board.cst`.

```bash
make pnr-gowin        # síntesis + P&R + bitstream con GOWIN CLI
make program-gowin    # flashea el bitstream generado por GOWIN
make compare          # corre AMBOS flujos e imprime una tabla comparativa
```

- Salida GOWIN: `build/gowin/impl/pnr/top.fs` (+ reportes `.rpt.txt` / `.tr.html`).
- Ruta de GOWIN EDA autodetectada vía `GOWIN_HOME` (por defecto
  `~/programas/Gowin_V1.9.11.02_linux`). Sobrescribible:
  `make pnr-gowin GOWIN_HOME=/ruta/a/Gowin_Vx.x_linux`.
- El target aísla el Qt embebido de GOWIN (`LD_LIBRARY_PATH` + `QT_QPA_PLATFORM=offscreen`)
  para evitar el error *"Cannot mix incompatible Qt library"* en Ubuntu reciente.
- El clock `clk` (E2) cae en un pin de doble propósito (CPU/SSPI); el flujo Tcl
  lo libera con `use_cpu_as_gpio` / `use_sspi_as_gpio` / `use_mspi_as_gpio`
  (equivalente al `--sspi_as_gpio` de nextpnr/gowin_pack).

> Requiere GOWIN EDA instalado (Standard o Education, según soporte del GW5A-25).
> El flujo abierto sigue siendo el principal; este es complementario/verificación.

## USB Permissions (Linux)

If `openFPGALoader` only works with `sudo`, install udev rules for the FTDI
JTAG interface and replug the board:

```bash
sudo tee /etc/udev/rules.d/99-ftdi.rules >/dev/null <<'EOF_UDEV'
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6010", MODE="0666", GROUP="plugdev"
EOF_UDEV
sudo udevadm control --reload-rules
sudo udevadm trigger
```
