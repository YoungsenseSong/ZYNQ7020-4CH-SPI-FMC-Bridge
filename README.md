# ZYNQ7020 FPGA Projects

This repository contains the current ZYNQ7020 FPGA project payloads under
`projects/`:

| Project | Entry | Status |
|---|---|---|
| Single-channel FMC | `projects/single_channel_fmc/` | Board-verified single-channel baseline |
| Dual-channel SPI/FMC | `projects/dual_channel/` | Digital project and same-source dual-receiver backend demo; TX2 RF path and physical sample sync remain open |
| Four-channel core | `projects/four_channel/` | RTL/simulation project; four-channel board acceptance is pending |

The older `releases/20261014/` packages are retained as historical release
inputs. `zynq7020_bridge/` remains the shared RTL/IP workspace and project
generator. Do not infer four-channel board readiness from RTL or synthesis
results.

# ZYNQ7020 团队开发交接版

先读 [HANDOFF.md](HANDOFF.md) 和 [验证摘要](HANDOFF_VALIDATION.md)。

工程目录为 `zynq7020_bridge/`，使用其现有 XPR，不另建工程。当前验证范围是 `ch0_test_top` 的 RTL 回归及 Vivado 构建，不是完整四路/FMC 系统。r8 恢复候选未集成，未新增板测结论。

共享测试数据来自独立 F730 仓的 `protocol/golden/`；开发时固定双方提交并按交接说明配置布局。Windows 构建目录需保持较短。
