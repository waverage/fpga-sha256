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
bd/system.tcl        block design (Zynq PS + sha256_axi), from write_bd_tcl
video/hdmi_filter/   second project: live HDMI in -> filter -> HDMI out,
                     built and run from batch scripts (see its README)
```

Simulated 2026-10-21 with Icarus Verilog 13 and Vivado 2026.1 XSim: both
testbenches pass. Built and run on the board the same day with Vivado and
Vitis 2026.1: timing met at 50 MHz (WNS +8.822 ns), hardware digests match
Python hashlib.

Register map (base 0x43C0_0000 by default):

| Offset | Name | Access | Meaning |
|---|---|---|---|
| 0x00 | CTRL | W | bit0 = 1 starts a hash |
| 0x04 | STATUS | R | bit0 busy, bit1 done (sticky) |
| 0x08 | MSG | RW | 32-bit message, byte 0 in bits 31:24 |
| 0x10..0x2C | DIGEST0..7 | R | hash, DIGEST0 is the first hex word |

## Build (Vivado 2026.1 on Windows)

1. Create Project, RTL, Boards tab, "Arty Z7-20" (refresh the board list
   or install Digilent board files if missing; bare part is
   `xc7z020clg400-1`). Add `hdl/*.v` as design sources and `sim/*.v` as
   simulation sources, with "Copy sources into project" unticked.
2. Simulation Sources: right-click `sha256_tb`, Set as Top. Run Simulation,
   Run Behavioral Simulation, Run All. Tcl console must show `ALL PASS`.
3. Create Block Design `system`. Add IP "ZYNQ7 Processing System". Run Block
   Automation (applies board preset). Double-click the PS, Clock
   Configuration, PL Fabric Clocks, set FCLK_CLK0 = 50 MHz.
4. Right-click canvas, Add Module, choose `sha256_axi`. Run Connection
   Automation, tick all. Vivado adds an AXI interconnect and reset block.
5. Address Editor tab: set `sha256_axi_0` Master Base Address to
   0x43C0_0000 (Vivado 2026.1 assigns 0x4000_0000, 4K by default; 4K is
   enough). `main.c` uses the `XPAR_SHA256_AXI_0_BASEADDR` macro Vitis
   generates, so any address works, but the docs assume 0x43C0_0000.
6. Validate Design (F6). Sources, right-click `system.bd`, Create HDL
   Wrapper, let Vivado manage. Set `system_wrapper` as top.
7. Generate Bitstream. Then File, Export, Export Hardware, include bitstream,
   gives `system_wrapper.xsa`. Any block design change (address, clock)
   needs a new bitstream and a new export.

Steps 3 to 5 can instead be done by running `source <repo>/bd/system.tcl`
in the Tcl console of a project that already has `hdl/*.v` added (not yet
tested from scratch).

Expected, harmless warnings: `[PSU-1] ... DQS_TO_CLK_DELAY ... negative
value` (from the Digilent DDR preset), `[BD 41-702] ... PCW_M_AXI_GP0_FREQMHZ`
(read-only, ignore), and `[Board 49-56]` for other vendors' board files.

## Software (Vitis Unified IDE 2026.1)

1. Tools, Launch Vitis IDE. Open Workspace on a new folder outside the
   repo, e.g. `E:\amd\sha256_vitis`.
2. File, New Component, Platform. Hardware design = the `.xsa`, OS
   standalone, processor `ps7_cortexa9_0`. FLOW panel, Build.
3. Examples view, Embedded Software Examples, Hello World, Create
   Application Component from Template, on that platform.
4. In `<app>\src`, delete `helloworld.c` and copy in `sw/main.c`.
5. Vitis 2026.1 bug: after the source change it regenerates
   `src\UserConfig.cmake` with two stray `endif()` lines at the end and
   keeps `"helloworld.c"` in `USER_COMPILE_SOURCES`. CMake fails with
   "Flow control statements are not properly nested". Delete both stray
   `endif()` lines and the `"helloworld.c"` entry, then Build.

## Run

1. Board: JP4 = JTAG, JP5 = USB, micro-USB to the PC.
2. PuTTY (or Vitis, Serial Monitor) on the higher-numbered COM port,
   115200 8N1, no flow control.
3. Vitis FLOW panel, application selected, Run. This programs the
   bitstream, runs ps7_init and loads the ELF over JTAG.
4. Terminal shows the "abcd" self test with OK, then asks for 4 characters.
   Each character is echoed (doubled if the terminal also echoes locally).

Check any result on the PC with
`python3 -c "import hashlib;print(hashlib.sha256(b'abcd').hexdigest())"`.

## Make it survive power-off (optional)

Vitis: Create Boot Image with FSBL + bitstream + application gives
`BOOT.BIN`. Copy it to a FAT32 microSD and set JP4 = SD, or use Program
Flash to write it to QSPI and set JP4 = QSPI.
