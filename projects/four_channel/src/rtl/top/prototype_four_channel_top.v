`timescale 1ns/1ps

module prototype_four_channel_top (
    input wire pl_clk, input wire ext_reset_n,
    input wire ch0_drdy, input wire ch0_miso, output wire ch0_sclk,
    output wire ch0_mosi, output wire ch0_cs_n, output wire ch0_sync_out,
    output wire ch0_reset_n,
    input wire ch1_drdy, input wire ch1_miso, output wire ch1_sclk,
    output wire ch1_mosi, output wire ch1_cs_n, output wire ch1_sync_out,
    output wire ch1_reset_n,
    input wire ch2_drdy, input wire ch2_miso, output wire ch2_sclk,
    output wire ch2_mosi, output wire ch2_cs_n, output wire ch2_sync_out,
    output wire ch2_reset_n,
    input wire ch3_drdy, input wire ch3_miso, output wire ch3_sclk,
    output wire ch3_mosi, output wire ch3_cs_n, output wire ch3_sync_out,
    output wire ch3_reset_n,
    inout wire [15:0] fmc_ad, input wire fmc_nadv_n, input wire fmc_ne1_n,
    input wire fmc_noe_n, input wire fmc_nwe_n, output wire fmc_nwait_n,
    output wire fpga_irq, output wire status_led
);
    wire [3:0] spi_drdy = {ch3_drdy, ch2_drdy, ch1_drdy, ch0_drdy};
    wire [3:0] spi_miso = {ch3_miso, ch2_miso, ch1_miso, ch0_miso};
    wire [3:0] spi_sclk, spi_mosi, spi_cs_n, spi_sync_out, nrf_reset_n;
    wire [287:0] debug_probe;
    (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *) wire [287:0] ila_probe;
    multichannel_product_top #(.ACTIVE_CHANNEL_MASK(4'b1111)) product_core(
        .pl_clk(pl_clk), .ext_reset_n(ext_reset_n), .spi_drdy(spi_drdy),
        .spi_miso(spi_miso), .spi_sclk(spi_sclk), .spi_mosi(spi_mosi),
        .spi_cs_n(spi_cs_n), .spi_sync_out(spi_sync_out), .nrf_reset_n(nrf_reset_n),
        .fmc_ad(fmc_ad), .fmc_nadv_n(fmc_nadv_n), .fmc_ne1_n(fmc_ne1_n),
        .fmc_noe_n(fmc_noe_n), .fmc_nwe_n(fmc_nwe_n), .fmc_nwait_n(fmc_nwait_n),
        .fpga_irq(fpga_irq), .status_led(status_led), .debug_probe(debug_probe)
    );
    assign ch0_sclk = spi_sclk[0]; assign ch0_mosi = spi_mosi[0];
    assign ch0_cs_n = spi_cs_n[0]; assign ch0_sync_out = spi_sync_out[0]; assign ch0_reset_n = nrf_reset_n[0];
    assign ch1_sclk = spi_sclk[1]; assign ch1_mosi = spi_mosi[1];
    assign ch1_cs_n = spi_cs_n[1]; assign ch1_sync_out = spi_sync_out[1]; assign ch1_reset_n = nrf_reset_n[1];
    assign ch2_sclk = spi_sclk[2]; assign ch2_mosi = spi_mosi[2];
    assign ch2_cs_n = spi_cs_n[2]; assign ch2_sync_out = spi_sync_out[2]; assign ch2_reset_n = nrf_reset_n[2];
    assign ch3_sclk = spi_sclk[3]; assign ch3_mosi = spi_mosi[3];
    assign ch3_cs_n = spi_cs_n[3]; assign ch3_sync_out = spi_sync_out[3]; assign ch3_reset_n = nrf_reset_n[3];
    assign ila_probe = debug_probe;
endmodule
