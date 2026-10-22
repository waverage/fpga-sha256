# Program the board and/or read the status VIO over JTAG (Vivado batch mode).
#
#   vivado -mode batch -source board.tcl -tclargs <project_dir> program
#   vivado -mode batch -source board.tcl -tclargs <project_dir> status
#
# Uses <project_dir>/hdmi_filter.bit and .ltx written by build.tcl.

set proj_dir [file normalize [lindex $argv 0]]
set action   [lindex $argv 1]

open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices xc7z020*] 0]
current_hw_device $dev
set_property PROBES.FILE $proj_dir/hdmi_filter.ltx $dev

if {$action eq "program"} {
    set_property PROGRAM.FILE $proj_dir/hdmi_filter.bit $dev
    program_hw_devices $dev
    after 2000
}
refresh_hw_device $dev

# Probe names are the net names Vivado kept for the VIO inputs.
set vio [lindex [get_hw_vios -of_objects $dev] 0]
proc probe {vio name} {
    set p [get_hw_probes -of_objects $vio -filter "NAME == $name"]
    set_property INPUT_VALUE_RADIX UNSIGNED $p
    return [get_property INPUT_VALUE $p]
}
foreach pass {1 2} {
    refresh_hw_vio $vio
    puts [format "STATUS pass %d: pll_locked=%s hdmi_in_locked=%s rotate=%s split=%s | %sx%s frames=%s | sw=%s btn=%s" \
        $pass [probe $vio clk_locked] [probe $vio lock_s] [probe $vio rot] [probe $vio split] \
        [probe $vio width] [probe $vio height] [probe $vio frames] \
        [probe $vio sw_IBUF] [probe $vio btn_s2]]
    after 1000
}
close_hw_target
disconnect_hw_server
