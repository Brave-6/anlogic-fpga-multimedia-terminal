`timescale 1ns/1ps
module tb_tf_status_abort;
reg clk=0;
always #5 clk=~clk;
reg rst=1,load_start=0,load_busy=0,byte_valid=0,pixel_valid=0,abort_pulse=0;
reg [31:0] sector=0;
wire [23:0] view;
wire [15:0] flags;
wire [19:0] pixels;
tf_status_monitor #(.PAGE_CYCLES(4),.WINDOW_CYCLES(8)) dut(
 .clk(clk),.rst(rst),.sd_ready(1'b1),.scan_done(1'b0),.found(3'd4),
 .state_code(4'd1),.scan_start(1'b0),.found_pulse(1'b0),
 .load_start(load_start),.load_busy(load_busy),.display_valid(1'b0),.pixel_valid(pixel_valid),
 .write_ack_async(1'b0),.write_finish_pulse(1'b0),.abort_pulse(abort_pulse),
 .source_done(1'b0),.write_done(1'b0),.sdram_ready_async(1'b1),.sector_addr(sector),
 .byte_valid(byte_valid),.view(view),.flags(flags),.pixels(pixels));
task tick; begin @(negedge clk); end endtask
task expect_page;
 input [23:0] expected;
 integer n;
 begin
  n=0;
  while(view!==expected && n<40) begin tick; n=n+1; end
  if(view!==expected) $fatal(1,"page mismatch wanted=%h got=%h",expected,view);
 end
endtask
task start_attempt;
 begin load_start=1; load_busy=1; tick; load_start=0; end
endtask
initial begin
 repeat(3) tick; rst=0;
 start_attempt;
 byte_valid=1; pixel_valid=1; sector=32'd34265;
 repeat(10) tick;
 byte_valid=0; pixel_valid=0;
 repeat(3) tick;
 // Capture while busy has already fallen, matching the real controller abort.
 abort_pulse=1; load_busy=0; tick;
 abort_pulse=0; sector=0;
 if(dut.abort_age!==20'd4 || dut.abort_sector!==20'd34265 || dut.abort_pixels!==20'd10 || dut.abort_recent_bytes!==16'd10)
   $fatal(1,"active case snapshot mismatch");
 expect_page(24'hd00004);
 expect_page({4'he,20'd34265});
 expect_page(24'hf0000a);
 expect_page(24'ha2000a);
 // Long idle after a successful byte: recent windows empty but age preserved.
 start_attempt;
 if(dut.abort_pixels!==20'd10) $fatal(1,"restart erased earlier abort evidence");
 byte_valid=1; tick; byte_valid=0;
 repeat(24) tick;
 abort_pulse=1; load_busy=0; tick; abort_pulse=0;
 if(dut.abort_age!==20'd25 || dut.abort_recent_bytes!==0)
   $fatal(1,"idle case wrong");
 // Byte and pixel on abort edge must be included, including a window boundary.
 start_attempt; repeat(7) tick;
 byte_valid=1; pixel_valid=1; abort_pulse=1; load_busy=0; sector=32'd32800; tick;
 byte_valid=0; pixel_valid=0; abort_pulse=0; sector=0;
 if(dut.abort_age!==0 || dut.abort_recent_bytes!==1 || dut.abort_pixels!==1 || dut.abort_sector!==32800)
   $fatal(1,"simultaneous event/boundary capture wrong");
 // No byte in an attempt is represented by saturated age, not false freshness.
 start_attempt; repeat(20) tick;
 abort_pulse=1; load_busy=0; tick; abort_pulse=0;
 if(dut.abort_age!==20'hfffff || dut.abort_recent_bytes!==0) $fatal(1,"no-byte case wrong");
 rst=1; tick; rst=0;
 if(dut.abort_age!==0 || dut.abort_recent_bytes!==0 || dut.abort_pixels!==0 || flags[8]!==0)
   $fatal(1,"reset did not clear snapshot");
 $display("PASS: V2 active vs stalled capture, age, pre-clear sector, pixel count, same-edge byte, window rollover, retry retention, reset.");
 $finish;
end
initial begin #100000; $fatal(1,"watchdog"); end
endmodule
