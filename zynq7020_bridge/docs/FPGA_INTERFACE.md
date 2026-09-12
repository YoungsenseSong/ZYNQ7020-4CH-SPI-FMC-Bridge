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

通用四路 `board_top` 中的 `spi_master_ch` 仍是旧的 raw-record 仿真路径，不能用于
nRF 实板验收。专用 `ch0_test_top` 已按冻结接口实现：mode 0、MSB first、1 MHz；
每条命令使用两个独立 CS 事务，A 为 8 B request，B 为 260 B response 且 MOSI 填 0；
CS setup/hold 均为 1 us。实板运行证明 1 ms A/B 和 300 ns B/next-A 电气下限不足以
保证 nRF Zephyr SPIS worker 在无线负载下完成 EasyDMA 重装，因此 CH0 bring-up 镜像
把 A/B 与 B/next-A 软件保护时间都设为 5 ms。若 response envelope/CRC、COMMIT 或
transaction timeout 出错，控制器先等待 5 ms 并发送一次 260 B 全零相位冲洗：从机若
在 response phase 会完成 B，若在 request phase 会把长事务作为 short transfer 丢弃，
两种情况随后都回到 request phase。再等待后才重试命令，避免一次漏装载造成永久错相。
这些 5 ms 和恢复事务都是 bring-up/self-recovery 策略，不是最终吞吐配置。

## SYNC 约定

软件先写通道掩码并触发 ARM，再触发 FIRE。第一版顶层把 delay 固定为 0、脉宽固定为 10 个 PL 周期；这些仅是占位值。`nrf_sync_ready` 只用于状态锁存，不会阻止 SYNC 发出。

CRC 合法 record 进入四路对齐器后，还必须满足四路 `status_flags.SYNCED=1`、
`sync_epoch` 等于当前 FPGA epoch、`logical_sample_index` 完全相同，才会成组输出。
对齐器不比较四路 `rx_tick`，因为它们尚未绑定到同一个硬件时基；也不改写 RF payload。
`SYNC_STATUS` 表示脉冲/ready 状态，`ALIGN_STATUS` 才表示 record 对齐缓冲状态，两者不能
互相替代。

## FMC 地址约定

STM32 提供 16-bit word address，RTL 内部转换为 byte offset：

```text
internal_byte_offset = fmc_word_address * 2
STM32_byte_address   = 0x60000000 + internal_byte_offset
```

当前总线没有 NBL0/NBL1 字节使能端口，因此 CSR 写按完整 16 位处理。真实硬件必须确认 FMC 模式为异步复用 PSRAM/SRAM、NE1 基址、NADV/NWAIT 极性和读写时序。

## 约束状态

CH0 专用 `constraints/ch0_test.xdc` 已加入当前测试工程，使用 J4/Bank13/LVCMOS33 和
板载 U18 50 MHz 时钟。`constraints/board_top.xdc` 仍是四路/FMC 集成顶层的未完成
约束说明；`board_top_pins.xdc.example` 不能直接用于产品引脚分配。CH0 测试约束和
bitstream 不证明 FMC 引脚、NWAIT 或 CH1..CH3 已完成。

## 当前实板接口状态

2026-09-03，CRC 修正后的 nRF 日志达到 `records=1957`、`pop_total=1956`、
`crc_errors=0`，确认 CH0 request/response、合法 record 和 COMMIT 主路径工作。残余
`invalid_cmd=44`、`short_xfer=29` 及 queue overflow 表明 bring-up 时序尚非持续吞吐
配置。同次 `Imp/iladata.csv` 只有 CSV 字段与 Radix 行，没有采样记录；因此仍需重新
Run Trigger/Immediate 并导出 ILA，才能把 FPGA 侧 CRC/COMMIT 计数纳入正式实验记录。
