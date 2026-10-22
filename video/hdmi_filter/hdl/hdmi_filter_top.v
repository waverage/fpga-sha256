`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// hdmi_filter_top : HDMI IN -> video_filter -> HDMI OUT, fabric only.
//
//   SW1:SW0  filter: 00 pass, 01 grayscale, 10 invert, 11 threshold
//   BTN0     toggle colour rotation
//   BTN1     toggle split screen (left half unfiltered)
//   LD0      heartbeat (bitstream loaded)
//   LD1      HDMI input locked
//   LD2      colour rotation on
//   LD3      split screen on
//
// The output pixel clock is the recovered input clock, so the output
// resolution and frame rate always equal the input (720p60 via the EDID).
// ---------------------------------------------------------------------------
module hdmi_filter_top (
    input  wire       clk125,
    input  wire [1:0] sw,
    input  wire [1:0] btn,
    output wire [3:0] led,

    input  wire       hdmi_rx_clk_p,
    input  wire       hdmi_rx_clk_n,
    input  wire [2:0] hdmi_rx_d_p,
    input  wire [2:0] hdmi_rx_d_n,
    output wire       hdmi_rx_hpd,
    inout  wire       hdmi_rx_scl,
    inout  wire       hdmi_rx_sda,

    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_d_p,
    output wire [2:0] hdmi_tx_d_n
);
    // ---- clocks ---------------------------------------------------------------
    wire clk200, clk100, clk_locked;

    clk_gen clocks (
        .clk_in1(clk125), .clk_out1(clk200), .clk_out2(clk100), .locked(clk_locked)
    );

    // Tell the source we are here once the receiver has its reference clock.
    assign hdmi_rx_hpd = clk_locked;

    // ---- HDMI receiver ----------------------------------------------------------
    wire        pix_clk, rx_locked;
    wire [23:0] rx_data;
    wire        rx_de, rx_hs, rx_vs;
    wire        sda_i, sda_o, sda_t, scl_i, scl_o, scl_t;

    IOBUF sda_buf (.IO(hdmi_rx_sda), .I(sda_o), .T(sda_t), .O(sda_i));
    IOBUF scl_buf (.IO(hdmi_rx_scl), .I(scl_o), .T(scl_t), .O(scl_i));

    dvi_rx rx (
        .TMDS_Clk_p(hdmi_rx_clk_p), .TMDS_Clk_n(hdmi_rx_clk_n),
        .TMDS_Data_p(hdmi_rx_d_p),  .TMDS_Data_n(hdmi_rx_d_n),
        .RefClk(clk200), .aRst(~clk_locked), .pRst(1'b0),
        .vid_pData(rx_data), .vid_pVDE(rx_de), .vid_pHSync(rx_hs), .vid_pVSync(rx_vs),
        .PixelClk(pix_clk), .aPixelClkLckd(), .pLocked(rx_locked),
        .SDA_I(sda_i), .SDA_O(sda_o), .SDA_T(sda_t),
        .SCL_I(scl_i), .SCL_O(scl_o), .SCL_T(scl_t)
    );

    // ---- buttons: debounce and toggle in the always-running 100 MHz domain ------
    (* ASYNC_REG = "TRUE" *) reg [1:0] btn_s1, btn_s2;
    reg [1:0]  btn_stable, btn_prev;
    reg [20:0] btn_cnt;                     // 2^21 / 100 MHz = 21 ms
    reg        rot = 1'b0, split = 1'b0;
    reg [26:0] beat;

    always @(posedge clk100) begin
        btn_s1 <= btn;
        btn_s2 <= btn_s1;
        if (btn_s2 == btn_stable) btn_cnt <= 21'd0;
        else if (&btn_cnt)        btn_stable <= btn_s2;
        else                      btn_cnt <= btn_cnt + 1'b1;
        btn_prev <= btn_stable;
        if (btn_stable[0] && !btn_prev[0]) rot   <= ~rot;
        if (btn_stable[1] && !btn_prev[1]) split <= ~split;
        beat <= beat + 1'b1;
    end

    initial begin btn_stable = 0; btn_prev = 0; btn_cnt = 0; beat = 0; end

    // ---- controls into the pixel clock domain ----------------------------------
    (* ASYNC_REG = "TRUE" *) reg [3:0] ctl_s1, ctl_s2;

    always @(posedge pix_clk) begin
        ctl_s1 <= {split, rot, sw};
        ctl_s2 <= ctl_s1;
    end

    // ---- filter ------------------------------------------------------------------
    wire [23:0] tx_data;
    wire        tx_de, tx_hs, tx_vs;

    video_filter filter (
        .clk(pix_clk), .mode(ctl_s2[1:0]), .rot(ctl_s2[2]), .split(ctl_s2[3]),
        .in_data(rx_data), .in_de(rx_de), .in_hs(rx_hs), .in_vs(rx_vs),
        .out_data(tx_data), .out_de(tx_de), .out_hs(tx_hs), .out_vs(tx_vs)
    );

    // ---- HDMI transmitter ------------------------------------------------------
    dvi_tx tx (
        .TMDS_Clk_p(hdmi_tx_clk_p), .TMDS_Clk_n(hdmi_tx_clk_n),
        .TMDS_Data_p(hdmi_tx_d_p),  .TMDS_Data_n(hdmi_tx_d_n),
        .aRst(~rx_locked),
        .vid_pData(tx_data), .vid_pVDE(tx_de), .vid_pHSync(tx_hs), .vid_pVSync(tx_vs),
        .PixelClk(pix_clk)
    );

    // ---- status ------------------------------------------------------------------
    wire [11:0] width, height;
    wire [15:0] frames;

    video_measure measure (
        .clk(pix_clk), .de(rx_de), .vs(rx_vs),
        .width(width), .height(height), .frames(frames)
    );

    (* ASYNC_REG = "TRUE" *) reg [1:0] lock_s;
    always @(posedge clk100) lock_s <= {lock_s[0], rx_locked};

    assign led = {split, rot, lock_s[1], beat[26]};

    // Multi-bit values cross clock domains unsynchronised; they change at most
    // once per frame, so reading twice in the Hardware Manager is enough.
    status_vio vio (
        .clk(clk100),
        .probe_in0({split, rot, lock_s[1], clk_locked}),
        .probe_in1(width),
        .probe_in2(height),
        .probe_in3(frames),
        .probe_in4({btn_s2, sw})
    );
endmodule
