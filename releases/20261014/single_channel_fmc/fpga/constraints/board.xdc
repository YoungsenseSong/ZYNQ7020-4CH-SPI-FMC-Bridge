# MC006 prototype board constraints
# Target: ATK ZYNQ7020 carrier/core, XC7Z020CLG400-2, VCCO 3.3 V.
# FMC host signals use the reviewed carrier J3 EXT_IO header; CH0 nRF uses J4.

set_property PACKAGE_PIN U18 [get_ports pl_clk]
set_property IOSTANDARD LVCMOS33 [get_ports pl_clk]
create_clock -period 20.000 -name pl_clk_50mhz [get_ports pl_clk]

set_property PACKAGE_PIN N16 [get_ports ext_reset_n]
set_property IOSTANDARD LVCMOS33 [get_ports ext_reset_n]
set_property PULLTYPE PULLUP [get_ports ext_reset_n]

# CH0 nRF on J4, as documented by the existing board handoff.
set_property PACKAGE_PIN T9 [get_ports ch0_sclk]
set_property PACKAGE_PIN T5 [get_ports ch0_mosi]
set_property PACKAGE_PIN U7 [get_ports ch0_miso]
set_property PACKAGE_PIN V8 [get_ports ch0_cs_n]
set_property PACKAGE_PIN U8 [get_ports ch0_drdy]
set_property PACKAGE_PIN V6 [get_ports ch0_sync_out]
set_property PACKAGE_PIN Y6 [get_ports ch0_reset_n]

# FMC AD[15:0] on J3 pins 5..20. J3 pins 1..4 remain UART/CAN nets.
set_property PACKAGE_PIN U19 [get_ports {fmc_ad[0]}]
set_property PACKAGE_PIN N20 [get_ports {fmc_ad[1]}]
set_property PACKAGE_PIN M19 [get_ports {fmc_ad[2]}]
set_property PACKAGE_PIN M20 [get_ports {fmc_ad[3]}]
set_property PACKAGE_PIN U20 [get_ports {fmc_ad[4]}]
set_property PACKAGE_PIN T20 [get_ports {fmc_ad[5]}]
set_property PACKAGE_PIN N18 [get_ports {fmc_ad[6]}]
set_property PACKAGE_PIN P19 [get_ports {fmc_ad[7]}]
set_property PACKAGE_PIN N17 [get_ports {fmc_ad[8]}]
set_property PACKAGE_PIN P18 [get_ports {fmc_ad[9]}]
set_property PACKAGE_PIN V20 [get_ports {fmc_ad[10]}]
set_property PACKAGE_PIN W20 [get_ports {fmc_ad[11]}]
set_property PACKAGE_PIN R17 [get_ports {fmc_ad[12]}]
set_property PACKAGE_PIN R16 [get_ports {fmc_ad[13]}]
set_property PACKAGE_PIN W19 [get_ports {fmc_ad[14]}]
set_property PACKAGE_PIN W18 [get_ports {fmc_ad[15]}]

# FMC control/handshake and interrupt on J3 pins 21..27.
set_property PACKAGE_PIN P16 [get_ports fmc_nadv_n]
set_property PACKAGE_PIN P15 [get_ports fmc_ne1_n]
set_property PACKAGE_PIN Y19 [get_ports fmc_noe_n]
set_property PACKAGE_PIN Y18 [get_ports fmc_nwe_n]
set_property PACKAGE_PIN R18 [get_ports fmc_nwait_n]
set_property PACKAGE_PIN T17 [get_ports fpga_irq]
set_property PACKAGE_PIN V18 [get_ports status_led]

set_property IOSTANDARD LVCMOS33 [get_ports {fmc_ad[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports fmc_nadv_n]
set_property IOSTANDARD LVCMOS33 [get_ports fmc_ne1_n]
set_property IOSTANDARD LVCMOS33 [get_ports fmc_noe_n]
set_property IOSTANDARD LVCMOS33 [get_ports fmc_nwe_n]
set_property IOSTANDARD LVCMOS33 [get_ports fmc_nwait_n]
set_property IOSTANDARD LVCMOS33 [get_ports fpga_irq]
set_property IOSTANDARD LVCMOS33 [get_ports status_led]
set_property IOSTANDARD LVCMOS33 [get_ports ch0_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports ch0_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports ch0_miso]
set_property IOSTANDARD LVCMOS33 [get_ports ch0_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports ch0_drdy]
set_property IOSTANDARD LVCMOS33 [get_ports ch0_sync_out]
set_property IOSTANDARD LVCMOS33 [get_ports ch0_reset_n]

set_property DRIVE 8 [get_ports ch0_sclk]
set_property DRIVE 8 [get_ports ch0_mosi]
set_property DRIVE 8 [get_ports ch0_cs_n]
set_property DRIVE 8 [get_ports ch0_sync_out]
set_property SLEW SLOW [get_ports ch0_sclk]
set_property SLEW SLOW [get_ports ch0_mosi]
set_property SLEW SLOW [get_ports ch0_cs_n]
set_property SLEW SLOW [get_ports ch0_sync_out]
set_property DRIVE 8 [get_ports ch0_reset_n]
set_property SLEW SLOW [get_ports ch0_reset_n]
set_property PULLTYPE PULLUP [get_ports ch0_cs_n]

# DRDY and FMC wait are asynchronous inputs to the PL clock domain.
set_false_path -from [get_ports ch0_drdy]
set_false_path -from [get_ports ext_reset_n]

