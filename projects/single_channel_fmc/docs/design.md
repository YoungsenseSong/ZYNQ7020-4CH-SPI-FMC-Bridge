# 设计思路

## 1. 问题背景

将 nRF 接收端记录通过 FPGA SPI、缓存和块封装送入 F730 的 16 位复用 FMC，再由 USB CDC 输出到主机。

## 2. 总体架构

```text
nRF RX -> SPI master/parser -> record FIFO -> block builder -> FMC slave
                                                        -> F730 USB
```

## 3. 模块划分

| 模块 | 职责 | 输入 | 输出 | 时钟/复位 |
|---|---|---|---|---|
| SPI 控制器/解析器 | PEEK/COMMIT 与 CRC | nRF SPI | 完整 record | PL 时钟 |
| FIFO/块封装 | 缓冲和块所有权 | record | 块头/记录 | PL 时钟 |
| FMC 从机 | 地址/数据复用窗口 | F730 FMC | 块数据/CSR | PL 时钟/总线控制 |

## 4. 关键设计决策

- FMC 数据采样采用已板测修复版本。
- 记录、块和 transport CRC 分层保留。
- bitstream、约束和构建脚本一并发布。

## 5. 时序、CDC 和复位

外部 FMC 地址/数据窗口与内部 PL 时钟分开约束；FPGA 重新配置后需按 F730 工具执行复位。

## 6. 资源和功耗考虑

当前为 ZYNQ7020 PL 原型，资源和时序报告属于 Xilinx 实现结果，不直接外推到高云器件。

## 7. 风险与未决问题

- [ ] 新自研高云板的引脚和 Bank 迁移
- [ ] RF 缺口与物理采样同步
