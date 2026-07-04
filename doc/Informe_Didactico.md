# Informe Didáctico — Display LCD I²C controlado por FPGA con entrada UART

**Instituto Tecnológico de Las Américas (ITLA) — Mecatrónica**
**Asignatura:** Sistemas Digitales
**Plataforma:** Tang Primer 25K (FPGA Gowin GW5A-LV25MG121NES)

---

## 1. Objetivo del proyecto

Diseñar, en lenguaje de descripción de hardware (Verilog), un sistema digital que:

1. Controle una pantalla **LCD 16×2** de tipo HD44780 conectada por un **expansor I²C PCF8574** (el típico "backpack" azul).
2. Reciba texto desde una **PC por UART** (puerto serie) y lo guarde en una **memoria interna** del FPGA.
3. Muestre ese texto en la pantalla, con **scroll automático** en la línea que supere los 16 caracteres.

El proyecto integra cuatro grandes temas de la electrónica digital: **máquinas de estado (FSM)**, **protocolos serie** (I²C y UART), **memorias en hardware**, y el **flujo de diseño FPGA** con herramientas de código abierto.

---

## 2. Arquitectura general

El diseño es jerárquico: módulos pequeños y verificables que se conectan para formar el sistema. El flujo de datos es:

```
   PC ──UART──►┌──────────┐   bytes   ┌──────────────┐  caracteres ┌─────────────────┐
              │ uart_rx  ├──────────►│ text_buffer  ├────────────►│ lcd_controller  │
   PC ◄──UART──┤ uart_tx  │◄─(eco)    │ (memoria     │   + longitud │ (init + refresco│
              └──────────┘           │  de video)   │   por línea  │  + scroll)      │
                                     └──────────────┘             └────────┬────────┘
                                                                           │ byte+RS
                                                                           ▼
                                                                  ┌─────────────────┐
                                                                  │  lcd_pcf8574    │  (protocolo HD44780
                                                                  │  (nibbles + EN) │   en 4 bits)
                                                                  └────────┬────────┘
                                                                           │ start/write/stop
                                                                           ▼
                                                                  ┌─────────────────┐
                                                                  │   i2c_master    │  (genera SDA/SCL
                                                                  │  (bit a bit)    │   open-drain)
                                                                  └────────┬────────┘
                                                                           ▼
                                                                     PCF8574 → LCD 16×2
```

**Jerarquía de módulos (quién instancia a quién):**

```
top
├── uart_rx          (recibe bytes del PC)
├── uart_tx          (eco hacia el PC)
├── text_buffer      (memoria de video + FSM de escritura)
└── lcd_controller   (secuencia de init + refresco + scroll)
    └── lcd_pcf8574  (traduce un byte a la trama de nibbles del HD44780)
        └── i2c_master (genera la señalización I²C bit a bit)
```

---

## 3. Conceptos previos imprescindibles

- **FPGA:** circuito reconfigurable. No "ejecuta" código como un microcontrolador; el Verilog **describe hardware** que se sintetiza en compuertas y biestables (flip-flops).
- **Reloj y flip-flops:** casi todo ocurre en el flanco de subida de `clk` (50 MHz en esta placa). Un flip-flop guarda un bit en cada flanco.
- **FSM (máquina de estados finita):** patrón fundamental. Un registro `state` guarda el estado actual; un `case` decide qué hacer y a qué estado pasar. Toda la lógica de protocolos de este proyecto son FSMs.
- **Open-drain:** modo de salida donde el pin solo puede "tirar a 0" o "soltar" (alta impedancia). La línea sube a 1 gracias a una **resistencia pull-up** externa. I²C lo usa para que varios dispositivos compartan el bus sin cortocircuitos.
- **Lógica activa en bajo:** en esta placa los LEDs y botones se activan con 0.

---

## 4. Módulos, uno por uno

### 4.1 `i2c_master.v` — Motor I²C bit a bit

**Qué hace:** genera las condiciones físicas del bus I²C: START, escritura de 8 bits (MSB primero), lectura del bit ACK, y STOP. Es el nivel más bajo.

**Interfaz:**
| Señal | Dirección | Función |
|---|---|---|
| `i_start`, `i_write`, `i_stop` | entrada | ordenan una sub-operación |
| `i_data[7:0]` | entrada | byte a transmitir |
| `o_done` | salida | pulso al terminar la sub-operación |
| `sda_oe`, `scl_oe` | salida | control open-drain (1=tirar a 0, 0=soltar) |
| `sda_i` | entrada | lectura del estado real de SDA (para el ACK) |

**Conceptos clave:**
- **División de reloj:** I²C va a 50–100 kHz, pero el FPGA a 50 MHz. Se cuenta hasta `QP = CLK_FREQ/(4·I2C_FREQ)` para dividir cada bit en 4 "cuartos de periodo" (fases), lo que permite colocar los flancos de SDA y SCL en el orden correcto.
- **START:** SDA baja **mientras SCL está alto**. **STOP:** SDA sube mientras SCL está alto. Los datos solo cambian con SCL en bajo.
- **FSM:** estados `S_IDLE → S_START / S_WRITE_BIT / S_READ_ACK / S_STOP`.

> 🐞 **Lección de depuración 1:** Originalmente, al volver a `S_IDLE` entre cada sub-operación, el módulo **soltaba el bus** (`sda_oe<=0; scl_oe<=0`). Eso inyectaba un pulso de reloj espurio que **corría toda la trama un bit**: el analizador veía "lectura a 0x53" en vez de "escritura a 0x27" (`0x4E`→`0xA7`). **Solución:** no soltar el bus en `S_IDLE`; mantener su último estado. *Moraleja: en un protocolo, los estados de espera no deben alterar las líneas sin querer.*

---

### 4.2 `lcd_pcf8574.v` — Adaptador HD44780 sobre PCF8574

**Qué hace:** traduce "envía este byte al LCD" en la secuencia de transacciones I²C que el PCF8574 necesita. El LCD se maneja en **modo 4 bits**, así que cada byte se parte en dos nibbles (mitades).

**El formato del byte del PCF8574** (cómo se mapean sus 8 salidas a los pines del LCD):
```
bit:  7   6   5   4    3    2    1    0
     [---nibble---]   BL   EN   RW   RS
```
- `RS`: 0 = comando, 1 = dato (carácter).
- `EN` (Enable): el LCD **captura el nibble en el flanco de bajada de EN**. Por eso cada nibble se envía dos veces: una con `EN=1` y otra con `EN=0` (genera el pulso).
- `BL`: backlight (retroiluminación).

**FSM (por cada byte):** `START → dirección → nibble con EN=1 → STOP → espera → START → dirección → nibble con EN=0 → STOP`, repetido para el nibble alto y el bajo.

**Conceptos clave:** sincronización de un bus paralelo (LCD) sobre uno serie (I²C), y la importancia del **flanco de Enable** para latch de datos.

---

### 4.3 `lcd_controller.v` — Cerebro de la pantalla

**Qué hace:**
1. **Inicializa** el HD44780 con la secuencia estándar (`0x30,0x30,0x30,0x20` para entrar en 4 bits, luego *function set* `0x28`, *display on* `0x0C`, *entry mode* `0x06`, *clear* `0x01`, *home* `0x02`), respetando los **retardos** que exige el datasheet.
2. **Refresca** continuamente ambas líneas leyendo el contenido desde la memoria de video (`text_buffer`).
3. Aplica **scroll condicional por línea**: si la línea tiene ≤16 caracteres se muestra estática; si tiene más, se desplaza.

**Conceptos clave:**
- **ROM de inicialización:** los comandos y sus retardos se guardan en arreglos `init_cmd_*` recorridos por la FSM.
- **Lectura combinacional de la memoria:** la dirección del carácter (`o_rd_addr`) se calcula con lógica combinacional a partir del índice de columna y el offset de scroll, con aritmética modular (`índice mod longitud`) para que el texto "dé la vuelta".
- **Scroll independiente:** dos contadores de offset (`scroll_off1`, `scroll_off2`) avanzan con un temporizador (`SCROLL_MS`); el offset se reinicia cuando cambia la longitud de la línea (texto nuevo).

> 🐞 **Lección de depuración 2:** Al escribir caracteres, la FSM asertaba `lcd_start` pero **se quedaba en el mismo estado** y volvía a comprobar `!lcd_busy`. Como `o_busy` tarda un ciclo en subir, **disparaba un segundo arranque que se perdía**, saltándose un carácter de cada dos: "Hola Alumnos" salía como "Hl lmo". **Solución:** tras enviar el carácter, pasar a un estado de espera (`S_CMD_WAIT`) hasta `lcd_done`. *Moraleja: condición de carrera clásica entre productor y consumidor — siempre esperar la confirmación (handshake) antes de lanzar la siguiente operación.*

---

### 4.4 `text_buffer.v` — La memoria de video

**Qué hace:** almacena el texto a mostrar y lo escribe a partir de los bytes que llegan por UART. Es la **memoria** central del proyecto.

**Organización:** `vram[0..79]` = 2 líneas × 40 caracteres (`LINE_MAX=40`). Cada línea admite hasta 40 caracteres (más de 16 → habrá scroll).

**Protocolo de control (qué hace cada byte recibido):**
| Byte | Significado |
|---|---|
| `0x20`–`0x7E` (imprimible) | se escribe en el cursor y este avanza |
| `0x0A` (`\n`) | salta al inicio de la línea 2 |
| `0x0D` (`\r`) | cursor al inicio de la línea actual |
| `0x0C` (`\f`) | limpia ambas líneas |

**Conceptos clave:**
- **Doble puerto:** la UART **escribe** y el LCD **lee** simultáneamente, en el mismo dominio de reloj (sin metaestabilidad).
- **Relleno por software:** no se borra físicamente la RAM; se lleva una `longitud` por línea y el puerto de lectura devuelve un espacio (`0x20`) más allá de esa longitud. Más simple y rápido que limpiar 80 celdas.

> 🐞 **Lección de depuración 3 (memorias en FPGA):** Con 80 bytes, el sintetizador infirió **LUTRAM** (`RAM16SDP4`), pero el GW5A **no tiene celdas físicas (BELs) de ese tipo** → el *place & route* falló. **Solución:** el atributo `(* mem2reg *)` de Yosys fuerza a implementar la memoria con **flip-flops** (640 bits caben de sobra) manteniendo la lectura combinacional. *Moraleja: una memoria pequeña puede ir en registros; una grande va en BRAM. Conviene saber qué recursos físicos existen en tu FPGA.*

---

### 4.5 `uart_rx.v` — Receptor serie

**Qué hace:** recibe bytes en formato **8N1** (8 datos, sin paridad, 1 stop) a 115200 baudios.

**Cómo funciona:**
1. Espera el **bit de start** (línea baja a 0).
2. Cuenta **medio bit** (`HALF`) para muestrear en el **centro** de cada bit (máxima inmunidad a ruido).
3. Muestrea 8 bits, **LSB primero**, espaciados un bit (`CLKS = CLK_FREQ/BAUD`).
4. Valida con el **bit de stop** y pulsa `o_valid`.

**Conceptos clave:**
- **Sincronizador de 2 flip-flops:** la señal `rx` es asíncrona respecto al reloj; dos FF en cascada evitan **metaestabilidad**.
- **Muestreo al centro del bit:** clave para tolerar pequeños errores de velocidad.

> 🐞 **Lección de depuración 4 (la más instructiva):** La UART entregaba basura. Primero se sospechó del reloj. Con el **analizador lógico** se midió el ancho de bit en el pin TX del FPGA: **8.75 µs** → `clk ≈ 50 MHz` confirmado y baud correcto. Es decir, **la lógica y el reloj estaban bien**: la basura **venía en el cable**, del puente USB-serie onboard, que no entregaba los datos limpios. *Moraleja: medir antes que suponer. El analizador lógico distingue "mi diseño está mal" de "el problema es físico/externo".*

---

### 4.6 `uart_tx.v` — Transmisor serie (eco)

**Qué hace:** transmite bytes en 8N1 a 115200. Se usa para hacer **eco**: devuelve al PC cada byte recibido, lo que sirve para confirmar la comunicación.

**FSM:** `IDLE → START (bit 0) → 8 bits de datos → STOP`. Cada bit dura `CLKS` ciclos de reloj.

**Detalle fino:** `CLKS = (CLK_FREQ + BAUD/2) / BAUD` redondea al entero más cercano para minimizar el error de baudios (a 50 MHz da 434, error 0.006%).

---

### 4.7 `top.v` — Integración del sistema

**Qué hace:** conecta todos los módulos y maneja lo "de placa":
- **Power-On Reset (POR):** un contador mantiene el sistema en reset ~21 ms tras encender, para que el LCD se estabilice antes de inicializarse.
- **Buses open-drain de I²C:** `assign io_sda = sda_oe ? 1'b0 : 1'bz;` (tirar a 0 o soltar en alta impedancia).
- **Eco UART:** cada byte recibido se reenvía por TX.

**Conceptos clave:** el manejo de pines `inout` con tri-estado (`1'bz`) y la propagación de parámetros (un solo `CLK_HZ` configura toda la jerarquía).

---

### 4.8 `constraints/board.cst` — Mapa de pines

**Qué hace:** indica a qué **bola física** del FPGA va cada señal del diseño, su nivel lógico (LVCMOS33), pull-ups y corriente.

```
clk   → E2     (reloj 50 MHz del dock)
io_sda→ K1,  io_scl → K2   (I²C, con PULL_MODE=UP)
rxd   → J10,  txd → J11    (UART por header de 40 pines, adaptador USB-TTL externo)
```

> 🐞 **Lección de depuración 5:** El I²C no respondía (NAK en todo) porque **SDA y SCL estaban intercambiados** en el `.cst`. Y la UART terminó saliendo por el **header de 40 pines (J10/J11)** con un adaptador USB-TTL externo, porque el puente onboard no entregaba datos limpios. *Moraleja: el archivo de constraints es tan importante como el HDL; un pin equivocado parece "un bug de código" pero es físico.*

---

## 5. Flujo de datos completo (ejemplo: escribir "Hi")

1. La PC envía los bytes `H`(0x48), `i`(0x69) por el puerto serie.
2. `uart_rx` los recibe y pulsa `o_valid` por cada uno.
3. `text_buffer` los escribe en `vram[0]`, `vram[1]` y pone `len1 = 2`.
4. `lcd_controller`, en su refresco continuo, lee `vram[0..15]` (los dos primeros caracteres + espacios).
5. Por cada carácter llama a `lcd_pcf8574`, que lo parte en dos nibbles con su pulso de Enable.
6. `i2c_master` genera la trama I²C hacia el PCF8574.
7. El PCF8574 mueve los pines del LCD y aparece "Hi" en pantalla.
8. En paralelo, `uart_tx` devuelve "Hi" al PC (eco).

---

## 6. La cadena de herramientas (toolchain de código abierto)

Todo el flujo usa software libre, orquestado por un `Makefile`.

| Etapa | Herramienta | Comando | Qué hace |
|---|---|---|---|
| **Síntesis** | **Yosys** (`synth_gowin`) | `make synth` | Convierte el Verilog en una **netlist** de celdas Gowin (LUTs, flip-flops, ALUs, RAM). |
| **Place & Route** | **nextpnr-himbaechel** | `make pnr` | **Coloca** cada celda en una posición física del chip y **rutea** las conexiones; verifica el **timing**. |
| **Bitstream** | **gowin_pack** (Proyecto Apicula) | `make pack` | Genera el `.fs`, el archivo binario que configura el FPGA. |
| **Programación** | **openFPGALoader** | `make program` | Carga el `.fs` al FPGA por JTAG/USB. |
| **Lint** | **Verilator** | `make lint` | Análisis estático: detecta anchos de bit incorrectos, señales sin usar, etc. |
| **Simulación** | **Icarus Verilog** | `make sim TB=...` | Ejecuta los testbenches y comprueba la lógica **sin hardware**. |
| **Formas de onda** | **GTKWave** | `make wave` | Visualiza las señales generadas por la simulación. |

**Concepto del flujo (RTL → bits):**
```
   Verilog (.v)
       │  Yosys: síntesis
       ▼
   Netlist (celdas Gowin)
       │  nextpnr: place & route
       ▼
   Diseño físico ubicado/ruteado
       │  gowin_pack: empaquetado
       ▼
   Bitstream (.fs)
       │  openFPGALoader: programación
       ▼
   FPGA configurado
```

**Verificación antes del hardware:** en este proyecto se escribieron testbenches (`tb_uart_rx.v`, `tb_text_buffer.v`) que se ejecutan con Icarus y comprueban automáticamente la recepción UART, el protocolo de la memoria, las longitudes y el scroll. Simular primero **ahorra horas** de depuración en placa.

**Notas específicas del GW5A (de la experiencia):**
- Los **pragmas de Gowin** (`syn_ramstyle`, etc.) **no funcionan** con Yosys; hay que confiar en patrones de código o atributos de Yosys (`mem2reg`).
- Una **BRAM** se infiere cuando `ancho × profundidad ≥ 1024` bits; por debajo de eso el sintetizador intenta LUTRAM, que este chip puede no soportar.

---

## 7. Resumen de lecciones de ingeniería

El valor de este proyecto no está solo en el resultado, sino en el **proceso de depuración**:

1. **Un estado de espera no debe alterar las líneas del bus** (bug del corrimiento de bit I²C).
2. **Verifica el mapa de pines**: SDA/SCL invertidos parecen un bug de software.
3. **Handshake antes de la siguiente operación** (carrera que perdía caracteres).
4. **Conoce los recursos físicos de tu FPGA** (LUTRAM vs BRAM vs registros).
5. **Mide, no supongas**: el analizador lógico reveló que el reloj y el HDL estaban bien y el problema era el cable/puente externo.
6. **Aísla el problema**: cuando el puente onboard falló, un adaptador USB-TTL externo en pines accesibles resolvió la comunicación.

---

## 8. Glosario rápido

- **HDL:** Hardware Description Language (Verilog).
- **FSM:** Máquina de estados finita.
- **I²C:** bus serie de 2 hilos (SDA datos, SCL reloj), open-drain.
- **UART:** comunicación serie asíncrona (8N1, 115200 baud aquí).
- **PCF8574:** expansor de E/S por I²C (8 pines).
- **HD44780:** controlador estándar de los LCD de caracteres.
- **LUT / Flip-flop / BRAM / LUTRAM:** recursos lógicos y de memoria del FPGA.
- **Bitstream:** archivo que configura el FPGA.
- **Netlist:** descripción del circuito como celdas interconectadas.

---

## 9. Cómo construir y probar

```bash
make            # síntesis + place&route + bitstream
make program    # programar la placa (o: sudo openFPGALoader -b tangprimer25k -f build/top.fs)
make lint       # análisis estático
make sim TB=tb_uart_rx       # simular el receptor UART
make sim TB=tb_text_buffer   # simular la memoria de video

# Prueba UART (adaptador USB-TTL externo en J10/J11, 115200 8N1):
stty -F /dev/ttyUSBn 115200 cs8 -cstopb -parenb -crtscts raw
printf 'Hola\nMundo con texto largo para scroll' > /dev/ttyUSBn
```

---

*Documento didáctico generado a partir del desarrollo real del proyecto, incluyendo los errores encontrados y su solución, como material de estudio para Sistemas Digitales — ITLA Mecatrónica.*
