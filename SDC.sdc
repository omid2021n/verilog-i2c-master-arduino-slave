# Base clock: 25 MHz board input
create_clock -name clk -period 40.000 [get_ports {clk}]

# Auto-generate constraints for the PLL-derived clock (clk_4m)
derive_pll_clocks

# Let the tool figure out clock uncertainty (jitter/skew) instead of guessing it yourself
derive_clock_uncertainty

# rst_n is an async pushbutton — exclude it from setup/hold analysis
set_false_path -from [get_ports {rst_n}]

# sda/scl toggle at 100 kHz — irrelevant to your 4 MHz internal timing, false-path them too
set_false_path -to [get_ports {sda}]
set_false_path -to [get_ports {scl}]
set_false_path -from [get_ports {sda}]
