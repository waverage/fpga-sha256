`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// hog_rsq : r = frecip(fsqrt(a) + EPS, P), as in model/hog_fixed.py.
// LUT-based square root and reciprocal; result 8 cycles after start.
// ---------------------------------------------------------------------------
module hog_rsq #(
    parameter integer EPS = 190,
    parameter integer P   = 31
) (
    input  wire        clk,
    input  wire        start,
    input  wire [39:0] a,
    output reg         done,
    output reg  [23:0] r
);
    function [5:0] bitlen(input [39:0] v);
        integer i;
        begin
            bitlen = 0;
            for (i = 0; i < 40; i = i + 1) if (v[i]) bitlen = i + 1;
        end
    endfunction

    reg  [39:0] ar;
    reg  [5:0]  k;
    reg  [11:0] sq_a;
    wire [12:0] sq_q;
    reg  [23:0] n;
    reg  [4:0]  e;
    reg  [10:0] rc_a;
    wire [12:0] rc_q;
    reg  [3:0]  st = 0;

    hog_sqrt_rom  sqrt_rom  (.clk(clk), .a(sq_a), .q(sq_q));
    hog_recip_rom recip_rom (.clk(clk), .a(rc_a), .q(rc_q));

    wire [5:0]  bl  = bitlen(ar);
    wire [5:0]  k0  = (bl > 12) ? bl - 6'd12 : 6'd0;
    wire [5:0]  bln = bitlen({16'd0, n});
    wire signed [7:0] sh = P - 12 - e;

    always @(posedge clk) begin
        done <= 1'b0;
        case (st)
            0: if (start) begin ar <= a; st <= 1; end
            1: begin k <= k0 + k0[0]; st <= 2; end
            2: begin sq_a <= ar >> k; st <= 3; end
            3: st <= 4;                                   // ROM read
            4: begin n <= ((sq_q << (k >> 1)) >> 6) + EPS; st <= 5; end
            5: begin e <= bln - 1'b1; st <= 6; end
            6: begin
                   rc_a <= (e >= 11) ? (n >> (e - 11)) : (n << (11 - e));
                   st <= 7;
               end
            7: st <= 8;                                   // ROM read
            8: begin
                   r <= (sh >= 0) ? ({11'd0, rc_q} << sh) : ({11'd0, rc_q} >> (-sh));
                   done <= 1'b1;
                   st <= 0;
               end
        endcase
    end
endmodule
