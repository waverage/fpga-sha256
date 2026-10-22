`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// hog_blocks : cell rows -> L2-Hys normalised block features (36 x 8 bits).
//
// Block (bx, by) = cells (by,bx), (by+1,bx), (by,bx+1), (by+1,bx+1), 9 bins
// each, the OpenCV order. Block row by starts once cell row by+1 is done.
// Three stages, each about 45 cycles, hand blocks on with busy flags:
//   S1  read 4 cells, ss  = sum v^2
//   S2  r1 = 2^31/(sqrt(ss)+EPS1), u = min(CLIP, v*r1 >> 15), ss2 = sum u^2
//   S3  r2 = 2^30/(sqrt(ss2)+EPS2), f = min(255, u*r2 >> 22)
// ---------------------------------------------------------------------------
module hog_blocks #(
    parameter integer W = 1280,
    parameter integer H = 720
) (
    input  wire         clk,
    input  wire         row_done,
    input  wire [6:0]   row_cy,
    output reg  [8:0]   rd_addr,
    input  wire [161:0] rd_data,

    output reg          f_valid,
    input  wire         f_ready,
    output reg  [287:0] f_data,      // feature k in bits [8k+7:8k]
    output reg  [7:0]   f_bx,
    output reg  [6:0]   f_by
);
    `include "hog_params.vh"
    localparam integer CW = W / 8;
    localparam integer BW = CW - 1;
    localparam integer BH = H / 8 - 1;

    function [8:0] caddr(input [6:0] cy, input [7:0] cx);
        caddr = (cy % 3) * CW + cx;
    endfunction

    integer i;

    // ---- S1 ---------------------------------------------------------------------
    reg [6:0]  by = 0, rows_avail = 0;
    reg [7:0]  bx = 0;
    reg [5:0]  c1;
    reg        run1 = 0, hold1 = 0;
    reg [17:0] v1 [0:35];
    reg [35:0] sq1;
    reg [39:0] ss1;

    // ---- S2 ---------------------------------------------------------------------
    reg        busy2 = 0, hold2 = 0, go2 = 0;
    reg [17:0] v2 [0:35];
    reg [39:0] ss2in;
    reg [7:0]  bx2;
    reg [6:0]  by2;
    reg [5:0]  c2;
    reg        loop2 = 0;
    wire       r1_done;
    wire [23:0] r1;
    reg [23:0] r1q;
    reg [41:0] p2;
    reg [13:0] u2v;
    reg [27:0] sq2;
    reg [5:0]  k2a, k2b;
    reg        s2a = 0, s2b = 0, s2c = 0;
    reg [13:0] u2 [0:35];
    reg [39:0] ss2;

    // ---- S3 ---------------------------------------------------------------------
    reg        busy3 = 0, go3 = 0;
    reg [13:0] u3 [0:35];
    reg [39:0] ss3in;
    reg [7:0]  bx3;
    reg [6:0]  by3;
    reg [5:0]  c3;
    reg        loop3 = 0;
    wire       r2_done;
    wire [23:0] r2;
    reg [23:0] r2q;
    reg [37:0] p3;
    reg [5:0]  k3a;
    reg        s3a = 0;
    reg [7:0]  f3 [0:35];
    reg [6:0]  done3;

    hog_rsq #(.EPS(EPS1), .P(31)) rsq1 (.clk(clk), .start(go2), .a(ss2in), .done(r1_done), .r(r1));
    hog_rsq #(.EPS(EPS2), .P(30)) rsq2 (.clk(clk), .start(go3), .a(ss3in), .done(r2_done), .r(r2));

    // S1: c1 0..3 issue reads, 2..5 capture, 6..41 square, 7..42 accumulate
    always @(posedge clk) begin
        if (row_done) begin
            rows_avail <= row_cy + 1'b1;
            if (row_cy == 0) begin by <= 0; bx <= 0; run1 <= 1'b0; hold1 <= 1'b0; end
        end

        if (!run1 && !hold1 && by < BH && rows_avail >= by + 2 && !(row_done && row_cy == 0)) begin
            run1 <= 1'b1;
            c1 <= 0;
        end else if (run1) begin
            c1 <= c1 + 1'b1;
            case (c1)
                0: rd_addr <= caddr(by,     bx);
                1: rd_addr <= caddr(by + 1, bx);
                2: rd_addr <= caddr(by,     bx + 1);
                3: rd_addr <= caddr(by + 1, bx + 1);
            endcase
            if (c1 >= 2 && c1 <= 5)
                for (i = 0; i < 9; i = i + 1) v1[(c1 - 2) * 9 + i] <= rd_data[i*18 +: 18];
            if (c1 >= 6 && c1 <= 41) sq1 <= v1[c1 - 6] * v1[c1 - 6];
            if (c1 == 6) ss1 <= 0;
            else if (c1 >= 7 && c1 <= 42) ss1 <= ss1 + sq1;
            if (c1 == 42) begin run1 <= 1'b0; hold1 <= 1'b1; end
        end

        // hand S1 -> S2
        go2 <= 1'b0;
        if (hold1 && !busy2 && !(row_done && row_cy == 0)) begin
            for (i = 0; i < 36; i = i + 1) v2[i] <= v1[i];
            ss2in <= ss1; bx2 <= bx; by2 <= by;
            busy2 <= 1'b1; go2 <= 1'b1;
            hold1 <= 1'b0;
            if (bx == BW - 1) begin bx <= 0; by <= by + 1'b1; end
            else bx <= bx + 1'b1;
        end

        // S2: wait for r1, then 36 issues, 3-deep pipeline
        if (r1_done) begin r1q <= r1; loop2 <= 1'b1; c2 <= 0; ss2 <= 0; end
        else if (loop2) begin
            c2 <= c2 + 1'b1;
            if (c2 == 35) loop2 <= 1'b0;
        end
        s2a <= loop2; k2a <= c2;
        if (loop2) p2 <= v2[c2] * r1q;
        s2b <= s2a; k2b <= k2a;
        if (s2a) u2v <= ((p2 >> 15) > CLIP) ? CLIP : (p2 >> 15);
        s2c <= s2b;
        if (s2b) begin u2[k2b] <= u2v; sq2 <= u2v * u2v; end
        if (s2c) ss2 <= ss2 + sq2;
        if (s2c && !s2b) hold2 <= 1'b1;               // last square added

        // hand S2 -> S3
        go3 <= 1'b0;
        if (hold2 && !busy3) begin
            for (i = 0; i < 36; i = i + 1) u3[i] <= u2[i];
            ss3in <= ss2; bx3 <= bx2; by3 <= by2;
            busy3 <= 1'b1; go3 <= 1'b1;
            hold2 <= 1'b0; busy2 <= 1'b0;
        end

        // S3: wait for r2, then 36 issues
        if (r2_done) begin r2q <= r2; loop3 <= 1'b1; c3 <= 0; done3 <= 0; end
        else if (loop3) begin
            c3 <= c3 + 1'b1;
            if (c3 == 35) loop3 <= 1'b0;
        end
        s3a <= loop3; k3a <= c3;
        if (loop3) p3 <= u3[c3] * r2q;
        if (s3a) begin
            f3[k3a] <= ((p3 >> 22) > 255) ? 8'd255 : (p3 >> 22);
            if (k3a == 35) begin
                f_valid <= 1'b1;
                f_bx <= bx3; f_by <= by3;
            end
        end
        if (f_valid && f_ready) begin
            f_valid <= 1'b0;
            busy3 <= 1'b0;
        end
    end

    always @(*) for (i = 0; i < 36; i = i + 1) f_data[i*8 +: 8] = f3[i];

    initial f_valid = 0;
endmodule
