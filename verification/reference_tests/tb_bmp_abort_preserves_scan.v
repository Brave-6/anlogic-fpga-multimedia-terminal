`timescale 1ns/1ps
module tb_bmp_abort_preserves_scan;
reg clk=0,rst=1,scan_start=0,load_start=0,load_abort=0;
reg data_valid=0,sector_end=0;
wire ready,load_done,scan_done,read_req,write_req;
wire [31:0] read_addr;
integer i;
always #5 clk=~clk;
bmp_read dut(
 .clk(clk),.rst(rst),.ready(ready),.load_done(load_done),
 .scan_start(scan_start),.scan_start_sector(32'd0),.scan_max_sector(32'd0),
 .scan_target_count(3'd4),.scan_done(scan_done),.scan_found_valid(),
 .scan_found_sector(),.scan_found_total(),.load_start(load_start),
 .load_abort(load_abort),.load_sector(32'd32800),.sd_init_done(1'b1),
 .state_code(),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_req(write_req),.write_req_ack(1'b0),.sd_sec_read(read_req),
 .sd_sec_read_addr(read_addr),.sd_sec_read_data(8'h00),
 .sd_sec_read_data_valid(data_valid),.sd_sec_read_end(sector_end),
 .bmp_data_wr_en(),.bmp_data());
task tick;begin @(negedge clk);end endtask
initial begin
 repeat(4)tick;rst=0;scan_start=1;tick;scan_start=0;
 for(i=0;i<512;i=i+1)begin data_valid=1;tick;end
 data_valid=0;sector_end=1;tick;sector_end=0;repeat(3)tick;
 if(scan_done!==1 || ready!==1)$fatal(1,"initial scan did not complete");
 load_start=1;tick;load_start=0;repeat(3)tick;
 if(ready!==0)$fatal(1,"load did not start");
 load_abort=1;tick;load_abort=0;repeat(3)tick;
 if(scan_done!==1 || ready!==1 || write_req!==0 || load_done!==0)
  $fatal(1,"abort destroyed scan result or left load active");
 // A new load must remain possible without rescanning.
 load_start=1;tick;load_start=0;repeat(3)tick;
 if(ready!==0 || read_addr!==32800)$fatal(1,"retry did not start from cached sector");
 $display("PASS: load abort preserves completed scan and permits direct retry.");
 $finish;
end
initial begin #100000;$fatal(1,"watchdog");end
endmodule
