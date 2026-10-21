`timescale 1ns / 1ps
// Behavioural testbench for sha256_core. Hashes "abcd" and a second vector
// and compares against values computed with Python hashlib.
module sha256_tb;
    reg          clk = 1'b0;
    reg          rst_n = 1'b0;
    reg          start = 1'b0;
    reg  [31:0]  msg = 32'h0;
    wire         busy, done;
    wire [255:0] digest;

    sha256_core dut (.clk(clk), .rst_n(rst_n), .start(start), .msg(msg),
                     .busy(busy), .done(done), .digest(digest));

    always #10 clk = ~clk;      // 50 MHz

    integer errors = 0;

    task hash_and_check;
        input [31:0]  m;
        input [255:0] expected;
        begin
            @(posedge clk); msg <= m; start <= 1'b1;
            @(posedge clk); start <= 1'b0;
            wait (done); @(posedge clk);
            $display("sha256(%08h) = %064h", m, digest);
            if (digest !== expected) begin
                $display("  FAIL, expected   %064h", expected);
                errors = errors + 1;
            end else
                $display("  PASS");
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);

        // "abcd"
        hash_and_check(32'h61626364,
            256'h88d4266fd4e6338d13b845fcf289579d209c897823b9217da3e161936f031589);
        // 0x00000000
        hash_and_check(32'h00000000,
            256'hdf3f619804a92fdb4057192dc43dd748ea778adc52bc498ce80524c014b81119);
        // "Nest"
        hash_and_check(32'h4e657374,
            256'he5716be7dc8f1b2c1d03714bee1aa4a61e7da9c92f09481344840b8664343b85);

        if (errors == 0) $display("ALL PASS");
        else             $display("%0d FAILURES", errors);
        $finish;
    end
endmodule
