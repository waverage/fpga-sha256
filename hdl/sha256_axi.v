`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// sha256_axi : AXI4-Lite slave wrapper around sha256_core.
//
// Register map (byte offsets from the base address):
//   0x00  CTRL    W   bit0 = 1 -> start a hash (self clearing)
//   0x04  STATUS  R   bit0 = busy, bit1 = done (sticky, cleared by CTRL write)
//   0x08  MSG     RW  32-bit message
//   0x10  DIGEST0 R   first word of the hash (most significant)
//   ...
//   0x2C  DIGEST7 R   last word
//
// Port names follow the s_axi_* convention so Vivado IP Integrator infers an
// AXI4-Lite interface when the file is added with "Add Module".
// ---------------------------------------------------------------------------
module sha256_axi (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 50000000" *)
    input  wire        s_axi_aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        s_axi_aresetn,

    input  wire [5:0]  s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [5:0]  s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);
    assign s_axi_bresp = 2'b00;     // OKAY
    assign s_axi_rresp = 2'b00;     // OKAY

    // ---- core ---------------------------------------------------------------
    reg          start;
    reg  [31:0]  msg_reg;
    reg          done_sticky;
    wire         busy, done;
    wire [255:0] digest;

    sha256_core core (
        .clk(s_axi_aclk), .rst_n(s_axi_aresetn), .start(start), .msg(msg_reg),
        .busy(busy), .done(done), .digest(digest)
    );

    // ---- write channel ------------------------------------------------------
    // Accept AW and W together, write the register, then raise BVALID one
    // cycle after the handshake and hold it until BREADY.
    reg wr_pending;
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0; s_axi_wready <= 1'b0; s_axi_bvalid <= 1'b0;
            wr_pending <= 1'b0; start <= 1'b0; msg_reg <= 32'h0; done_sticky <= 1'b0;
        end else begin
            start         <= 1'b0;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            if (done) done_sticky <= 1'b1;

            if (s_axi_awvalid && s_axi_wvalid && !s_axi_awready && !wr_pending && !s_axi_bvalid) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                wr_pending    <= 1'b1;
                case (s_axi_awaddr[5:2])
                    4'h0: if (s_axi_wdata[0] && !busy) begin
                              start       <= 1'b1;
                              done_sticky <= 1'b0;
                          end
                    4'h2: msg_reg <= s_axi_wdata;
                    default: ;
                endcase
            end
            if (wr_pending) begin
                wr_pending   <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
        end
    end

    // ---- read channel -------------------------------------------------------
    reg       rd_pending;
    reg [3:0] rd_addr;
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0; s_axi_rvalid <= 1'b0; s_axi_rdata <= 32'h0;
            rd_pending <= 1'b0; rd_addr <= 4'h0;
        end else begin
            s_axi_arready <= 1'b0;
            if (s_axi_arvalid && !s_axi_arready && !rd_pending && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
                rd_pending    <= 1'b1;
                rd_addr       <= s_axi_araddr[5:2];
            end
            if (rd_pending) begin
                rd_pending   <= 1'b0;
                s_axi_rvalid <= 1'b1;
                case (rd_addr)
                    4'h0: s_axi_rdata <= 32'h0;
                    4'h1: s_axi_rdata <= {30'h0, done_sticky, busy};
                    4'h2: s_axi_rdata <= msg_reg;
                    4'h4: s_axi_rdata <= digest[255:224];
                    4'h5: s_axi_rdata <= digest[223:192];
                    4'h6: s_axi_rdata <= digest[191:160];
                    4'h7: s_axi_rdata <= digest[159:128];
                    4'h8: s_axi_rdata <= digest[127:96];
                    4'h9: s_axi_rdata <= digest[95:64];
                    4'hA: s_axi_rdata <= digest[63:32];
                    4'hB: s_axi_rdata <= digest[31:0];
                    default: s_axi_rdata <= 32'hdeadbeef;
                endcase
            end
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
        end
    end
endmodule
