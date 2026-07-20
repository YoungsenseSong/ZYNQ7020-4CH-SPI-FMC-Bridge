# ZYNQ7020 FMC Bridge FPGA v1

本目录是 STM32F730 与四路 nRF 数据采集端之间的第一版纯 PL 桥接工程。设计目标、数据块格式和寄存器布局来源于 [`zynq7020.docx`](../../zynq7020.docx)。工程复用已确认的 Vivado 项目 `zynq7020_bridge.xpr`，没有创建第二份工程。

## 当前状态

- 目标器件：`xc7z020clg400-1`
- 顶层：`board_top`
- 工具：Vivado 2025.2
- RTL：四路 SPI 主机、记录校验入口、独立 FIFO、轮询/高水位调度、64 字节块头、A/B 双缓冲、FMC 复用总线从机、CSR/IRQ
- 验证：Vivado `check_syntax` 已通过，MCP 项目审计已通过
- 未执行：综合、实现、时序分析、引脚 DRC、bitstream、上板测试
- 约束：当前 `constrs_1` 为空；`constraints/board_top.xdc` 仅说明缺项，不会被加入工程

## 目录

- `rtl/`：可综合 Verilog RTL
- `constraints/`：空约束说明与不可直接使用的引脚模板
- `scripts/project_files.tcl`：唯一 RTL 文件清单
- `scripts/update_project.tcl`：更新现有 XPR 并运行静态语法检查
- `docs/`：架构、接口、寄存器、MCP 报告和开发日志

## 安全验证方式

通过 MCP 调用时必须显式指定 `chip=zynq7020`：

```text
fpga.check_syntax(project="configured", chip="zynq7020")
```

不指定 `chip` 时 MCP 仍默认使用 H723。ZYNQ v1 的 MCP 会拒绝 `clean`、综合、实现和 bitstream 阶段。

## 上板前必须冻结

以下项目均以 `CONFIG_REQUIRED` 集中在 `rtl/common/protocol_defs.vh` 或约束模板中，禁止根据经验猜测：

- FPGA ID、协议版本、BUILD 编码
- SPI 命令、记录长度、记录魔数和 SPI 模式/频率
- CRC16/CRC32 的多项式、初值、反射、字节序和终值
- CSR 控制/状态/IRQ 位定义及 BLOCK_ACK 编码
- SYNC 延迟、脉宽、RESET 极性与时序
- PL 时钟来源、频率、所有 PACKAGE_PIN、IOSTANDARD、Bank 电压
- STM32 FMC 建立/保持时间和 NWAIT 行为

在上述内容经原理图和三端协议评审冻结前，不应生成可下载 bitstream。
