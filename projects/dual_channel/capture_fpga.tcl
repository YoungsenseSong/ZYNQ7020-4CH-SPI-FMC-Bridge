set root [file normalize [file dirname [info script]]]
set out [file normalize [lindex $argv 0]]
set ltx [file normalize $root/bitstream/dual_channel.ltx]
set bit [file normalize $root/bitstream/dual_channel.bit]
file mkdir $out
open_hw_manager
connect_hw_server -allow_non_jtag
set targets [get_hw_targets]
if {[llength $targets] != 1} {error "EXPECTED_ONE_JTAG_TARGET"}
open_hw_target [lindex $targets 0]
set d [lindex [get_hw_devices xc7z020*] 0]
if {$d eq ""} {error "NO_XC7Z020"}
set_property PROBES.FILE $ltx $d
if {[lindex $argv 1] eq "program"} {
    set_property PROGRAM.FILE $bit $d
    program_hw_devices $d
    after 5000
}
refresh_hw_device $d
set ila [lindex [get_hw_ilas -of_objects $d] 0]
proc save_capture {ila path} {
    global d
    wait_on_hw_ila -timeout 0.1667 $ila
    refresh_hw_device $d
    set state [get_property STATUS.CORE_STATUS $ila]
    for {set retry 0} {$state eq "IDLE" && $retry < 3} {incr retry} {
        after 100
        refresh_hw_device $d
        set state [get_property STATUS.CORE_STATUS $ila]
    }
    if {$state ne "FULL"} {error "CAPTURE_INCOMPLETE: $state"}
    set data [upload_hw_ila_data $ila]
    write_hw_ila_data -csv_file $path $data
}
run_hw_ila $ila -trigger_now
save_capture $ila $out/status.csv
close_hw_target [lindex $targets 0]
close_hw_manager
exit
