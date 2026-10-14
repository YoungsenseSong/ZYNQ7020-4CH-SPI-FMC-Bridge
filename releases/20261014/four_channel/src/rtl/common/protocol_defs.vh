`ifndef ZYNQ7020_PROTOCOL_DEFS_VH
`define ZYNQ7020_PROTOCOL_DEFS_VH

// Values marked CONFIG_REQUIRED must be replaced only after the matching
// nRF/STM32/FPGA protocol definition is frozen.
`define CONFIG_REQUIRED_FPGA_ID          1
`define CONFIG_REQUIRED_PROTO_VERSION    0
`define CONFIG_REQUIRED_SPI_COMMAND      1
`define CONFIG_REQUIRED_SPI_RECORD       0
`define CONFIG_REQUIRED_SPI_MAGIC        0
`define CONFIG_REQUIRED_CRC16            0
`define CONFIG_REQUIRED_CRC32            0
`define CONFIG_REQUIRED_CSR_BITS         0
`define CONFIG_REQUIRED_BLOCK_ACK        0

`define FPGA_ID_VALUE                    16'h0000
`define PROTO_VERSION_VALUE              16'h0001

`define CHANNEL_COUNT                    4
// The command byte and physical SPI transaction remain CONFIG_REQUIRED.
// The raw-record path below is simulation-only until the nRF SPIS backend,
// CPOL/CPHA, turnaround and maximum SCLK are frozen.
`define SPI_READ_COMMAND                 8'h00
`define SPI_RECORD_BYTES                 16'd248
`define SPI_SCLK_DIVIDER                 16'd6
`define SPI_TIMEOUT_CYCLES               32'd1000000
`define SPI_CHECK_MAGIC                  1
`define SPI_MAGIC_VALUE                  32'h3146524E
`define SPI_RECORD_VERSION               8'd1
`define SPI_RECORD_TYPE                  16'd1
`define SPI_RECORD_PAYLOAD_BYTES         16'd204
`define SPI_CHECK_CRC                    1

`define CRC16_POLYNOMIAL                 16'h1021
`define CRC16_INITIAL                    16'hFFFF
`define CRC16_FINAL_XOR                  16'h0000
// Reflected CRC-32/ISO-HDLC update polynomial (Zephyr crc32_ieee()).
`define CRC32_POLYNOMIAL                 32'hEDB88320
`define CRC32_INITIAL                    32'hFFFFFFFF
`define CRC32_FINAL_XOR                  32'hFFFFFFFF

`define BLOCK_MAGIC_VALUE                32'h31425046
`define BLOCK_HEADER_BYTES               16'd64
// Both limits are exact multiples of the fixed 248-byte record.
`define BLOCK_TARGET_PAYLOAD_BYTES       16'd16368
`define BLOCK_MAX_PAYLOAD_BYTES          16'd32736
`define BLOCK_TIMEOUT_CYCLES             32'd2000000

// Frozen v0 CSR bit positions.  Reserved bits read as zero and are ignored on
// write unless a register-specific rule says otherwise.
`define GLOBAL_CTRL_ENABLE_BIT           0
`define GLOBAL_CTRL_SOFT_RESET_BIT       1
`define GLOBAL_CTRL_START_BIT            2
`define GLOBAL_CTRL_STOP_BIT             3
`define GLOBAL_STATUS_IDLE_BIT           0
`define GLOBAL_STATUS_RUNNING_BIT        1
`define GLOBAL_STATUS_DEGRADED_BIT       2
`define GLOBAL_STATUS_FATAL_BIT          3

// Release only the MCU-claimed bank whose block_seq[15:0] matches the write.
`define BLOCK_ACK_POLICY                 1

`endif
