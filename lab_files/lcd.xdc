###############################################################################
# AC701 Artix-7 Constraint File (AHB SoC + LCD J23 + UART PMOD)
###############################################################################

# ----------------------------------------------------------------------------
# 1. System Clock & Reset
# ----------------------------------------------------------------------------
# CPU Reset (Active High - Button U4)
set_property -dict { PACKAGE_PIN U4  IOSTANDARD LVCMOS33 } [get_ports { RESET }];

# System Clock (156.25 MHz - Pin M21)
set_property -dict { PACKAGE_PIN M21 IOSTANDARD LVCMOS33 } [get_ports { CLK }];
create_clock -add -name sys_clk_pin -period 6.400 -waveform {0 3.200} [get_ports CLK]

# ----------------------------------------------------------------------------
# 2. UART (PMOD J2 - Pin 1 & 2)
# ----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN P26 IOSTANDARD LVCMOS33 } [get_ports { RsRx }]; 
set_property -dict { PACKAGE_PIN T22 IOSTANDARD LVCMOS33 } [get_ports { RsTx }]; 

# ----------------------------------------------------------------------------
# 3. LCD Interface (Header J23 - AC701 Dedicated LCD Port)
# ----------------------------------------------------------------------------
# Mapping d?a trên UG952 Table 1-21
# Code AHBLITE_SYS c?a b?n có các c?ng: lcd_rs, lcd_rw, lcd_e, lcd_db[3:0]

# Control Signals
set_property -dict { PACKAGE_PIN L23 IOSTANDARD LVCMOS33 } [get_ports { lcd_rs }];
set_property -dict { PACKAGE_PIN L24 IOSTANDARD LVCMOS33 } [get_ports { lcd_rw }];
set_property -dict { PACKAGE_PIN L20 IOSTANDARD LVCMOS33 } [get_ports { lcd_e }];

# Data Signals (4-bit Mode)
set_property -dict { PACKAGE_PIN L25 IOSTANDARD LVCMOS33 } [get_ports { lcd_db[0] }]; # DB4
set_property -dict { PACKAGE_PIN M24 IOSTANDARD LVCMOS33 } [get_ports { lcd_db[1] }]; # DB5
set_property -dict { PACKAGE_PIN M25 IOSTANDARD LVCMOS33 } [get_ports { lcd_db[2] }]; # DB6
set_property -dict { PACKAGE_PIN L22 IOSTANDARD LVCMOS33 } [get_ports { lcd_db[3] }]; # DB7

# Switch
set_property -dict { PACKAGE_PIN P6  IOSTANDARD LVCMOS33 } [get_ports { GPIOIN[0] }]; # GPIO_SW_N
set_property -dict { PACKAGE_PIN T5  IOSTANDARD LVCMOS33 } [get_ports { GPIOIN[1] }]; # GPIO_SW_S
set_property -dict { PACKAGE_PIN R5  IOSTANDARD LVCMOS33 } [get_ports { GPIOIN[2] }]; # GPIO_SW_W
set_property -dict { PACKAGE_PIN U5  IOSTANDARD LVCMOS33 } [get_ports { GPIOIN[3] }]; # GPIO_SW_E

# LED
set_property -dict { PACKAGE_PIN M26 IOSTANDARD LVCMOS33 } [get_ports { LED[0] }];  # GPIO_LED_0
set_property -dict { PACKAGE_PIN T24 IOSTANDARD LVCMOS33 } [get_ports { LED[1] }];  # GPIO_LED_1
set_property -dict { PACKAGE_PIN T25 IOSTANDARD LVCMOS33 } [get_ports { LED[2] }];  # GPIO_LED_2
set_property -dict { PACKAGE_PIN R26 IOSTANDARD LVCMOS33 } [get_ports { LED[3] }];  # GPIO_LED_3

# ----------------------------------------------------------------------------
# 4. Config
# ----------------------------------------------------------------------------
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]