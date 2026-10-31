`timescale 1ns/1ps
// Controlled fault injection, NOT an SD-card or SDRAM timing simulation.
// Exercise unchanged original controller + BMP reader after a load timeout.
module tb_tf_timeout;
reg clk=0;
always #5 clk=~clk;
reg rst=1;
wire display_valid;
wire [3:0] state_code;
wire [1:0] wb,db;
wire wr;
wire wen;
wire [31:0] data;
wire cs,sclk,mosi;
sd_card_bmp dut(
 .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),
 .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(display_valid),
 .state_code(state_code),.write_finish_toggle(1'b0),
 .write_buf_idx(wb),.disp_buf_idx(db),.write_req(wr),.write_req_ack(1'b0),
 .write_en(wen),.write_data(data),.SD_nCS(cs),.SD_DCLK(sclk),.SD_MOSI(mosi),.SD_MISO(1'b1)
`ifdef OBSERVED_TF
 ,.debug_sdram_ready(1'b1),.debug_view()
`endif
`ifdef WRITE_PROBE
 ,.debug_capture_req(),.debug_capture_ack(1'b0),.debug_capture_data(96'd0),
 .debug_fifo_accept(1'b0),.debug_fifo_reject(1'b0)
`endif
 );
integer i;
initial begin
 // Keep the real lower modules in the compilation, but inject initialization
 // and discovery outputs so no physical SPI card model is needed.
 force dut.sd_init_done=1'b1;
 repeat(5) @(negedge clk);
 rst=0;
 repeat(8) @(negedge clk);
 if(dut.scan_kicked !== 1'b1) $fatal(1,"scan did not start");
 force dut.scan_found_valid=1'b1;
 force dut.scan_found_sector=32'd32800;
 @(negedge clk);
 force dut.scan_found_valid=1'b0;
 force dut.scan_done=1'b1;
 force dut.bmp_ready=1'b1;
 repeat(4) @(negedge clk);
 if(dut.load_busy !== 1'b1 || dut.img_found_count !== 3'd1)
   $fatal(1,"injected discovered image did not start load");
 // Skip elapsed-time counting; test comparator boundaries in the 5s variant.
`ifdef TIMEOUT_5S
 force dut.load_timeout_cnt=32'd100000001;
 repeat(3) @(negedge clk);
 if(dut.load_abort !== 1'b0 || dut.load_busy !== 1'b1)
   $fatal(1,"5s variant still aborts after 1s");
 force dut.load_timeout_cnt=32'd500000000;
 @(negedge clk);
 if(dut.load_abort !== 1'b0) $fatal(1,"strict greater-than boundary wrong");
 force dut.load_timeout_cnt=32'd500000001;
`else
 force dut.load_timeout_cnt=32'd100000001;
`endif
 @(negedge clk);
 if(dut.load_abort !== 1'b1) $fatal(1,"timeout did not assert abort");
 release dut.load_timeout_cnt;
 release dut.scan_done;
 release dut.bmp_ready;
 @(negedge clk); // real bmp_read consumes load_abort and clears scan_done
 repeat(6) @(negedge clk);
 for(i=0;i<100;i=i+1) begin
   @(negedge clk);
   if(state_code !== 4'd1 || display_valid !== 1'b0 ||
      dut.scan_done !== 1'b0 || dut.scan_kicked !== 1'b1 ||
      dut.scan_start_pulse !== 1'b0 || dut.load_busy !== 1'b0)
     $fatal(1,"unexpected post-timeout control state");
 end
`ifdef OBSERVED_TF
 if(dut.status_monitor_m0.flags[8] !== 1'b1)
   $fatal(1,"Observer missed controller timeout event");
 $display("PASS: passive observer latched the real controller's abort pulse.");
`endif
 $display("REPRODUCED: after injected load timeout, state_code=1 display_valid=0 scan_done=0 scan_kicked=1 load_busy=0; no automatic rescan in 100 cycles.");
 $display("LIMIT: this proves a timeout-recovery path in RTL, NOT that the real board timed out or why it did.");
 $finish;
end
initial begin #100000; $fatal(1,"test watchdog"); end
endmodule
