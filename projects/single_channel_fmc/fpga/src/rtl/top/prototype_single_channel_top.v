`timescale 1ns/1ps

// Board prototype wrapper for the ATK ZYNQ7020 carrier and the STM32F730 FMC
// host. The product core remains protocol compatible with MC005; this wrapper
// only gives it the physical board names used by the reviewed XDC.
module prototype_single_channel_top (
    input  wire        pl_clk,
    input  wire        ext_reset_n,
    output wire        ch0_sclk,
    output wire        ch0_mosi,
    input  wire        ch0_miso,
    output wire        ch0_cs_n,
    input  wire        ch0_drdy,
    output wire        ch0_sync_out,
    output wire        ch0_reset_n,
    inout  wire [15:0] fmc_ad,
    input  wire        fmc_nadv_n,
    input  wire        fmc_ne1_n,
    input  wire        fmc_noe_n,
    input  wire        fmc_nwe_n,
    output wire        fmc_nwait_n,
    output wire        fpga_irq,
    output wire        status_led
);
    (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) wire [447:0] ila_probe;

    single_channel_product_top #(
        .CLOCK_HZ(50000000),
        .SCLK_HZ(1000000), .DEBUG_AUTONOMOUS(0),
        // Keep advertised initial SCLK and 1 ms A-to-B minimum.
        // 500 us B-to-next-A allows rearming without limiting RF drain to 40/s.
        .AB_GAP_CYCLES(50000), .B_TO_NEXT_A_GAP_CYCLES(25000)
    ) product_core (
        .pl_clk(pl_clk),
        .ext_reset_n(ext_reset_n),
        .nrf_sclk(ch0_sclk),
        .nrf_mosi(ch0_mosi),
        .nrf_miso(ch0_miso),
        .nrf_cs_n(ch0_cs_n),
        .nrf_drdy(ch0_drdy),
        .nrf_reset_n(ch0_reset_n),
        .nrf_sync_out(ch0_sync_out),
        .fmc_ad(fmc_ad),
        .fmc_nadv_n(fmc_nadv_n),
        .fmc_ne1_n(fmc_ne1_n),
        .fmc_noe_n(fmc_noe_n),
        .fmc_nwe_n(fmc_nwe_n),
        .fmc_nwait_n(fmc_nwait_n),
        .fpga_irq(fpga_irq),
        .status_led(status_led),
        .debug_probe(ila_probe)
    );
endmodule
