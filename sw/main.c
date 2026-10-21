/*
 * Bare-metal test program for the sha256_axi peripheral (Arty Z7-20, Zynq PS).
 * In a Vitis "Hello World" application, delete helloworld.c and add this
 * file next to platform.c (see README for the UserConfig.cmake fix).
 *
 * Type 4 characters in the serial terminal (115200 8N1). The PS packs them
 * into one 32-bit word, hands it to the FPGA core, waits for done and prints
 * the 256-bit digest as 64 hex characters.
 */
#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "xparameters.h"

/* Check Vivado's Address Editor or xparameters.h if this does not match. */
#ifdef XPAR_SHA256_AXI_0_BASEADDR
#define SHA_BASE XPAR_SHA256_AXI_0_BASEADDR
#else
#define SHA_BASE 0x43C00000u
#endif

#define REG_CTRL    0x00u
#define REG_STATUS  0x04u
#define REG_MSG     0x08u
#define REG_DIGEST  0x10u
#define STATUS_BUSY (1u << 0)
#define STATUS_DONE (1u << 1)

static void sha256_hw(u32 msg, u32 out[8])
{
    Xil_Out32(SHA_BASE + REG_MSG, msg);
    Xil_Out32(SHA_BASE + REG_CTRL, 1u);
    while (!(Xil_In32(SHA_BASE + REG_STATUS) & STATUS_DONE))
        ;
    for (int i = 0; i < 8; i++)
        out[i] = Xil_In32(SHA_BASE + REG_DIGEST + 4u * i);
}

int main(void)
{
    u32 d[8];
    init_platform();

    xil_printf("\r\nSHA-256 in FPGA fabric, Arty Z7-20\r\n");

    /* Self test: "abcd" -> 88d4266f d4e6338d 13b845fc f289579d 209c8978 23b9217d a3e16193 6f031589 */
    sha256_hw(0x61626364u, d);
    xil_printf("self test sha256(\"abcd\") = ");
    for (int i = 0; i < 8; i++) xil_printf("%08x", d[i]);
    xil_printf("  %s\r\n", (d[0] == 0x88d4266fu && d[7] == 0x6f031589u) ? "OK" : "MISMATCH");

    while (1) {
        char s[4];
        xil_printf("type 4 characters: ");
        for (int i = 0; i < 4; i++) {
            s[i] = inbyte();
            outbyte(s[i]);
        }
        u32 msg = ((u32)(u8)s[0] << 24) | ((u32)(u8)s[1] << 16) |
                  ((u32)(u8)s[2] << 8)  |  (u32)(u8)s[3];
        sha256_hw(msg, d);
        xil_printf("\r\nsha256(%08x) = ", msg);
        for (int i = 0; i < 8; i++) xil_printf("%08x", d[i]);
        xil_printf("\r\n");
    }

    cleanup_platform();
    return 0;
}
