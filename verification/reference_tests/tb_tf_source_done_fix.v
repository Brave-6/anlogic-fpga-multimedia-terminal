`timescale 1ns/1ps
module tb_tf_source_done_fix;
reg clk=0,rst=1,finish_toggle=0;
always #5 clk=~clk;
wire valid;
sd_card_bmp dut(
 .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),
 .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(valid),.state_code(),
 .write_finish_toggle(finish_toggle),.write_buf_idx(),.disp_buf_idx(),
 .write_req(),.write_req_ack(1'b0),.write_en(),.write_data(),
 .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1)
`ifndef AUDIO_INTEGRATED
 ,
 .debug_sdram_ready(1'b1),.debug_view());
`else
 );
`endif
task tick;begin @(negedge clk);end endtask
initial begin
 force dut.sd_init_done=1'b1;
 repeat(5)tick;rst=0;repeat(8)tick;
 force dut.scan_found_valid=1'b1;force dut.scan_found_sector=32'd32800;tick;
 force dut.scan_found_valid=1'b0;force dut.scan_done=1'b1;force dut.bmp_ready=1'b1;
 repeat(4)tick;
 if(dut.load_busy!==1)$fatal(1,"first load did not start");
 // bmp_ready remains high across this injected boundary, but must no longer
 // be mistaken for source completion.
 repeat(20)tick;
 if(dut.source_done_seen!==0)$fatal(1,"bmp_ready prematurely completed source");
 force dut.bmp_load_done=1'b1;tick;force dut.bmp_load_done=1'b0;repeat(2)tick;
 if(dut.source_done_seen!==1)$fatal(1,"explicit load_done was not latched");
 finish_toggle=1;repeat(8)tick;
 if(valid!==1 || dut.first_image_committed!==1 || dut.load_busy!==0)
  $fatal(1,"source/write completion did not commit frame");
 $display("PASS: source completion requires explicit BMP EOF pulse; bmp_ready cannot commit early.");
 $finish;
end
initial begin #100000;$fatal(1,"watchdog");end
endmodule
