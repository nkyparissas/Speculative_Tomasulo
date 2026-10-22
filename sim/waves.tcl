# Speculative Tomasulo processor
# Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
# Speculative Tomasulo project (see README.md).
#
# Waveform setup for tb_top_level in the Vivado simulator.
#
# Source this script in the Tcl console after launching the behavioural
# simulation (source <repository>/sim/waves.tcl), or register it once as a
# custom Tcl script in the simulation settings (xsim.simulate.custom_tcl).
# The groups mirror the stages of the processor. To keep the arrangement as a
# waveform configuration file, save it with
#   save_wave_config tb_top_level_behav.wcfg

set tb  /tb_top_level
set dut $tb/dut

add_wave_divider "TESTBENCH"
add_wave $tb/clk
add_wave $tb/rst
add_wave $tb/exception_flag
add_wave -radix unsigned $tb/exception_tag
add_wave -radix unsigned $tb/exception_pc

add_wave_divider "ISSUE"
add_wave -radix unsigned $dut/pc
add_wave $dut/instruction
add_wave $dut/ack_logical
add_wave $dut/ack_arithmetic
add_wave -radix unsigned $dut/rob_tail

add_wave_divider "OPERAND LOOKUP"
add_wave -radix unsigned $dut/rob_rs_tag
add_wave -radix hex $dut/rob_rs_value
add_wave $dut/rob_rs_valid
add_wave -radix unsigned $dut/rob_rt_tag
add_wave -radix hex $dut/rob_rt_value
add_wave $dut/rob_rt_valid
add_wave -radix hex $dut/rf_rs_value
add_wave -radix hex $dut/rf_rt_value

add_wave_divider "LOGICAL UNIT"
add_wave $dut/u_logical/u_rs/stations
add_wave $dut/u_logical/u_rs/fill_pending
add_wave $dut/u_logical/u_rs/in_flight
add_wave -radix unsigned $dut/u_logical/u_fu/tags
add_wave -radix hex $dut/u_logical/u_fu/values

add_wave_divider "ARITHMETIC UNIT"
add_wave $dut/u_arithmetic/u_rs/stations
add_wave $dut/u_arithmetic/u_rs/fill_pending
add_wave $dut/u_arithmetic/u_rs/in_flight
add_wave -radix unsigned $dut/u_arithmetic/u_fu/tags
add_wave -radix hex $dut/u_arithmetic/u_fu/values

add_wave_divider "COMMON DATA BUS"
add_wave $dut/cdb_req_logical
add_wave $dut/cdb_req_arithmetic
add_wave $dut/cdb_grant
add_wave -radix unsigned $dut/cdb_tag
add_wave -radix hex $dut/cdb_value

add_wave_divider "REORDER BUFFER"
add_wave -radix unsigned $dut/u_rob/head
add_wave -radix unsigned $dut/u_rob/tail
add_wave $dut/u_rob/entries
add_wave -radix unsigned $dut/flush_tag

add_wave_divider "REGISTER FILE"
add_wave $dut/commit_we
add_wave -radix unsigned $dut/commit_rd
add_wave -radix hex $dut/commit_value
add_wave -radix hex $dut/u_regfile/regs
