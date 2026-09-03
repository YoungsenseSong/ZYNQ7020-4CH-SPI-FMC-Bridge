set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ..]]

set rtl_files [list \
    [file join $project_root rtl common cdc_sync.v] \
    [file join $project_root rtl common pulse_toggle.v] \
    [file join $project_root rtl common crc16.v] \
    [file join $project_root rtl common crc32.v] \
    [file join $project_root rtl clock reset_clock_mgr.v] \
    [file join $project_root rtl sync sync_pulse_gen.v] \
    [file join $project_root rtl spi spi_master_ch.v] \
    [file join $project_root rtl spi spi_fixed_transaction_master.v] \
    [file join $project_root rtl spi ch0_spi_controller.v] \
    [file join $project_root rtl spi spi_record_parser.v] \
    [file join $project_root rtl fifo channel_fifo_wrap.v] \
    [file join $project_root rtl alignment four_channel_record_aligner.v] \
    [file join $project_root rtl scheduler rr_watermark_scheduler.v] \
    [file join $project_root rtl block block_builder.v] \
    [file join $project_root rtl block bram_pingpong.v] \
    [file join $project_root rtl fmc fmc_mux_slave.v] \
    [file join $project_root rtl csr irq_ctrl.v] \
    [file join $project_root rtl csr csr_bank.v] \
    [file join $project_root rtl top board_top.v] \
    [file join $project_root rtl top ch0_test_top.v] \
]

set include_dirs [list [file join $project_root rtl common]]

set constraint_files [list \
    [file join $project_root constraints ch0_test.xdc] \
]
