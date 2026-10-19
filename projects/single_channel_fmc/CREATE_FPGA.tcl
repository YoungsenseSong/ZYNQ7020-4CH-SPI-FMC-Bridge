set root [file normalize [file dirname [info script]]]
set source [file join $root fpga]
proc collect_verilog {dir} {
    set files {}
    foreach item [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $item]} {
            set files [concat $files [collect_verilog $item]]
        } elseif {[file extension $item] eq ".v" && ![string match "*_failed.v" $item]} {
            lappend files $item
        }
    }
    return $files
}
create_project FPGA_single_channel $source -part xc7z020clg400-2
set_property target_language Verilog [current_project]
set_property include_dirs [list [file join $source src rtl common]] [get_filesets sources_1]
add_files -norecurse [collect_verilog [file join $source src rtl]]
set_property top prototype_single_channel_top [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $source constraints board.xdc]
update_compile_order -fileset sources_1
close_project
exit 0
