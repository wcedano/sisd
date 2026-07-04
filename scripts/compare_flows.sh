#!/usr/bin/env bash
# compare_flows.sh — Compara el flujo abierto (Yosys+nextpnr+Apicula) contra
# el flujo propietario (GOWIN CLI / gw_sh) para el mismo diseño.
#
# Lee los reportes que cada flujo deja en build/ y arma una tabla. Invocado
# por `make compare` (que corre ambos flujos antes). No falla si a algún
# reporte le falta un dato: muestra "N/A".
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
NP_LOG="$BUILD/nextpnr.log"
NP_FS="$BUILD/top.fs"
GW_RPT="$BUILD/gowin/impl/pnr/top.rpt.txt"
GW_TR="$BUILD/gowin/impl/pnr/top_tr_content.html"
GW_FS="$BUILD/gowin/impl/pnr/top.fs"

na() { local v="$1"; [ -n "$v" ] && printf '%s' "$v" || printf 'N/A'; }

# ---- nextpnr (flujo abierto) ------------------------------------------------
np_val() {  # extrae la columna "usado" (antes del '/') de una fila de nextpnr
    [ -f "$NP_LOG" ] || return
    # nextpnr imprime "usado/  total", con espacios tras la barra.
    grep -E "^Info:[[:space:]]+$1:" "$NP_LOG" | tail -1 \
        | sed -nE "s#.*$1:[[:space:]]*([0-9]+)/.*#\1#p"
}
np_lut=$(np_val LUT4)
np_ff=$(np_val DFF)
np_alu=$(np_val ALU)
np_iob=$(np_val IOB)
# Fmax: última línea "Max frequency for clock ..." (post-routing)
np_fmax=$([ -f "$NP_LOG" ] && grep -E 'Max frequency for clock' "$NP_LOG" \
    | tail -1 | grep -oE '[0-9]+\.[0-9]+ MHz' | head -1 | awk '{print $1}')
np_fs_sz=$([ -f "$NP_FS" ] && du -h "$NP_FS" | cut -f1)

# ---- GOWIN (flujo propietario) ----------------------------------------------
gw_res() {  # extrae "usado/total" de la fila del Resource Usage Summary
    [ -f "$GW_RPT" ] || return
    grep -E "^[[:space:]]*$1[[:space:]]*\|" "$GW_RPT" | head -1 \
        | awk -F'|' '{gsub(/ /,"",$2); print $2}' | grep -oE '^[0-9]+/[0-9]+' \
        | cut -d/ -f1
}
gw_logic=$(gw_res Logic)
gw_reg=$(gw_res Register)
gw_cls=$(gw_res CLS)
gw_bsram=$(gw_res BSRAM)
# Fmax "Actual" de la Max Frequency Summary (2º valor "(MHz)" del bloque)
gw_fmax=$([ -f "$GW_TR" ] && sed 's/<[^>]*>/\n/g' "$GW_TR" \
    | grep -A40 'Max Frequency Summary' | grep -oE '[0-9]+\.[0-9]+\(MHz\)' \
    | sed -n '2p' | grep -oE '[0-9]+\.[0-9]+')
gw_fs_sz=$([ -f "$GW_FS" ] && du -h "$GW_FS" | cut -f1)

# ---- Tabla ------------------------------------------------------------------
line() { printf '%-22s | %-22s | %-22s\n' "$1" "$2" "$3"; }
sep() {  printf '%.0s-' {1..70}; echo; }

echo
echo "======================================================================"
echo "  Comparación de flujos — Tang Primer 25K (GW5A-LV25MG121NES)"
echo "======================================================================"
line "Métrica" "Abierto (nextpnr)" "Propietario (GOWIN)"
sep
line "Síntesis" "Yosys synth_gowin" "GowinSynthesis"
line "Place & Route" "nextpnr-himbaechel" "gw_sh (run all)"
sep
line "LUT / Logic"     "$(na "$np_lut")"  "$(na "$gw_logic")"
line "Flip-Flops"      "$(na "$np_ff")"   "$(na "$gw_reg")"
line "ALU"             "$(na "$np_alu")"  "(incl. en Logic)"
line "CLS / Slices"    "N/A"              "$(na "$gw_cls")"
line "BSRAM"           "N/A"              "$(na "$gw_bsram")"
line "IOB"             "$(na "$np_iob")"  "-"
line "Fmax (MHz)"      "$(na "$np_fmax")" "$(na "$gw_fmax")"
line "Bitstream (.fs)" "$(na "$np_fs_sz")" "$(na "$gw_fs_sz")"
sep
echo "Nota: los conteos de primitivas NO son directamente comparables — cada"
echo "flujo usa su propio mapeo tecnológico (Yosys vs GowinSynthesis), por eso"
echo "difieren LUT/FF. Fmax y tamaño de bitstream sí son indicadores útiles."
echo "Reportes completos:"
echo "  Abierto : $NP_LOG"
echo "  GOWIN   : $GW_RPT , $GW_TR"
echo
