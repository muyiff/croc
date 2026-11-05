// CRV SoC functional demonstration for RTL simulation and presentations.
// Exercises only the currently verified CPU, memory-mapped I/O, and UART paths.

#include <stdint.h>

#include "clint.h"
#include "config.h"
#include "print.h"
#include "soc_ctrl.h"
#include "uart.h"
#include "util.h"

static int sram_read_write_test(uint32_t *checksum) {
    volatile uint32_t words[4];

    words[0] = 0x13579BDF;
    words[1] = 0x2468ACE0;
    words[2] = 0x0F0F0F0F;
    words[3] = 0x55AA55AA;

    *checksum = words[0] ^ words[1] ^ words[2] ^ words[3];
    return *checksum == 0x6D9A6D9A;
}

int main() {
    uint32_t checksum;
    uint32_t boot_addr;
    uint32_t msip;
    int pass = 1;

    uart_init();

    if (!sram_read_write_test(&checksum)) {
        pass = 0;
    }

    boot_addr = *reg32(SOCCTRL_BASE_ADDR, SOC_CTRL_BOOTADDR_REG_OFFSET);
    if (boot_addr != 0x10000000) {
        pass = 0;
    }

    // The BootROM clears MSIP after the JTAG release handshake.
    msip = *reg32(CLINT_BASE_ADDR, CLINT_MSIP_REG_OFFSET);
    if (msip & 1u) {
        pass = 0;
    }

    if (pass)
        printf("CRV-SOC PASS: CPU SRAM UART\n");
    else
        printf("CRV-SOC FAIL\n");
    uart_write_flush();

    return pass ? 0 : 1;
}
