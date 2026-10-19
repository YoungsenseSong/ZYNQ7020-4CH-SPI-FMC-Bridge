# 双通道 FPGA + F730 + TX1/RX1 + TX2/RX2

本工程继承已通过单通道FMC的地址/数据采样修复和F730块标志兼容处理。CH0/CH1为两路独立SPI控制器与FIFO，记录按node_id=0/1汇聚，经同一FMC/F730/USB输出。

接线见WIRING.md。两套无线配置分别为channel40/prefix0x54和channel60/prefix0x64。两路物理采样同步方案及限制见PHYSICAL_TIME_ALIGNMENT.md。

## TX1 同源双接收演示

MC013/run09 已实际验证 TX1 同时由 RX1/RX2 接收，经两个独立 SPI 通道、FPGA/FMC/F730 到 USB。终端入口为 `SHOW_USB.cmd`，分别显示两路计数、真实采样值及 CRC/传输序号/同源载荷匹配；Ctrl+C 停止。也可 `SHOW_USB.cmd -Seconds 60` 限时采集。详细启动、归档及恢复说明见 `tools/dual_rx_demo/README.md`。

RX2 当前同收 TX1 使用临时运行参数，断电后恢复原 channel60；FPGA JTAG 配置也在断电后丢失，重新上电后需先加载现有双通道 bitstream 并重新配对。此演示不作为 TX2 发射、两个独立传感源或物理时间同步通过证据。

MC013/run10 已在用户将 TX1 换成 TX2、其它接线保持不变的条件下复测：TX2 本地 `frames_ok/rf_ok` 持续增长，但 RX1/RX2 没有实时 RADIO/SPI 增量，USB 60 秒无有效块；TX2 完整通路未通过。详细原始日志和恢复记录见 `../../diagnostics/MC013/run10/RESULTS.md`。

## 构建

    vivado -mode batch -source scripts/build_dual_prototype.tcl
    ./BUILD_F730.ps1
    ./nrf/BUILD_NRF.ps1 -Target rx -Lane 1 -Pristine
    ./nrf/BUILD_NRF.ps1 -Target rx -Lane 2 -Pristine
    ./nrf/BUILD_NRF.ps1 -Target tx -Lane 1 -Pristine
    ./nrf/BUILD_NRF.ps1 -Target tx -Lane 2 -Pristine

同一个Target的两个Lane顺序构建，避免共享SDK连接目录冲突。SDK与工具默认路径在脚本参数中可修改。FLASH_NRF.ps1需要明确Target、Lane及ProbeUid；不自动猜测第二套探针。

## 验证

TEST_CORE.ps1覆盖FIFO、复用、CRC隔离及块所有权；TEST_FMC.ps1从真实复用总线模型读出两路记录，验证早期NWE/地址切换、身份、ACK及ARM不误报物理锁定；独立Python解析器再校验输出块CRC和每路记录身份。

本轮不下载双通道到现有硬件。构建成功、RTL执行、单通道已板测和双通道实物验证是不同状态，最终记录在../../diagnostics/MC012/RESULTS.md。

2026-10-15接续MC013：用户已授权两路实物链路验收，时间对齐暂不验收。逐通道接收入口为 `python tools/accept_dual_cdc.py --port COM6 --seconds 60 --output <新证据目录>`；要求两路均有真实MEMS记录、CRC/USB/block及每路transport连续，并分别报告RF缺口和最长停流。run10 已完成 TX2 换接复测，当前未得到 TX2→RX→USB 数据；MC012未下载是历史状态，不是本轮禁止下载。

bitstream/dual_channel.bit与dual_channel.ltx为本轮实际综合/实现产物；capture_fpga.tcl是下载入口。FLASH_F730.py仅接受已保存的当前单通道完整Flash作为升级起点，未知镜像拒绝覆盖，下载失败尝试完整读回回滚。nrf/images/tx1_*、tx2_*、rx1、rx2为分别构建的候选，不以旧CH0镜像冒充第二路版本。

自动审批拒绝了旧nrf54l15_*基线镜像的清理，这些文件暂留但下载脚本不引用，当前工程包也排除它们。只使用带tx1/tx2/rx1/rx2名称的新镜像。

当前V1 source_time缺失，因此SYNC_LOCKED保持0；RX接收逻辑起点只作诊断。不能用这里的双通道传输数据宣称两颗IIM已同时采样。F730本身不需要双路专用数据格式，块头四路计数和每条node_id已有支持；后续物理同步V2需显式升级源帧和记录格式。
