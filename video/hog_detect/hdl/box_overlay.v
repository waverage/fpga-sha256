`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// box_overlay : draws up to 8 green 64x128 rectangles, 3 pixels thick.
// One clock of latency on data, de, hs and vs.
// ---------------------------------------------------------------------------
module box_overlay (
    input  wire            clk,
    input  wire            en,
    input  wire [7:0]      box_ok,
    input  wire [8*11-1:0] box_x,
    input  wire [8*10-1:0] box_y,
    input  wire [23:0]     in_data,
    input  wire            in_de,
    input  wire            in_hs,
    input  wire            in_vs,
    output reg  [23:0]     out_data,
    output reg             out_de,
    output reg             out_hs,
    output reg             out_vs
);
    reg        de_q = 0, vs_q = 0, vs_idle = 0;
    reg [10:0] x = 0;
    reg [9:0]  y = 0;
    wire vs_act = in_vs ^ vs_idle, vs_act_q = vs_q ^ vs_idle;

    always @(posedge clk) begin
        de_q <= in_de;
        vs_q <= in_vs;
        if (in_de) vs_idle <= in_vs;
        x <= in_de ? x + 1'b1 : 11'd0;
        if (vs_act && !vs_act_q) y <= 10'd0;
        else if (de_q && !in_de) y <= y + 1'b1;
    end

    reg on;
    integer i;
    reg [10:0] bx;
    reg [9:0]  by;
    always @(*) begin
        on = 1'b0;
        for (i = 0; i < 8; i = i + 1) begin
            bx = box_x[i*11 +: 11];
            by = box_y[i*10 +: 10];
            if (box_ok[i] && x >= bx && x < bx + 64 && y >= by && y < by + 128 &&
                !(x >= bx + 3 && x < bx + 61 && y >= by + 3 && y < by + 125))
                on = 1'b1;
        end
    end

    always @(posedge clk) begin
        out_data <= (en && on && in_de) ? 24'h0000FF : in_data;    // green, {R,B,G}
        out_de <= in_de;
        out_hs <= in_hs;
        out_vs <= in_vs;
    end
endmodule
