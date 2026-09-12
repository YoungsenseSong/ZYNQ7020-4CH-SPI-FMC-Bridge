# FPGA v1 设计说明

## 数据通路

```text
nRF[0..3] DRDY
      -> 四路独立 SPI 主机
      -> 记录捕获/可选 Magic 与 CRC 校验
      -> 四路 10-bit FIFO（data + last + error）
      -> 四路 record 对齐器（epoch + logical_sample_index）
      -> 64-byte header + payload 数据块构建器
      -> A/B ping-pong BRAM
      -> FMC 16-bit 复用总线 + CSR + IRQ
      -> STM32F730
```

第一版不使用 ZYNQ PS、DDR 或 Linux。CH0 测试顶层使用板载 U18 50 MHz 时钟并由
正式 XDC 约束；四路/FMC `board_top` 的完整板级约束仍需单独验收。外部低有效复位
经过三级同步释放。

## 四路 SPI

每个通道包含独立的 `spi_master_ch`、`spi_record_parser` 和 `channel_fifo_wrap`。当系统已启动、DRDY 有效、SPI/解析器空闲且 FIFO 未到高水位时开始一次传输。每次事务先发送一个 8-bit 命令，再读取固定长度记录。

软件 record 数据面已冻结为固定 248 字节：40 B `NRF1` header、204 B RF frame 和 4 B payload CRC32。解析器强制检查 magic `0x3146524E`、版本 1、type 1、payload 长度 204、header CRC16/CCITT-FALSE 和反射 CRC32/IEEE，完整通过后才输出。

当前通用四路 `spi_master_ch` 仍是仿真用 raw-record 拉取：命令 `0x00`、
`sclk_divider=6` 和 1,000,000 PL 周期超时不代表 nRF 实板事务。CH0 板级验证必须使用
专用 `ch0_test_top`/`ch0_spi_controller`：8 B request 与 260 B response 分两个 CS
事务，mode 0、MSB first、1 MHz，A/B 和 B/next-A 都等待 5 ms，给当前 Zephyr SPIS
worker 留出 EasyDMA 重装时间。检测到坏 response 或 transaction timeout 时，额外发送
一次 260 B 全零恢复事务，把阻塞式从机状态机重新同步到 request phase 后再重试。
5 ms 与恢复冲洗只用于 bring-up；扩展四路或提高吞吐前，必须改成可持续的异步/双缓冲
SPIS 交接方案并重新实测。

解析器先缓存完整记录，只有校验通过才向 FIFO 输出，避免把半条坏记录写入数据块。每路 FIFO 默认深度 16 Ki 项，高水位 14 Ki 项。

## 四路逻辑时间对齐

`four_channel_record_aligner` 在每路 FIFO 后各缓存一条已经通过 CRC 的完整 248 B
record，并从 header 提取 `sync_epoch`、`logical_sample_index` 和状态标志。只有四路都带
`SYNCED`、epoch 与 FPGA 当前 epoch 一致且逻辑样本起点完全相同，才按通道
0、1、2、3 输出一组。未同步/DEGRADED、旧 epoch 和旧逻辑索引的记录会被显式淘汰并
按通道计数；不会复制样本、插零或静默修改 204 B RF payload。输出仍保持完整 record
边界，block 边界即使跨过四条一组，也可由 record 自带 epoch/index 在 F730/host 重组。

这一级完成的是 nRF V2 已定义的逻辑整数样本对齐，不是物理相位校正。四个 nRF 的
`rx_tick` 来自各自本地时钟，不能直接相减当作传感器采样相位；当前空中 V1 也没有公共
TX/MEMS 采样时钟或高分辨率采样时间戳。因此 RTL 不做分数采样延迟 FIR，也不写入未经
标定的固定延迟。后续只有在采样率、公共时基、每路标定延迟和滤波器系数冻结后，才能
在这一层之后增加整数/分数延迟补偿。

## 数据块构建

构建器申请一个 FREE bank 后写 payload，再回填 64 字节小端块头。目标固定为 66 条记录（16,368 B），最大 132 条（32,736 B），两者都是 248 B 的整数倍。目标、STOP flush 和 timeout 都等到 record 边界再封块；非法流在最大长度仍无边界时封为带 bit1 错误标志的坏块，避免永久反压，F730 会拒绝且不 ACK。

块头包含 `FPB1`、版本、块序号、SYNC epoch、payload 长度、通道掩码、首末 FPGA tick、各通道记录数、flags 和 payload CRC32。详细字节布局见 `FPGA_REGISTER_MAP.md`。

## 双缓冲所有权

每个 bank 的实现状态为：

```text
FREE -> FILLING -> READY -> MCU_READING -> FREE
```

首次读取数据窗口会把 READY bank 标记为 MCU_READING。当前 `BLOCK_ACK_POLICY=1`：只有写入值等于该 bank 的 `block_sequence[15:0]` 才释放；未 claim、错误、过期和重复 ACK 都不会释放其他 bank。该行为由 `tb_bram_pingpong.sv` 覆盖。

## FMC 与 CSR

`fmc_mux_slave` 在 NADV 有效期锁存 16-bit word address，并转换为内部 byte offset。读事务使用 NWAIT 等待 CSR/BRAM 返回，写事务在 NWE 有效期采样数据。该结构仅通过 HDL 静态语法检查；必须用 STM32 FMC 时序和真实 PL 时钟约束后才能判断硬件时序是否成立。

IRQ 状态为粘滞位，`IRQ_STATUS` 按 W1C 清除；`IRQ_MASK` 复位为 0，因此复位后不会直接拉高外部 IRQ。

## 2026-09-03 CH0 实板边界

nRF 修正 header CRC16 后，串口统计从零增长至 `records=1957`、`pop_total=1956`，且
`crc_errors=0`，说明 FPGA 已能读取合法 record 并通过 COMMIT 释放队首。当前仍有低比例
invalid/short 事务和 nRF submit 竞争，1 MHz 加双 5 ms 保护也导致 record queue 大量
overflow。设计下一步应先取得包含采样行的 ILA 导出，核对 FPGA `crc_ok_count` 和
`commit_ok_count`，再优化 SPIS buffer 交接和事务间隔；不能直接扩成四路。
