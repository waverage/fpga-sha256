# Build the HDMI filter bitstream from scratch (Vivado batch mode).
#
#   vivado -mode batch -source build.tcl -tclargs <project_dir> <digilent_vivado_library> [ip_only]
#
# <digilent_vivado_library> is a clone of github.com/Digilent/vivado-library
# (provides the dvi2rgb and rgb2dvi IP). The project directory is created or
# overwritten; keep it outside the repo. Output: <project_dir>/hdmi_filter.bit

set proj_dir [file normalize [lindex $argv 0]]
set dgl_lib  [file normalize [lindex $argv 1]]
set ip_only  [expr {[llength $argv] > 2 && [lindex $argv 2] eq "ip_only"}]
set here     [file dirname [file normalize [info script]]]

create_project -force hdmi_filter $proj_dir -part xc7z020clg400-1
set_property board_part digilentinc.com:arty-z7-20:part0:1.1 [current_project]
set_property target_language Verilog [current_project]
set_property ip_repo_paths [list $dgl_lib/ip] [current_project]
update_ip_catalog

# 125 MHz board clock -> 200 MHz (dvi2rgb IDELAY reference) and 100 MHz (control).
# A PLL, not an MMCM: the board clock and HDMI OUT share a clock region, and
# rgb2dvi needs that region's only MMCM for its dedicated BUFIO path.
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_gen
set_property -dict [list \
    CONFIG.PRIMITIVE {PLL} \
    CONFIG.PRIM_IN_FREQ {125.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.USE_RESET {false} \
] [get_ips clk_gen]

# HDMI receiver: 720p EDID, 74.25 MHz pixel clock is in range 2 (>= 60 MHz)
create_ip -name dvi2rgb -vendor digilentinc.com -library ip -module_name dvi_rx
set_property -dict [list \
    CONFIG.kEmulateDDC {true} \
    CONFIG.kEdidFileName {dgl_720p_cea.data} \
    CONFIG.kRstActiveHigh {true} \
    CONFIG.kClkRange {2} \
    CONFIG.kDebug {false} \
] [get_ips dvi_rx]

# HDMI transmitter, serial clock generated from the pixel clock
create_ip -name rgb2dvi -vendor digilentinc.com -library ip -module_name dvi_tx
set_property -dict [list \
    CONFIG.kGenerateSerialClk {true} \
    CONFIG.kClkPrimitive {MMCM} \
    CONFIG.kClkRange {2} \
    CONFIG.kRstActiveHigh {true} \
] [get_ips dvi_tx]

# Status readable over JTAG from the Vivado Hardware Manager
create_ip -name vio -vendor xilinx.com -library ip -module_name status_vio
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {5} \
    CONFIG.C_NUM_PROBE_OUT {0} \
    CONFIG.C_EN_PROBE_IN_ACTIVITY {0} \
    CONFIG.C_PROBE_IN0_WIDTH {4} \
    CONFIG.C_PROBE_IN1_WIDTH {12} \
    CONFIG.C_PROBE_IN2_WIDTH {12} \
    CONFIG.C_PROBE_IN3_WIDTH {16} \
    CONFIG.C_PROBE_IN4_WIDTH {4} \
] [get_ips status_vio]

generate_target {instantiation_template synthesis} [get_ips]
if {$ip_only} { exit }

add_files [glob $here/hdl/*.v]
add_files -fileset constrs_1 $here/constraints/hdmi_filter.xdc
add_files -fileset sim_1 [glob $here/sim/*.v]
set_property top hdmi_filter_top [current_fileset]
set_property top video_filter_tb [get_filesets sim_1]

launch_runs synth_1 -jobs 12
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synthesis failed" }

launch_runs impl_1 -to_step write_bitstream -jobs 12
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "implementation failed" }

open_run impl_1
report_timing_summary -max_paths 5 -file $proj_dir/timing_summary.rpt
report_utilization -file $proj_dir/utilization.rpt
file copy -force $proj_dir/hdmi_filter.runs/impl_1/hdmi_filter_top.bit $proj_dir/hdmi_filter.bit
file copy -force $proj_dir/hdmi_filter.runs/impl_1/hdmi_filter_top.ltx $proj_dir/hdmi_filter.ltx
puts "WNS: [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]"
puts "BITSTREAM: $proj_dir/hdmi_filter.bit"
