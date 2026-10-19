# MC004 四通道数字核心

默认入口`four_channel_bridge_core`；只需要记录流时用`four_channel_capture_core`。未替换现有CH0 XPR/板级顶层，不包含UG324物理管脚、WCH完整总线顶层或无线共同采样时基。

## 接口

- 输入`clk`默认50MHz，`reset_n`异步有效、由外层同步释放；复位必须至少跨一个clk上升沿，以清除新FIFO的同步复位指针/状态。四路`spi_drdy`在内部同步；每路MISO由原SPI事务主机采样。
- 每路`spi_sclk/mosi/cs_n/sync_out`；默认掩码1111。SYNC是原接收端ARM后的协议脉冲，不是MEMS共同采样时钟。
- capture输出字节ready/valid、last与2位通道索引。所有者整条记录锁定，直到last握手后轮询。记录流可有间断，来源必须最终输出完整record，任意中途截断来源不会自动修复。
- 每通道32位计数以`[ch*32 +: 32]`读取。`fifo_levels[ch*16 +:16]`包括RAM中数据和1项预取；`fifo_blocked_cycles`仅代表持有有效字节时的反压周期。
- bridge的`host_read_request/bank/word_address`由同一clk域产生；在请求的时钟沿后读响应valid/data有效，一个word为小端16位。主机先观察ready元信息，claim对应bank，读完后ACK序号低16位；claim与ACK使用不同周期。
- 地址必须小于`BLOCK_BYTES/2`。读无效地址返回0；主机不得靠非法/无效读取判断块内容。复位后RAM不清零，所有权与有效标记清零使旧内容不可交付。
- `block_ready`优先表示两块中较旧的一块，包含已claim但未ACK的块；每次claim/ACK仅针对元信息对应的bank。单消费者顺序处理；不要同时claim两块后绕序ACK。
- `flush`只请求封装层完成当前块；不是清空FIFO或回滚nRF提交。

## 默认参数

四路SCLK=1MHz；A/B与B→下一A间隔各250,000clk。每路FIFO深度16,384、地址宽度14、高水位14,336；另有1项预取。FIFO_DEPTH=0可旁路，综合资源测量用此选项。

共享块容量2×32,800字节，默认payload目标16,368、最大32,736，每条record248字节，块头64字节；超时2,000,000clk。修改FIFO深度须同时匹配地址宽度/高水位；块参数须为整record且总容量足够。参数错误由仿真initial检查报告。

记录/块线上格式维持现有v0定义。sync_epoch固定1继承当前ARM；接收侧64位fpga_tick只表示封块路径时间，不能当作源样本采样时刻。错误累计后`degraded`置真直至复位；FIFO阻塞不自动表示数据已丢失。

原控制器在成功COMMIT后才输出数据，本轮未改变它；因而全局复位/长期主控停读可能丢失已经从nRF提交的数据，不能据有限仿真声明端到端无损。

## 验证与资源复跑

```
python scripts/test_four_channel.py --out <全新证据目录> --iverilog <iverilog.exe> --vvp <vvp.exe>
vivado -mode batch -source scripts/synth_four_channel.tcl -tclargs <全新目录> bridge
```

13个RTL回归及独立字节/CRC检查已通过；Vivado OOC默认桥接14,177 LUT6、28,360 FF、48 RAMB36＋4 RAMB18、0 DSP。准确证据在工作区`artifacts/multichannel/MC004`，资源规划在`paper/manuscript/team/four_channel_fpga_requirements_20261008.md`。

没有Gowin执行、物理WCH适配、布局布线或四通道板测。三版代码ZIP单独整理，仅含代码、工程、约束和脚本，验证报告保留在工作区。

新FIFO地址指针已采用同步复位；OOC DRC仍报告旧命令FSM/仲裁状态到RAM使能的异步复位Warning（未屏蔽）及ZYNQ纯PL的PS7提示，无Error。板级轮次须复核复位/使能隔离，不把本轮综合当作完整物理DRC通过。
