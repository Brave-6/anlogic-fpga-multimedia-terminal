`timescale 1ns/1ps
module tb_tf_status_monitor;
reg clk=0;
always #5 clk=~clk;
reg rst=1;
reg sd_ready=0,scan_done=0,scan_start=0,found_pulse=0,load_start=0;
reg load_busy=0,display_valid=0,pixel_valid=0,ack=0,finish_pulse=0;
reg abort_pulse=0,source_done=0,write_done=0,sdram_ready=0;
reg [2:0] found=0;
reg [3:0] state_code=0;
reg [31:0] sector_addr=0;
wire [23:0] view;
wire [15:0] flags;
wire [19:0] pixels;
integer i;
tf_status_monitor #(.PAGE_CYCLES(8)) dut(
 .clk(clk),.rst(rst),.sd_ready(sd_ready),.scan_done(scan_done),.found(found),
 .state_code(state_code),.scan_start(scan_start),.found_pulse(found_pulse),
 .load_start(load_start),.load_busy(load_busy),.display_valid(display_valid),
 .pixel_valid(pixel_valid),.write_ack_async(ack),.write_finish_pulse(finish_pulse),
 .abort_pulse(abort_pulse),.source_done(source_done),.write_done(write_done),
 .sdram_ready_async(sdram_ready),.sector_addr(sector_addr),.view(view),.flags(flags),.pixels(pixels)
`ifdef MONITOR_V2
 ,.byte_valid(1'b0)
`endif
 );
task tick; begin @(negedge clk); end endtask
task expect_page;
 input [23:0] expected;
 integer tries;
 begin
  tries=0;
  while(view !== expected && tries<80) begin tick; tries=tries+1; end
  if(view !== expected) $fatal(1,"Page mismatch expected=%h actual=%h",expected,view);
 end
endtask
initial begin
 repeat(3) tick;
 rst=0; sd_ready=1; sdram_ready=1; found=4; scan_done=1;
 scan_start=1; found_pulse=1; state_code=1; tick;
 scan_start=0; found_pulse=0;
 load_start=1; load_busy=1; tick; load_start=0;
 ack=1; repeat(4) tick; ack=0;
 state_code=4; pixel_valid=1;
 repeat(307200) tick;
 pixel_valid=0;
 if(pixels!==20'd307200 || flags[10]!==1) $fatal(1,"Frame count/full flag wrong");
 state_code=1; source_done=1; finish_pulse=1; write_done=1; tick;
 finish_pulse=0; source_done=0; write_done=0; load_busy=0; display_valid=1;
 repeat(4) tick;
 if(flags!==16'hf6fb) $fatal(1,"Normal flags wrong: %h",flags);
 expect_page(24'ha01411);
 expect_page(24'ha1f6fb);
 expect_page(24'hb4b000);
 sector_addr=32'd32800;
 expect_page(24'hc08020);
 // A fresh run with a partial frame that times out must retain its count.
 rst=1; tick; rst=0; display_valid=0; load_busy=1; state_code=4;
 load_start=1; tick; load_start=0; pixel_valid=1;
 repeat(17) tick;
 pixel_valid=0; abort_pulse=1; state_code=0; tick;
 abort_pulse=0; state_code=1; scan_done=0; load_busy=0;
 repeat(8) tick;
 if(pixels!==20'd17 || flags[8]!==1 || flags[7]!==0 || flags[9]!==0 || flags[10]!==0)
   $fatal(1,"Timeout observation wrong flags=%h pixels=%h",flags,pixels);
 expect_page(24'hb00011);
 // Count resets on next attempt, timeout history does not.
 load_start=1; tick; load_start=0;
 if(pixels!==0 || flags[8]!==1) $fatal(1,"Retry count/history wrong");
 force dut.pixels=20'hfffff; pixel_valid=1; tick; release dut.pixels;
 tick; pixel_valid=0;
 if(pixels!==20'hfffff || flags[11]!==1) $fatal(1,"Saturation wrong");
 $display("PASS: page encoding, 307200 pixels, completion flags, timeout retention, retry, overflow saturation.");
 $finish;
end
initial begin #4000000; $fatal(1,"watchdog"); end
endmodule
