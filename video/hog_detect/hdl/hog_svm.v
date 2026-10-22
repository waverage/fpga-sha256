`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// hog_svm : streaming linear SVM over all 64x128 windows (stride 8).
//
// Window (x0, y0) covers blocks x0..x0+6, y0..y0+14 and scores
//   S = RHO + sum_{i,j} W[i][j] . block(x0+i, y0+j)
// Each block is used by up to 7 x 15 windows. Lane j (0..14) handles the
// window row y0 = by - j and computes the 7 dot products W[i][j] . block
// with 6 multipliers (6 features each), 42 cycles per block.
//   horizontal: H[i] += d_i, after each block H[6] is the finished row sum
//               for x0 = bx - 6, then H shifts.
//   vertical:   V[x0][y0 % 15] collects row sums; j = 0 writes, j = 14
//               completes the window and emits its score.
// Windows come out in raster order (y0, then x0).
// ---------------------------------------------------------------------------
module hog_svm #(
    parameter integer W = 1280,
    parameter integer H = 720
) (
    input  wire         clk,
    input  wire         f_valid,
    output wire         f_ready,
    input  wire [287:0] f_data,
    input  wire [7:0]   f_bx,
    input  wire [6:0]   f_by,

    output reg          s_valid,
    output reg  [7:0]   s_x0,
    output reg  [6:0]   s_y0,
    output reg  signed [39:0] s_score
);
    `include "hog_params.vh"
    localparam integer BW = W / 8 - 1;
    localparam integer NX = W / 8 - 7;
    localparam integer NY = H / 8 - 15;
    localparam integer SUB = 6, TPS = 6;

    // ---- block intake ----------------------------------------------------------------
    reg  [7:0] fr [0:35];
    reg  [7:0] bx, by_r;
    reg  [6:0] by;
    reg        busy = 0;
    reg  [5:0] c;                        // 0..41 issue, then drain
    reg  [2:0] ci;                       // i
    reg  [2:0] ct;                       // t
    integer k;

    assign f_ready = !busy;

    // issue counters
    always @(posedge clk) begin
        if (f_valid && !busy) begin
            for (k = 0; k < 36; k = k + 1) fr[k] <= f_data[k*8 +: 8];
            bx <= f_bx; by <= f_by;
            busy <= 1'b1;
            c <= 0; ci <= 0; ct <= 0;
        end else if (busy) begin
            c <= c + 1'b1;
            if (ct == TPS - 1) begin ct <= 0; ci <= ci + 1'b1; end
            else ct <= ct + 1'b1;
            if (c == 42 + 6) busy <= 1'b0;   // issue 0..41, last H update at 47, shift at 48
        end
    end

    wire issuing = busy && (c < 42);
    wire [5:0] waddr = ci * TPS + ct;

    // pipeline tags: P1 (ROM out, feature select), P2 (product), P3 (acc), P4 (dot), P5 (H)
    reg       v1 = 0, v2 = 0, v3 = 0, v4 = 0;
    reg [2:0] i1, i2, i3, i4;
    reg [2:0] t1, t2;
    reg       last3, first2, first3;
    always @(posedge clk) begin
        v1 <= issuing; i1 <= ci; t1 <= ct;
        v2 <= v1;      i2 <= i1; t2 <= t1; first2 <= (t1 == 0);
        v3 <= v2 && (t2 == TPS - 1); i3 <= i2;
        v4 <= v3;      i4 <= i3;
    end

    // per-sublane feature select (shared by all lanes)
    reg [7:0] fsel [0:SUB-1];
    integer s;
    always @(posedge clk)
        for (s = 0; s < SUB; s = s + 1) fsel[s] <= fr[s * TPS + ct];

    // ---- lanes ---------------------------------------------------------------------------
    reg  signed [39:0] Hh  [0:14][0:6];
    wire signed [29:0] dot [0:14];
    reg  signed [39:0] R   [0:14];
    reg                r_valid = 0;
    reg  [7:0]         r_x0;
    reg  [6:0]         r_by;

    genvar gj, gs;
    generate
        for (gj = 0; gj < 15; gj = gj + 1) begin : lane
            wire signed [15:0] wq [0:SUB-1];
            reg  signed [24:0] prod [0:SUB-1];
            reg  signed [29:0] acc  [0:SUB-1];
            reg  signed [29:0] dsum;
            for (gs = 0; gs < SUB; gs = gs + 1) begin : sub
                hog_wrom #(.LANE(gj), .SUB(gs)) rom (.clk(clk), .a(waddr), .q(wq[gs]));
                always @(posedge clk) begin
                    prod[gs] <= wq[gs] * $signed({1'b0, fsel[gs]});            // P2
                    acc[gs]  <= first2 ? prod[gs] : acc[gs] + prod[gs];       // P3
                end
            end
            always @(posedge clk)
                dsum <= acc[0] + acc[1] + acc[2] + acc[3] + acc[4] + acc[5];  // P4
            assign dot[gj] = dsum;
        end
    endgenerate

    // H update at P5, shift and emit after the block
    integer j, ii;
    always @(posedge clk) begin
        r_valid <= 1'b0;
        if (f_valid && !busy && f_bx == 0)
            for (j = 0; j < 15; j = j + 1) for (ii = 0; ii < 7; ii = ii + 1) Hh[j][ii] <= 0;
        else if (v4)
            for (j = 0; j < 15; j = j + 1) Hh[j][i4] <= Hh[j][i4] + dot[j];
        else if (busy && c == 42 + 6) begin
            if (bx >= 6) begin
                for (j = 0; j < 15; j = j + 1) R[j] <= Hh[j][6];
                r_valid <= 1'b1;
                r_x0 <= bx - 6;
                r_by <= by;
            end
            for (j = 0; j < 15; j = j + 1) begin
                for (ii = 6; ii > 0; ii = ii - 1) Hh[j][ii] <= Hh[j][ii - 1];
                Hh[j][0] <= 0;
            end
        end
    end

    // ---- vertical accumulation ----------------------------------------------------------
    reg  signed [39:0] V [0:4095];
    reg  [11:0] va_r, va_w;
    reg  signed [39:0] vrd, vwd;
    reg         vwe = 0;
    always @(posedge clk) begin
        if (vwe) V[va_w] <= vwd;
        vrd <= V[va_r];
    end

    reg        q_run = 0;
    reg  [3:0] qj;
    reg        q1 = 0, q1ok, q2 = 0, q2ok;
    reg  [3:0] q1j, q2j;
    reg  [6:0] q1y, q2y;
    reg  [11:0] q1a, q2a;
    reg  [7:0] qx0;
    reg  [6:0] qby;
    wire signed [8:0] y0n = $signed({2'b0, qby}) - $signed({5'b0, qj});
    wire       yok = (y0n >= 0) && (y0n <= NY - 1);
    wire [6:0] y0  = y0n[6:0];

    always @(posedge clk) begin
        if (r_valid) begin q_run <= 1'b1; qj <= 0; qx0 <= r_x0; qby <= r_by; end
        else if (q_run) begin
            qj <= qj + 1'b1;
            if (qj == 14) q_run <= 1'b0;
        end
        // Q0: address
        q1 <= q_run; q1ok <= yok; q1j <= qj; q1y <= y0;
        q1a <= {qx0, 4'b0} + (y0 % 15);
        va_r <= {qx0, 4'b0} + (y0 % 15);
        // Q1: wait for RAM
        q2 <= q1; q2ok <= q1ok; q2j <= q1j; q2y <= q1y; q2a <= q1a;
        // Q2: data back
        vwe <= 1'b0;
        s_valid <= 1'b0;
        if (q2 && q2ok) begin
            if (q2j == 0) begin vwe <= 1'b1; va_w <= q2a; vwd <= R[0]; end
            else if (q2j == 14) begin
                s_valid <= 1'b1;
                s_x0 <= qx0;
                s_y0 <= q2y;
                s_score <= vrd + R[14] + RHO;
            end else begin
                vwe <= 1'b1; va_w <= q2a; vwd <= vrd + R[q2j];
            end
        end
    end
endmodule
