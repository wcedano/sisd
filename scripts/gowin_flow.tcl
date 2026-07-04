# gowin_flow.tcl — Flujo GOWIN CLI (gw_sh) para Tang Primer 25K
#
# Ejecuta el flujo propietario completo: síntesis (GowinSynthesis) ->
# place & route -> generación de bitstream (.fs), en paralelo al flujo
# abierto (Yosys + nextpnr + Apicula).
#
# gw_sh siempre escribe sus artefactos en ./impl/ relativo al directorio
# de trabajo, por eso `make pnr-gowin` invoca gw_sh con cwd = build/gowin
# y pasa GW_ROOT para resolver las fuentes/constraints como rutas absolutas.
#
# Variables de entorno:
#   GW_ROOT    raíz del proyecto (donde están src/ y constraints/)
#   GW_TOP     nombre del top module        (ej. top)
#   GW_PART    part number completo          (ej. GW5A-LV25MG121NES)
#   GW_FAMILY  device/family name            (ej. GW5A-25A)
#   GW_SRC     lista de fuentes Verilog (opcional; por defecto glob $root/src/*.v)
#   GW_CST     archivo de constraints .cst   (por defecto $root/constraints/board.cst)
#   GW_SDC     archivo de timing .sdc        (opcional)
#   GW_SSPI_AS_GPIO  usar el pin SSPI dedicado como GPIO (default 1; el clk
#                    del board está en E2, un pin SSPI, igual que en nextpnr)

proc env_or {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default
}

set root    [env_or GW_ROOT          [pwd]]
set top     [env_or GW_TOP           top]
set part    [env_or GW_PART          GW5A-LV25MG121NES]
set family  [env_or GW_FAMILY        GW5A-25A]
set cst     [env_or GW_CST           [file join $root constraints board.cst]]
set sdc     [env_or GW_SDC           ""]
set sspi    [env_or GW_SSPI_AS_GPIO  1]

# 1. Dispositivo objetivo
set_device -name $family $part

# 2. Fuentes Verilog (rutas absolutas para funcionar desde cualquier cwd)
if {[info exists ::env(GW_SRC)] && $::env(GW_SRC) ne ""} {
    set sources [split $::env(GW_SRC)]
} else {
    set sources [lsort [glob -nocomplain [file join $root src *.v]]]
}
foreach f $sources {
    puts "add_file (verilog): $f"
    add_file -type verilog $f
}

# 3. Constraints físicos (.cst) — mismo formato nativo Gowin que usa nextpnr
if {[file exists $cst]} {
    puts "add_file (cst): $cst"
    add_file -type cst $cst
} else {
    puts "WARNING: constraints file no encontrado: $cst"
}

# 4. Constraints de timing (.sdc) — opcional
if {$sdc ne "" && [file exists $sdc]} {
    puts "add_file (sdc): $sdc"
    add_file -type sdc $sdc
}

# 5. Opciones de dispositivo y reportes
#    El clk (E2) cae en un pin de doble propósito dedicado (CPU/SSPI): hay que
#    liberarlo como GPIO. En el GW5A esto requiere habilitar el pin CPU además
#    del SSPI (equivalente al --sspi_as_gpio de nextpnr/gowin_pack, que en el
#    flujo abierto basta, pero GowinSynthesis distingue CPU y SSPI por separado).
if {$sspi} {
    set_option -use_cpu_as_gpio 1
    set_option -use_sspi_as_gpio 1
    set_option -use_mspi_as_gpio 1
}
set_option -output_base_name $top
set_option -gen_text_timing_rpt 1
set_option -print_all_synthesis_warning 1

# 6. Flujo completo: síntesis + place & route + bitstream
run all
