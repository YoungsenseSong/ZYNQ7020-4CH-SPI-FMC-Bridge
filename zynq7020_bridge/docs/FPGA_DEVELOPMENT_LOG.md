# FPGA v1 开发日志

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
