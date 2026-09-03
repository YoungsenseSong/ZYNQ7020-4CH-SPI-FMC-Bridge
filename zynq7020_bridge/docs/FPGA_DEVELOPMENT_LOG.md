# FPGA v1 开发日志

## 2026-09-03 CRC 修正版 CH0 实板功能闭环

- nRF 将 record header CRC 改为冻结的 CRC-16/CCITT-FALSE 后重新烧录；FPGA RTL、
  接线和最新 CH0 bitstream 未再次修改。
- 新串口日志最终为 `records=1957`、`QUEUE pop_total=1956`、`crc_errors=0`、
  `req_xfer=3996`、`rsp_xfer=3995`，证明 CH0 已从启动/SYNC 进入真实 record 的
  PEEK/COMMIT 和队列释放。
- 残余累计值为 `invalid_cmd=44`、`short_xfer=29`、`submit_errors=49`；record queue
  `overflow=4270`。因此功能闭环成立，但当前 1 MHz 与双 5 ms 保护不满足持续无损
  吞吐，也未完成 30 min/2 h 稳定性验收。
- 同次 `Imp/iladata.csv` 只有表头和 Radix 行，没有采样行，不能据此记录 FPGA
  `crc_ok_count`/`commit_ok_count`。下一次必须先完成一次 ILA capture 再导出。
- 暂不继续修改 FPGA。先由 nRF 侧消除 transport service 并发 submit 窗口并补有效
  ILA 证据，再逐步缩短保护间隔；之后才进入四路和 FMC 顶层。

## 2026-08-17 四路 record 逻辑对齐

- 只读核对 nRF 默认分支提交 `4e360863a3569c9494197ec701604404519d811d`：RX V2
  已产生 `sync_epoch`、`rx_tick`、`logical_sample_index` 和 `SYNCED/DEGRADED` 标志，
  但文档与代码都明确真实 SPIS、GPIOTE-DPPI-TIMER SYNC 捕获及远端 MEMS 公共采样时基
  尚未完成。
- 新增 `four_channel_record_aligner.v`，四路各缓存一条 CRC 合法 record；只对同 FPGA
  epoch、同逻辑样本起点的四路记录按 0..3 顺序成组输出。未同步、旧 epoch、旧索引和
  record 边界错误均显式计数，204 B payload 不被改写。
- 新增只读 ALIGN CSR：缓存/输出状态、组数、元数据错误、最近 epoch/index 和每路淘汰数。
- `tb_four_channel_record_aligner.sv` 覆盖正常 4 路组、未同步淘汰、旧索引追赶和旧 epoch
  追赶；Icarus 结果为 4 组、drop 2/1/0/0、error 3。原 parser、block builder、A/B ACK
  三项回归继续通过。
- Vivado 2025.2 对原 XPR 再次 `check_syntax` 返回 0；日志为
  `artifacts/bridge-validation/20260817/zynq-four-channel-align-check-syntax-final.log`。
  未运行综合、实现或 bitstream。
- 仍不实现分数相位 FIR 或固定每路延迟：缺少统一采样时钟、采样率、可比时间戳和实测
  标定值，不能把接收/传输到达时间冒充传感器相位。

## 2026-08-16

- 继续复用既有 `zynq7020_bridge.xpr`、part `xc7z020clg400-1`、顶层 `board_top`，未创建第二份工程。
- 按根仓 `bridge_contract_v0.md` 把 record 从 240 B 改为 248 B，启用 `NRF1` magic、版本/type/长度、CRC16/CCITT-FALSE 和 reflected CRC32/IEEE 校验。
- block target/max 改为 66/132 条完整 record（16,368/32,736 B），BRAM 和 CSR 数据窗口同步扩为 32,800 B。
- `BLOCK_ACK_POLICY=1`：只有已 claim bank 且 ACK 等于 `block_sequence[15:0]` 才释放。
- 修复 one-cycle flush 与下一条 record 首字节同周期时可能丢失的问题；非法最大长度无边界时封错误块而不死锁。
- `tb_spi_record_parser.sv` 使用共享正/负 record；`tb_block_builder.sv` 对 560 B golden 逐字节比对并测两个 flush 边界；`tb_bram_pingpong.sv` 覆盖未 claim、错误、正确和重复 ACK，三项均通过。
- Vivado 2025.2 `check_syntax` 再次通过；日志 `artifacts/bridge-validation/20260816/zynq-check-syntax-final.log`。只出现全局 Board Store/空 BoardPart 环境警告，没有 RTL error；未综合、实现或生成 bitstream。
- 仍未填写 FPGA ID、XDC、PL clock、Bank 电压、nRF 物理 SPI 事务和 reset/sync 极性。

## 2026-07-20

- 固定使用已确认工程 `zynq7020_bridge/zynq7020_bridge.xpr`，未搜索或创建重复 Vivado 工程。
- 从 XPR 确认 part 为 `xc7z020clg400-1`，BoardPart 为空。
- 阅读并视觉复核 `zynq7020.docx`，据此实现纯 PL 四路 SPI 到 STM32 FMC 的第一版结构。
- 新增 clock/reset、SYNC、四路 SPI、记录解析、FIFO、调度器、block builder、A/B BRAM、FMC slave、CSR 和 IRQ RTL。
- 把未冻结协议量集中到 `rtl/common/protocol_defs.vh`，默认禁用 SPI Magic/CRC 和 BLOCK_ACK bank release。
- 新增 comment-only XDC 和引脚模板；因缺少原理图引脚、Bank 电压及 PL 时钟信息，没有把 XDC 加入 Vivado 工程。
- 新增 `project_files.tcl` 和 `update_project.tcl`，把源文件加入现有 XPR 并只运行 `check_syntax`。
- 修正 CSR 的 SYNC 掩码读回位置和 BLOCK_STATUS 拼接位宽。
- MCP 新增 ZYNQ target、Vivado inspect/audit/static syntax、独立 FMC map 和 `fpga.check_syntax`；默认目标继续保持 H723。
- 补齐 Xilinx Windows loader 必需的受限运行环境变量，任意用户环境变量仍不会透传。
- MCP unit tests 42/42 通过。
- Vivado operation `op_20260720T074649_b270c67ee0` 静态语法检查成功；项目审计成功；未运行综合、实现或 bitstream。

## 第一版交付边界

已完成的是可继续集成的 RTL 骨架、现有 XPR source registration、静态语法验证和接口文档。以下事项仍需外部输入后才能进入可上板版本：

- 原理图确认的全部引脚、IOSTANDARD、Bank 电压和 PL 时钟
- nRF SPI 命令/记录/Magic/CRC 与 DRDY 行为
- FPGA ID、协议版本和 BUILD 编码
- CSR/IRQ 位定义和 BLOCK_ACK 语义
- SYNC 延迟/脉宽、RESET 极性
- STM32 FMC 时序、NWAIT 配置和硬件总线验证
- 仿真 testbench、CDC/复位专项检查、综合资源评估、实现/时序收敛和上板联调

在上述输入冻结前，保持 `CONFIG_REQUIRED` 标记，不生成 bitstream。
