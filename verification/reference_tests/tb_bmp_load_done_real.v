`timescale 1ns/1ps
module tb_bmp_load_done_real;
reg clk=0,rst=1,load_start=0,write_ack=0,data_valid=0,sector_end=0;
reg [7:0] data=0;
wire ready,load_done,read_req,write_req,pixel_valid;
wire [31:0] read_addr;
wire [23:0] pixel;
integer i,pixels,done_pulses;
always #5 clk=~clk;
bmp_read dut(
 .clk(clk),.rst(rst),.ready(ready),.load_done(load_done),
 .scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(3'd1),
 .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
 .load_start(load_start),.load_abort(1'b0),.load_sector(32'd100),.sd_init_done(1'b1),
 .state_code(),.bmp_width(16'd2),.bmp_height(16'd1),.write_req(write_req),
 .write_req_ack(write_ack),.sd_sec_read(read_req),.sd_sec_read_addr(read_addr),
 .sd_sec_read_data(data),.sd_sec_read_data_valid(data_valid),.sd_sec_read_end(sector_end),
 .bmp_data_wr_en(pixel_valid),.bmp_data(pixel));
always @(posedge clk)if(!rst)begin
 if(pixel_valid)pixels=pixels+1;
 if(load_done)done_pulses=done_pulses+1;
end
function [7:0] sector_byte;
 input integer n;
 begin
  case(n)
   0:sector_byte="B";1:sector_byte="M";
   2:sector_byte=8'd60;10:sector_byte=8'd54;
   18:sector_byte=8'd2;22:sector_byte=8'd1;
   28:sector_byte=8'd24;
   54:sector_byte=8'h11;55:sector_byte=8'h22;56:sector_byte=8'h33;
   57:sector_byte=8'h44;58:sector_byte=8'h55;59:sector_byte=8'h66;
   default:sector_byte=0;
  endcase
 end
endfunction
task tick;begin @(negedge clk);end endtask
task send_sector;
 begin
  for(i=0;i<512;i=i+1)begin data=sector_byte(i);data_valid=1;tick;end
  data_valid=0;sector_end=1;tick;sector_end=0;
 end
endtask
initial begin
 pixels=0;done_pulses=0;repeat(4)tick;rst=0;
 load_start=1;tick;load_start=0;repeat(2)tick;
 if(read_addr!==100)$fatal(1,"header address mismatch");
 send_sector;
 repeat(2)tick;
 if(write_req!==1)$fatal(1,"valid header did not request frame write");
 write_ack=1;tick;write_ack=0;repeat(2)tick;
 send_sector;
 repeat(3)tick;
 if(pixels!==2 || done_pulses!==1 || ready!==1 || load_done!==0)
  $fatal(1,"real load completion/pixel count mismatch");
 $display("PASS: real 2x1 RGB24 BMP stream emits two pixels and exactly one EOF completion pulse.");
 $finish;
end
initial begin #200000;$fatal(1,"watchdog");end
endmodule
