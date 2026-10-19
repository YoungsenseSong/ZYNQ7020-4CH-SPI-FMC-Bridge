# 工程上手指南

## 1. 环境

- Vivado 2025.2
- XC7Z020CLG400-2 原型板

## 2. 硬件准备

四通道 release 当前只作为数字原型，不能按已有 CH0 管脚推断 CH1–CH3。

## 3. 获取和配置

```powershell
git clone https://github.com/YoungsenseSong/ZYNQ7020-4CH-SPI-FMC-Bridge.git
cd ZYNQ7020-4CH-SPI-FMC-Bridge
```

## 4. 编译和下载

在本项目目录使用 `scripts/build_four_prototype.tcl` 和 `create_four_project.tcl`。

## 5. 运行和观察

先运行 `scripts/TEST_CORE.ps1`，再保存 Vivado 综合/实现报告。没有冻结 CH1–CH3 球位前不生成产品 bitstream。

## 6. 常见问题

| 现象 | 可能原因 | 排查方法 |
|---|---|---|
| 无法 implementation | CH1–CH3 球位未冻结 | 先完成 Bank/IO/时钟表 |
| FIFO 资源异常 | RAM 推断不完整 | 查看目标综合 RAM 映射 |
