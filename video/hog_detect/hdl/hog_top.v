`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// hog_top : HDMI IN -> filter -> person boxes -> HDMI OUT, 720p60, fabric only.
//
//   SW1:SW0  filter: 00 pass, 01 grayscale, 10 invert, 11 threshold
//   BTN0     toggle colour rotation
//   BTN1     toggle split screen
//   BTN2     toggle person boxes (on after configuration)
//   LD0      heartbeat
//   LD1      HDMI input locked
//   LD2      at least one person box in the current frame
//   LD3      person boxes enabled
//
// Detection always runs on the unfiltered input; boxes are drawn on top of
// the filtered picture, one frame late.
// ---------------------------------------------------------------------------
module hog_top (
    input  wire       clk125,
    input  wire [1:0] sw,
    input  wire [2:0] btn,
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

    // ---- buttons: debounce and toggle in the 100 MHz domain -----------------------
    (* ASYNC_REG = "TRUE" *) reg [2:0] btn_s1, btn_s2;
    reg [2:0]  btn_stable = 0, btn_prev = 0;
    reg [20:0] btn_cnt = 0;
    reg        rot = 1'b0, split = 1'b0, boxes_en = 1'b1;
    reg [26:0] beat = 0;

    always @(posedge clk100) begin
        btn_s1 <= btn;
        btn_s2 <= btn_s1;
        if (btn_s2 == btn_stable) btn_cnt <= 21'd0;
        else if (&btn_cnt)        btn_stable <= btn_s2;
        else                      btn_cnt <= btn_cnt + 1'b1;
        btn_prev <= btn_stable;
        if (btn_stable[0] && !btn_prev[0]) rot      <= ~rot;
        if (btn_stable[1] && !btn_prev[1]) split    <= ~split;
        if (btn_stable[2] && !btn_prev[2]) boxes_en <= ~boxes_en;
        beat <= beat + 1'b1;
    end

    (* ASYNC_REG = "TRUE" *) reg [4:0] ctl_s1, ctl_s2;
    always @(posedge pix_clk) begin
        ctl_s1 <= {boxes_en, split, rot, sw};
        ctl_s2 <= ctl_s1;
    end

    // ---- detection on the raw input -------------------------------------------------
    wire [7:0]      box_ok;
    wire [8*11-1:0] box_x;
    wire [8*10-1:0] box_y;
    wire [15:0]     hits;
    wire [3:0]      nboxes;

    hog_detect #(.W(1280), .H(720)) detect (
        .clk(pix_clk), .in_data(rx_data), .in_de(rx_de), .in_vs(rx_vs), .thr(40'sd0),
        .box_ok(box_ok), .box_x(box_x), .box_y(box_y), .hits(hits), .nboxes(nboxes)
    );

    // ---- filter, then boxes -----------------------------------------------------------
    wire [23:0] f_data, o_data;
    wire        f_de, f_hs, f_vs, o_de, o_hs, o_vs;

    video_filter filter (
        .clk(pix_clk), .mode(ctl_s2[1:0]), .rot(ctl_s2[2]), .split(ctl_s2[3]),
        .in_data(rx_data), .in_de(rx_de), .in_hs(rx_hs), .in_vs(rx_vs),
        .out_data(f_data), .out_de(f_de), .out_hs(f_hs), .out_vs(f_vs)
    );

    box_overlay overlay (
        .clk(pix_clk), .en(ctl_s2[4]),
        .box_ok(box_ok), .box_x(box_x), .box_y(box_y),
        .in_data(f_data), .in_de(f_de), .in_hs(f_hs), .in_vs(f_vs),
        .out_data(o_data), .out_de(o_de), .out_hs(o_hs), .out_vs(o_vs)
    );

    dvi_tx tx (
        .TMDS_Clk_p(hdmi_tx_clk_p), .TMDS_Clk_n(hdmi_tx_clk_n),
        .TMDS_Data_p(hdmi_tx_d_p),  .TMDS_Data_n(hdmi_tx_d_n),
        .aRst(~rx_locked),
        .vid_pData(o_data), .vid_pVDE(o_de), .vid_pHSync(o_hs), .vid_pVSync(o_vs),
        .PixelClk(pix_clk)
    );

    // ---- status ---------------------------------------------------------------------------
    wire [11:0] width, height;
    wire [15:0] frames;

    video_measure measure (
        .clk(pix_clk), .de(rx_de), .vs(rx_vs),
        .width(width), .height(height), .frames(frames)
    );

    (* ASYNC_REG = "TRUE" *) reg [1:0] lock_s, any_s;
    always @(posedge clk100) begin
        lock_s <= {lock_s[0], rx_locked};
        any_s  <= {any_s[0], |box_ok};
    end

    assign led = {boxes_en, any_s[1], lock_s[1], beat[26]};

    // Multi-bit values cross clock domains unsynchronised; they change once per
    // frame, so read them twice.
    status_vio vio (
        .clk(clk100),
        .probe_in0({split, rot, lock_s[1], clk_locked}),
        .probe_in1(width),
        .probe_in2(height),
        .probe_in3(frames),
        .probe_in4({btn_s2[1:0], sw}),
        .probe_in5(hits),
        .probe_in6(nboxes),
        .probe_in7(box_x[10:0]),
        .probe_in8(box_y[9:0]),
        .probe_in9(box_ok)
    );
endmodule
