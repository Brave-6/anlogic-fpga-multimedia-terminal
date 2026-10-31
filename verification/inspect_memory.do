onerror {quit -code 1 -f}
vsim -c -novopt work.tb_memory_bandwidth_40
puts [find instances -recursive /tb_memory_bandwidth_40/ram/*]
puts [find signals -recursive /tb_memory_bandwidth_40/ram/*ref*]
quit -code 0 -f
