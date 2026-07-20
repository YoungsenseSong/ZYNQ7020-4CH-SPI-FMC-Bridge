# FPGA v1 外部接口

## 顶层端口

| 端口 | 方向 | 宽度 | 说明 |
|---|---:|---:|---|
| `pl_clk` | input | 1 | PL 工作时钟；频率和引脚 `CONFIG_REQUIRED` |
| `ext_reset_n` | input | 1 | 外部低有效复位；板级极性仍需确认 |
| `spi_sclk` | output | 4 | 四路独立 SPI 时钟 |
| `spi_mosi` | output | 4 | 四路 SPI MOSI |
| `spi_miso` | input | 4 | 四路 SPI MISO |
| `spi_cs_n` | output | 4 | 四路低有效片选 |
| `spi_drdy` | input | 4 | 四路数据就绪，经双触发器同步 |
| `nrf_reset_n` | output | 4 | 当前随内部低有效复位释放；实际极性 `CONFIG_REQUIRED` |
| `sync_out` | output | 4 | 按通道掩码发出的同步脉冲 |
| `nrf_sync_ready` | input | 4 | 四路同步就绪状态，经同步后锁存显示 |
| `fmc_ad` | inout | 16 | STM32 FMC 复用地址/数据总线 |
| `fmc_nadv_n` | input | 1 | 低有效地址有效 |
| `fmc_ne1_n` | input | 1 | 低有效片选 |
| `fmc_noe_n` | input | 1 | 低有效读使能 |
| `fmc_nwe_n` | input | 1 | 低有效写使能 |
| `fmc_nwait_n` | output | 1 | 低有效等待 |
| `fpga_irq` | output | 1 | 高有效中断输出 |
| `status_led` | output | 1 | 当前直接显示 running 状态 |

## SPI 事务约定

当前 RTL 实现 SPI mode 0：空闲 SCLK 为低，上升沿采样 MISO、下降沿更新 MOSI，MSB first。CS 在命令和整条记录期间保持有效。SPI 命令、记录长度、目标频率、DRDY 去断言行为和 nRF 响应延迟均须与 nRF 固件一起冻结。

## SYNC 约定

软件先写通道掩码并触发 ARM，再触发 FIRE。第一版顶层把 delay 固定为 0、脉宽固定为 10 个 PL 周期；这些仅是占位值。`nrf_sync_ready` 只用于状态锁存，不会阻止 SYNC 发出。

## FMC 地址约定

STM32 提供 16-bit word address，RTL 内部转换为 byte offset：

```text
internal_byte_offset = fmc_word_address * 2
STM32_byte_address   = 0x60000000 + internal_byte_offset
```

当前总线没有 NBL0/NBL1 字节使能端口，因此 CSR 写按完整 16 位处理。真实硬件必须确认 FMC 模式为异步复用 PSRAM/SRAM、NE1 基址、NADV/NWAIT 极性和读写时序。

## 约束状态

`constraints/board_top.xdc` 有意保持为注释文件，且 `scripts/project_files.tcl` 不把任何 XDC 加入 `constrs_1`。`board_top_pins.xdc.example` 中不存在可用引脚，仅列出需要从已审核原理图填写的项目。
