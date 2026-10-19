# 双通道接线与版本

主机仍使用原 F730 蓝板和当前 ZYNQ7020 V3.9 底板/2V5 核心板。F730↔FPGA 的 16 位 FMC 接线完全沿用已通过版本。逻辑 CH0 对应 TX1/RX1，逻辑 CH1 对应 TX2/RX2。

| 功能 | RX1 引脚 | CH0 的 FPGA J4/球位 | RX2 引脚 | CH1 的 FPGA J4/球位 |
| --- | --- | --- | --- | --- |
| SCK | P2.01 | J4-12 / T9 | P2.01 | J4-17 / Y9 |
| MOSI | P2.04 | J4-4 / T5 | P2.04 | J4-18 / Y8 |
| MISO | P2.02 | J4-6 / U7 | P2.02 | J4-19 / W10 |
| CS_N | P2.05 | J4-8 / V8 | P2.05 | J4-20 / W9 |
| DRDY | P1.10 | J4-10 / U8 | P1.10 | J4-21 / V11 |
| RX SYNC | P1.09 | J4-14 / V6 | P1.09 | J4-22 / V10 |
| RESET 输出 | 预留、不接 | J4-16 / Y6 | 预留、不接 | J4-23 / Y13 |
| GND | GND | J4-37 或 39 | GND | J4-37 或 39 |

CH1 来源：底板原理图第5页 J4-17..23 为 B13_L14_P/N、B13_L16_P/N、B13_L21_P/N、B13_L20_N；核心板原理图第6页分别对应 Y9/Y8、W10/W9、V11/V10、Y13，均 Bank13。设计使用 LVCMOS33，沿用当前 CH0 所在 Bank13。新接 RX2 时须与实物 VDDIO 电平一致。J4-38/40 是电源，不作信号。

这张表是本轮的 CH1 设计分配，不代表第二路已接线或实测。原 RX1 排线不用改。FPGA→RX SYNC 仍仅是接收侧时间捕获，不是 TX 传感器采样同步。

| 设备 | 无线配置 | 接收记录 node_id | 构建 |
| --- | --- | --- | --- |
| TX1 / RX1 | channel=40、pipe prefix=0x54 | 0 | BUILD_NRF.ps1 -Target tx/rx -Lane 1 |
| TX2 / RX2 | channel=60、pipe prefix=0x64 | 1 | BUILD_NRF.ps1 -Target tx/rx -Lane 2 |

不同频点和地址用于降低互相误收；不能保证无干扰，仍需两路同开时实测。RF V1 数据帧没有源 node_id，当前身份由成对 RF 配置及 RX 固定 node_id 赋予。
