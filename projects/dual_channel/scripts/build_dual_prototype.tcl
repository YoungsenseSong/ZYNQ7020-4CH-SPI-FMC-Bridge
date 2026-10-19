set root [file normalize [file join [file dirname [info script]] ..]]
set out [file normalize [file join $root build_fpga]]
if {[llength $argv] > 0} {set out [file normalize [lindex $argv 0]]}
file mkdir $out
proc verilog_files {dir} {
    set result {}
    foreach path [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $path]} {
            set result [concat $result [verilog_files $path]]
        } elseif {[file extension $path] eq ".v"} {
            lappend result $path
        }
    }
    return $result
}
create_project -in_memory -part xc7z020clg400-2
set_property include_dirs [list $root/src/rtl/common] [current_fileset]
read_verilog [verilog_files $root/src/rtl]
read_xdc $root/constraints/prototype_zynq7020_f730_dual.xdc
synth_design -top prototype_dual_channel_top -part xc7z020clg400-2
foreach port [get_ports] {
    if {[get_property PACKAGE_PIN $port] eq ""} {error "UNASSIGNED_PORT $port"}
}
create_debug_core prototype_ila ila
set_property C_DATA_DEPTH 4096 [get_debug_cores prototype_ila]
set_property C_ADV_TRIGGER true [get_debug_cores prototype_ila]
set_property port_width 288 [get_debug_ports prototype_ila/probe0]
connect_debug_port prototype_ila/clk [get_nets pl_clk_IBUF_BUFG]
set ordered {}
for {set bit 0} {$bit < 288} {incr bit} {
    set net [get_nets -quiet [format {ila_probe[%d]} $bit]]
    if {[llength $net] != 1} {error "MISSING_DEBUG_BIT $bit"}
    lappend ordered $net
}
connect_debug_port prototype_ila/probe0 $ordered
set_property C_CLK_INPUT_FREQ_HZ 50000000 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets pl_clk_IBUF_BUFG]
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file $out/timing.rpt
report_drc -file $out/drc.rpt
report_io -file $out/io.rpt
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} {
    error "TIMING_FAILED"
}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]] != 0} {
    error "DRC_ERRORS"
}
write_checkpoint -force $out/routed.dcp
write_debug_probes -force $out/dual_channel.ltx
write_bitstream -force $out/dual_channel.bit
puts "DUAL_BUILD_OK $out"
exit
