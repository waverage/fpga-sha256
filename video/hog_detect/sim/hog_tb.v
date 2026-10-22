`timescale 1ns / 1ps
// Streams img.hex (W*H words, Digilent {R,B,G}) through hog_detect for two
// frames with video timing, and dumps for comparison with model/hog_fixed.py:
//   blocks.txt  bx by f0..f35   (first frame)
//   scores.txt  x0 y0 score     (first frame)
//   boxes.txt   hits, then ok x y per cluster (first frame)
// Also checks that the block stage keeps up with the cell rows.
module hog_tb;
`ifdef FULL720
    parameter integer W = 1280, H = 720, HB = 370, VB = 30;   // CEA 720p60 timing
`else
    parameter integer W = 192, H = 224, HB = 40, VB = 20;
`endif

    reg         clk = 0;
    reg  [23:0] data = 0;
    reg         de = 0, vs = 1;
    reg  [23:0] img [0:W*H-1];

    always #5 clk = ~clk;

    wire [7:0]      box_ok;
    wire [8*11-1:0] box_x;
    wire [8*10-1:0] box_y;
    wire [15:0]     hits;
    wire [3:0]      nboxes;

    hog_detect #(.W(W), .H(H)) dut (
        .clk(clk), .in_data(data), .in_de(de), .in_vs(vs), .thr(40'sd0),
        .box_ok(box_ok), .box_x(box_x), .box_y(box_y), .hits(hits), .nboxes(nboxes)
    );

    integer fb, fs, fx, frame = 0, errors = 0, i, done_seen = 0;

    always @(posedge clk) begin
        if (frame == 0 && dut.f_valid && dut.f_ready) begin
            $fwrite(fb, "%0d %0d", dut.f_bx, dut.f_by);
            for (i = 0; i < 36; i = i + 1) $fwrite(fb, " %0d", dut.f_data[i*8 +: 8]);
            $fwrite(fb, "\n");
        end
        if (frame == 0 && dut.s_valid)
            $fwrite(fs, "%0d %0d %0d\n", dut.s_x0, dut.s_y0, dut.s_score);
        if (dut.g_done && done_seen == 0) begin
            done_seen = 1;
            $fwrite(fx, "%0d\n", dut.g_hits);
            for (i = 0; i < 8; i = i + 1)
                $fwrite(fx, "%0d %0d %0d\n", dut.g_ok[i], dut.g_x[i*11 +: 11], dut.g_y[i*10 +: 10]);
        end
        if (dut.row_done && dut.row_cy >= 2 && dut.blocks.by < dut.row_cy - 1) begin
            errors = errors + 1;
            $display("OVERRUN: cell row %0d done, block row %0d still pending", dut.row_cy, dut.blocks.by);
        end
    end

    integer x, y, f;
    initial begin
        $readmemh("img.hex", img);
        fb = $fopen("blocks.txt", "w");
        fs = $fopen("scores.txt", "w");
        fx = $fopen("boxes.txt", "w");
        repeat (10) @(posedge clk);
        for (f = 0; f < 2; f = f + 1) begin
            frame = f;
            for (y = 0; y < H + VB; y = y + 1)
                for (x = 0; x < W + HB; x = x + 1) begin
                    de   <= (y < H) && (x < W);
                    data <= ((y < H) && (x < W)) ? img[y * W + x] : 24'd0;
                    vs   <= !(y == H + 3 || y == H + 4);
                    @(posedge clk);
                end
        end
        repeat (100) @(posedge clk);
        $fclose(fb); $fclose(fs); $fclose(fx);
        $display("frames done, boxes shown now: %b, hits %0d, overruns %0d", box_ok, hits, errors);
        $finish;
    end
endmodule
