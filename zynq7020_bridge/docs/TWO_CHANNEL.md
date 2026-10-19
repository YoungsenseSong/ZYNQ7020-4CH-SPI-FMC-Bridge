# 两通道工程首版（MC002）

日期：2026-09-18。入口为`rtl/top/two_channel_capture_core.v`。这是已实现的两路SPI记录接入核心，供无板回归和后续板级集成；不是完整无线采样系统或可烧录板级顶层。

## 数据路径与取舍

```text
RX0 -- SPI v1 两段CS -- CH0控制器实例0 -- 完整记录缓存 --+
                                                       +-- 记录级轮询 -- ready/valid观测出口
RX1 -- SPI v1 两段CS -- CH0控制器实例1 -- 完整记录缓存 --+
```

首版明确采用两路独立SPI接收端这一数字接口拓扑。每个接收端沿用现有nRF v1 GET_INFO/GET_STATUS/ARM_SYNC/START_STREAM/PEEK/COMMIT协议，数据记录仍为248字节。两个控制器独立进行CRC校验和重试，通道0位于所有打包端口的低位；错误、COMMIT和交付计数按通道分别输出。正常数据路径关闭CH0验收版故意执行错误/重复COMMIT的诊断选项。

没有直接把`board_top`的通道掩码改为0011：它使用的`spi_master_ch`原始读取路径不同于现有CH0命令路径，且严格对齐器在缺一路时不能独立输出健康通道。首版保留原始记录和来源，先实现可观测的独立接入，跨通道成窗另行处理。

| 现有部件 | 本轮处理 |
| --- | --- |
| `ch0_spi_controller`、固定SPI事务引擎、记录parser | 原样复用两份，现有文件不改 |
| `cdc_sync` | 复用为两位DRDY同步器 |
| `two_channel_record_mux` | 新增；完整记录级轮询，先登记授权再输出valid，背压期间保持授权 |
| `four_channel_record_aligner` | 不接入新核心；原四路/CH0回归继续运行 |
| `board_top`、`ch0_test_top`、XPR、XDC | 不修改；新核心不具有板级管脚配置 |
| nRF、F730与共享协议 | 本轮只读；不更改线上格式，不把未完成FMC/USB当现成出口 |

## 输入输出契约

- `clk`：默认50 MHz。`reset_n`须由外层提供同步释放；不在核心内猜测板载时钟/复位电路。
- `spi_*[1:0]`：端口0/1，各自独立SCLK/MOSI/MISO/CS/DRDY。MISO沿用CH0采样路径；实际板级时序需约束和验证。
- `sync_out[1:0]`：两个控制器各自的接收端同步脉冲，**不是同时触发承诺**。两端初始化/重试时间可以不同。
- `record_data[7:0]`、`record_channel`、`record_valid`、`record_last`、`record_ready`：同一`clk`域。仅在valid与ready同高的上升沿接收一个字节，last标识248字节记录末尾。channel是物理SPI入口号，不能丢弃后仅拼接字节流。
- 同一记录期间不能切换channel；在valid且ready低时，数据、channel和last保持不变。首字节也受这一约束保护。两路都可用时按完整记录轮询；每完成一条记录有一个重新选择周期。
- `delivered_count`仅在最后一个字节握手时增加；`commit_ok_count`是在源端响应成功时增加。二者本就不是同一完成点。
- 新汇聚模块只接受已有控制器提供的、已验证且完整缓存的记录；它不是任意损坏/无last流的修复器。若任意替代上游在记录中途永久停顿，授权不会擅自转给另一路。当前控制器输出记录时不依赖SPI继续接收。
- 复位中断当前输出，计数清零；采集主机必须结束旧run并丢弃其未完成尾记录，再创建新run。该规则不表示跨复位无损或单端复位可自动恢复。

## 元数据与同步边界

原始头保留`node_id`、`transport_seq`、`sync_epoch`、`rx_tick`、`logical_sample_index`、`status_flags`及校验。`record_channel`是附带来源信息，不替换头内node_id，不重新计算/修改记录内容。

nRF当前`sync_manager`基于接收端捕获事件和后续BATCH_START重置逻辑索引；`rx_tick`为接收时刻。两个实例均ARM epoch=1，也不表示两传感器同一时刻采样。物理采样时基、跨通道配对、真正会话身份与单端重启识别仍须设计验证。本轮测试run标签由testbench/采集记录器提供，不是假装新增了线上的session_id字段。

## 粗预算（源码估算，非吞吐实测）

默认SPI=1 MHz，A请求8字节、B响应260字节，一条记录需PEEK与COMMIT两次命令，总计536字节，纯移位时间4.288 ms。每次命令含5 ms A→B及5 ms B→下一A等待，稳态两次命令约再增加20 ms。因此单路上界约41.17记录/s，即10.21 kB/s原始记录或8.40 kB/s的204字节载荷；尚未计CS保护、字节装载、parser、输出背压和错误恢复，实际更低。

两路SPI独立并行，粗略总上界约20.42 kB/s原始记录；扩四路理论约40.84 kB/s只是同条件外推，不能视作四路能力证明。不能用仿真加速参数替代生产时序。给定每路每秒记录数R，必须逐路核对服务能力；输入连续高于服务率时，有限缓存最终溢出。

每个现有控制器分配248字节记录缓存及parser的512字节声明数组，两路源码声明共1520字节，实际资源由综合报告确定。nRF当前CH0配置队列深度64，仅按原始记录折算是15872字节/接收端；内部对象及RAM占用不同，不把这个数当实际内存测量。缺乏实际采样配置时，本轮不承诺持续采样率。

## 可重跑验证

从工作区根运行（输出目录必须不存在）：

```powershell
python -B F730+FPGA/zynq7020/zynq7020_bridge/scripts/test_two_channel.py --out artifacts/multichannel/MC002/my_rtl_run
```

需要Python标准库及PATH中的Icarus `iverilog`/`vvp`，也可用`--iverilog`/`--vvp`指定路径。不会调用探针、串口或修改原始golden。脚本在新输出目录生成两个节点各4条合成记录，从冻结248字节记录派生头布局，使用Python标准库重算CRC；载荷用于数字路径检验，不代表真实传感器数据。

| 测试 | 覆盖 |
| --- | --- |
| `tb_two_channel_record_mux` | 首字节背压时另一通道到达；首/中/末字节背压；记录中途短暂valid间隙；记录不交织；一路空闲；同时连续输入的轮询界限；复位后新记录 |
| `tb_two_channel_capture_core` | 两个真实CH0控制器和实际SPI移位引擎连接数字从机；一路无数据时另一路至少完成2条；CH1一次载荷CRC错误、拒绝错误记录并重试；两路差异化载荷；下游背压；整体复位废弃在途run；32位序号ffffffff→0 |
| 原六项回归 | parser、block builder、BRAM pingpong、四路对齐、CH0对齐、CH0命令控制器 |
| 独立捕获检查 | Python从CSV重新组装16条/3968字节，核对每字节与头/载荷CRC；缺失、重复、错位会失败 |

新增集成测试使用5 MHz和缩短等待加速运行；旧CH0回归仍覆盖其默认1 MHz和5 ms间隔。模拟从机不模拟真实Zephyr调度、DMA生命周期、无线链路或电气故障。序号回绕只证明记录/命令值传递，没有增加通用乱序去重机制。

综合使用`scripts/synth_two_channel.tcl`，先运行上述编译/RTL回归检查语法，再在新的证据工作目录调用Vivado：

```powershell
# 从工作区根执行，日志和Vivado临时文件均留在新目录。
$mcRoot = (Get-Location).Path
$mcRun = Join-Path $mcRoot 'artifacts/multichannel/MC002/my_synth_run'
New-Item -ItemType Directory -Path $mcRun -ErrorAction Stop | Out-Null
Push-Location $mcRun
try {
    & vivado -mode batch -nojournal -nolog -source "$mcRoot/F730+FPGA/zynq7020/zynq7020_bridge/scripts/synth_two_channel.tcl" -tclargs "$mcRun/synth" *> console.log
    if ($LASTEXITCODE -ne 0) { throw 'Vivado synthesis failed; inspect console.log' }
} finally { Pop-Location }
```

脚本针对`xc7z020clg400-2`进行内存中out-of-context综合并保存DCP/报告，不打开或改变现有XPR，不生成另一XPR；50 MHz综合后时序报告仅作初步检查，没有CH1/FMC引脚约束、布局布线、IO时序或bitstream结论。

## 本轮证据入口与后续

本次最终RTL结果：`rtl_run02`八项通过，独立复核16条/3968字节。Vivado `vivado_run02` out-of-context综合退出0，LUT 6674（12.55%）、FF 13668（12.85%）、BRAM 0；综合后50 MHz内部路径WNS 15.274 ns，不能作为布局布线/IO时序验收。DRC为0 Error、1项PS7相关Warning；6个输入端与413个输出端缺少IO延时约束，符合核心尚未接板的边界。

必须保留的综合警告：既有parser/controller缓存出现Synth 8-7137（同优先级set/reset，提示潜在仿真差异）及8-4767（不能推断RAM，转为寄存器）。本轮未改旧模块，未做综合后功能等价验证；上板前需处理或验证这些警告，后续优先优化缓存推断。首次综合`vivado_run01`因脚本使用不支持的`read_verilog -include_dirs`参数失败，已改为fileset include_dirs并在run02通过，失败日志保留。

本轮工作区证据目录：`artifacts/multichannel/MC002/`，最终状态与精确日志路径以其中`result.md`为准。脚本的`summary.json`、`commands.json`、输入SHA-256和捕获CSV提供复现依据。既有r8/revision01仍BLOCKED/HOLD，不被本轮复用或解除。

进入实物阶段前需完成：两对无线节点/接收端配置及资源确认（当前复制相同配置不能自动形成两条隔离无线链路）、CH1实际引脚/Bank电压与时序、观测数据出口、源采样时基设计，以及成对镜像和停止条件。下一轮优先把这个核心接成可观测的两通道板级入口；器材未齐时可继续实现离线记录配对与质量标记。

已知继承限制：现有控制器先COMMIT后输出；成功释放后发生FPGA复位/响应不确定等情形仍可能丢失记录。汇聚公平性不解除该生命周期问题；永久下游背压不保证不溢出，不宣称exactly-once或持续无损。
