set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir project_files.tcl]

set project_path [file normalize [file join $project_root zynq7020_bridge.xpr]]
if {![file exists $project_path]} {
    error "Confirmed Vivado project is missing: $project_path"
}

open_project $project_path
set_property PART xc7z020clg400-2 [current_project]
set detected_part [get_property PART [current_project]]
set detected_board_part [get_property BOARD_PART [current_project]]
puts "MCP_PROJECT_PATH=$project_path"
puts "MCP_PART=$detected_part"
puts "MCP_BOARD_PART=$detected_board_part"

foreach source_file $rtl_files {
    if {![file exists $source_file]} {
        close_project
        error "Required RTL source is missing: $source_file"
    }
    if {[llength [get_files -quiet $source_file]] == 0} {
        add_files -norecurse -fileset sources_1 $source_file
    }
}

foreach constraint_file $constraint_files {
    if {![file exists $constraint_file]} {
        close_project
        error "Configured XDC is missing: $constraint_file"
    }
    if {[llength [get_files -quiet $constraint_file]] == 0} {
        add_files -norecurse -fileset constrs_1 $constraint_file
    }
}

set_property include_dirs $include_dirs [get_filesets sources_1]
set_property top ch0_test_top [get_filesets sources_1]
update_compile_order -fileset sources_1

set syntax_ok 1
if {[catch {check_syntax -fileset sources_1} syntax_result]} {
    puts "MCP_CHECK_SYNTAX_UNAVAILABLE_OR_FAILED=$syntax_result"
    set syntax_ok 0
} else {
    puts "MCP_CHECK_SYNTAX_RESULT=$syntax_result"
}

# Vivado project-mode mutations above are persisted directly in the existing
# XPR. There is no save_project command; save_project_as would create/overwrite
# a project copy and is intentionally not used here.
close_project

if {!$syntax_ok} {
    exit 3
}
exit 0
