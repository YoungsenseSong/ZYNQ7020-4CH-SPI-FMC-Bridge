# Standalone OOC resource measurement. No original XPR/constraints are changed.
# usage: vivado -mode batch -source this.tcl -tclargs <new-output> <transport|bridge|fmc|csr>
if {$argc != 2} { error "usage: <new-output> <transport|bridge|fmc|csr>" }
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file normalize [lindex $argv 0]]
set variant [lindex $argv 1]
if {[file exists $out]} { error "refusing to overwrite $out" }
file mkdir $out
set_part xc7z020clg400-2
set_property include_dirs [list [file join $root rtl common]] [current_fileset]
set sources [list rtl/common/cdc_sync.v rtl/spi/spi_record_parser.v \
    rtl/spi/spi_fixed_transaction_master.v rtl/spi/ch0_spi_controller.v \
    rtl/fifo/record_fifo_bram.v rtl/scheduler/four_channel_record_mux.v \
    rtl/top/four_channel_capture_core.v rtl/block/block_builder.v \
    rtl/block/block_pingpong_bram.v rtl/top/four_channel_bridge_core.v]
set generic {}
switch $variant {
    transport { set top four_channel_capture_core; set generic [list FIFO_DEPTH=0] }
    bridge { set top four_channel_bridge_core }
    fmc { set top fmc_mux_slave; set sources [list rtl/common/cdc_sync.v rtl/fmc/fmc_mux_slave.v] }
    csr { set top csr_bank; set sources [list rtl/csr/csr_bank.v] }
    default { error "unknown variant $variant" }
}
foreach source $sources { read_verilog [file join $root $source] }
if {[llength $generic]} {
    synth_design -top $top -part xc7z020clg400-2 -mode out_of_context -generic $generic
} else {
    synth_design -top $top -part xc7z020clg400-2 -mode out_of_context
}
create_clock -name core_clk -period 20.000 [get_ports clk]
report_utilization -hierarchical -file [file join $out hierarchy.rpt]
report_utilization -file [file join $out utilization.rpt]
report_timing_summary -file [file join $out timing_summary.rpt]
report_drc -file [file join $out drc.rpt]
write_checkpoint [file join $out ${top}.dcp]
set stream [open [file join $out summary.txt] w]
puts $stream "TOP=$top"
puts $stream "VARIANT=$variant"
puts $stream "PART=xc7z020clg400-2"
puts $stream "SYNTHESIS=PASS"
puts $stream "EVIDENCE=OOC_ONLY_NOT_GOWIN"
puts $stream "IMPLEMENTATION=NOT_RUN"
puts $stream "BITSTREAM=NOT_GENERATED"
close $stream
puts "FOUR_CHANNEL_SYNTH_OK $variant"
exit 0
