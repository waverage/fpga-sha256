`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// sha256_core : SHA-256 of a fixed 4-byte (32-bit) message.
//
// The message is always exactly 4 bytes, so the padding is constant and the
// core builds the single 512-bit block itself:
//   W0  = msg            (byte 0 in msg[31:24], byte 3 in msg[7:0])
//   W1  = 0x80000000     (the mandatory '1' bit, then zeros)
//   W2..W14 = 0
//   W15 = 32             (message length in bits)
//
// Iterative design: one compression round per clock, 64 rounds + 1 final
// cycle. Message schedule is a 16-word sliding window, so no 64-word RAM.
//
// Protocol: pulse `start` for one clock while `busy` is low. `done` pulses
// for one clock when `digest` is valid. `digest[255:224]` is H0, the first
// word of the standard hex string.
// ---------------------------------------------------------------------------
module sha256_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [31:0]  msg,
    output reg          busy,
    output reg          done,
    output reg  [255:0] digest
);

    // ---- SHA-256 primitive functions (FIPS 180-4, section 4.1.2) ----------
    function [31:0] bsig0; input [31:0] x;          // Sigma0: ROTR2 ^ ROTR13 ^ ROTR22
        bsig0 = {x[1:0],  x[31:2]}  ^ {x[12:0], x[31:13]} ^ {x[21:0], x[31:22]};
    endfunction
    function [31:0] bsig1; input [31:0] x;          // Sigma1: ROTR6 ^ ROTR11 ^ ROTR25
        bsig1 = {x[5:0],  x[31:6]}  ^ {x[10:0], x[31:11]} ^ {x[24:0], x[31:25]};
    endfunction
    function [31:0] ssig0; input [31:0] x;          // sigma0: ROTR7 ^ ROTR18 ^ SHR3
        ssig0 = {x[6:0],  x[31:7]}  ^ {x[17:0], x[31:18]} ^ (x >> 3);
    endfunction
    function [31:0] ssig1; input [31:0] x;          // sigma1: ROTR17 ^ ROTR19 ^ SHR10
        ssig1 = {x[16:0], x[31:17]} ^ {x[18:0], x[31:19]} ^ (x >> 10);
    endfunction
    function [31:0] ch;  input [31:0] e, f, g;  ch  = (e & f) ^ (~e & g);            endfunction
    function [31:0] maj; input [31:0] a, b, c;  maj = (a & b) ^ (a & c) ^ (b & c);   endfunction

    // ---- Round constants K[0..63] (FIPS 180-4, section 4.2.2) -------------
    function [31:0] K; input [5:0] t;
        case (t)
            6'd0:  K = 32'h428a2f98; 6'd1:  K = 32'h71374491; 6'd2:  K = 32'hb5c0fbcf; 6'd3:  K = 32'he9b5dba5;
            6'd4:  K = 32'h3956c25b; 6'd5:  K = 32'h59f111f1; 6'd6:  K = 32'h923f82a4; 6'd7:  K = 32'hab1c5ed5;
            6'd8:  K = 32'hd807aa98; 6'd9:  K = 32'h12835b01; 6'd10: K = 32'h243185be; 6'd11: K = 32'h550c7dc3;
            6'd12: K = 32'h72be5d74; 6'd13: K = 32'h80deb1fe; 6'd14: K = 32'h9bdc06a7; 6'd15: K = 32'hc19bf174;
            6'd16: K = 32'he49b69c1; 6'd17: K = 32'hefbe4786; 6'd18: K = 32'h0fc19dc6; 6'd19: K = 32'h240ca1cc;
            6'd20: K = 32'h2de92c6f; 6'd21: K = 32'h4a7484aa; 6'd22: K = 32'h5cb0a9dc; 6'd23: K = 32'h76f988da;
            6'd24: K = 32'h983e5152; 6'd25: K = 32'ha831c66d; 6'd26: K = 32'hb00327c8; 6'd27: K = 32'hbf597fc7;
            6'd28: K = 32'hc6e00bf3; 6'd29: K = 32'hd5a79147; 6'd30: K = 32'h06ca6351; 6'd31: K = 32'h14292967;
            6'd32: K = 32'h27b70a85; 6'd33: K = 32'h2e1b2138; 6'd34: K = 32'h4d2c6dfc; 6'd35: K = 32'h53380d13;
            6'd36: K = 32'h650a7354; 6'd37: K = 32'h766a0abb; 6'd38: K = 32'h81c2c92e; 6'd39: K = 32'h92722c85;
            6'd40: K = 32'ha2bfe8a1; 6'd41: K = 32'ha81a664b; 6'd42: K = 32'hc24b8b70; 6'd43: K = 32'hc76c51a3;
            6'd44: K = 32'hd192e819; 6'd45: K = 32'hd6990624; 6'd46: K = 32'hf40e3585; 6'd47: K = 32'h106aa070;
            6'd48: K = 32'h19a4c116; 6'd49: K = 32'h1e376c08; 6'd50: K = 32'h2748774c; 6'd51: K = 32'h34b0bcb5;
            6'd52: K = 32'h391c0cb3; 6'd53: K = 32'h4ed8aa4a; 6'd54: K = 32'h5b9cca4f; 6'd55: K = 32'h682e6ff3;
            6'd56: K = 32'h748f82ee; 6'd57: K = 32'h78a5636f; 6'd58: K = 32'h84c87814; 6'd59: K = 32'h8cc70208;
            6'd60: K = 32'h90befffa; 6'd61: K = 32'ha4506ceb; 6'd62: K = 32'hbef9a3f7; default: K = 32'hc67178f2;
        endcase
    endfunction

    // ---- Initial hash value (FIPS 180-4, section 5.3.3) -------------------
    localparam [31:0] H0 = 32'h6a09e667, H1 = 32'hbb67ae85, H2 = 32'h3c6ef372, H3 = 32'ha54ff53a,
                      H4 = 32'h510e527f, H5 = 32'h9b05688c, H6 = 32'h1f83d9ab, H7 = 32'h5be0cd19;

    // ---- State ------------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0, S_ROUND = 2'd1, S_FINAL = 2'd2;
    reg [1:0]  state;
    reg [5:0]  t;                       // round counter 0..63
    reg [31:0] a, b, c, d, e, f, g, h;  // working variables
    reg [31:0] w [0:15];                // sliding message-schedule window, w[0] = W[t]
    integer i;

    // Combinational round math (this is the critical timing path)
    wire [31:0] T1   = h + bsig1(e) + ch(e, f, g) + K(t) + w[0];
    wire [31:0] T2   = bsig0(a) + maj(a, b, c);
    wire [31:0] wnew = ssig1(w[14]) + w[9] + ssig0(w[1]) + w[0];   // W[t+16]

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            busy  <= 1'b0;
            done  <= 1'b0;
            t     <= 6'd0;
        end else begin
            done <= 1'b0;                              // done is a 1-cycle pulse
            case (state)

                S_IDLE: if (start) begin
                    a <= H0; b <= H1; c <= H2; d <= H3;
                    e <= H4; f <= H5; g <= H6; h <= H7;
                    w[0]  <= msg;
                    w[1]  <= 32'h80000000;
                    for (i = 2; i < 15; i = i + 1) w[i] <= 32'h0;
                    w[15] <= 32'd32;
                    t     <= 6'd0;
                    busy  <= 1'b1;
                    state <= S_ROUND;
                end

                S_ROUND: begin
                    h <= g;  g <= f;  f <= e;  e <= d + T1;
                    d <= c;  c <= b;  b <= a;  a <= T1 + T2;
                    for (i = 0; i < 15; i = i + 1) w[i] <= w[i + 1];
                    w[15] <= wnew;
                    t <= t + 6'd1;
                    if (t == 6'd63) state <= S_FINAL;
                end

                S_FINAL: begin
                    digest <= {H0 + a, H1 + b, H2 + c, H3 + d,
                               H4 + e, H5 + f, H6 + g, H7 + h};
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
