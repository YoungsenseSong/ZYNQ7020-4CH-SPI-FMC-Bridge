set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ..]]
set project_path [file join $project_root zynq7020_bridge.xpr]
set report_dir [file join $project_root build ch0]
file mkdir $report_dir

open_project $project_path
if {[get_property PART [current_project]] ne "xc7z020clg400-2"} {
    error "CH0 build refuses unexpected part: [get_property PART [current_project]]"
}
if {[get_property top [get_filesets sources_1]] ne "ch0_test_top"} {
    error "CH0 build refuses unexpected top: [get_property top [get_filesets sources_1]]"
}

reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} {
    error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}

open_run synth_1
set marked_nets [get_nets -hier -filter {MARK_DEBUG == 1}]
if {[llength $marked_nets] == 0} {
    error "No MARK_DEBUG nets survived synthesis"
}
if {[llength [get_debug_cores -quiet ch0_ila]] == 0} {
    set ila_clock [get_nets -quiet clk]
    if {[llength $ila_clock] != 1} {
        set ila_clock [get_nets -hier -quiet -filter {NAME =~ *clock_mgr/clk_out}]
    }
    if {[llength $ila_clock] != 1} {
        error "Expected one ILA clock net, got [llength $ila_clock]: $ila_clock"
    }
    create_debug_core ch0_ila ila
    set_property C_DATA_DEPTH 4096 [get_debug_cores ch0_ila]
    set_property C_ADV_TRIGGER true [get_debug_cores ch0_ila]
    set_property port_width [llength $marked_nets] [get_debug_ports ch0_ila/probe0]
    connect_debug_port ch0_ila/clk $ila_clock
    connect_debug_port ch0_ila/probe0 $marked_nets
    save_constraints
} else {
    puts "CH0_ILA_REUSED_FROM_CONSTRAINTS"
}
close_design

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {
    error "Implementation failed: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -max_paths 20 -file [file join $report_dir timing_summary.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_io -file [file join $report_dir io.rpt]
report_clocks -file [file join $report_dir clocks.rpt]

set timing_paths [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $timing_paths] == 0} {
    error "No constrained setup timing path was found"
}
set wns [get_property SLACK [lindex $timing_paths 0]]
if {$wns < 0} {
    error "Timing failed with WNS=$wns ns"
}
set error_drcs [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $error_drcs] != 0} {
    error "DRC has [llength $error_drcs] error violations: $error_drcs"
}

set bit_file [file join $project_root zynq7020_bridge.runs impl_1 ch0_test_top.bit]
if {$bit_file eq "" || ![file exists $bit_file]} {
    error "Expected implementation bitstream is missing: $bit_file"
}
set ltx_file [file join $report_dir ch0_test_top.ltx]
write_debug_probes -force $ltx_file

set summary [open [file join $report_dir build_summary.txt] w]
puts $summary "PART=[get_property PART [current_project]]"
puts $summary "TOP=[get_property top [get_filesets sources_1]]"
puts $summary "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
puts $summary "IMPL_STATUS=[get_property STATUS [get_runs impl_1]]"
puts $summary "WNS_NS=$wns"
puts $summary "DRC_ERROR_COUNT=[llength $error_drcs]"
puts $summary "MARK_DEBUG_NET_COUNT=[llength $marked_nets]"
puts $summary "BIT=$bit_file"
puts $summary "LTX=$ltx_file"
close $summary

puts "CH0_BUILD_OK"
puts "CH0_WNS_NS=$wns"
puts "CH0_BIT=$bit_file"
puts "CH0_LTX=$ltx_file"
close_project
exit 0
