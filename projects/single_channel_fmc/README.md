# ZYNQ7020 单通道 FMC 采集桥

当前成熟单通道 FPGA 工程，包含 Vivado 工程、RTL、XDC、Tcl 入口和板测 bitstream。F730/nRF 配对源代码分别维护在独立仓库。

- 类型：FPGA
- 状态：已验证
- 负责人：Oliver
- 器件：XC7Z020CLG400-2

## 工程入口

- 设计思路：[docs/design.md](docs/design.md)
- 工程指标：[docs/spec.md](docs/spec.md)
- 上手指南：[docs/getting-started.md](docs/getting-started.md)
- 验证记录：[docs/verification.md](docs/verification.md)
- 改进记录：[docs/changes/](docs/changes/)
- Vivado 工程：[fpga/FPGA_single_channel.xpr](fpga/FPGA_single_channel.xpr)
- FPGA RTL：[fpga/src/rtl/](fpga/src/rtl/)
- 管脚约束：[fpga/constraints/board.xdc](fpga/constraints/board.xdc)
- 构建/下载入口：[BUILD_FPGA.tcl](BUILD_FPGA.tcl)、[capture_fpga.tcl](capture_fpga.tcl)

## 版本里程碑

| 版本 | 日期 | 内容 | 状态 |
|---|---|---|---|
| v0.1 | 2026-10-19 | 发布单通道 FMC 工程 | 已验证 |
