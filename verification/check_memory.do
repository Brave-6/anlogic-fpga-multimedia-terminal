# Run from the extracted snapshot root with ModelSim 10.3c.
onerror {quit -code 1 -f}
if {![file isdirectory work]} {vlib work}
set h [file normalize src/user_source/hdl_source]
set p [file normalize src/td_project]
vlog -sv -permissive +incdir+$p +incdir+$h/include $h/include/sdr_as_ram.enc.v $h/include/sdr_init_ref.enc.v $h/include/sdr_wrrd.enc.v
vlog -sv +incdir+$h/SD +incdir+$h/include $h/SD/frame_read_write.v $h/SD/frame_fifo_read.v $h/SD/frame_fifo_write.v $h/IP/afifo_32_16_256.v $h/IP/afifo_16_32_256.v $h/SD/video_timing_data.v $h/SD/color_bar.v verification/tb_memory_bandwidth_40.v
vsim -c -novopt work.tb_memory_bandwidth_40
onfinish exit
run -all
