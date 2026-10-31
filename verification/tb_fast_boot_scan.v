`timescale 1ns/1ps
module tb_fast_boot_scan;
reg clk=0,rst=1,start=0,resume_scan=0,load_start=0,abort_load=0;
reg sd_init=1,dv=0,se=0,wr_ack=0;
reg [7:0] data=0;
reg [2:0] target=4;
wire ready,done,found,paused,verified,fallback,wr,rd,load_done,pixel_wr;
wire [31:0] addr,found_sector;
wire [2:0] total;
reg [7:0] image_mem[0:2047];
reg [31:0] seen[0:3];
integer found_count=0,load_count=0,pixel_count=0,reads=0;
integer i,j,k,bad;
always #5 clk=~clk;
bmp_read #(.FAST_SCAN_ENABLE(1),.PAUSE_AFTER_FIRST(1),
 .FAST_SECTOR0(100),.FAST_SECTOR1(200),.FAST_SECTOR2(300),.FAST_SECTOR3(400),
 .FAST_CRC0(32'hE50B1743),.FAST_CRC1(32'h1D21DFEC),
 .FAST_CRC2(32'h7AEC90D2),.FAST_CRC3(32'hC7B4CD6C)) dut(
 .clk(clk),.rst(rst),.ready(ready),.load_done(load_done),
 .scan_start(start),.scan_start_sector(32'd5),.scan_max_sector(32'd8000),
 .scan_target_count(target),.scan_resume(resume_scan),.scan_paused(paused),
 .fast_scan_verified(verified),.fast_scan_fallback(fallback),
 .scan_done(done),.scan_found_valid(found),.scan_found_sector(found_sector),.scan_found_total(total),
 .load_start(load_start),.load_abort(abort_load),.load_sector(32'd100),
 .sd_init_done(sd_init),.state_code(),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_req(wr),.write_req_ack(wr_ack),.sd_sec_read(rd),.sd_sec_read_addr(addr),
 .sd_sec_read_data(data),.sd_sec_read_data_valid(dv),.sd_sec_read_end(se),
 .bmp_data_wr_en(pixel_wr),.bmp_data());
always @(posedge clk) begin
 if(rst || !sd_init) begin found_count=0;load_count=0;pixel_count=0;end
 else begin
  if(found)begin
   if(found_count>=4)$fatal(1,"duplicate catalogue entry");
   seen[found_count]=found_sector;found_count=found_count+1;
  end
  if(load_done)load_count=load_count+1;
  if(pixel_wr)pixel_count=pixel_count+1;
 end
end
task tick;begin @(negedge clk);end endtask
task reset_start;
 begin
  rst=1;start=0;resume_scan=0;load_start=0;abort_load=0;dv=0;se=0;wr_ack=0;sd_init=1;target=4;reads=0;
  repeat(4)tick;rst=0;repeat(2)tick;start=1;tick;start=0;
 end
endtask
task send_sector;
 input integer page,corrupt,byte_count;
 integer n;
 begin
  wait(rd);tick;reads=reads+1;
  for(n=0;n<byte_count;n=n+1)begin
   data=(page<0)?0:image_mem[page*512+n];
   if(corrupt && n==511)data=data^8'h01;
   dv=1;tick;
   if((n%17)==0)begin dv=0;tick;end
  end
  dv=0;repeat(2)tick;se=1;tick;se=0;repeat(4)tick;
 end
endtask
task good_probes;
 integer p;
 begin
  for(p=0;p<4;p=p+1)begin
   if(addr!==100*(p+1))$fatal(1,"probe order/address incorrect");
   if(found_count!=0)$fatal(1,"published a partially verified map");
   send_sector(p,0,512);
  end
  repeat(4)tick;
  if(!verified || fallback || !paused || !ready || done || found_count!=1 || total!=1 || seen[0]!=100)
   $fatal(1,"fast map did not yield P1 exclusively");
 end
endtask
task resume_and_check;
 begin
  resume_scan=1;tick;resume_scan=0;repeat(10)tick;
  if(!done || !ready || paused || total!=4 || found_count!=4)$fatal(1,"resume failed");
  for(k=0;k<4;k=k+1)if(seen[k]!==100*(k+1))$fatal(1,"fast catalogue reordered");
 end
endtask
initial begin
 $readmemh("verification/fast_boot_fixtures/P1.mem",image_mem,0,511);
 $readmemh("verification/fast_boot_fixtures/P2.mem",image_mem,512,1023);
 $readmemh("verification/fast_boot_fixtures/P3.mem",image_mem,1024,1535);
 $readmemh("verification/fast_boot_fixtures/P4.mem",image_mem,1536,2047);
 reset_start;good_probes;
 repeat(20)tick;if(rd || found_count!=1)$fatal(1,"scanner did not yield TF bus");
 load_start=1;tick;load_start=0;send_sector(0,0,512);
 if(!wr)$fatal(1,"P1 write handshake missing");
 wr_ack=1;tick;wr_ack=0;
 for(j=0;j<1801;j=j+1)send_sector(0,0,512);
 if(load_count!=1 || pixel_count!=307200 || !ready || !paused || done)
  $fatal(1,"full P1 load did not preserve suspended scan: EOF=%0d pixels=%0d",load_count,pixel_count);
 resume_and_check;
 if(reads!=1806)$fatal(1,"fast map made unexpected sector reads %0d",reads);
 $display("PASS fast boot: four header sectors only, full 307200-pixel P1 before catalogue completion, exact EOF and resume.");
 for(bad=0;bad<4;bad=bad+1)begin
  reset_start;
  for(i=0;i<=bad;i=i+1)send_sector(i,i==bad,512);
  if(!fallback || verified || found_count || addr!=5)$fatal(1,"stale hint did not fall back atomically slot=%0d",bad);
  send_sector(-1,0,512);send_sector(-1,0,512);send_sector(0,0,512);
  if(!paused || found_count!=1 || seen[0]!=7 || total!=1)$fatal(1,"fallback did not yield first image");
  load_start=1;tick;load_start=0;send_sector(0,0,512);
  abort_load=1;tick;abort_load=0;repeat(3)tick;
  if(!ready || !paused || total!=1)$fatal(1,"abort lost partial catalogue");
  resume_scan=1;tick;resume_scan=0;repeat(3)tick;
  if(addr!=1808)$fatal(1,"resume restarted scan instead of continuing");
  send_sector(1,0,512);send_sector(2,0,512);send_sector(3,0,512);
  if(!done || total!=4 || found_count!=4 || seen[1]!=1808 || seen[2]!=3609 || seen[3]!=5410)
   $fatal(1,"fallback catalogue wrong");
 end
 $display("PASS fallback: CRC corruption in each slot, no partial-map exposure, P1 yield, abort and saved-position resume.");
 reset_start;send_sector(0,0,511);
 if(!fallback || found_count || addr!=5)$fatal(1,"truncated sector accepted");
 reset_start;good_probes;
 sd_init=0;repeat(3)tick;
 if(verified || paused || total || found_count)$fatal(1,"card loss retained stale map");
 reset_start;good_probes;resume_and_check;
 $display("PASS recovery: truncated-sector rejection, card-init loss, reset, repeat boot.");
 $finish;
end
initial begin #200000000;$fatal(1,"fast-boot watchdog state=%0d addr=%0d",dut.state,addr);end
endmodule
