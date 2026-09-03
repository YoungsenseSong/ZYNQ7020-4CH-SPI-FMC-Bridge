# ZYNQ7020 FMC Bridge FPGA v1

本目录是 STM32F730 与四路 nRF 数据采集端之间的第一版纯 PL 桥接工程。设计目标、数据块格式和寄存器布局来源于 [`zynq7020.docx`](../../zynq7020.docx)。工程复用已确认的 Vivado 项目 `zynq7020_bridge.xpr`，没有创建第二份工程。

## 当前状态

- 目标器件：实物与资料复核后的 `xc7z020clg400-2`
- 当前 CH0 测试顶层：`ch0_test_top`；四路/FMC 集成顶层仍为 `board_top`
- 工具：Vivado 2025.2
- RTL：四路 SPI 主机、记录校验入口、独立 FIFO、按 epoch/逻辑样本号成组的四路 record 对齐、64 字节块头、A/B 双缓冲、FMC 复用总线从机、CSR/IRQ
- 验证：共享 golden vector 回归通过；CH0 已完成综合、实现、时序、DRC、bitstream
  和实板 SPI 功能闭环
- CH0 最新证据：nRF `records=1957`、`pop_total=1956`、`crc_errors=0`；仍有
  `invalid_cmd=44`、`short_xfer=29`、`submit_errors=49` 和 queue overflow，持续无损
  吞吐未通过
- 约束：`constraints/ch0_test.xdc` 是已审核 J4/Bank13 CH0 约束；
  `constraints/board_top.xdc` 仍不是完整四路/FMC 产品约束

## 目录

- `rtl/`：可综合 Verilog RTL
- `constraints/`：空约束说明与不可直接使用的引脚模板
- `scripts/project_files.tcl`：唯一 RTL 文件清单
- `scripts/update_project.tcl`：更新现有 XPR 并运行静态语法检查
- `scripts/build_ch0.tcl`、`scripts/finalize_ch0.tcl`：CH0 测试镜像构建和签核
- `docs/`：架构、接口、寄存器、MCP 报告和开发日志

## 安全验证方式

通过 MCP 调用时必须显式指定 `chip=zynq7020`：

```text
fpga.check_syntax(project="configured", chip="zynq7020")
```

不指定 `chip` 时 MCP 仍默认使用 H723。ZYNQ v1 的 MCP 会拒绝 `clean`、综合、实现和 bitstream 阶段。

## CH0 已冻结与后续门控

CH0 已冻结 J4 引脚、Bank13/LVCMOS33、50 MHz PL 时钟、mode 0、MSB first、1 MHz、
8 B request/260 B response 双 CS、DRDY 高有效和 SYNC 上升沿。248 B record、CRC、
64 B block、协议版本和 ACK 也已冻结。以下项目仍不得根据经验猜测：

- FPGA ID、BUILD 编码
- CH1..CH3 的实际引脚、电气和四路并行调度
- RESET_N 的最终连接、极性与时序；CH0 首轮不接
- 双 5 ms bring-up 保护的最终替代方案和可持续 SCLK
- STM32 FMC 建立/保持时间和 NWAIT 行为

当前 CH0 bitstream 只用于 RX0 接口验证，不含 F730/FMC 验收。上述内容经评审前，
不得生成或宣称四路/FMC 产品镜像。

四路对齐仅落实 nRF V2 的逻辑同步语义：四条 record 必须具有同一 FPGA epoch 和
`logical_sample_index` 才输出。CH0 的真实 SPIS 和一次 SYNC capture 已运行，但仍没有
公共 TX/MEMS 采样时基；因此不能称为四路物理同时采样或分数相位补偿。

统一工作区入口、论文证据规则和迁移步骤见顶层 `../../README.md`、
`../../handoff.md` 与 `../../docs/WORKSPACE_MIGRATION.md`。迁移时保留本目录所属的
`zynq7020/.git/`；XPR 源文件采用 `$PPRDIR`，生成缓存必须在新路径重建。
