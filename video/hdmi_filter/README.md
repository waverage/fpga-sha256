# HDMI live filter, Arty Z7-20

HDMI IN -> per-pixel filter in the fabric -> HDMI OUT, 1280x720 at 60 Hz.
Fabric only, the ARM is not used. Verified on the board 2026-10-22: input
locked at 1280x720, 60 frames/s, all filters visible on the monitor.

```
hdl/hdmi_filter_top.v     clocks, Digilent dvi2rgb/rgb2dvi, buttons, LEDs, status VIO
hdl/video_filter.v        the filter, 3-clock pipeline
hdl/video_measure.v       measured width/height/frame count for the VIO
sim/video_filter_tb.v     all 16 mode/rotate/split combinations vs a model, prints FILTER PASS
constraints/hdmi_filter.xdc
build.tcl                 creates the project and IP, builds the bitstream
board.tcl                 programs the board and/or reads the status over JTAG
```

## Controls

| Control | Effect |
|---|---|
| SW1 SW0 = 00 | pass through |
| 01 | grayscale (BT.601 weights) |
| 10 | invert |
| 11 | black/white threshold at luma 128 |
| BTN0 | toggle colour rotation, out R,G,B = in G,B,R |
| BTN1 | toggle split screen, left half unfiltered |
| LD0 | heartbeat |
| LD1 | HDMI input locked |
| LD2, LD3 | rotation on, split on |

## Connect

Micro-USB PROG/UART for power and JTAG (JP4 = JTAG, JP5 = USB). HDMI
source (PC, laptop) to **HDMI IN**, monitor to **HDMI OUT**. The receiver
emulates a 720p-only EDID, so the source picks 1280x720 60 Hz. HDCP
protected content shows black.

## Build and run, no GUI needed

Needs Vivado 2026.1 and a clone of https://github.com/Digilent/vivado-library
(dvi2rgb 2.0, rgb2dvi 1.4). Paths below are the ones used on the build PC.

```
vivado -mode batch -source build.tcl -tclargs E:/amd/hdmi_filter E:/amd/digilent-vivado-library
vivado -mode batch -source board.tcl -tclargs E:/amd/hdmi_filter program
vivado -mode batch -source board.tcl -tclargs E:/amd/hdmi_filter status
```

`status` prints PLL lock, HDMI lock, rotate/split, measured resolution, a
frame counter, switches and buttons, read twice one second apart.
The bitstream is volatile: after a power cycle run `program` again.

Simulation:

```
xvlog hdl/video_filter.v hdl/video_measure.v sim/video_filter_tb.v
xelab video_filter_tb -s tb && xsim tb -R
```

## Notes

- Digilent packs pixels as `[23:16]` red, `[15:8]` blue, `[7:0]` green.
- The 125 MHz board clock and HDMI OUT are in the same clock region, which
  has one MMCM. rgb2dvi needs that MMCM (dedicated path to BUFIO), so the
  200/100 MHz clock generator is a PLL. With an MMCM, placement fails with
  `[Place 30-149] Unroutable Placement! A MMCM / (BUFIO/BUFR)`.
- Critical warnings about `ila_pixclk`/`ila_refclk` come from debug cores
  inside dvi2rgb that are disabled (`kDebug = false`); harmless.
- Timing at 74.25 MHz: WNS +1.140 ns, no failing endpoints. 2.4% of LUTs.
- Output timing is the input timing; the pipeline only delays de/hs/vs.
