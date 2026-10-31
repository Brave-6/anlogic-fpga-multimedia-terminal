`timescale 1ns/1ps
// Control-path test only. Inject elapsed count and completion, not real SD data.
module tb_tf_late_commit;
reg clk=0;
always #5 clk=~clk;
reg rst=1,finish_toggle=0;
wire valid;
wire [3:0] state_code;
sd_card_bmp dut(.clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),
 .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(valid),.state_code(state_code),
 .write_finish_toggle(finish_toggle),.write_buf_idx(),.disp_buf_idx(),
 .write_req(),.write_req_ack(1'b0),.write_en(),.write_data(),
 .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),.debug_sdram_ready(1'b1),.debug_view());
initial begin
 force dut.sd_init_done=1'b1;
 repeat(5) @(negedge clk); rst=0;
 repeat(8) @(negedge clk);
 force dut.scan_found_valid=1'b1; force dut.scan_found_sector=32'd32800;
 @(negedge clk); force dut.scan_found_valid=1'b0;
 force dut.scan_done=1'b1; force dut.bmp_ready=1'b1;
 repeat(4) @(negedge clk);
 if(dut.load_busy!==1'b1) $fatal(1,"load did not start");
 force dut.load_timeout_cnt=32'd150000000;
 repeat(4) @(negedge clk);
 if(dut.load_abort!==0 || valid!==0) $fatal(1,"premature abort/commit at 1.5s");
 finish_toggle=1;
 repeat(8) @(negedge clk);
 if(valid!==1 || dut.first_image_committed!==1 || dut.load_busy!==0 || dut.status_monitor_m0.flags[8]!==0)
   $fatal(1,"late completion failed");
 if(dut.status_monitor_m0.flags[7]!==1) $fatal(1,"completion observation failed");
 $display("PASS: 5s variant accepts injected 1.5s completion without abort; display commit observed.");
 $display("LIMIT: control conditions injected; not a real full-frame transfer or SDRAM correctness test.");
 $finish;
end
initial begin #100000; $fatal(1,"watchdog"); end
endmodule
