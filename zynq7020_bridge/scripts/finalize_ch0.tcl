# Re-check and package an already completed CH0 implementation.  This avoids
# rerunning place/route when only report or artifact packaging was interrupted.
set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ..]]
set report_dir [file join $project_root build ch0]
set bit_file [file join $project_root zynq7020_bridge.runs impl_1 ch0_test_top.bit]
set ltx_file [file join $report_dir ch0_test_top.ltx]
file mkdir $report_dir

open_project [file join $project_root zynq7020_bridge.xpr]
if {[get_property PART [current_project]] ne "xc7z020clg400-2"} {
    error "Unexpected part"
}
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {
    error "Implementation is not complete: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_io -file [file join $report_dir io.rpt]
report_clocks -file [file join $report_dir clocks.rpt]

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup_path] == 0 || [llength $hold_path] == 0} {
    error "No constrained timing path was found"
}
set wns [get_property SLACK [lindex $setup_path 0]]
set whs [get_property SLACK [lindex $hold_path 0]]
if {$wns < 0 || $whs < 0} {
    error "Timing failed: WNS=$wns WHS=$whs"
}
set error_drcs [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $error_drcs] != 0} {
    error "DRC error violations: $error_drcs"
}
if {![file exists $bit_file]} {
    error "Bitstream is missing: $bit_file"
}
write_debug_probes -force $ltx_file
if {![file exists $ltx_file]} {
    error "Debug probes are missing: $ltx_file"
}
set marked_nets [get_nets -hier -filter {MARK_DEBUG == 1}]

set summary [open [file join $report_dir build_summary.txt] w]
puts $summary "PART=[get_property PART [current_project]]"
puts $summary "TOP=[get_property top [get_filesets sources_1]]"
puts $summary "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
puts $summary "IMPL_STATUS=[get_property STATUS [get_runs impl_1]]"
puts $summary "WNS_NS=$wns"
puts $summary "WHS_NS=$whs"
puts $summary "DRC_ERROR_COUNT=[llength $error_drcs]"
puts $summary "MARK_DEBUG_NET_COUNT=[llength $marked_nets]"
puts $summary "BIT=$bit_file"
puts $summary "LTX=$ltx_file"
close $summary

puts "CH0_FINALIZE_OK"
puts "CH0_WNS_NS=$wns"
puts "CH0_WHS_NS=$whs"
puts "CH0_BIT=$bit_file"
puts "CH0_LTX=$ltx_file"
close_project
exit 0
