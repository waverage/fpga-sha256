`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// video_filter : per-pixel filter between Digilent dvi2rgb and rgb2dvi.
//
// Pixel data uses the Digilent packing: [23:16] red, [15:8] blue, [7:0] green.
//
//   mode 0  pass through
//   mode 1  grayscale, Y = (77 R + 150 G + 29 B) / 256 (BT.601 weights)
//   mode 2  invert
//   mode 3  threshold, Y >= 128 -> white, else black
//   rot     rotate colours after the filter: out R,G,B = in G,B,R
//   split   left half of each line unfiltered, 2-pixel white divider
//
// Fixed latency of 3 clocks; de/hs/vs are delayed to match.
// ---------------------------------------------------------------------------
module video_filter (
    input  wire        clk,
    input  wire [1:0]  mode,
    input  wire        rot,
    input  wire        split,
    input  wire [23:0] in_data,
    input  wire        in_de,
    input  wire        in_hs,
    input  wire        in_vs,
    output reg  [23:0] out_data,
    output reg         out_de,
    output reg         out_hs,
    output reg         out_vs
);
    // ---- x position and line width (for split screen) -----------------------
    reg  [11:0] x;
    reg  [11:0] line_width;
    reg         de_q;

    always @(posedge clk) begin
        de_q <= in_de;
        if (in_de) x <= x + 1'b1;
        else       x <= 12'd0;
        if (de_q && !in_de) line_width <= x;    // x == pixels in the line just ended
    end

    initial begin x = 0; line_width = 0; de_q = 0; end

    wire [11:0] half = {1'b0, line_width[11:1]};

    // ---- stage 1: register input, weighted channels -------------------------
    reg  [7:0]  r1, g1, b1;
    reg  [15:0] wr1, wg1, wb1;
    reg         de1, hs1, vs1, left1, div1;

    always @(posedge clk) begin
        r1  <= in_data[23:16];
        b1  <= in_data[15:8];
        g1  <= in_data[7:0];
        wr1 <= in_data[23:16] * 8'd77;
        wg1 <= in_data[7:0]   * 8'd150;
        wb1 <= in_data[15:8]  * 8'd29;
        de1 <= in_de;  hs1 <= in_hs;  vs1 <= in_vs;
        left1 <= split && (x < half);
        div1  <= split && (x == half || x == half + 1'b1);
    end

    // ---- stage 2: luma -------------------------------------------------------
    reg  [7:0]  r2, g2, b2, y2;
    reg         de2, hs2, vs2, left2, div2;
    wire [16:0] ysum = wr1 + wg1 + wb1;         // max 255*256 = 65280

    always @(posedge clk) begin
        y2 <= ysum[15:8];
        r2 <= r1;  g2 <= g1;  b2 <= b1;
        de2 <= de1;  hs2 <= hs1;  vs2 <= vs1;
        left2 <= left1;  div2 <= div1;
    end

    // ---- stage 3: select, rotate, split, pack --------------------------------
    reg [7:0] fr, fg, fb;       // filtered
    reg [7:0] or_, og, ob;      // after rotate / split

    always @(*) begin
        case (mode)
            2'd0: begin fr = r2;        fg = g2;        fb = b2;        end
            2'd1: begin fr = y2;        fg = y2;        fb = y2;        end
            2'd2: begin fr = ~r2;       fg = ~g2;       fb = ~b2;       end
            2'd3: begin fr = {8{y2[7]}}; fg = {8{y2[7]}}; fb = {8{y2[7]}}; end
        endcase
        if (rot) begin or_ = fg; og = fb; ob = fr; end
        else     begin or_ = fr; og = fg; ob = fb; end
        if (div2)       begin or_ = 8'hFF; og = 8'hFF; ob = 8'hFF; end
        else if (left2) begin or_ = r2;    og = g2;    ob = b2;    end
    end

    always @(posedge clk) begin
        out_data <= de2 ? {or_, ob, og} : 24'd0;
        out_de   <= de2;
        out_hs   <= hs2;
        out_vs   <= vs2;
    end
endmodule
