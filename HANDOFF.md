# Handoff, 2026-10-21

For whoever (or whichever Claude session) picks this up on the Windows PC.
Read this, then `README.md`.

## Goal

Learning project on a Digilent **Arty Z7-20** (Zynq XC7Z020-1CLG400C). Hash
a 32-bit message with SHA-256 implemented in the FPGA fabric, print the
digest on the USB serial console. The owner is new to FPGAs; explain Vivado
and Vitis steps concretely, not by reference.

## State: working on the board (2026-10-21)

Next steps 1 to 5 below are done on the Windows PC with Vivado and Vitis
2026.1. The board prints the "abcd" self test OK, and typed input "2222"
gives `edee29f8...b4c995e9`, identical to Python hashlib.

| File | Status |
|---|---|
| `hdl/sha256_core.v` | Passes `sim/sha256_tb.v` in Icarus and Vivado XSim |
| `hdl/sha256_axi.v` | Passes `sim/sha256_axi_tb.v` in Icarus and Vivado XSim |
| `bd/system.tcl` | Block design exported with `write_bd_tcl -no_ip_version` |
| `sw/main.c` | Builds in Vitis 2026.1 unchanged, runs on the board |

Build result: timing met at FCLK_CLK0 = 50 MHz, WNS +8.822 ns (critical
path about 11.2 ns, so roughly 85 MHz may be reachable).

Local paths on the Windows PC (not in git): Vivado installed at
`E:\amd\2026.1`, Vivado project `E:\amd\sha256\sha256.xpr` (sources point
at the repo files, not copies), Vitis workspace `E:\amd\sha256_vitis`
with components `sha256_platform` and `sha256_app`.

Run the simulations with Vivado's simulator (README step 2) or Icarus:

```
iverilog -g2005 -o core_tb hdl/sha256_core.v sim/sha256_tb.v && vvp core_tb
iverilog -g2005 -o axi_tb hdl/sha256_core.v hdl/sha256_axi.v sim/sha256_axi_tb.v && vvp axi_tb
```

Expected output ends in `ALL PASS` and `AXI PASS`.

## Environment facts learned so far

- Development PC: Windows 11 x86-64, Ryzen 9 5900X. Vivado/Vitis 2026.1
  installed under `E:\amd\2026.1` (not `C:\Xilinx` as first assumed).
  Batch Tcl works: `E:\amd\2026.1\Vivado\bin\vivado.bat -mode batch -source x.tcl`.
- Licensing: this Vivado release has **Basic Tier** (free, needs a no-charge
  node-locked licence file) and **Enterprise Tier**. The older names "ML
  Standard / WebPACK" no longer exist. A Basic Tier `Xilinx.lic` is already
  generated and loaded on the Windows PC via Vivado License Manager. It is
  node-locked to that machine's host ID.
- Board part: "Arty Z7-20" is available in 2026.1 (board_part
  `digilentinc.com:arty-z7-20:part0:1.1`), picked from the Boards tab.
- Keep projects in short paths without spaces, never inside OneDrive.

## Vivado/Vitis 2026.1 differences found

- Address Editor assigns the first GP0 slave 0x4000_0000 with range 4K,
  not 0x43C0_0000 / 64K. Changed by hand to 0x43C0_0000; 4K kept.
- Vitis does generate `XPAR_SHA256_AXI_0_BASEADDR` (and `_HIGHADDR`) for
  the module reference, so `main.c` follows the Address Editor.
- Vitis Unified bug: replacing `helloworld.c` with `main.c` made it rewrite
  `src/UserConfig.cmake` with two stray `endif()` at the end and a stale
  `"helloworld.c"` source entry. Removed by hand; documented in README.
- Harmless warnings: `[PSU-1]` negative DQS_TO_CLK_DELAY from the board
  DDR preset; `[BD 41-702]` PCW_M_AXI_GP0_FREQMHZ (read-only parameter,
  cannot be set); `[Board 49-56]` parse errors for other vendors' boards.
- Vivado 2026.1 uses SmartConnect (`axi_smc`) rather than AXI Interconnect.

## Board facts

- Micro-USB "PROG/UART" carries JTAG and the serial console (FTDI, two COM
  ports, the higher-numbered one is the UART, 115200 8N1).
- Jumpers: JP5 = `USB` for power from the cable. JP4 = `JTAG` to program
  from Vivado/Vitis, `SD` or `QSPI` to boot a stored image.
- Arty Z7-20 is layout-identical to PYNQ-Z1; PYNQ-Z1 constraint files and
  SD images work on it.
- Useful PL pins if a pure-fabric test is ever needed (LVCMOS33):
  125 MHz clock H16; LEDs LD0..LD3 = R14, P14, N16, M14;
  buttons BTN0..3 = D19, D20, L20, L19; switches SW0, SW1 = M20, M19.

## Design decisions

- **PS + PL, not pure PL.** The USB UART is wired to the PS MIO pins, so the
  fabric cannot talk to the PC directly without an extra USB-serial Pmod.
  The ARM reads 4 chars, writes them to the core over AXI-Lite, prints the
  result. This is the standard Zynq pattern and worth learning.
- **Fixed 4-byte message.** Padding is constant, so the core builds its own
  512-bit block (W0 = msg, W1 = 0x80000000, W15 = 32).
- **One round per clock, 65 cycles per hash.** Message schedule is a 16-word
  shift register.
- **FCLK_CLK0 = 50 MHz.** The round has a 5-adder chain. Measured WNS
  +8.822 ns at 50 MHz. `sha256_axi.v` hardcodes `FREQ_HZ 50000000` in its
  clock interface attribute; change it together with FCLK_CLK0.
- **Register map** (base 0x43C0_0000) is in the header of
  `hdl/sha256_axi.v` and in `README.md`. `main.c` falls back to that address
  if `XPAR_SHA256_AXI_0_BASEADDR` is missing from `xparameters.h`.
- AXI port names are `s_axi_*` so Vivado "Add Module" infers the interface.
  Fallback if inference fails: Tools, Create and Package New IP.

## Original plan (all done 2026-10-21)

1. Vivado project, README build steps 1 to 7. Done.
2. Behavioural simulation prints `ALL PASS` and `AXI PASS`. Done.
3. Bitstream, no failing endpoints at 50 MHz. Done, WNS +8.822 ns.
4. Vitis platform and app with `sw/main.c`. Done, only the
   UserConfig.cmake fix was needed.
5. Run on the board over JTAG, self test OK. Done.
6. Block design exported to `bd/system.tcl`. Done. Not yet tested by
   recreating a project from scratch with it.

## Second project: HDMI live filter (2026-10-22)

`video/hdmi_filter/`, fabric-only HDMI IN -> filter -> HDMI OUT at 720p60,
working on the board. Everything is driven from Vivado batch mode
(`build.tcl`, `board.tcl`); the owner does not want to open the Vivado or
Vitis GUI, so keep new work scriptable. Digilent IP clone at
`E:\amd\digilent-vivado-library`, project at `E:\amd\hdmi_filter`.
Board status (HDMI lock, resolution, frame counter) is readable over JTAG
through a VIO, which is how a session without a monitor checks the result.
The SHA-256 app can be loaded the same way with xsdb (`fpga`, `ps7_init`,
`dow`, `con`), serial console on COM8.

## Open loose ends

- Test `bd/system.tcl` in a fresh project.
- Optional: `BOOT.BIN` on microSD so it runs without the PC (README).

## Ideas after it works

- Pipeline or unroll the round to raise the clock, measure hashes per second.
- Variable-length message: PS writes 16 words of a padded block, or the core
  does padding itself with a byte-count register.
- Drive the same peripheral from Linux: boot the PYNQ-Z1 image and talk to
  the registers with `pynq.MMIO`, or write a tiny UIO driver.

## Repo

https://github.com/waverage/fpga-sha256 , branch `main`.
Commit messages end with a `Co-Authored-By: Claude ...` line naming the
model that made the change.
