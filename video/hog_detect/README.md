# HOG person detector, Arty Z7-20

HDMI IN -> person detection in the fabric -> green boxes on HDMI OUT, 1280x720
at 60 frames/s, no ARM, no frame buffer. Classic HOG + linear SVM (Dalal &
Triggs) with OpenCV's trained default people detector weights, one scale,
64x128 window, stride 8. Builds on `../hdmi_filter` (the switch filters and
buttons still work).

Verified 2026-10-23:

- RTL vs bit-exact Python model, two full 720p frames in XSim with real 720p
  timing: all 14151 block feature vectors and 11475 window scores identical,
  same hits and boxes, no row overruns.
- On the board, a still frame shown pixel-exact over HDMI: 9 window hits,
  3 boxes, the same clusters as simulation. Live video: boxes follow people.

## What it detects

Whole, upright, standing or walking people about 100-150 pixels tall (the
window is 64x128 with the person ~96 px inside). Not seated people, not
head-and-shoulders webcam framing, not people much larger or smaller (single
scale). Test material: OpenCV's `vtest.avi` at native size centred in
1280x720 (`vtest_720p.mp4`, see below).

## Controls

| Control | Effect |
|---|---|
| SW1 SW0 | filter as in hdmi_filter (pass, grayscale, invert, threshold) |
| BTN0, BTN1 | colour rotation, split screen |
| BTN2 | toggle person boxes (on after programming) |
| LD0 | heartbeat |
| LD1 | HDMI input locked |
| LD2 | at least one person box in the frame |
| LD3 | person boxes enabled |

Detection runs on the unfiltered input; boxes from frame N are drawn on frame N+1.

## Pipeline

```
hdl/hog_pixel.v    luma, gamma 16*sqrt, 2 line buffers, central differences,
                   10-stage CORDIC: magnitude + 9 unsigned bins, vote split
                   between the two nearest bins
hdl/hog_cells.v    8x8 cell histograms, 3-row ring of cell memory
hdl/hog_blocks.v   16x16 blocks, L2-Hys with LUT sqrt and reciprocal (hog_rsq.v),
                   3 pipelined stages, 36 x 8-bit features
hdl/hog_svm.v      streaming SVM: 15 lanes x 6 DSPs, horizontal partial sums
                   in registers, vertical in BRAM, one score per window
hdl/hog_group.v    raster-order clustering into up to 8 boxes, >= 2 hits each
hdl/box_overlay.v  64x128 green rectangles
hdl/hog_tables.v   generated: gamma/sqrt/reciprocal ROMs, 3780 SVM weights
hdl/hog_top.v      board top level (HDMI, filter, detector, VIO)
model/hog_fixed.py bit-exact Python model of all of the above
model/gen_tables.py  writes hdl/hog_tables.v and hdl/hog_params.vh
model/tb_compare.py  prepares testbench images, compares RTL dumps to the model
sim/hog_tb.v       streams an image with video timing, dumps blocks/scores/boxes
```

Differences from OpenCV's HOG, chosen for hardware and checked on vtest
frames (window score correlation 0.96 with OpenCV, same people found):
grayscale instead of max-over-channels gradient, no Gaussian block weighting,
no spatial interpolation between cells, fixed point throughout.

Resources: 23% LUTs, 12% FFs, 10% BRAM, 140 of 220 DSPs. Timing met at
74.25 MHz. Per 720p block row the SVM needs 159 x 49 cycles of the 13200
available.

## Build, run, test (no GUI)

Needs Vivado 2026.1, Python with numpy and opencv-python, and a clone of
github.com/Digilent/vivado-library.

```
python model/gen_tables.py                        # only after changing the model
vivado -mode batch -source build.tcl -tclargs E:/amd/hog_detect E:/amd/digilent-vivado-library
vivado -mode batch -source board.tcl -tclargs E:/amd/hog_detect program
vivado -mode batch -source board.tcl -tclargs E:/amd/hog_detect status 5
```

Test video, 768x576 vtest centred in 1280x720, played borderless on the
board's display (here the second Windows display, at x = 2560):

```
ffmpeg -i vtest.avi -vf "pad=1280:720:256:72:black" -r 10 -c:v libx264 -pix_fmt yuv420p -crf 10 vtest_720p.mp4
ffplay -loop 0 -noborder -left 2560 -top 0 vtest_720p.mp4
```

Simulation (small 192x224 crop by default, `-d FULL720` for full frames):

```
python model/tb_compare.py prep <rundir> vtest:0 674 154 192 224
cd <rundir>
xvlog -i <repo>/video/hog_detect/hdl <all hdl/*.v except hog_top.v> sim/hog_tb.v
xelab hog_tb -s hogtb && xsim hogtb -R
python model/tb_compare.py check <rundir>          # prints HOG MATCH
```

Elaboration takes about 4 minutes (90 weight ROM instances); a full 720p
frame pair simulates in about 80 s.

## Notes

- Set the VIO probe count before the probe widths in a separate
  `set_property`; widths of not-yet-existing probes are silently dropped
  and the probes come out 1 bit wide.
- Windows on the build PC sees the board as display "DGL 720P CEA"; a
  screenshot of that display equals what the board receives (checked:
  identical to the test PNG).
