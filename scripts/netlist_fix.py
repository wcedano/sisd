#!/usr/bin/env python3
"""Sanitiza un netlist JSON de Yosys para netlistsvg.

netlistsvg solo acepta direcciones de puerto 'input'/'output' y valores de bit
'0'/'1'/'x'. El diseno usa I2C open-drain con puertos 'inout' y constantes 'z'
(alta impedancia), que hacen fallar netlistsvg. Este script:
  - convierte los puertos 'inout' en 'output'
  - reemplaza los bits 'z' por 'x' en puertos y conexiones de celdas

Uso: netlist_fix.py entrada.json salida.json
"""
import json
import sys


def fix_bits(bits):
    return ["x" if b == "z" else b for b in bits]


def main(src, dst):
    with open(src) as f:
        nl = json.load(f)

    for mod in nl.get("modules", {}).values():
        for port in mod.get("ports", {}).values():
            if port.get("direction") == "inout":
                port["direction"] = "output"
            port["bits"] = fix_bits(port.get("bits", []))
        for cell in mod.get("cells", {}).values():
            conns = cell.get("connections", {})
            for name, bits in conns.items():
                conns[name] = fix_bits(bits)
        for net in mod.get("netnames", {}).values():
            net["bits"] = fix_bits(net.get("bits", []))

    with open(dst, "w") as f:
        json.dump(nl, f)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("uso: netlist_fix.py entrada.json salida.json")
    main(sys.argv[1], sys.argv[2])
