`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// hog_cells : orientation votes -> 8x8 cell histograms (9 bins x 18 bits).
//
// Votes of one 8-pixel run are summed in registers, then added to the cell's
// entry in a 3-row ring of cell memory (read-modify-write, one per 8 pixels).
// row_done pulses when the last run of a cell row has been written.
// Port B gives the block stage read access: address (cy % 3) * CW + cx.
// ---------------------------------------------------------------------------
module hog_cells #(
    parameter integer W = 1280
) (
    input  wire         clk,
    input  wire         i_valid,
    input  wire [10:0]  i_x,
    input  wire [9:0]   i_y,
    input  wire [3:0]   i_h0,
    input  wire [3:0]   i_h1,
    input  wire [10:0]  i_v0,
    input  wire [10:0]  i_v1,

    output reg          row_done,
    output reg  [6:0]   row_cy,

    input  wire [8:0]   rd_addr,
    output reg  [161:0] rd_data
);
    localparam integer CW = W / 8;

    // ---- run accumulation --------------------------------------------------------
    reg  [17:0] acc [0:8];
    reg  [161:0] nacc;
    integer b;

    always @(*) begin
        for (b = 0; b < 9; b = b + 1)
            nacc[b*18 +: 18] = (i_x[2:0] == 3'd0 ? 18'd0 : acc[b])
                             + (i_h0 == b ? i_v0 : 11'd0)
                             + (i_h1 == b ? i_v1 : 11'd0);
    end

    reg         run_v = 0, run_first, run_end;
    reg [161:0] run_h;
    reg [7:0]   run_cx;
    reg [6:0]   run_cy;

    always @(posedge clk) begin
        run_v <= 1'b0;
        if (i_valid) begin
            for (b = 0; b < 9; b = b + 1) acc[b] <= nacc[b*18 +: 18];
            if (i_x[2:0] == 3'd7) begin
                run_v     <= 1'b1;
                run_h     <= nacc;
                run_cx    <= i_x[10:3];
                run_cy    <= i_y[9:3];
                run_first <= (i_y[2:0] == 3'd0);
                run_end   <= (i_y[2:0] == 3'd7) && (i_x == W - 1);
            end
        end
    end

    // ---- cell memory, 3 cell rows ------------------------------------------------------
    reg [161:0] mem [0:3*CW-1];
    reg [8:0]   a_addr;
    reg         a_we = 0;
    reg [161:0] a_wd, a_rd;

    always @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_wd;
        a_rd <= mem[a_addr];
    end
    always @(posedge clk) rd_data <= mem[rd_addr];

    // run_v: address set; r1: address applied, read; r2: data back, write issued;
    // r3: written. Runs are 8 cycles apart, so a_addr is stable throughout.
    reg         r1 = 0, r2 = 0, r3 = 0;
    reg [161:0] h1, h2, sum;
    reg         f1, f2, e1, e2, e3;
    reg [6:0]   cy1, cy2, cy3;
    integer k;

    always @(*) begin
        for (k = 0; k < 9; k = k + 1)
            sum[k*18 +: 18] = a_rd[k*18 +: 18] + h2[k*18 +: 18];
    end

    always @(posedge clk) begin
        a_we <= 1'b0;
        row_done <= 1'b0;
        if (run_v) a_addr <= (run_cy % 3) * CW + run_cx;
        r1 <= run_v; h1 <= run_h; f1 <= run_first; e1 <= run_end; cy1 <= run_cy;
        r2 <= r1;    h2 <= h1;    f2 <= f1;        e2 <= e1;      cy2 <= cy1;
        r3 <= r2;    e3 <= e2;    cy3 <= cy2;
        if (r2) begin
            a_we <= 1'b1;
            a_wd <= f2 ? h2 : sum;
        end
        if (r3 && e3) begin
            row_done <= 1'b1;
            row_cy   <= cy3;
        end
    end
endmodule
