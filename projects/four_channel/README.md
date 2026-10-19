# ZYNQ7020 四通道采集核心

四通道数字核心和 Vivado 原型工程入口。当前 RTL、约束、仿真与 Tcl 随本项目一起发布。

- 类型：FPGA
- 状态：开发中
- 负责人：Oliver
- 当前结论：四路数字核心和回归可复建；四通道实物板测尚未完成。

## 工程入口

- 设计思路：[docs/design.md](docs/design.md)
- 工程指标：[docs/spec.md](docs/spec.md)
- 上手指南：[docs/getting-started.md](docs/getting-started.md)
- 验证记录：[docs/verification.md](docs/verification.md)
- 改进记录：[docs/changes/](docs/changes/)
- Vivado 工程：[FPGA_four_channel_prototype.xpr](FPGA_four_channel_prototype.xpr)
- RTL：[src/](src/)
- 约束：[constraints/](constraints/)
- 仿真：[sim/](sim/)
- 构建与回归：[scripts/](scripts/)

当前只交付数字核心和工程文件。CH1-CH3 的产品板球位尚未冻结，因此本项目没有可宣称板级通过的四通道 bitstream。
