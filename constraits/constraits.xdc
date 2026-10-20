## Constraints for top_module on Digilent Cmod A7 (15T or 35T - same pins)
## Port names match top_module.v: clk, rst_pin, uart_rxd, uart_txd, led[1:0]

## 12 MHz system clock
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 83.333 -waveform {0 41.667} [get_ports clk]

## Reset = BTN0 (active high: reads 1 while pressed)
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports rst_pin]

## USB-UART bridge (names on the Digilent board are from the PC's point of view)
## uart_rxd = FPGA input  <- data from PC   (Digilent: uart_txd_in,  J17)
## uart_txd = FPGA output -> data to PC     (Digilent: uart_rxd_out, J18)
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports uart_rxd]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports uart_txd]

## LEDs: led[0] = motion, led[1] = heartbeat
set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]

## The UART RX input and the async reset button are not timed against clk
set_false_path -from [get_ports { uart_rxd rst_pin }]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
