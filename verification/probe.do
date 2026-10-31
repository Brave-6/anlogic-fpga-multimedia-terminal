onerror {quit -code 1 -f}
vlog -sv verification/tb_sdram_probe.v
vsim -c -novopt work.tb_sdram_probe
onfinish exit
run -all
