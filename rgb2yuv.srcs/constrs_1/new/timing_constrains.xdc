# Clock (100 MHz) - Using HDA16_CC which is available with LVCMOS33
set_property PACKAGE_PIN E12 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 2.135 -name clk [get_ports clk]