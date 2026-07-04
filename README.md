# verilog-i2c-master-arduino-slave
I2C communication project between FPGA and Arduino.
# FPGA I2C Master (Verilog) — Cyclone 10 LP to Arduino Slave

A from-scratch Verilog I2C master, implemented on an Intel Cyclone 10 LP FPGA, tested against an Arduino configured as an I2C slave.

## What this project does

The FPGA acts as the I2C **master**. Once per second, it sends one byte from a 10-element counter array (values 1–10) to an Arduino I2C **slave** at address `0x08`. The Arduino receives the byte over its `Wire` library `onReceive()` callback and prints it to the Serial monitor.

This was built as a from-scratch design exercise — the I2C master FSM, clock-pulse generation, and open-drain SDA/SCL driving logic are all hand-written in Verilog, not a vendor IP block.

## Hardware / toolchain

- **FPGA board:** Intel Cyclone 10 LP <!-- TODO: add exact board name/part number -->
- **Toolchain:** Quartus Prime Lite <!-- TODO: confirm version, e.g. 20.1 -->
- **Slave device:** Arduino <!-- TODO: which board — Uno / Nano / etc. -->
- **I2C clock:** 100 kHz (master clocked from a 4 MHz internal clock derived via PLL from a 25 MHz board input)
- **Slave address:** `0x08`

## Design overview

The I2C master is a Moore-style FSM with the following states:

```
IDLE_S → START_S → WRITE_ADDR_S → ACK1_S → WRITE_DATA_S → ACK2_S → STOP_S → IDLE_S
```

- `WRITE_ADDR_S` shifts out the 7-bit slave address + R/W bit, MSB first.
- `ACK1_S` samples SDA to check the slave acknowledged the address.
- `WRITE_DATA_S` shifts out the 8-bit data byte.
- `ACK2_S` samples SDA to check the slave acknowledged the data byte.
- `STOP_S` releases the bus.

A top-level sequencer (`top` module) generates a 1-second tick, walks a 10-entry array, and issues one write transaction per tick.

## Known issue found during debugging (and how it was diagnosed)

During testing, the Arduino only ever received the odd values (1, 3, 5, 7, 9) instead of the full 1–10 sequence.

**Cause:** the top-level sequencer advanced its array index on every completed transaction, regardless of whether the transaction succeeded or was NACKed. Every second transaction was being NACKed and silently dropped, which produced the alternating pattern.

**Suspected root cause of the NACKs:** the Arduino's original `receiveEvent()` callback called `Serial.print()`/`println()` directly inside the I2C interrupt context. On AVR, this blocks the CPU (and effectively the TWI hardware's readiness) for several milliseconds per call, which is believed to have caused every other transaction to arrive before the Arduino's I2C hardware had fully re-armed.

**Fix applied:**
1. FPGA side: the sequencer now only advances the array index when `ack_err` is low (i.e., on a successful transaction), rather than unconditionally. <!-- TODO: confirm this change is actually in your committed top.v -->
2. Arduino side: moved all `Serial` output out of the `onReceive()` ISR context. The callback now only stores the received byte and sets a `volatile` flag; the actual printing happens in `loop()`.

**Status:** <!-- TODO — be honest here. Choose one:
  (a) "Confirmed via logic analyzer capture on `ack_err`, SDA, and SCL — NACKs no longer occur after the Arduino-side fix."
  (b) "Fix applied and values now increment correctly 1–10 on the Serial monitor; root cause not yet confirmed via logic analyzer capture."
Do not write (a) unless you have actually captured and reviewed the trace. -->

## How to build and run

1. Open the Quartus project <!-- TODO: filename --> in Quartus Prime.
2. Compile and program the Cyclone 10 LP board via USB Blaster.
3. Flash `arduino/i2c_slave.ino` <!-- TODO: confirm path/filename --> to the Arduino using the Arduino IDE.
4. Wire SDA/SCL between FPGA and Arduino <!-- TODO: confirm pull-up resistor values used, e.g. 4.7kΩ -->, common ground.
5. Open the Arduino Serial monitor at 115200 baud.
6. Reset the FPGA. Values should increment from 1 to 10, once per second, then repeat.

## Repository structure

```
<!-- TODO: fill in actual file layout, e.g. -->
/rtl/top.v
/rtl/i2c_master.v
/arduino/i2c_slave.ino
/README.md
```

## Next steps

- <!-- TODO: e.g. "Capture ACK1-to-data-byte boundary on logic analyzer to fully confirm root cause" -->
- <!-- TODO: e.g. "Add SystemVerilog testbench / SVA-based verification" -->
- <!-- TODO: anything else still open -->
