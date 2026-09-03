# FPGA v1 FMC 寄存器与数据格式

所有地址以下表的 byte offset 为准。STM32 FMC 16-bit word offset 等于 byte offset / 2，基地址暂按 `0x60000000`。

## CSR

| Byte offset | Word offset | 名称 | 访问 | v1 行为 |
|---:|---:|---|---|---|
| `0x0000` | `0x0000` | `FPGA_ID` | RO | 当前 `0x0000`，`CONFIG_REQUIRED` |
| `0x0002` | `0x0001` | `PROTO_VERSION` | RO | `0x0001` |
| `0x0004` | `0x0002` | `BUILD_WORD` | RO | 当前 `0x0000`，`CONFIG_REQUIRED` |
| `0x0010` | `0x0008` | `GLOBAL_CTRL` | RW | provisional：bit0 enable、bit1 soft reset、bit2 start、bit3 stop |
| `0x0012` | `0x0009` | `GLOBAL_STATUS` | RO | provisional：bit0 idle、bit1 running、bit2 degraded、bit3 fatal |
| `0x0020` | `0x0010` | `IRQ_STATUS` | RW1C | 见下方 IRQ 位 |
| `0x0022` | `0x0011` | `IRQ_MASK` | RW | bit=1 允许对应状态驱动 IRQ；复位为 0 |
| `0x0030` | `0x0018` | `SYNC_CTRL` | RW | bits[3:0] mask、bit8 arm pulse、bit9 fire pulse |
| `0x0032` | `0x0019` | `SYNC_STATUS` | RO | bits[3:0] locked/ready mask、bit8 armed |
| `0x0040` | `0x0020` | `BLOCK_STATUS` | RO | bit0 ready、bit1 bank、bits[4:2] owner0、bits[7:5] owner1 |
| `0x0042` | `0x0021` | `BLOCK_LEN` | RO | header + payload 的有效字节数 |
| `0x0044` | `0x0022` | `BLOCK_ACK` | RW | 写当前 MCU_READING bank 的 `block_sequence[15:0]` 才释放 |
| `0x0050` | `0x0028` | `ALIGN_STATUS` | RO | bits[3:0] 各路已有完整 record；bit8 正在输出四路组 |
| `0x0052..0x0054` | `0x0029..0x002A` | `ALIGN_GROUP_COUNT` | RO | 已输出四路对齐组数，低字在前 |
| `0x0056..0x0058` | `0x002B..0x002C` | `ALIGN_ERROR_COUNT` | RO | 未同步、epoch/index 不一致或 record 边界错误次数 |
| `0x005A..0x005C` | `0x002D..0x002E` | `ALIGN_EPOCH` | RO | 最近完成组的 epoch，低字在前 |
| `0x0060..0x0066` | `0x0030..0x0033` | `ALIGN_INDEX` | RO | 最近完成组的 64-bit logical sample index，低字在前 |
| `0x0068..0x0076` | `0x0034..0x003B` | `ALIGN_DROP0..3` | RO | 每路淘汰 record 数；每路 32-bit，低字在前 |

v0 控制位、状态位、IRQ 和 ACK 布局已冻结；保留位读 0，未定义写入不产生动作。最终 `FPGA_ID`、BUILD 编码和板级 reset/时序仍为 `CONFIG_REQUIRED`。

对齐诊断寄存器为新增只读扩展，不改变已冻结地址。任一 `ALIGN_DROP` 或
`ALIGN_ERROR_COUNT` 非零会置 `GLOBAL_STATUS.degraded`。计数只说明 record 级逻辑错位，
不能作为四路传感器物理相位已经测得或补偿的证据。

## IRQ 位

| Bit | 事件 |
|---:|---|
| 0 | 新 block 进入 READY |
| 1 | SYNC 脉冲完成 |
| 2 | 保留 |
| 3 | SPI timeout 或记录解析错误 |
| 4 | 任一 FIFO 达到高水位 |
| 5 | fatal（第一版固定为 0） |
| 15:6 | 保留 |

## 通道状态窗口

`0x0100..0x013F` 按每通道 16 byte 分组。每组当前实现：

| 组内 byte offset | 字段 | 说明 |
|---:|---|---|
| `0x0` | FIFO level | 低 16 位 |
| `0x2` | FIFO drop count | 低 16 位 |
| `0x4` | good record count | 低 16 位 |
| `0x6` | parser error count | 低 16 位 |

`0x0400..0x04FF` 为命令/响应保留区，第一版尚未实现，读取返回 0。

## 数据窗口

`0x1000..0x901F` 映射当前 READY/MCU_READING bank，共 16,400 个 16-bit word，即 64-byte header 加最大 32,736 B payload。首次数据窗口读取会 claim 当前 READY bank。

## 64-byte block header

多字节字段按 little-endian 存放。

| Byte range | 长度 | 字段 |
|---:|---:|---|
| `0..3` | 4 | Magic：`FPB1`，数值 `0x31425046` |
| `4..5` | 2 | protocol version，固定 `1` |
| `6..7` | 2 | header bytes，固定 64 |
| `8..11` | 4 | block sequence |
| `12..15` | 4 | sync epoch |
| `16..19` | 4 | payload bytes |
| `20..23` | 4 | channel mask，低 4 位有效 |
| `24..31` | 8 | first FPGA tick |
| `32..39` | 8 | last FPGA tick |
| `40..55` | 16 | channel 0..3 record count，各 32 位 |
| `56..59` | 4 | flags |
| `60..63` | 4 | payload CRC32 |

Flags：bit0 输入错误、bit1 最大长度仍无记录边界、bit2 STOP flush 在记录中间到达、bit3 timeout flush；正常块低 4 位必须全为 0。payload CRC 使用 CRC-32/ISO-HDLC：reflected polynomial `0xEDB88320`、init/xorout 均 `0xFFFFFFFF`，覆盖 header 后全部 payload，小端存放。
