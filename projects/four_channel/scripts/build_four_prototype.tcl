set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set project_path [file join $root FPGA_four_channel_prototype.xpr]
set evidence [file normalize [file join $root .. evidence four_build]]
file mkdir $evidence
if {![file exists $project_path]} { error "Missing project. Run create_four_project.tcl first." }
open_project $project_path
if {[get_property PART [current_project]] ne "xc7z020clg400-2"} { error "Unexpected part" }
if {[get_property top [get_filesets sources_1]] ne "prototype_four_channel_top"} { error "Unexpected top" }
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} { error "Synthesis failed: [get_property STATUS [get_runs synth_1]]" }
open_run synth_1
set marked_nets [get_nets -hier -quiet -filter {MARK_DEBUG == 1}]
if {[llength $marked_nets] != 288} { error "Expected 288 MARK_DEBUG bits, got [llength $marked_nets]" }
if {[llength [get_debug_cores -quiet prototype_ila]] == 0} {
    create_debug_core prototype_ila ila
    set_property C_DATA_DEPTH 4096 [get_debug_cores prototype_ila]
    set_property C_ADV_TRIGGER true [get_debug_cores prototype_ila]
    set_property port_width 288 [get_debug_ports prototype_ila/probe0]
    set ila_clock [get_nets -hier -quiet -filter {NAME =~ *pl_clk_IBUF_BUFG*}]
    if {[llength $ila_clock] == 0} { error "Cannot locate ILA clock" }
    connect_debug_port prototype_ila/clk [lindex $ila_clock 0]
    connect_debug_port prototype_ila/probe0 $marked_nets
    save_constraints
}
set missing {}
foreach p {ch1_sclk ch1_mosi ch1_miso ch1_cs_n ch1_drdy ch1_sync_out ch1_reset_n ch2_sclk ch2_mosi ch2_miso ch2_cs_n ch2_drdy ch2_sync_out ch2_reset_n ch3_sclk ch3_mosi ch3_miso ch3_cs_n ch3_drdy ch3_sync_out ch3_reset_n} {
    if {[get_property PACKAGE_PIN [get_ports $p]] eq ""} { lappend missing $p }
}
if {[llength $missing] != 0} {
    set f [open [file join $evidence build_status.txt] w]
    puts $f "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
    puts $f "MARK_DEBUG_NET_COUNT=[llength $marked_nets]"
    puts $f "ILA=prototype_ila DEPTH=4096 PROBE_WIDTH=288"
    puts $f "PIN_FREEZE_REQUIRED=[join $missing {, }]"
    close $f
    close_design
    close_project
    error "CH1..CH3 package pins are not frozen; synth/ILA complete, bitstream intentionally withheld: $missing"
}
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} { error "Implementation failed: [get_property STATUS [get_runs impl_1]]" }
open_run impl_1
report_utilization -file [file join $evidence utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 -file [file join $evidence timing_summary.rpt]
report_drc -file [file join $evidence drc.rpt]
report_io -file [file join $evidence io.rpt]
set bit_file [file join $root FPGA_four_channel_prototype.runs impl_1 prototype_four_channel_top.bit]
if {![file exists $bit_file]} { error "Missing bitstream: $bit_file" }
set ltx_file [file join $root .. evidence four_build prototype_four_channel_top.ltx]
write_debug_probes -force $ltx_file
close_project
puts "MC008_FOUR_BUILD_OK"
exit 0
