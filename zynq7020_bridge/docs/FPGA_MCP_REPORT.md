# FPGA v1 MCP 验证报告

## 目标隔离

- MCP target：`zynq7020_bridge`
- 调用别名：`zynq7020`、`zynq-7020`、`zynq7020_bridge`
- artifact namespace：`artifacts/mcp/zynq7020`
- 未指定 `chip` 时默认目标仍为 `stm32h723zg`
- ZYNQ 使用独立 FMC map；未冻结的写操作全部保持 RO/禁用

## 自动测试

执行：

```text
.venv\Scripts\python.exe -m unittest discover -s tests -v
```

结果：42/42 通过。覆盖默认 H723、显式 F730、显式 ZYNQ7020 的隔离，ZYNQ 器件识别、Vivado 工具选择、Quartus 拒绝、独立 FMC map 和 MCP tool schema。

## Vivado 静态检查

最终成功 operation：`op_20260720T074649_b270c67ee0`

- Vivado：2025.2
- part：`xc7z020clg400-1`
- BoardPart：未设置
- top：`board_top`
- return code：0
- `check_syntax`：成功
- RTL/约束错误：0
- synthesis started：false
- implementation started：false
- bitstream started：false

成功 operation 的审计文件位于：

```text
F:\OliverS\AI_Embedded\stm32-fpga-mcp\artifacts\mcp\zynq7020\op_20260720T074649_b270c67ee0
```

其中包含 `operation.json`、`command.tcl`、`vivado.log`、`vivado.jou`、`messages.json`、`source_manifest.json`、`project_before.json` 和 `project_after.json`。

Vivado 报告 154 条环境警告：152 条来自全局 Board Store 中与本器件无关的 board part，2 条说明当前工程 BoardPart 为空。没有 RTL 或 XDC 警告。工程按已确认器件 part 工作，不据此猜测 BoardPart。

## 失败审计保留

- `op_20260720T065234_249738df79`：受限子进程环境缺少 Xilinx loader 所需的 `PROCESSOR_ARCHITECTURE`，Vivado 在 Tcl 前退出，XPR 未改变。
- `op_20260720T074403_844dc95363`：RTL `check_syntax` 已通过，但 Tcl 误用了不存在的 `save_project`；Vivado 已自动持久化 source registration，随后脚本修正为 `close_project`。

失败 operation 保留用于追踪，不作为成功构建产物。

## 结论边界

本报告只证明现有源文件能被 Vivado 2025.2 解析且工程身份匹配。因为没有真实 XDC、未综合、未实现、未做 timing/DRC，也未连接硬件，不能据此宣称工程可生成或下载 bitstream。
