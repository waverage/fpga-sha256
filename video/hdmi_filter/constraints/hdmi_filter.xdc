## Arty Z7-20 pins, from Digilent's Arty-Z7-20-Master.xdc

set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports clk125]

set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN D19 IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN D20 IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]

## HDMI IN connector
set_property -dict { PACKAGE_PIN N18 IOSTANDARD TMDS_33 } [get_ports hdmi_rx_clk_p]
set_property -dict { PACKAGE_PIN P19 IOSTANDARD TMDS_33 } [get_ports hdmi_rx_clk_n]
set_property -dict { PACKAGE_PIN V20 IOSTANDARD TMDS_33 } [get_ports {hdmi_rx_d_p[0]}]
set_property -dict { PACKAGE_PIN W20 IOSTANDARD TMDS_33 } [get_ports {hdmi_rx_d_n[0]}]
set_property -dict { PACKAGE_PIN T20 IOSTANDARD TMDS_33 } [get_ports {hdmi_rx_d_p[1]}]
set_property -dict { PACKAGE_PIN U20 IOSTANDARD TMDS_33 } [get_ports {hdmi_rx_d_n[1]}]
set_property -dict { PACKAGE_PIN N20 IOSTANDARD TMDS_33 } [get_ports {hdmi_rx_d_p[2]}]
set_property -dict { PACKAGE_PIN P20 IOSTANDARD TMDS_33 } [get_ports {hdmi_rx_d_n[2]}]
set_property -dict { PACKAGE_PIN T19 IOSTANDARD LVCMOS33 } [get_ports hdmi_rx_hpd]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports hdmi_rx_scl]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports hdmi_rx_sda]

## HDMI OUT connector
set_property -dict { PACKAGE_PIN L16 IOSTANDARD TMDS_33 } [get_ports hdmi_tx_clk_p]
set_property -dict { PACKAGE_PIN L17 IOSTANDARD TMDS_33 } [get_ports hdmi_tx_clk_n]
set_property -dict { PACKAGE_PIN K17 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_d_p[0]}]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_d_n[0]}]
set_property -dict { PACKAGE_PIN K19 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_d_p[1]}]
set_property -dict { PACKAGE_PIN J19 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_d_n[1]}]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_d_p[2]}]
set_property -dict { PACKAGE_PIN H18 IOSTANDARD TMDS_33 } [get_ports {hdmi_tx_d_n[2]}]

## Timing
# 720p60 pixel clock, 74.25 MHz (the EDID advertises 720p only)
create_clock -name hdmi_rx_clk -period 13.468 [get_ports hdmi_rx_clk_p]

set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks -of_objects [get_ports clk125]] \
    -group [get_clocks -include_generated_clocks hdmi_rx_clk]

set_false_path -from [get_ports {sw[*] btn[*]}]
set_false_path -to   [get_ports {led[*] hdmi_rx_hpd}]
set_false_path -from [get_ports {hdmi_rx_scl hdmi_rx_sda}]
set_false_path -to   [get_ports {hdmi_rx_scl hdmi_rx_sda}]
