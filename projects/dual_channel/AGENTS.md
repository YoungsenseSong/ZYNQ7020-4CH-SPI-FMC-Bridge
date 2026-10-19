# 当前工程说明

继承仓库根目录 AGENTS.md。本工程目录按 src/rtl、constraints、sim、scripts、docs 和 esults 分层；板测结论必须与仿真、综合、实现和下载证据分开。

- 单通道：保持 FMC→F730 基线入口。
- 双通道：保持 CH0/CH1 两路 SPI 与双接收演示边界。
- 四通道：保持四路数字原型和独立 CRC 回归边界。
