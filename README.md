# SHA-256 in FPGA fabric, Arty Z7-20

Hashes one 32-bit (4-byte) message in the Zynq-7020 programmable logic.
The ARM core writes the message over AXI-Lite, the fabric runs the 64 SHA-256
rounds (one per clock), and the ARM prints the 256-bit digest on the USB
serial console.

```
hdl/sha256_core.v    the hash core (pure Verilog, no Xilinx primitives)
hdl/sha256_axi.v     AXI4-Lite register wrapper for the Zynq PS
sim/sha256_tb.v      core testbench, 3 vectors, prints ALL PASS
sim/sha256_axi_tb.v  bus-level testbench, drives the wrapper like the C code
sw/main.c            bare-metal program for Vitis (replaces helloworld.c)
```

Simulated 2026-10-21 with Icarus Verilog 13: both testbenches pass.

Register map (base 0x43C0_0000 by default):

| Offset | Name | Access | Meaning |
|---|---|---|---|
| 0x00 | CTRL | W | bit0 = 1 starts a hash |
| 0x04 | STATUS | R | bit0 busy, bit1 done (sticky) |
| 0x08 | MSG | RW | 32-bit message, byte 0 in bits 31:24 |
| 0x10..0x2C | DIGEST0..7 | R | hash, DIGEST0 is the first hex word |

## Build (Vivado 2025.x on Windows, Digilent board files installed)

1. Create Project, RTL, board "Arty Z7-20". Add `hdl/*.v` as design
   sources and `sim/*.v` as simulation sources.
2. Simulation Sources: right-click `sha256_tb`, Set as Top. Run Simulation,
   Run Behavioral Simulation, Run All. Tcl console must show `ALL PASS`.
3. Create Block Design `system`. Add IP "ZYNQ7 Processing System". Run Block
   Automation (applies board preset). Double-click the PS, Clock
   Configuration, PL Fabric Clocks, set FCLK_CLK0 = 50 MHz.
4. Right-click canvas, Add Module, choose `sha256_axi`. Run Connection
   Automation, tick all. Vivado adds an AXI interconnect and reset block.
5. Address Editor tab: `sha256_axi_0` should be at 0x43C0_0000, 64K.
6. Validate Design (F6). Sources, right-click `system.bd`, Create HDL
   Wrapper, let Vivado manage. Set `system_wrapper` as top.
7. Generate Bitstream. Then File, Export, Export Hardware, include bitstream,
   gives `system_wrapper.xsa`.

## Software (Vitis)

1. Tools, Launch Vitis IDE. New workspace, e.g. `C:\fpga\sha256\vitis`.
2. Create Platform Component from the `.xsa`, OS standalone, processor
   `ps7_cortexa9_0`. Build it.
3. Create Application Component from template "Hello World" on that
   platform. Replace `helloworld.c` with `sw/main.c`. Build.

## Run

1. Board: JP4 = JTAG, JP5 = USB, micro-USB to the PC.
2. PuTTY on the higher-numbered COM port, 115200 8N1, no flow control.
3. Vitis: right-click the application, Run As, Launch Hardware. This
   programs the bitstream and loads the ELF over JTAG.
4. Terminal shows the "abcd" self test with OK, then asks for 4 characters.

Check any result on the PC with
`python3 -c "import hashlib;print(hashlib.sha256(b'abcd').hexdigest())"`.

## Make it survive power-off (optional)

Vitis: Create Boot Image with FSBL + bitstream + application gives
`BOOT.BIN`. Copy it to a FAT32 microSD and set JP4 = SD, or use Program
Flash to write it to QSPI and set JP4 = QSPI.
