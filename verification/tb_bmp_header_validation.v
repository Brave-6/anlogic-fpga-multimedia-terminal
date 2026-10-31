`timescale 1ns/1ps
module tb_bmp_header_validation;
reg clk=0,rst=1,scan_start=0,load_start=0,abort_load=0;
reg dv=0,se=0;reg [7:0] data=0;
wire ready,done,found,wr,rd;wire [2:0] total;wire [31:0] addr,found_sector;
integer i,k,found_count=0;
always #5 clk=~clk;
bmp_read dut(.clk(clk),.rst(rst),.ready(ready),.load_done(),
 .scan_start(scan_start),.scan_start_sector(32'd100),.scan_max_sector(32'd106),
 .scan_target_count(3'd2),.scan_done(done),.scan_found_valid(found),
 .scan_found_sector(found_sector),.scan_found_total(total),
 .load_start(load_start),.load_abort(abort_load),.load_sector(32'd100),
 .sd_init_done(1'b1),.state_code(),.bmp_width(16'd2),.bmp_height(16'd1),
 .write_req(wr),.write_req_ack(1'b0),.sd_sec_read(rd),.sd_sec_read_addr(addr),
 .sd_sec_read_data(data),.sd_sec_read_data_valid(dv),.sd_sec_read_end(se),
 .bmp_data_wr_en(),.bmp_data());
always @(posedge clk)if(!rst && found)begin
 if(found_sector !== (found_count==0 ? 32'd100 : 32'd106))
  $fatal(1,"wrong scan match %d",found_sector);
 found_count=found_count+1;
end
function [7:0] header_byte;
 input integer n,kind;
 begin
  case(n)
   0:header_byte=(kind==1)?"X":"B";
   1:header_byte="M";
   2:header_byte=60;
   10:header_byte=54;
   18:header_byte=(kind==2)?3:2;
   22:header_byte=(kind==3)?2:1;
   28:header_byte=(kind==4)?16:24;
   30:header_byte=(kind==5)?1:0;
   default:header_byte=0;
  endcase
 end
endfunction
task tick;begin @(negedge clk);end endtask
task send_header;
 input integer kind;
 begin
  wait(rd);tick;
  for(i=0;i<512;i=i+1)begin data=header_byte(i,kind);dv=1;tick;end
  dv=0;se=1;tick;se=0;repeat(3)tick;
 end
endtask
initial begin
 repeat(4)tick;rst=0;scan_start=1;tick;scan_start=0;
 for(k=0;k<7;k=k+1)begin
  if(addr !== 100+k)$fatal(1,"scan address %d expected %d",addr,100+k);
  send_header((k==6)?0:k);
 end
 if(!done || !ready || total!==2 || found_count!=2)$fatal(1,"scan validation failed");
 // Reject malformed headers after valid headers without resetting the parser.
 for(k=0;k<6;k=k+1)begin
  load_start=1;tick;load_start=0;send_header(k);
  if(k==0)begin
   if(!wr || ready)$fatal(1,"valid load header rejected");
   abort_load=1;tick;abort_load=0;repeat(2)tick;
  end else if(wr || !ready)$fatal(1,"malformed load header accepted kind=%d",k);
 end
 $display("PASS: sequential valid/invalid BMP scan and load headers reject wrong signature, width, height, bit depth and compression without stale validation.");
 $finish;
end
initial begin #200000;$fatal(1,"header watchdog");end
endmodule
