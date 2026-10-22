`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// hog_group : window scores -> up to 8 person boxes per frame.
//
// A hit (score > thr) joins the first cluster whose anchor (its first hit) is
// within 2 windows in x and y, else opens a new cluster if one of 8 is free.
// After the last window of the frame each cluster with >= 2 hits becomes a
// box at its average position: x = 8*sum_x0/n, y = 8*sum_y0/n (floor).
// Mirrors group() in model/hog_fixed.py.
// ---------------------------------------------------------------------------
module hog_group #(
    parameter integer W = 1280,
    parameter integer H = 720
) (
    input  wire               clk,
    input  wire signed [39:0] thr,
    input  wire               s_valid,
    input  wire [7:0]         s_x0,
    input  wire [6:0]         s_y0,
    input  wire signed [39:0] s_score,

    output reg                done,        // pulse, boxes below are new
    output reg  [7:0]         box_ok,
    output reg  [8*11-1:0]    box_x,
    output reg  [8*10-1:0]    box_y,
    output reg  [15:0]        hits
);
    localparam integer NX = W / 8 - 7;
    localparam integer NY = H / 8 - 15;

    reg  [7:0]  cv = 0;
    reg  [7:0]  ax [0:7];
    reg  [6:0]  ay [0:7];
    reg  [15:0] sx [0:7];
    reg  [15:0] sy [0:7];
    reg  [7:0]  n  [0:7];
    reg  [3:0]  used = 0;
    reg  [15:0] hit_cnt = 0;

    wire hit = s_valid && (s_score > thr);
    wire last = s_valid && (s_x0 == NX - 1) && (s_y0 == NY - 1);

    reg  [7:0] match;
    integer c;
    always @(*)
        for (c = 0; c < 8; c = c + 1)
            match[c] = cv[c]
                && ((s_x0 >= ax[c]) ? (s_x0 - ax[c] <= 2) : (ax[c] - s_x0 <= 2))
                && ((s_y0 >= ay[c]) ? (s_y0 - ay[c] <= 2) : (ay[c] - s_y0 <= 2));

    reg [2:0] first;
    always @(*) begin
        first = 0;
        for (c = 7; c >= 0; c = c - 1) if (match[c]) first = c;
    end

    // ---- finalisation: 16 serial divisions ---------------------------------------------
    reg        fin = 0;
    reg  [3:0] fi;              // division index: cluster fi[3:1], fi[0] = y
    reg  [4:0] fb;              // bit counter
    reg  [18:0] num, quo;
    reg  [8:0]  rem;
    reg  [7:0]  den;

    always @(posedge clk) begin
        done <= 1'b0;
        if (!fin) begin
            if (hit) begin
                hit_cnt <= hit_cnt + 1'b1;
                if (|match) begin
                    sx[first] <= sx[first] + s_x0;
                    sy[first] <= sy[first] + s_y0;
                    n[first]  <= n[first] + 1'b1;
                end else if (used < 8) begin
                    cv[used] <= 1'b1;
                    ax[used] <= s_x0; ay[used] <= s_y0;
                    sx[used] <= s_x0; sy[used] <= s_y0;
                    n[used]  <= 1;
                    used <= used + 1'b1;
                end
            end
            if (last) begin
                fin <= 1'b1; fi <= 0; fb <= 0;
                hits <= hit_cnt + hit;
            end
        end else begin
            // restoring division num / den, one quotient bit per cycle
            if (fb == 0) begin
                num <= fi[0] ? {sy[fi[3:1]], 3'b0} : {sx[fi[3:1]], 3'b0};
                den <= n[fi[3:1]];
                rem <= 0; quo <= 0;
                fb <= 1;
            end else if (fb <= 19) begin
                if ({rem[7:0], num[18]} >= den) begin
                    rem <= {rem[7:0], num[18]} - den;
                    quo <= {quo[17:0], 1'b1};
                end else begin
                    rem <= {rem[7:0], num[18]};
                    quo <= {quo[17:0], 1'b0};
                end
                num <= {num[17:0], 1'b0};
                fb <= fb + 1'b1;
            end else begin
                if (fi[0]) begin
                    box_y[fi[3:1]*10 +: 10] <= quo[9:0];
                    box_ok[fi[3:1]] <= cv[fi[3:1]] && (n[fi[3:1]] >= 2);
                end else
                    box_x[fi[3:1]*11 +: 11] <= quo[10:0];
                fb <= 0;
                if (fi == 15) begin
                    fin <= 1'b0; done <= 1'b1;
                    cv <= 0; used <= 0; hit_cnt <= 0;
                end else fi <= fi + 1'b1;
            end
        end
    end

    initial begin box_ok = 0; hits = 0; end
endmodule
