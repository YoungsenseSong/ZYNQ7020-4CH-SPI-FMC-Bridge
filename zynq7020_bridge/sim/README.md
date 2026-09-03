# 协议 RTL 仿真

四个 testbench 中，协议 parser/block builder 使用根仓同一份 `protocol/golden/`，
不自行生成另一套期望值；四路对齐 testbench 直接构造已通过 parser 的记录流，覆盖
同 epoch/逻辑索引成组、未同步记录、旧索引和旧 epoch 淘汰。
在 `zynq7020_bridge` 目录执行：

```powershell
$iverilog = 'C:\Tools\iverilog\bin\iverilog.exe'
$vvp = 'C:\Tools\iverilog\bin\vvp.exe'
$golden = 'F:/OliverS/AI_Embedded/F730+FPGA/protocol/golden'

& $iverilog -g2012 -Wall -s tb_spi_record_parser `
  -o tb_spi_record_parser.vvp sim\tb_spi_record_parser.sv `
  rtl\spi\spi_record_parser.v
& $vvp tb_spi_record_parser.vvp "+GOLDEN_DIR=$golden"

& $iverilog -g2012 -Wall -s tb_block_builder `
  -o tb_block_builder.vvp sim\tb_block_builder.sv `
  rtl\block\block_builder.v
& $vvp tb_block_builder.vvp "+GOLDEN_DIR=$golden"

& $iverilog -g2012 -Wall -s tb_bram_pingpong `
  -o tb_bram_pingpong.vvp sim\tb_bram_pingpong.sv `
  rtl\block\bram_pingpong.v
& $vvp tb_bram_pingpong.vvp

& $iverilog -g2012 -Wall -s tb_four_channel_record_aligner `
  -o tb_four_channel_record_aligner.vvp `
  sim\tb_four_channel_record_aligner.sv `
  rtl\alignment\four_channel_record_aligner.v
& $vvp tb_four_channel_record_aligner.vvp

& $iverilog -g2012 -Wall -s tb_ch0_record_aligner `
  -o tb_ch0_record_aligner.vvp `
  sim\tb_ch0_record_aligner.sv `
  rtl\alignment\four_channel_record_aligner.v
& $vvp tb_ch0_record_aligner.vvp

& $iverilog -g2012 -Wall -I rtl\common -s tb_ch0_spi_controller `
  -o tb_ch0_spi_controller.vvp `
  sim\tb_ch0_spi_controller.sv `
  rtl\spi\ch0_spi_controller.v `
  rtl\spi\spi_fixed_transaction_master.v `
  rtl\spi\spi_record_parser.v
& $vvp tb_ch0_spi_controller.vvp
```

通过标记分别是 `TB_SPI_RECORD_PARSER_OK`、`TB_BLOCK_BUILDER_OK`、
`TB_BRAM_PINGPONG_OK`、`TB_FOUR_CHANNEL_RECORD_ALIGNER_OK`、
`TB_CH0_RECORD_ALIGNER_OK` 和 `TB_CH0_SPI_CONTROLLER_OK`。生成的 `.vvp`
不提交。本仿真不覆盖 nRF 物理 SPIS、FMC
引脚/时序、CDC、综合、实现或板级行为。
