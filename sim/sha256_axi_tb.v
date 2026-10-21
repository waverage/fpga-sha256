`timescale 1ns / 1ps
// Bus-level testbench: drives sha256_axi exactly like the C program does.
module sha256_axi_tb;
    reg clk = 0, rstn = 0;
    always #10 clk = ~clk;

    reg  [5:0]  awaddr = 0; reg awvalid = 0; wire awready;
    reg  [31:0] wdata = 0;  reg wvalid = 0;  wire wready;
    wire [1:0]  bresp;      wire bvalid;     reg  bready = 1;
    reg  [5:0]  araddr = 0; reg arvalid = 0; wire arready;
    wire [31:0] rdata;      wire [1:0] rresp; wire rvalid; reg rready = 1;

    sha256_axi dut (
        .s_axi_aclk(clk), .s_axi_aresetn(rstn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'b0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(4'hf), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(3'b0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready));

    task axi_write(input [5:0] a, input [31:0] d); begin
        @(posedge clk); awaddr <= a; wdata <= d; awvalid <= 1; wvalid <= 1;
        wait (awready && wready); @(posedge clk); awvalid <= 0; wvalid <= 0;
        wait (bvalid); @(posedge clk);
    end endtask

    task axi_read(input [5:0] a, output [31:0] d); begin
        @(posedge clk); araddr <= a; arvalid <= 1;
        wait (arready); @(posedge clk); arvalid <= 0;
        wait (rvalid); d = rdata; @(posedge clk);
    end endtask

    reg [31:0] r; reg [255:0] dig; integer i;
    initial begin
        repeat (3) @(posedge clk); rstn <= 1; repeat (2) @(posedge clk);
        axi_write(6'h08, 32'h61626364);          // MSG = "abcd"
        axi_write(6'h00, 32'h1);                 // CTRL.start
        r = 0; while (!(r & 2)) axi_read(6'h04, r);
        for (i = 0; i < 8; i = i + 1) begin axi_read(6'h10 + 4*i, r); dig[255 - 32*i -: 32] = r; end
        $display("AXI readback = %064h", dig);
        if (dig === 256'h88d4266fd4e6338d13b845fcf289579d209c897823b9217da3e161936f031589) $display("AXI PASS");
        else $display("AXI FAIL");
        $finish;
    end
endmodule
