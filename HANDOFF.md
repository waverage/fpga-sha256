# Handoff, 2026-10-21

For whoever (or whichever Claude session) picks this up on the Windows PC.
Read this, then `README.md`.

## Goal

Learning project on a Digilent **Arty Z7-20** (Zynq XC7Z020-1CLG400C). Hash
a 32-bit message with SHA-256 implemented in the FPGA fabric, print the
digest on the USB serial console. The owner is new to FPGAs; explain Vivado
and Vitis steps concretely, not by reference.

## State

Done and verified on macOS with Icarus Verilog 13 (`brew install icarus-verilog`):

| File | Status |
|---|---|
| `hdl/sha256_core.v` | Passes `sim/sha256_tb.v`, 3 vectors vs Python hashlib |
| `hdl/sha256_axi.v` | Passes `sim/sha256_axi_tb.v`, full AXI-Lite write/poll/read sequence |
| `sw/main.c` | Written, not compiled yet (needs Vitis BSP headers) |

Not done:

- Vivado synthesis, implementation, timing, bitstream.
- Block design with the Zynq PS and the AXI connection.
- Vitis platform and application build.
- Running on the board.

Run the simulations yourself on the Windows PC with Vivado's simulator
(README step 2) or Icarus if installed:

```
iverilog -g2005 -o core_tb hdl/sha256_core.v sim/sha256_tb.v && vvp core_tb
iverilog -g2005 -o axi_tb hdl/sha256_core.v hdl/sha256_axi.v sim/sha256_axi_tb.v && vvp axi_tb
```

Expected output ends in `ALL PASS` and `AXI PASS`.

## Environment facts learned so far

- Development PC: Windows 11 x86-64. Vivado 2025.x installed under `C:\Xilinx`.
- Licensing: this Vivado release has **Basic Tier** (free, needs a no-charge
  node-locked licence file) and **Enterprise Tier**. The older names "ML
  Standard / WebPACK" no longer exist. A Basic Tier `Xilinx.lic` is already
  generated and loaded on the Windows PC via Vivado License Manager. It is
  node-locked to that machine's host ID.
- Digilent board files: install from github.com/Digilent/vivado-boards
  into `C:\Xilinx\Vivado\2025.x\data\boards\board_files` so "Arty Z7-20"
  appears in New Project. Not confirmed installed yet.
- Keep projects in short paths without spaces, e.g. `C:\fpga\sha256`,
  never inside OneDrive. Add Defender exclusions for `C:\Xilinx` and the
  project folder.

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
- **FCLK_CLK0 = 50 MHz.** The round has a 5-adder chain; 50 MHz leaves margin
  on a -1 Artix-class fabric. 100 MHz may or may not close timing.
- **Register map** (base 0x43C0_0000 by default) is in the header of
  `hdl/sha256_axi.v` and in `README.md`. `main.c` falls back to that address
  if `XPAR_SHA256_AXI_0_BASEADDR` is missing from `xparameters.h`.
- AXI port names are `s_axi_*` so Vivado "Add Module" infers the interface.
  Fallback if inference fails: Tools, Create and Package New IP.

## Next steps, in order

1. Clone to `C:\fpga\sha256`. Create the Vivado project in `C:\fpga\sha256\vivado`
   (gitignored). Follow README build steps 1 to 7.
2. First checkpoint: behavioural simulation prints `ALL PASS`.
3. Second checkpoint: bitstream generated, timing report has no failing
   endpoints at 50 MHz.
4. Vitis: platform from the `.xsa`, Hello World app, replace `helloworld.c`
   with `sw/main.c`. Fix any header or macro name differences the new Vitis
   Unified IDE introduces; record them here.
5. Run on the board over JTAG. Expected console:
   `self test sha256("abcd") = 88d4266f...6f031589  OK`.
6. Commit any constraint, Tcl or wrapper files Vivado needs that are not
   build output. Consider exporting the block design as Tcl
   (`write_bd_tcl`) so the `.bd` can be regenerated without committing it.

## Ideas after it works

- Pipeline or unroll the round to raise the clock, measure hashes per second.
- Variable-length message: PS writes 16 words of a padded block, or the core
  does padding itself with a byte-count register.
- Drive the same peripheral from Linux: boot the PYNQ-Z1 image and talk to
  the registers with `pynq.MMIO`, or write a tiny UIO driver.

## Repo

https://github.com/waverage/fpga-sha256 , branch `main`.
Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
