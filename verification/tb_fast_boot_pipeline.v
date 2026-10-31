`timescale 1ns/1ps
module tb_fast_boot_pipeline;
reg clk=0,vclk=0,rst=1,finish_toggle=0;
reg [5:0] vcnt=0;
always #5 clk=~clk;
always #20 vclk=~vclk;
always @(posedge vclk)if(rst)vcnt<=0;else vcnt<=vcnt+1'b1;
wire vs=(vcnt>=2);
reg [7:0] data=0;
reg dv=0,se=0;
wire req,ack,accept,stable,emergency,valid;
wire [1:0] offered_page,offered_bank,shown,shown_bank;
reg [7:0] image_mem[0:2047];
integer i,k,reads=0,pixel_count=0;
sd_card_bmp_scene #(.CLK_FREQ_HZ(1000),.FAST_SCAN_ENABLE(1),
 .FAST_SECTOR0(100),.FAST_SECTOR1(200),.FAST_SECTOR2(300),.FAST_SECTOR3(400)) source(
 .clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),
 .present_ack_toggle(ack),.present_accept(accept),.scene_stable(stable),
 .present_req_toggle(req),.present_page(offered_page),.present_buffer(offered_bank),
 .emergency_request(emergency),.state_code(),.bmp_width(16'd640),.bmp_height(16'd480),
 .display_valid(),.write_finish_toggle(finish_toggle),.write_buf_idx(),.disp_buf_idx(),
 .image_idx(),.auto_play_active(),.emergency_active(),.write_req(),.write_req_ack(1'b1),
 .write_en(),.write_data(),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1));
video_scene_transition video(.I_clk(vclk),.I_rst(rst),.I_vs(vs),.I_rgb(24'hffffff),
 .I_req_toggle(req),.I_page(offered_page),.I_buffer(offered_bank),.I_emergency_request(emergency),
 .O_ack_toggle(ack),.O_accept(accept),.O_page(shown),.O_buffer(shown_bank),
 .O_valid(valid),.O_emergency(),.O_stable(stable),.O_rgb());
always @(posedge clk)begin
 if(rst)pixel_count=0;
 else begin
  if(source.write_en)pixel_count=pixel_count+1;
  if(source.scan_resume_pulse && (!source.first_image_committed || source.load_busy))
   $fatal(1,"scan resumed before video acceptance");
  if(!valid && source.scan_done)$fatal(1,"catalogue completed before P1 acceptance");
 end
end
task tick;begin @(negedge clk);end endtask
task sector;
 input integer page;
 begin
  wait(source.sd_sec_read);tick;reads=reads+1;
  for(k=0;k<512;k=k+1)begin data=image_mem[page*512+k];dv=1;tick;end
  dv=0;repeat(2)tick;se=1;tick;se=0;repeat(4)tick;
 end
endtask
initial begin
 $readmemh("verification/fast_boot_fixtures/P1.mem",image_mem,0,511);
 $readmemh("verification/fast_boot_fixtures/P2.mem",image_mem,512,1023);
 $readmemh("verification/fast_boot_fixtures/P3.mem",image_mem,1024,1535);
 $readmemh("verification/fast_boot_fixtures/P4.mem",image_mem,1536,2047);
 // Mock only physical SD transport; parser and controller run unchanged.
 force source.sd_init_done=1'b1;
 force source.sd_sec_read_data=data;
 force source.sd_sec_read_data_valid=dv;
 force source.sd_sec_read_end=se;
 repeat(5)tick;rst=0;
 for(i=0;i<4;i=i+1)begin
  wait(source.sd_sec_read);
  if(source.sd_sec_read_addr!==100*(i+1))$fatal(1,"wrong physical fast probe");
  sector(i);
 end
 wait(source.load_busy);
 if(source.scan_done || source.img_found_count!=1 || offered_page!=0)
  $fatal(1,"P1 did not get priority");
 sector(0);
 for(i=0;i<1801;i=i+1)sector(0);
 repeat(20)tick;
 if(valid || source.scan_done || !source.scan_paused || !source.source_done_seen || pixel_count!=307200)
  $fatal(1,"EOF alone committed/restarted scanner or pixel count wrong");
 finish_toggle=~finish_toggle;
 wait(valid);wait(source.scan_done);repeat(10)tick;
 if(source.img_found_count!=4 || source.img_sector0!=100 || source.img_sector1!=200 ||
    source.img_sector2!=300 || source.img_sector3!=400 || shown!=0 || shown_bank!=0 || reads!=1806)
  $fatal(1,"scene catalogue/resume corrupt");
 wait(stable);repeat(10)tick;
 if(!source.first_image_committed)$fatal(1,"P1 commit missing");
 $display("PASS recovery integration: real BMP parser, 307200 pixel writes, memory completion plus asynchronous frame ACK before scan resume, P1 fade and ordered catalogue.");
 $finish;
end
initial begin #100000000;$fatal(1,"fast boot integration watchdog");end
endmodule
