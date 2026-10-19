# Standalone, in-memory OOC synthesis. Does not edit/open/reset the board XPR.
# Run from a fresh evidence directory; argument 0 is a fresh output directory.
if {$argc != 1} { error "usage: -tclargs <new-output-directory>" }
set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ..]]
set out [file normalize [lindex $argv 0]]
if {[file exists $out]} { error "refusing to overwrite $out" }
file mkdir $out
set_part xc7z020clg400-2
set_property include_dirs [list [file join $project_root rtl common]] [current_fileset]
set source_files [list \
    rtl/common/cdc_sync.v rtl/spi/spi_record_parser.v \
    rtl/spi/spi_fixed_transaction_master.v rtl/spi/ch0_spi_controller.v \
    rtl/scheduler/two_channel_record_mux.v rtl/top/two_channel_capture_core.v]
foreach source_file $source_files {
    read_verilog [file join $project_root $source_file]
}
synth_design -top two_channel_capture_core -part xc7z020clg400-2 -mode out_of_context
create_clock -name core_clk -period 20.000 [get_ports clk]
report_utilization -file [file join $out utilization.rpt]
report_timing_summary -file [file join $out timing_summary.rpt]
report_drc -file [file join $out drc.rpt]
write_checkpoint [file join $out two_channel_capture_core.dcp]
set report [open [file join $out summary.txt] w]
puts $report "TOP=two_channel_capture_core"
puts $report "PART=xc7z020clg400-2"
puts $report "SYNTHESIS=PASS"
puts $report "EVIDENCE=out_of_context_synthesis_only"
puts $report "IMPLEMENTATION=NOT_RUN"
puts $report "BITSTREAM=NOT_GENERATED_NO_CH1_PIN_ASSIGNMENT"
close $report
puts "TWO_CHANNEL_SYNTH_OK"
exit 0
