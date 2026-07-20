`ifndef ZYNQ7020_PROTOCOL_DEFS_VH
`define ZYNQ7020_PROTOCOL_DEFS_VH

// Values marked CONFIG_REQUIRED must be replaced only after the matching
// nRF/STM32/FPGA protocol definition is frozen.
`define CONFIG_REQUIRED_FPGA_ID          1
`define CONFIG_REQUIRED_PROTO_VERSION    1
`define CONFIG_REQUIRED_SPI_COMMAND      1
`define CONFIG_REQUIRED_SPI_RECORD       1
`define CONFIG_REQUIRED_SPI_MAGIC        1
`define CONFIG_REQUIRED_CRC16             1
`define CONFIG_REQUIRED_CRC32             1
`define CONFIG_REQUIRED_CSR_BITS          1
`define CONFIG_REQUIRED_BLOCK_ACK         1

`define FPGA_ID_VALUE                    16'h0000
`define PROTO_VERSION_VALUE              16'h0000

`define CHANNEL_COUNT                    4
`define SPI_READ_COMMAND                 8'h00
`define SPI_RECORD_BYTES                 16'd240
`define SPI_SCLK_DIVIDER                 16'd6
`define SPI_TIMEOUT_CYCLES               32'd1000000
`define SPI_CHECK_MAGIC                  0
`define SPI_MAGIC_VALUE                  32'h00000000
`define SPI_CHECK_CRC                    0

`define CRC16_POLYNOMIAL                 16'h1021
`define CRC16_INITIAL                    16'hFFFF
`define CRC16_FINAL_XOR                  16'h0000
`define CRC32_POLYNOMIAL                 32'h04C11DB7
`define CRC32_INITIAL                    32'hFFFFFFFF
`define CRC32_FINAL_XOR                  32'hFFFFFFFF

`define BLOCK_MAGIC_VALUE                32'h31425046
`define BLOCK_HEADER_BYTES               16'd64
`define BLOCK_TARGET_PAYLOAD_BYTES       16'd16384
`define BLOCK_MAX_PAYLOAD_BYTES          16'd32768
`define BLOCK_TIMEOUT_CYCLES             32'd2000000

// Provisional bit positions. Software must not use these until the register
// bit allocation is frozen and CONFIG_REQUIRED_CSR_BITS is cleared.
`define GLOBAL_CTRL_ENABLE_BIT           0
`define GLOBAL_CTRL_SOFT_RESET_BIT       1
`define GLOBAL_CTRL_START_BIT            2
`define GLOBAL_CTRL_STOP_BIT             3
`define GLOBAL_STATUS_IDLE_BIT           0
`define GLOBAL_STATUS_RUNNING_BIT        1
`define GLOBAL_STATUS_DEGRADED_BIT       2
`define GLOBAL_STATUS_FATAL_BIT          3

// BLOCK_ACK remains disabled by default. Policy 0 records the write but does
// not release a bank; policy 1 treats the write value as block_seq[15:0].
`define BLOCK_ACK_POLICY                 0

`endif
