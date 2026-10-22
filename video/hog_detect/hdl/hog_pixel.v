`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// hog_pixel : RGB stream -> per-pixel orientation votes.
//
// luma -> gamma (16*sqrt) -> 3-row window -> central differences -> CORDIC.
// Emits every pixel position of the frame exactly once, in raster order:
// the last column of each line is emitted the cycle after de falls, and the
// last line (zero gradient, image border) is emitted during vertical blanking.
// Border pixels have zero gradient. Mirrors cell_hist() in model/hog_fixed.py.
// ---------------------------------------------------------------------------
module hog_pixel #(
    parameter integer W = 1280,
    parameter integer H = 720
) (
    input  wire        clk,
    input  wire [23:0] in_data,      // Digilent packing {R, B, G}
    input  wire        in_de,
    input  wire        in_vs,
    output reg         o_valid,
    output reg  [10:0] o_x,
    output reg  [9:0]  o_y,
    output reg  [3:0]  o_h0,
    output reg  [3:0]  o_h1,
    output reg  [10:0] o_v0,
    output reg  [10:0] o_v1
);
    `include "hog_params.vh"

    // ---- input position --------------------------------------------------------
    reg        de_q = 0, vs_q = 0, vs_idle = 0;
    reg [10:0] xi = 0;
    reg [9:0]  yi = 0;
    wire vs_act   = in_vs ^ vs_idle;
    wire vs_act_q = vs_q ^ vs_idle;

    always @(posedge clk) begin
        de_q <= in_de;
        vs_q <= in_vs;
        if (in_de) vs_idle <= in_vs;
        xi <= in_de ? xi + 1'b1 : 11'd0;
        if (vs_act && !vs_act_q) yi <= 10'd0;
        else if (de_q && !in_de) yi <= yi + 1'b1;
    end

    // ---- luma and gamma, 3 cycles -------------------------------------------------
    reg [15:0] pr, pg, pb;
    reg [7:0]  yl;
    wire [7:0] gam;
    reg        d1 = 0, d2 = 0, d3 = 0;
    reg [10:0] x1, x2, x3;
    reg [9:0]  y1, y2, y3;

    always @(posedge clk) begin
        pr <= in_data[23:16] * 8'd77;
        pb <= in_data[15:8]  * 8'd29;
        pg <= in_data[7:0]   * 8'd150;
        yl <= (pr + pg + pb) >> 8;
        d1 <= in_de; x1 <= xi; y1 <= yi;
        d2 <= d1;    x2 <= x1; y2 <= y1;
        d3 <= d2;    x3 <= x2; y3 <= y2;
    end

    hog_gamma_rom gamma (.clk(clk), .a(yl), .q(gam));   // valid with d3

    // ---- line buffers: lb1 = previous line, lb2 = the one before -------------------
    reg [7:0]  lb1 [0:W-1];
    reg [7:0]  lb2 [0:W-1];
    reg [7:0]  rd1, rd2, g4;
    reg        d4 = 0;
    reg [10:0] x4;
    reg [9:0]  y4;

    always @(posedge clk) begin
        if (d3) begin
            rd1 <= lb1[x3];
            rd2 <= lb2[x3];
            lb1[x3] <= gam;
        end
        if (d4) lb2[x4] <= rd1;
        d4 <= d3; x4 <= x3; y4 <= y3; g4 <= gam;
    end

    // ---- 3x3 taps (only the cross is used) -------------------------------------
    reg [7:0]  mA, mB, mC, bA, bB, tA, tB;
    reg        d5 = 0, d5q = 0;
    reg [10:0] x5;
    reg [9:0]  y5, last_y;

    always @(posedge clk) begin
        if (d4) begin
            mA <= rd1; mB <= mA; mC <= mB;      // row y-1 at x, x-1, x-2
            bA <= g4;  bB <= bA;                // row y   at x, x-1
            tA <= rd2; tB <= tA;                // row y-2 at x, x-1
        end
        d5 <= d4; x5 <= x4; y5 <= y4;
        d5q <= d5;
        if (d5) last_y <= y5;
    end

    // ---- emit gradients for centre (x5-1, y5-1), plus line-end and last line -------
    reg        e_valid = 0;
    reg [10:0] e_x;
    reg [9:0]  e_y;
    reg signed [9:0] e_dx, e_dy;
    reg        vline = 0;
    reg [10:0] vx;

    wire signed [9:0] dx5 = $signed({2'b0, mA}) - $signed({2'b0, mC});
    wire signed [9:0] dy5 = $signed({2'b0, bB}) - $signed({2'b0, tB});

    function border(input [10:0] x, input [9:0] y);
        border = (x == 0) || (x == W - 1) || (y == 0) || (y == H - 1);
    endfunction

    always @(posedge clk) begin
        e_valid <= 1'b0;
        if (d5 && x5 >= 1 && y5 >= 1) begin
            e_valid <= 1'b1;
            e_x <= x5 - 1'b1;
            e_y <= y5 - 1'b1;
            e_dx <= border(x5 - 1'b1, y5 - 1'b1) ? 10'sd0 : dx5;
            e_dy <= border(x5 - 1'b1, y5 - 1'b1) ? 10'sd0 : dy5;
        end else if (d5q && !d5 && last_y >= 1) begin
            e_valid <= 1'b1;
            e_x <= W - 1;  e_y <= last_y - 1'b1;
            e_dx <= 10'sd0; e_dy <= 10'sd0;
            if (last_y == H - 1) begin vline <= 1'b1; vx <= 11'd0; end
        end else if (vline) begin
            e_valid <= 1'b1;
            e_x <= vx;  e_y <= H - 1;
            e_dx <= 10'sd0; e_dy <= 10'sd0;
            vx <= vx + 1'b1;
            if (vx == W - 1) vline <= 1'b0;
        end
    end

    // ---- CORDIC vectoring, 10 stages -------------------------------------------
    // fold to the upper half plane, rotate by -90 degrees, scale by 16
    reg signed [16:0] cx [0:10];
    reg signed [16:0] cy [0:10];
    reg signed [12:0] cz [0:10];
    reg        cv [0:10];
    reg [10:0] cpx [0:10];
    reg [9:0]  cpy [0:10];

    wire flip = (e_dy < 0) || (e_dy == 0 && e_dx < 0);
    wire signed [9:0] fdx = flip ? -e_dx : e_dx;
    wire signed [9:0] fdy = flip ? -e_dy : e_dy;

    always @(posedge clk) begin
        cx[0] <= {{3{fdy[9]}}, fdy, 4'b0};
        cy[0] <= -{{3{fdx[9]}}, fdx, 4'b0};
        cz[0] <= 13'sd0;
        cv[0] <= e_valid; cpx[0] <= e_x; cpy[0] <= e_y;
    end

    function integer atan(input integer i);
        case (i)
            0: atan = ATAN0; 1: atan = ATAN1; 2: atan = ATAN2; 3: atan = ATAN3; 4: atan = ATAN4;
            5: atan = ATAN5; 6: atan = ATAN6; 7: atan = ATAN7; 8: atan = ATAN8; default: atan = ATAN9;
        endcase
    endfunction

    genvar gi;
    generate
        for (gi = 0; gi < 10; gi = gi + 1) begin : cordic
            always @(posedge clk) begin
                if (cy[gi] < 0) begin
                    cx[gi+1] <= cx[gi] - (cy[gi] >>> gi);
                    cy[gi+1] <= cy[gi] + (cx[gi] >>> gi);
                    cz[gi+1] <= cz[gi] - atan(gi);
                end else begin
                    cx[gi+1] <= cx[gi] + (cy[gi] >>> gi);
                    cy[gi+1] <= cy[gi] - (cx[gi] >>> gi);
                    cz[gi+1] <= cz[gi] + atan(gi);
                end
                cv[gi+1] <= cv[gi]; cpx[gi+1] <= cpx[gi]; cpy[gi+1] <= cpy[gi];
            end
        end
    endgenerate

    // ---- bins and votes ------------------------------------------------------------
    wire signed [13:0] q   = cz[10] + 14'sd1152 - 14'sd128;   // theta - half bin
    wire signed [5:0]  qh  = q >>> 8;
    wire [3:0]  h0a = (qh < 0) ? qh + 9 : (qh > 8) ? qh - 9 : qh;
    reg  [10:0] mag;
    reg  [7:0]  frac;
    reg  [3:0]  h0b;
    reg         vb;
    reg  [10:0] xb;
    reg  [9:0]  yb;
    wire [18:0] mf = mag * frac;

    always @(posedge clk) begin
        mag  <= cx[10] >>> 3;
        frac <= q[7:0];
        h0b  <= h0a;
        vb <= cv[10]; xb <= cpx[10]; yb <= cpy[10];

        o_valid <= vb;
        o_x <= xb; o_y <= yb;
        o_h0 <= h0b;
        o_h1 <= (h0b == 4'd8) ? 4'd0 : h0b + 1'b1;
        o_v1 <= mf >> 8;
        o_v0 <= mag - (mf >> 8);
    end
endmodule
