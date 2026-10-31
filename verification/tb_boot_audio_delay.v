`timescale 1ns/1ps
module tb_boot_audio_delay;
reg clk=0,rst=1,valid=0,ready=0,emerg=0;
wire bclk,lrck,dout;
integer events=0,wait_cycles=0,n;
always #5 clk=~clk;
scene_audio_i2s #(.BOOT_DELAY_CYCLES(32),.INIT_FILE("scene_audio_test.mem"),
 .BOOT_START(0),.BOOT_LENGTH(4),.EMERGENCY_START(4),.EMERGENCY_LENGTH(4),
 .CLEAR_START(8),.CLEAR_LENGTH(4),.TOTAL_SAMPLES(12)) dut(
 .I_mclk(clk),.I_rst(rst),.I_display_valid(valid),.I_emergency_active(emerg),
 .I_boot_ready(ready),.O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
always @(posedge clk) begin
 if(rst)begin events=0;wait_cycles=0;end
 else begin
  if(dut.boot_armed && dut.display_sync && dut.boot_ready_sync && !dut.emergency_sync)
   wait_cycles=wait_cycles+1;
  else wait_cycles=0;
  if(dut.boot_event)begin
   if(wait_cycles!=32)$fatal(1,"startup event did not wait exactly 32 consecutive cycles: %0d",wait_cycles);
   events=events+1;
  end
 end
end
task tick;begin @(negedge clk);end endtask
task reset_case;begin rst=1;valid=0;ready=0;emerg=0;repeat(4)tick;rst=0;end endtask
initial begin
 reset_case;valid=1;repeat(100)tick;
 if(events || dut.playing)$fatal(1,"display-valid alone started startup audio");
 ready=1;repeat(15)tick;ready=0;repeat(10)tick;
 if(events || dut.boot_delay_count!=0)$fatal(1,"readiness interruption failed to restart countdown");
 ready=1;repeat(40)tick;
 if(events!=1 || !dut.playing || dut.sample_addr!=0)$fatal(1,"startup missing after readiness delay");
 repeat(100)tick;ready=0;repeat(10)tick;ready=1;repeat(100)tick;
 valid=0;repeat(10)tick;valid=1;repeat(100)tick;
 if(events!=1)$fatal(1,"startup repeated after frame/readiness changes");
 emerg=1;repeat(8)tick;
 if(dut.sample_addr!=4 || !dut.playing)$fatal(1,"emergency did not preempt startup");
 emerg=0;repeat(8)tick;
 if(dut.sample_addr!=8 || !dut.playing)$fatal(1,"clear clip did not preempt");
 repeat(300)tick;if(events!=1)$fatal(1,"startup replayed after emergency");
 reset_case;valid=1;ready=1;repeat(12)tick;emerg=1;repeat(8)tick;
 if(events || dut.boot_armed || dut.sample_addr!=4)$fatal(1,"pending chime not canceled by emergency");
 emerg=0;repeat(100)tick;if(events || dut.sample_addr!=8)$fatal(1,"canceled chime interrupted clear");
 // An emergency on the exact delayed-start deadline must win.
 reset_case;valid=1;ready=1;
 wait(dut.boot_delay_count==29);@(negedge clk);emerg=1;repeat(12)tick;
 if(dut.sample_addr!=4 || dut.boot_armed)$fatal(1,"deadline collision lost emergency priority");
 reset_case;valid=1;ready=1;repeat(40)tick;
 if(events!=1 || !dut.playing || dut.sample_addr!=0)$fatal(1,"KEY1-style reset did not rearm chime");
 $display("PASS delayed boot audio: readiness+exact delay, countdown restart, once per reset, emergency preemption/cancellation/deadline collision, clear priority and reset rearm.");
 $finish;
end
initial begin #100000;$fatal(1,"startup audio delay watchdog");end
endmodule
