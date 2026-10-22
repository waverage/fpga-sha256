`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// hog_detect : HOG person detector on the incoming video stream.
//
// pixel -> cells -> blocks -> svm -> group. Boxes found in frame N are shown
// from the first active line of frame N+1 until that of frame N+2.
// Box i is 64x128 at (box_x[i], box_y[i]) when box_ok[i].
// ---------------------------------------------------------------------------
module hog_detect #(
    parameter integer W = 1280,
    parameter integer H = 720
) (
    input  wire               clk,
    input  wire [23:0]        in_data,
    input  wire               in_de,
    input  wire               in_vs,
    input  wire signed [39:0] thr,

    output reg  [7:0]         box_ok,
    output reg  [8*11-1:0]    box_x,
    output reg  [8*10-1:0]    box_y,
    output reg  [15:0]        hits,       // window hits in the last frame
    output reg  [3:0]         nboxes
);
    wire        p_valid;
    wire [10:0] p_x, p_v0, p_v1;
    wire [9:0]  p_y;
    wire [3:0]  p_h0, p_h1;

    hog_pixel #(.W(W), .H(H)) pixel (
        .clk(clk), .in_data(in_data), .in_de(in_de), .in_vs(in_vs),
        .o_valid(p_valid), .o_x(p_x), .o_y(p_y),
        .o_h0(p_h0), .o_h1(p_h1), .o_v0(p_v0), .o_v1(p_v1)
    );

    wire         row_done;
    wire [6:0]   row_cy;
    wire [8:0]   c_addr;
    wire [161:0] c_data;

    hog_cells #(.W(W)) cells (
        .clk(clk), .i_valid(p_valid), .i_x(p_x), .i_y(p_y),
        .i_h0(p_h0), .i_h1(p_h1), .i_v0(p_v0), .i_v1(p_v1),
        .row_done(row_done), .row_cy(row_cy), .rd_addr(c_addr), .rd_data(c_data)
    );

    wire         f_valid, f_ready;
    wire [287:0] f_data;
    wire [7:0]   f_bx;
    wire [6:0]   f_by;

    hog_blocks #(.W(W), .H(H)) blocks (
        .clk(clk), .row_done(row_done), .row_cy(row_cy),
        .rd_addr(c_addr), .rd_data(c_data),
        .f_valid(f_valid), .f_ready(f_ready), .f_data(f_data), .f_bx(f_bx), .f_by(f_by)
    );

    wire               s_valid;
    wire [7:0]         s_x0;
    wire [6:0]         s_y0;
    wire signed [39:0] s_score;

    hog_svm #(.W(W), .H(H)) svm (
        .clk(clk), .f_valid(f_valid), .f_ready(f_ready), .f_data(f_data),
        .f_bx(f_bx), .f_by(f_by),
        .s_valid(s_valid), .s_x0(s_x0), .s_y0(s_y0), .s_score(s_score)
    );

    wire           g_done;
    wire [7:0]     g_ok;
    wire [8*11-1:0] g_x;
    wire [8*10-1:0] g_y;
    wire [15:0]    g_hits;

    hog_group #(.W(W), .H(H)) group (
        .clk(clk), .thr(thr),
        .s_valid(s_valid), .s_x0(s_x0), .s_y0(s_y0), .s_score(s_score),
        .done(g_done), .box_ok(g_ok), .box_x(g_x), .box_y(g_y), .hits(g_hits)
    );

    // ---- hand the boxes over at the first active line of the next frame -----------------
    reg        de_q = 0, vs_q = 0, vs_idle = 0, first_line = 0, pend = 0;
    reg [7:0]  p_ok = 0;
    reg [8*11-1:0] p_xr;
    reg [8*10-1:0] p_yr;
    wire vs_act = in_vs ^ vs_idle, vs_act_q = vs_q ^ vs_idle;
    integer i;

    always @(posedge clk) begin
        de_q <= in_de;
        vs_q <= in_vs;
        if (in_de) vs_idle <= in_vs;
        if (vs_act && !vs_act_q) first_line <= 1'b1;
        if (g_done) begin
            pend <= 1'b1;
            p_ok <= g_ok; p_xr <= g_x; p_yr <= g_y;
            hits <= g_hits;
        end
        if (in_de && !de_q && first_line) begin
            first_line <= 1'b0;
            if (pend) begin
                pend <= 1'b0;
                box_ok <= p_ok; box_x <= p_xr; box_y <= p_yr;
                nboxes <= p_ok[0] + p_ok[1] + p_ok[2] + p_ok[3]
                        + p_ok[4] + p_ok[5] + p_ok[6] + p_ok[7];
            end
        end
    end

    initial begin box_ok = 0; hits = 0; nboxes = 0; end
endmodule
