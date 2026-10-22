`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// video_measure : active width/height and a frame counter, for debugging.
//
// Sync polarity differs between video modes, so the idle level of vs is
// learned from its value during active video (sync never overlaps de).
// ---------------------------------------------------------------------------
module video_measure (
    input  wire        clk,
    input  wire        de,
    input  wire        vs,
    output reg  [11:0] width,
    output reg  [11:0] height,
    output reg  [15:0] frames
);
    reg        de_q, vs_q, vs_idle;
    reg [11:0] x, lines;

    wire vs_active   = vs ^ vs_idle;
    wire vs_active_q = vs_q ^ vs_idle;

    always @(posedge clk) begin
        de_q <= de;
        vs_q <= vs;
        if (de) vs_idle <= vs;

        if (de) x <= x + 1'b1;
        else    x <= 12'd0;
        if (de_q && !de) begin
            width <= x;
            lines <= lines + 1'b1;
        end

        if (vs_active && !vs_active_q) begin    // start of vertical sync
            height <= lines;
            lines  <= 12'd0;
            frames <= frames + 1'b1;
        end
    end

    initial begin
        width = 0; height = 0; frames = 0; lines = 0; x = 0;
        de_q = 0; vs_q = 0; vs_idle = 0;
    end
endmodule
