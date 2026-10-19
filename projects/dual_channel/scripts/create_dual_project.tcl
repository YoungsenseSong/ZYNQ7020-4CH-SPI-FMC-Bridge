set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set name FPGA_dual_channel_prototype
if {[file exists [file join $root ${name}.xpr]]} { error "project already exists: [file join $root ${name}.xpr]" }
proc collect_verilog {dir} {
    set files {}
    foreach item [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $item]} { set files [concat $files [collect_verilog $item]]
        } elseif {[string equal [file extension $item] ".v"]} { lappend files $item }
    }
    return $files
}
create_project $name $root -part xc7z020clg400-2
set_property target_language Verilog [current_project]
set_property include_dirs [list [file join $root src rtl common]] [get_filesets sources_1]
foreach file [collect_verilog [file join $root src rtl]] { add_files -norecurse $file }
set_property top prototype_dual_channel_top [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $root constraints prototype_zynq7020_f730_dual.xdc]
update_compile_order -fileset sources_1
close_project
exit 0
