TOP      := top
SRC      := $(wildcard src/*.v)
CST      := constraints/board.cst

BUILD    := build
JSON     := $(BUILD)/$(TOP).json
PNRJSON  := $(BUILD)/$(TOP)_pnr.json
FS       := $(BUILD)/$(TOP).fs

TB_DIR   := tb
VCD      := $(BUILD)/sim.vcd

YOSYS    := yosys
IVERILOG := iverilog
VVP      := vvp
VERILATOR:= verilator
GTKWAVE  := gtkwave
NETLISTSVG := netlistsvg

# Prefer the nextpnr you built from source in ~/nextpnr/build.
# If it doesn't exist, fall back to whatever is in PATH.
NEXTPNR_LOCAL := $(HOME)/nextpnr/build/nextpnr-himbaechel
ifeq ($(wildcard $(NEXTPNR_LOCAL)),)
NEXTPNR := nextpnr-himbaechel
else
NEXTPNR := $(NEXTPNR_LOCAL)
endif

# gowin_pack comes from apycula (pipx or venv).
PACK     := gowin_pack
OPENFPGALOADER := openFPGALoader

# --- Flujo GOWIN CLI (propietario, para comparación) ---
# gw_sh es la shell Tcl de GOWIN EDA. Ruta autodetectable; sobrescribible
# con GOWIN_HOME. Sus artefactos van a build/gowin/impl/ (gw_sh siempre
# escribe en ./impl relativo al cwd, por eso el target hace cd a GW_OUT).
GOWIN_HOME ?= $(HOME)/programas/Gowin_V1.9.11.02_linux
GW_SH      ?= $(GOWIN_HOME)/IDE/bin/gw_sh
GW_TCL     := scripts/gowin_flow.tcl
GW_OUT     := $(BUILD)/gowin
GW_PART    ?= GW5A-LV25MG121NES
GW_FAMILY  ?= GW5A-25A
GW_FS      := $(GW_OUT)/impl/pnr/$(TOP).fs
# Aísla el Qt embebido de GOWIN para evitar "Cannot mix incompatible Qt library"
# en Ubuntu reciente, y corre headless.
GW_ENV     := env LD_LIBRARY_PATH="$(GOWIN_HOME)/IDE/lib:$$LD_LIBRARY_PATH" \
                  QT_QPA_PLATFORM=offscreen

# Tang Primer 25K (GW5A) device settings.
# nextpnr-himbaechel must use the LV package device name and a family vopt.
NEXTPNR_DEVICE ?= GW5A-LV25MG121NES
NEXTPNR_FAMILY ?= GW5A-25A
PACK_DEVICE    ?= GW5A-25A
SSPI_AS_GPIO   ?= 1

# Himbächel needs a device chip database file at runtime.
CHIPDB_DIR ?= $(HOME)/nextpnr/build/himbaechel/uarch/gowin
CHIPDB_DEV := GW5A-25A
CHIPDB     ?= $(CHIPDB_DIR)/chipdb-$(CHIPDB_DEV).bin

.PHONY: all clean synth pnr pack bitstream tools sanity-check program detect \
       lint sim wave schematic check pnr-gowin program-gowin compare

all: bitstream

$(BUILD):
	mkdir -p $(BUILD)

sanity-check:
	@test -f "$(CHIPDB)" || (echo "[ERROR] chipdb missing: $(CHIPDB)" && \
		echo "Build nextpnr-himbaechel with Gowin chipdbs." && exit 1)
	@if [ -x "$(NEXTPNR)" ]; then :; \
	elif command -v "$(NEXTPNR)" >/dev/null 2>&1; then :; \
	else echo "[ERROR] nextpnr-himbaechel not executable: $(NEXTPNR)"; exit 1; fi

synth: $(BUILD)
	$(YOSYS) -p "read_verilog $(SRC); synth_gowin -top $(TOP) -json $(JSON)"

# Comando nextpnr compartido por `pnr` y `compare` (evita duplicar flags).
NEXTPNR_CMD = $(NEXTPNR) --device $(NEXTPNR_DEVICE) --chipdb $(CHIPDB) \
		--json $(JSON) --write $(PNRJSON) \
		--vopt family=$(NEXTPNR_FAMILY) --vopt cst=$(CST) \
		$(if $(SSPI_AS_GPIO),--vopt sspi_as_gpio,)

pnr: synth sanity-check
	$(NEXTPNR_CMD)

pack: pnr
	$(PACK) -d $(PACK_DEVICE) -o $(FS) $(PNRJSON) \
		$(if $(SSPI_AS_GPIO),--sspi_as_gpio,)

bitstream: pack
	@echo "Bitstream ready: $(FS)"

tools:
	@echo "yosys: $$($(YOSYS) -V 2>/dev/null | head -n 1)"
	@echo "nextpnr-himbaechel: $$($(NEXTPNR) --version 2>/dev/null | head -n 1)"
	@echo "gowin_pack: $$($(PACK) --version 2>/dev/null | head -n 1)"
	@echo "openFPGALoader: $$($(OPENFPGALOADER) --version 2>/dev/null | head -n 1)"

program: bitstream
	$(OPENFPGALOADER) -b tangprimer25k -f $(FS)

# --- Flujo GOWIN CLI ---------------------------------------------------------
# Corre síntesis + place & route + bitstream con el toolchain propietario de
# GOWIN, en paralelo (y sin interferir) al flujo abierto. Reutiliza el mismo
# constraints/board.cst. Salida: build/gowin/impl/pnr/top.fs
pnr-gowin:
	@test -x "$(GW_SH)" || { echo "[ERROR] gw_sh no encontrado en $(GW_SH)"; \
		echo "        Ajusta GOWIN_HOME (make pnr-gowin GOWIN_HOME=/ruta/a/Gowin_...)."; exit 1; }
	@mkdir -p $(GW_OUT)
	cd $(GW_OUT) && $(GW_ENV) \
		GW_ROOT="$(CURDIR)" GW_TOP=$(TOP) GW_PART=$(GW_PART) GW_FAMILY=$(GW_FAMILY) \
		"$(GW_SH)" "$(CURDIR)/$(GW_TCL)"
	@echo "Bitstream GOWIN: $(GW_FS)"

program-gowin: pnr-gowin
	$(OPENFPGALOADER) -b tangprimer25k -f $(GW_FS)

# Corre ambos flujos y muestra una tabla comparativa (recursos, Fmax, tamaño).
# El flujo abierto se corre aquí capturando el log de nextpnr para poder
# parsear utilización y Fmax; el flujo GOWIN deja su reporte en build/gowin/.
compare: pack pnr-gowin
	@$(NEXTPNR_CMD) 2> $(BUILD)/nextpnr.log || \
		echo "[WARN] nextpnr falló o no está disponible; log en $(BUILD)/nextpnr.log"
	@bash scripts/compare_flows.sh

detect:
	$(OPENFPGALOADER) --detect

lint:
	$(VERILATOR) --lint-only -Wall $(SRC)

sim: $(BUILD)
ifndef TB
	@echo "Usage: make sim TB=tb_name  (without .v extension)"
	@echo "Available testbenches:"; ls $(TB_DIR)/tb_*.v 2>/dev/null || echo "  (none in $(TB_DIR)/)"
	@exit 1
endif
	$(IVERILOG) -o $(BUILD)/$(TB).vvp -I src $(TB_DIR)/$(TB).v $(SRC)
	$(VVP) $(BUILD)/$(TB).vvp -vcd $(VCD)

wave:
	@test -f "$(VCD)" || (echo "No waveform found. Run 'make sim TB=...' first." && exit 1)
	$(GTKWAVE) $(VCD) &

schematic: $(BUILD)
	$(YOSYS) -p "read_verilog $(SRC); prep -top $(TOP); write_json $(BUILD)/$(TOP)_netlist.json"
	$(NETLISTSVG) $(BUILD)/$(TOP)_netlist.json -o $(BUILD)/$(TOP)_schematic.svg
	@echo "Schematic: $(BUILD)/$(TOP)_schematic.svg"

check: lint sim

clean:
	rm -rf $(BUILD)
