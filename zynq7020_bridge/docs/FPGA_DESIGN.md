# FPGA v1 设计说明

## 数据通路

```text
nRF[0..3] DRDY
      -> 四路独立 SPI 主机
      -> 记录捕获/可选 Magic 与 CRC 校验
      -> 四路 10-bit FIFO（data + last + error）
      -> 高水位优先的轮询调度器
      -> 64-byte header + payload 数据块构建器
      -> A/B ping-pong BRAM
      -> FMC 16-bit 复用总线 + CSR + IRQ
      -> STM32F730
```

第一版不使用 ZYNQ PS、DDR 或 Linux。`pl_clk` 直接作为内部时钟，外部低有效复位经过三级同步释放；实际时钟引脚和频率尚未确认。

## 四路 SPI

每个通道包含独立的 `spi_master_ch`、`spi_record_parser` 和 `channel_fifo_wrap`。当系统已启动、DRDY 有效、SPI/解析器空闲且 FIFO 未到高水位时开始一次传输。每次事务先发送一个 8-bit 命令，再读取固定长度记录。

当前默认值仅用于保持结构可检查：命令 `0x00`、记录 240 字节、`sclk_divider=6`、超时 1,000,000 个 PL 周期；Magic 和记录 CRC 校验默认关闭。这些数值均不代表三端协议已经冻结。

解析器先缓存完整记录，只有校验通过才向 FIFO 输出，避免把半条坏记录写入数据块。每路 FIFO 默认深度 16 Ki 项，高水位 14 Ki 项。

## 调度器

调度器只在记录边界切换通道，避免一条记录在数据块中被拆散。普通情况下按轮询顺序选择；任何 FIFO 达到高水位后，只在高水位集合中优先调度。输出携带通道号、记录结束和错误标记。

## 数据块构建

构建器申请一个 FREE bank 后写 payload，再回填 64 字节小端块头。默认目标 payload 为 16 KiB，最大 32 KiB；达到目标后等待记录边界封块，达到上限、STOP flush 或边界超时也会封块。

块头包含 `FPB1`、版本、块序号、SYNC epoch、payload 长度、通道掩码、首末 FPGA tick、各通道记录数、flags 和 payload CRC32。详细字节布局见 `FPGA_REGISTER_MAP.md`。

## 双缓冲所有权

每个 bank 的实现状态为：

```text
FREE -> FILLING -> READY -> MCU_READING -> FREE
```

首次读取数据窗口会把 READY bank 标记为 MCU_READING。`BLOCK_ACK_POLICY=0` 时 ACK 写入不会释放 bank，这是当前安全默认值；ACK 编码冻结后可选按低 16 位 block sequence 校验释放，或显式无条件释放策略。

## FMC 与 CSR

`fmc_mux_slave` 在 NADV 有效期锁存 16-bit word address，并转换为内部 byte offset。读事务使用 NWAIT 等待 CSR/BRAM 返回，写事务在 NWE 有效期采样数据。该结构仅通过 HDL 静态语法检查；必须用 STM32 FMC 时序和真实 PL 时钟约束后才能判断硬件时序是否成立。

IRQ 状态为粘滞位，`IRQ_STATUS` 按 W1C 清除；`IRQ_MASK` 复位为 0，因此复位后不会直接拉高外部 IRQ。
