`timescale 1ns/1ps
module tb_tf_writeprobe;
reg clk=0,mem_clk=0,rst=1;
always #5 clk=~clk;
always #4 mem_clk=~mem_clk;
reg load_start=0,load_busy=0,pixel=0,accept=0,reject=0,abort=0,source_done=0,write_done=0;
reg [15:0] local_meta=0;
reg mem_ack=0,app_write=0,read_accept=0,finish=0;
reg [3:0] write_state=0;
reg [19:0] ctrl_count=0;
reg [9:0] fifo_level=0;
wire req,ack;
wire [95:0] mem_data;
wire [23:0] view;
wire [15:0] flags;
wire [19:0] pixels;
tf_status_capture #(.PAGE_CYCLES(4)) dut(
 .clk(clk),.rst(rst),.sd_ready(1'b1),.scan_done(1'b1),.found(3'd4),.state_code(4'd1),
 .scan_start(1'b0),.found_pulse(1'b0),.load_start(load_start),.load_busy(load_busy),
 .display_valid(1'b1),.pixel_valid(pixel),.write_ack_async(mem_ack),.write_finish_pulse(1'b0),
 .abort_pulse(abort),.source_done(source_done),.write_done(write_done),.sdram_ready_async(1'b1),
 .local_meta(local_meta),.fifo_accept(accept),.fifo_reject(reject),
 .capture_req(req),.capture_ack(ack),.capture_data(mem_data),.view(view),.flags(flags),.pixels(pixels));
tf_mem_probe mem(.clk(mem_clk),.rst(rst),.capture_req(req),.write_ack(mem_ack),
 .app_write(app_write),.fifo_read_accept(read_accept),.write_finish(finish),.write_state(write_state),
 .controller_count(ctrl_count),.fifo_level(fifo_level),.sdram_ready(1'b1),.sdram_busy(1'b0),
 .read_busy(1'b0),.write_busy(1'b0),.fifo_empty(1'b0),.fifo_reset(1'b0),
 .capture_ack(ack),.capture_data(mem_data));
task tick;begin @(negedge clk);end endtask
task mtick;begin @(negedge mem_clk);end endtask
task await_snapshot;
 integer n;
 begin n=0;while(!dut.snapshot_valid && n<40)begin tick;n=n+1;end
  if(!dut.snapshot_valid) $fatal(1,"snapshot handshake timeout");
 end
endtask
task expect_page;
 input [23:0] expected;
 integer n;
 begin n=0;while(view!==expected && n<60)begin tick;n=n+1;end
 if(view!==expected)$fatal(1,"unexpected display page");end
endtask
initial begin
 repeat(5)tick;rst=0;
 // Attempt one: four write requests, only three FIFO accepts.
 load_start=1;load_busy=1;tick;load_start=0;
 pixel=1;accept=1;repeat(3)tick;accept=0;reject=1;tick;pixel=0;reject=0;
 mtick;mem_ack=1;mtick;mem_ack=0;
 app_write=1;read_accept=1;repeat(3)mtick;
 read_accept=0;mtick;app_write=0;
 write_state=2;ctrl_count=0;fifo_level=1;
 tick;local_meta=16'h010d;tick;
 // Abort arrives after controller clears its flags. Observer must retain prior flags.
 abort=1;load_busy=0;local_meta=0;tick;abort=0;
 await_snapshot;
 if(dut.meta_saved!==16'h012d || dut.accepted_saved!==3 || dut.rejected_saved!==1)
  $fatal(1,"pre-abort or local counters wrong");
 if(dut.mem_saved[19:0]!==4 || dut.mem_saved[39:20]!==3 || dut.mem_saved[69:60]!==1)
  $fatal(1,"memory snapshot counter/level wrong");
 if(dut.mem_saved[85:70]!==16'h1812)$fatal(1,"memory flags wrong");
 expect_page(24'ha3012d);expect_page(24'ha41812);expect_page(24'ha50001);
 expect_page(24'ha60101);expect_page(24'h500004);expect_page(24'h600000);
 expect_page(24'h700003);expect_page(24'h800001);expect_page(24'h900003);
 // Changing memory-side live values must not change an acknowledged snapshot.
 mtick;app_write=1;read_accept=1;repeat(3)mtick;app_write=0;read_accept=0;ctrl_count=99;
 repeat(10)tick;
 if(dut.mem_saved[19:0]!==4 || dut.mem_saved[59:40]!==0)$fatal(1,"snapshot changed without request");
 // Attempt two succeeds. Counters/history reset per attempt; handshake toggles back.
 load_start=1;load_busy=1;tick;load_start=0;
 pixel=1;accept=1;repeat(4)tick;pixel=0;accept=0;
 mtick;mem_ack=1;mtick;mem_ack=0;app_write=1;read_accept=1;
 repeat(4)mtick;app_write=0;read_accept=0;finish=1;mtick;finish=0;
 ctrl_count=4;fifo_level=0;write_state=0;
 tick;source_done=1;write_done=1;local_meta=16'h015f;tick;
 source_done=0;write_done=0;load_busy=0;local_meta=0;
 await_snapshot;
 if(dut.attempt_saved!==2 || dut.meta_saved!==16'h015f || dut.accepted_saved!==4 || dut.rejected_saved!==0)
  $fatal(1,"second attempt local snapshot wrong");
 if(dut.mem_saved[19:0]!==4 || dut.mem_saved[39:20]!==4 || dut.mem_saved[59:40]!==4)
  $fatal(1,"second attempt memory counters wrong");
 if(dut.mem_saved[85:70]!==16'h1410 || dut.overrun!==0)$fatal(1,"second attempt flags wrong");
 expect_page(24'ha60102);
 rst=1;tick;rst=0;
 if(dut.snapshot_valid!==0 || req!==0 || ack!==0 || pixels!==0)$fatal(1,"reset failed");
 $display("PASS: asynchronous request/ack stable snapshot, pre-clear abort flags, exact counters, reject/underflow, attempt reset, commit, all new display pages.");
 $finish;
end
initial begin #100000; $fatal(1,"watchdog");end
endmodule
