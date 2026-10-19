# 工程上手指南

## 1. 环境

- Vivado 2025.2
- XC7Z020CLG400-2
- 当前双通道 release

## 2. 硬件准备

使用本项目 `constraints/`、`WIRING.md` 和现有 F730 FMC 连接。

## 3. 获取和配置

```powershell
git clone https://github.com/YoungsenseSong/ZYNQ7020-4CH-SPI-FMC-Bridge.git
cd ZYNQ7020-4CH-SPI-FMC-Bridge
```

## 4. 编译和下载

在本项目目录运行 `scripts/build_dual_prototype.tcl`；已发布 bitstream 位于 `bitstream/dual_channel.bit`，下载前核对 SHA256。

## 5. 运行和观察

使用 `TEST_CORE.ps1` 做数字回归；实物使用 WCH/F730 终端入口并记录 CH0/CH1 统计。

## 6. 常见问题

| 现象 | 可能原因 | 排查方法 |
|---|---|---|
| 只有 CH0 | RX2 临时无线配置未恢复 | 核对 RX2 channel/prefix |
| WCH 静默 | FPGA DONE 丢失或桥接状态 fault | 先留现场读取 DONE/状态 |
