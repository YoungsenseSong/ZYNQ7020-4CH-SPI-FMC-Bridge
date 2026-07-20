# The first-version project already exists and is the sole authorized entry.
# This script intentionally refuses to create another XPR; it delegates to the
# idempotent update flow after confirming the existing project.
set script_dir [file dirname [file normalize [info script]]]
set project_path [file normalize [file join $script_dir .. zynq7020_bridge.xpr]]
if {![file exists $project_path]} {
    error "Do not create a duplicate project. Confirmed XPR is missing: $project_path"
}
source [file join $script_dir update_project.tcl]
