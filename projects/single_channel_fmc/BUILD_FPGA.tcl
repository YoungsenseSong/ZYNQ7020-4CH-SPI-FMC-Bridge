set root [file normalize [file dirname [info script]]]
set out $root/build_fpga_reproduce
file mkdir $out
proc verilog_files {dir} {
    set result {}
    foreach p [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $p]} {
            set result [concat $result [verilog_files $p]]
        } elseif {[file extension $p] eq ".v" && ![string match "*_failed.v" $p]} {
            lappend result $p
        }
    }
    return $result
}
create_project -in_memory -part xc7z020clg400-2
set_property include_dirs [list $root/fpga/src/rtl/common] [current_fileset]
read_verilog [verilog_files $root/fpga/src/rtl]
read_xdc $root/fpga/constraints/board.xdc
synth_design -top prototype_single_channel_top -part xc7z020clg400-2
create_debug_core prototype_ila ila
set_property C_DATA_DEPTH 4096 [get_debug_cores prototype_ila]
set_property C_ADV_TRIGGER true [get_debug_cores prototype_ila]
set_property port_width 448 [get_debug_ports prototype_ila/probe0]
connect_debug_port prototype_ila/clk [get_nets pl_clk_IBUF_BUFG]
set ordered {}
for {set n 0} {$n < 448} {incr n} {
    set net [get_nets -quiet [format {ila_probe[%d]} $n]]
    if {[llength $net] != 1} {error "MISSING_PROBE_BIT $n"}
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
set paths [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $paths] == 0} {error "NO_SETUP_TIMING_PATH"}
if {[get_property SLACK [lindex $paths 0]] < 0} {error "TIMING_FAILED"}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]] != 0} {error "DRC_ERRORS"}
write_checkpoint -force $out/routed.dcp
write_debug_probes -force $out/nrf_spi_debug.ltx
write_bitstream -force $out/nrf_spi_debug.bit
puts "REBUILD_OK $out"
exit
