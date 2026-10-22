# Program the board and/or read the status VIO over JTAG (Vivado batch mode).
#
#   vivado -mode batch -source board.tcl -tclargs <project_dir> program
#   vivado -mode batch -source board.tcl -tclargs <project_dir> status [reads]
#
# Uses <project_dir>/hog_detect.bit and .ltx written by build.tcl. Status
# prints every VIO probe as name=value (unsigned), <reads> times (default 2),
# one second apart.

set proj_dir [file normalize [lindex $argv 0]]
set action   [lindex $argv 1]
set reads    [expr {[llength $argv] > 2 ? [lindex $argv 2] : 2}]

open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices xc7z020*] 0]
current_hw_device $dev
set_property PROBES.FILE $proj_dir/hog_detect.ltx $dev

if {$action eq "program"} {
    set_property PROGRAM.FILE $proj_dir/hog_detect.bit $dev
    program_hw_devices $dev
    after 2000
}
refresh_hw_device $dev

set vio [lindex [get_hw_vios -of_objects $dev] 0]
set probes [lsort [get_hw_probes -of_objects $vio]]
foreach p $probes { set_property INPUT_VALUE_RADIX UNSIGNED $p }
for {set n 1} {$n <= $reads} {incr n} {
    refresh_hw_vio $vio
    set line "STATUS $n:"
    foreach p $probes { append line " [get_property NAME $p]=[get_property INPUT_VALUE $p]" }
    puts $line
    after 1000
}
close_hw_target
disconnect_hw_server
