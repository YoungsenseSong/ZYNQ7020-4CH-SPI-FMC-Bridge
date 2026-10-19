# 工程上手指南

## 1. 环境

- Vivado 2025.2
- XC7Z020CLG400-2
- STM32F730 FMC 板

## 2. 硬件准备

使用本项目 `fpga/constraints/board.xdc` 和板级接线，先确认 FPGA DONE、FMC 共地和 USB。

## 3. 获取和配置

```powershell
git clone https://github.com/YoungsenseSong/ZYNQ7020-4CH-SPI-FMC-Bridge.git
cd ZYNQ7020-4CH-SPI-FMC-Bridge
```

## 4. 编译和下载

从本项目目录运行 `BUILD_FPGA.tcl` 或 `CREATE_FPGA.tcl`；下载使用 `capture_fpga.tcl`。

## 5. 运行和观察

按 F730 工具采集 USB CDC，记录块/记录 CRC 和 transport 序号。

## 6. 常见问题

| 现象 | 可能原因 | 排查方法 |
|---|---|---|
| USB 无数据 | FPGA 未配置或 F730 状态未复位 | 检查 DONE/ILA，随后复位 F730 |
| FMC 读错 | 总线窗口或排线问题 | 先执行无等待 FMC 模式测试 |
