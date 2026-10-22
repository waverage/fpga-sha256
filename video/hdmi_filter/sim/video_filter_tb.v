`timescale 1ns / 1ps
// Drives small frames (16x6 active, with blanking) through video_filter in
// every mode / rotate / split combination and compares each output pixel
// with a reference model. Also checks video_measure. Prints FILTER PASS.
module video_filter_tb;
    localparam W = 16, H = 6, HBLANK = 8, VBLANK = 3, LATENCY = 3;

    reg         clk = 0;
    reg  [1:0]  mode = 0;
    reg         rot = 0, split = 0;
    reg  [23:0] in_data = 0;
    reg         in_de = 0, in_hs = 0, in_vs = 0;
    wire [23:0] out_data;
    wire        out_de, out_hs, out_vs;
    wire [11:0] width, height;
    wire [15:0] frames;

    video_filter dut (
        .clk(clk), .mode(mode), .rot(rot), .split(split),
        .in_data(in_data), .in_de(in_de), .in_hs(in_hs), .in_vs(in_vs),
        .out_data(out_data), .out_de(out_de), .out_hs(out_hs), .out_vs(out_vs)
    );

    video_measure meas (
        .clk(clk), .de(in_de), .vs(in_vs),
        .width(width), .height(height), .frames(frames)
    );

    always #5 clk = ~clk;

    // reference model, Digilent packing {R, B, G}
    function [23:0] model(input [23:0] px, input [11:0] x, input [1:0] m,
                          input rt, input sp, input chk_split);
        reg [7:0] r, g, b, y, fr, fg, fb, t;
        begin
            r = px[23:16]; b = px[15:8]; g = px[7:0];
            y = (r * 77 + g * 150 + b * 29) >> 8;
            case (m)
                0: begin fr = r;  fg = g;  fb = b;  end
                1: begin fr = y;  fg = y;  fb = y;  end
                2: begin fr = 255 - r; fg = 255 - g; fb = 255 - b; end
                3: begin t = (y >= 128) ? 255 : 0; fr = t; fg = t; fb = t; end
            endcase
            if (rt) begin t = fr; fr = fg; fg = fb; fb = t; end
            if (sp && chk_split && (x == W/2 || x == W/2 + 1)) begin fr = 255; fg = 255; fb = 255; end
            else if (sp && chk_split && x < W/2) begin fr = r; fg = g; fb = b; end
            model = {fr, fb, fg};
        end
    endfunction

    // expected-value pipeline, LATENCY deep
    reg [23:0] exp_data [0:LATENCY-1];
    reg        exp_de   [0:LATENCY-1];
    reg        exp_chk  [0:LATENCY-1];
    integer i, errors = 0, checked = 0;
    reg     chk_now;
    reg [11:0] xpos;

    always @(posedge clk) begin
        // compare what the DUT produced with what went in LATENCY clocks ago
        if (exp_chk[LATENCY-1]) begin
            if (out_de !== exp_de[LATENCY-1] ||
                (exp_de[LATENCY-1] && out_data !== exp_data[LATENCY-1])) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("  mismatch mode=%0d rot=%0d split=%0d got %06h/%b expected %06h/%b",
                             mode, rot, split, out_data, out_de,
                             exp_data[LATENCY-1], exp_de[LATENCY-1]);
            end
            checked = checked + 1;
        end
        for (i = LATENCY-1; i > 0; i = i - 1) begin
            exp_data[i] <= exp_data[i-1];
            exp_de[i]   <= exp_de[i-1];
            exp_chk[i]  <= exp_chk[i-1];
        end
        exp_data[0] <= model(in_data, xpos, mode, rot, split, 1'b1);
        exp_de[0]   <= in_de;
        exp_chk[0]  <= chk_now;
    end

    // one frame; vsync active-low, hsync active-high, as some sources do
    task frame(input check);
        integer l, p;
        begin
            in_vs = 1;
            for (l = 0; l < H + VBLANK; l = l + 1) begin
                for (p = 0; p < W + HBLANK; p = p + 1) begin
                    in_de   = (l < H) && (p < W);
                    in_hs   = (p >= W + 2) && (p < W + 5);
                    in_vs   = !(l == H + 1);
                    in_data = in_de ? $random : 24'd0;
                    xpos    = p;
                    // the first line of a frame is also checked: line width is known by then
                    chk_now = check;
                    @(posedge clk); #1;
                end
            end
        end
    endtask

    integer m, rt, sp;
    reg [15:0] frames0;
    initial begin
        for (i = 0; i < LATENCY; i = i + 1) begin exp_chk[i] = 0; exp_de[i] = 0; exp_data[i] = 0; end
        chk_now = 0; xpos = 0;
        @(posedge clk); #1;
        frame(0);                                   // learn line width and sync polarity
        frames0 = frames;
        for (m = 0; m < 4; m = m + 1)
            for (rt = 0; rt < 2; rt = rt + 1)
                for (sp = 0; sp < 2; sp = sp + 1) begin
                    chk_now = 0;
                    mode = m; rot = rt; split = sp;
                    repeat (LATENCY + 1) @(posedge clk); #1;
                    frame(1);
                end
        chk_now = 0;
        repeat (LATENCY + 1) @(posedge clk);

        $display("checked %0d pixels/blank cycles, %0d errors", checked, errors);
        $display("measured %0dx%0d, %0d frames", width, height, frames);
        if (width != W || height != H || frames - frames0 != 16) begin
            $display("  measure FAIL, expected %0dx%0d, 16 frames after warm-up", W, H);
            errors = errors + 1;
        end
        if (errors == 0) $display("FILTER PASS");
        else             $display("FILTER FAIL");
        $finish;
    end
endmodule
