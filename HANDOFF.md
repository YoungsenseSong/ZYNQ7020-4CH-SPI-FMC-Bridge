# ZYNQ7020 工程交接（R005/r1）

## 工程身份与用途
- 本机目录/Git 根：`F:/OliverS/MultiSensorResearch/F730+FPGA/zynq7020`，它是 F730 仓内的独立嵌套 Git 仓。
- HEAD `c81d1c53487c2468dd2175e1491b7194026ee1c7`，分支 `codex/zynq7020-v1`，上游 `origin/codex/zynq7020-v1`，本轮前后 clean。
- 用途：ZYNQ7020 PL 侧四路 SPI/记录校验/对齐/块缓存/FMC/CSR；当前可生成并验证的是 CH0 测试顶层 `ch0_test_top`，不是完整四路/FMC 产品顶层。

## 当前阶段与证据分层
- **源码可开发：是。** XPR、RTL、XDC、Tcl、testbench 和文档齐全；XPR 指向相对工程文件。
- **RTL 可测试：是。** 本轮从隔离副本用 Icarus Verilog 12.0 编译并运行 6 个 testbench，全部退出 0；golden vectors 来自 F730 仓 `protocol/golden/`。
- **本轮构建：CH0 通过。** Vivado 2025.2 在短路径隔离副本综合、实现、bitstream 成功，exit 0；part `xc7z020clg400-2`、top `ch0_test_top`、WNS 8.792 ns、DRC Error 0。bit SHA-256 `2fc4538dce9b1620f8eb75d54cbeda946612b0b0971504ff0a85e714592fb139`。
- 首次隔离构建因 Windows/Vivado debug-core 临时路径 161>146 字符失败，改用本轮目录内较短副本后通过；这是可移植性/路径长度风险，不是 RTL 修复。
- **已有板测证据：有限。** 生产文档记录 CH0 与 nRF 曾有 CRC/PEEK/COMMIT 功能闭环，但存在 invalid_cmd、short_xfer、submit_errors 和 queue overflow；不等于持续无损、四路/FMC 或 F730 联调通过。
- **r8 隔离候选：BLOCKED/HOLD。** 本轮没有集成；其两端构建不解除 DMA/CSN/身份化完成与板证据阻塞，禁止把它包装成稳定上板版。

## 环境依赖
- Vivado 2025.2（本机 SW Build 6299465 / IP Build 6300035），需要 Zynq-7000 器件支持/许可；目标 part 是已明确的 `xc7z020clg400-2`，BoardPart 为空，不猜板型。
- Icarus Verilog 12.0 + `vvp` 可做无板 RTL 回归。
- 跨仓测试依赖：F730 仓 `protocol/golden/`；发布时应带来源 commit/hash或复制获许可的最小 vectors 到明确测试包，不依赖本机 `../../` 偶然布局。
- 完整产品顶层还依赖经审核的 CH1..3/FMC 引脚、电压、时钟、RESET/NWAIT 条件；当前未齐。

## 从仓库开始开发
1. 克隆独立 ZYNQ 仓并记录 commit；安装 Vivado 2025.2 及 xc7z020 支持。
2. 在 `zynq7020_bridge/` 打开唯一 XPR `zynq7020_bridge.xpr`；不要新建第二工程。
3. 用 `scripts/update_project.tcl` 更新登记/语法；CH0 构建用 `scripts/build_ch0.tcl`。该脚本会 reset runs 并写工程目录，验证时必须在 disposable copy 或干净专用工作树运行。
4. 将 testbench 需要的 golden vectors 放在约定路径或通过 `+GOLDEN_DIR=` 传入；两个旧 testbench仍硬编码 `../../protocol/golden`，需保持兼容布局。
5. Windows 路径要短，避免 Vivado ILA/debug hub 的 146 字符临时路径上限。

## 构建与测试入口
- Vivado batch：`vivado -mode batch -nojournal -nolog -source zynq7020_bridge/scripts/build_ch0.tcl`。
- Testbench 命令模板见 `zynq7020_bridge/sim/README.md`；把 `iverilog`/`vvp` 与 golden 路径改成环境参数。
- 输出：`zynq7020_bridge.runs/impl_1/ch0_test_top.bit`、`build/ch0/ch0_test_top.ltx` 和报告，均为生成物，发布源码时默认排除；批准的发布镜像应单独建版本化资产/哈希清单。

## 烧录前条件
- Astra/用户批准 commit、bit/LTX 成对哈希及目标板 part；确认使用生产 CH0 基线，不是 r8 BLOCKED candidate。
- 逐项复核已冻结 CH0：J4/Bank13 LVCMOS33、50 MHz、mode 0、MSB first、1 MHz、双 CS、DRDY/SYNC；RESET_N 首轮不接。
- 当前 bit 仅用于 CH0 RX0 接口，不含 F730 FMC 验收。要进入四路/FMC 必须先完成真实 XDC/Bank/时钟/RESET/NWAIT 审核。
- 编程前留存旧 bit/LTX/哈希；板测需同步保存 nRF UART、ILA/逻分和失败日志。

## 回退
- bit 与 LTX 必须成对回退到记录哈希的版本；nRF 端同样回到匹配生产版本。
- 源码切回已知 commit，再从 clean、短路径副本重建；不把 `.runs/.cache/.Xil` 当源码或唯一证据。
- 任一 CSN/UNKNOWN/CRC/身份或时序异常即回到上一批准镜像，保留失败证据。

## 已知问题与首个建议任务
- `sim/README.md` 写死 `C:/Tools/iverilog`，两个 testbench 写死 `../../protocol/golden`；XPR XML还记录本机绝对 Path 属性。相对源注册可工作，但文档/测试入口需参数化。
- `board_top.xdc` 不是完整四路/FMC 产品约束；CH0 bit不能标为系统稳定版。
- Windows 长路径会令 debug core 生成失败；建议给发布构建入口增加短工作根检查/说明（本轮仅记录，未改生产）。
- 首个建议任务：将六项 RTL 回归包装成不依赖本机路径的脚本，并由 Astra决定是否发布最小 golden vectors/固定 F730 commit；随后再做批准的 CH0 板回归。


## 本次发布说明

本文件基于已冻结的 R005/r1 Opus 交付，由 Astra 核对清单和当前 Git 基线后整理。上述 HEAD 是被验证的源码基线，不是加入交接文档后的提交号。构建与仿真由 Opus 执行；Astra 本次不宣称独立重跑全部构建。仅发布现有开发分支和说明，不新增稳定版或板测通过声明。
