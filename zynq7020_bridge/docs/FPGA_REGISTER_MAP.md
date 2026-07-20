# FPGA v1 FMC 寄存器与数据格式

所有地址以下表的 byte offset 为准。STM32 FMC 16-bit word offset 等于 byte offset / 2，基地址暂按 `0x60000000`。

## CSR

| Byte offset | Word offset | 名称 | 访问 | v1 行为 |
|---:|---:|---|---|---|
| `0x0000` | `0x0000` | `FPGA_ID` | RO | 当前 `0x0000`，`CONFIG_REQUIRED` |
| `0x0002` | `0x0001` | `PROTO_VERSION` | RO | 当前 `0x0000`，`CONFIG_REQUIRED` |
| `0x0004` | `0x0002` | `BUILD_WORD` | RO | 当前 `0x0000`，`CONFIG_REQUIRED` |
| `0x0010` | `0x0008` | `GLOBAL_CTRL` | RW | provisional：bit0 enable、bit1 soft reset、bit2 start、bit3 stop |
| `0x0012` | `0x0009` | `GLOBAL_STATUS` | RO | provisional：bit0 idle、bit1 running、bit2 degraded、bit3 fatal |
| `0x0020` | `0x0010` | `IRQ_STATUS` | RW1C | 见下方 IRQ 位 |
| `0x0022` | `0x0011` | `IRQ_MASK` | RW | bit=1 允许对应状态驱动 IRQ；复位为 0 |
| `0x0030` | `0x0018` | `SYNC_CTRL` | RW | bits[3:0] mask、bit8 arm pulse、bit9 fire pulse |
| `0x0032` | `0x0019` | `SYNC_STATUS` | RO | bits[3:0] locked/ready mask、bit8 armed |
| `0x0040` | `0x0020` | `BLOCK_STATUS` | RO | bit0 ready、bit1 bank、bits[4:2] owner0、bits[7:5] owner1 |
| `0x0042` | `0x0021` | `BLOCK_LEN` | RO | header + payload 的有效字节数 |
| `0x0044` | `0x0022` | `BLOCK_ACK` | RW | ACK 语义未冻结；默认不释放 bank |

除已明确的数据布局外，控制位、状态位和 ACK 都属于 `CONFIG_REQUIRED`，STM32 正式固件不得依赖 provisional 值。

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

`0x1000..0x903F` 映射当前 READY/MCU_READING bank，共 16,416 个 16-bit word，即 64-byte header 加最大 32 KiB payload。首次数据窗口读取会 claim 当前 READY bank。

## 64-byte block header

多字节字段按 little-endian 存放。

| Byte range | 长度 | 字段 |
|---:|---:|---|
| `0..3` | 4 | Magic：`FPB1`，数值 `0x31425046` |
| `4..5` | 2 | protocol version，`CONFIG_REQUIRED` |
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

Flags 当前实现：bit0 输入错误标记、bit1 达到最大长度但不在记录边界、bit2 STOP flush 时不在记录边界、bit3 边界超时封块。CRC32 参数仍须三端冻结。
