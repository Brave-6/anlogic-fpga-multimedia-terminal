`timescale 1ns/1ps
module tb_scene_pipeline;
reg sdclk=0,vclk=0,rst=1,key2=1,key4=1,finish_toggle=0;
always #5 sdclk=~sdclk;
always #20 vclk=~vclk;
reg [5:0] vcnt=0;
always @(posedge vclk) if(rst) vcnt<=0;else vcnt<=vcnt+1'b1;
wire vs=(vcnt>=2);
wire req,ack,accept,stable,emergency_request;
wire [1:0] pending_page,pending_buf,shown,bank,source_page,write_bank;
wire valid,auto_active,emerg;
sd_card_bmp_scene #(.CLK_FREQ_HZ(1000)) source(
 .clk(sdclk),.rst(rst),.key_next(key2),.key_auto(key4),.bmp_width(16'd640),.bmp_height(16'd480),
 .write_finish_toggle(finish_toggle),.write_req_ack(1'b0),.SD_MISO(1'b1),
 .present_ack_toggle(ack),.present_accept(accept),.scene_stable(stable),
 .present_req_toggle(req),.present_page(pending_page),.present_buffer(pending_buf),
 .emergency_request(emergency_request),.image_idx(source_page),.write_buf_idx(write_bank),.auto_play_active(auto_active),
 .state_code(),.display_valid(),.disp_buf_idx(),.emergency_active(),.write_req(),.write_en(),.write_data(),
 .SD_nCS(),.SD_DCLK(),.SD_MOSI());
video_scene_transition #(.FADE_OUT_FRAMES(4),.FADE_IN_FRAMES(6)) video(
 .I_clk(vclk),.I_rst(rst),.I_vs(vs),.I_rgb(24'hffffff),
 .I_req_toggle(req),.I_page(pending_page),.I_buffer(pending_buf),.I_emergency_request(emergency_request),
 .O_ack_toggle(ack),.O_accept(accept),.O_page(shown),.O_buffer(bank),.O_valid(valid),
 .O_emergency(emerg),.O_stable(stable),.O_rgb());
task tick;begin @(negedge sdclk);end endtask
task press2;begin key2=0;repeat(30)tick;key2=1;repeat(30)tick;end endtask
task press4;begin key4=0;repeat(30)tick;key4=1;repeat(30)tick;end endtask
task complete_load;
 begin
  tick; // Start asynchronous completion stimulus away from the producer edge.
  if(!source.load_busy || source.present_pending) $fatal(1,"not loading");
  force source.bmp_load_done=1;tick;force source.bmp_load_done=0;
  finish_toggle=~finish_toggle;repeat(8)tick;
 end
endtask
integer j;
integer daily_wait;
task expect_daily_load_soon;
 begin
  daily_wait=0;
  while(!source.load_busy && daily_wait<200)begin tick;daily_wait=daily_wait+1;end
  if(!source.load_busy)$fatal(1,"8-second daily deadline exceeded");
 end
endtask
reg [1:0] locked_page,locked_buf;
reg lock_mailbox=0;
always @(posedge sdclk) begin
 if(!rst) begin
   if(source.load_start_pulse) $display("load page=%0d bank=%0d t=%0t",pending_page,pending_buf,$time);
   if(source.present_pending && source.present_ack_sync[2]==req) $display("ack accept=%b page=%0d t=%0t",accept,pending_page,$time);
   if(source.load_start_pulse && valid && write_bank==bank) $fatal(1,"writer touched displayed buffer");
   if(lock_mailbox && source.present_pending && (pending_page!=locked_page || pending_buf!=locked_buf))
      $fatal(1,"mailbox payload changed before ack");
 end
 lock_mailbox<=source.present_pending;locked_page<=pending_page;locked_buf<=pending_buf;
end
initial begin
 if(source.DAILY_HOLD_SECONDS!=8)$fatal(1,"daily duration is not 8 seconds");
 force source.sd_init_done=1;force source.bmp_ready=1;force source.scan_done=0;
 force source.scan_found_valid=0;force source.bmp_load_done=0;
 repeat(5)tick;rst=0;repeat(6)tick;
 // Inject only SD scanner output/transfer completion, not UI/controller state.
 force source.scan_found_valid=1;force source.scan_found_sector=32'd100;tick;
 force source.scan_found_sector=32'd200;tick;
 force source.scan_found_sector=32'd300;tick;
 force source.scan_found_sector=32'd400;tick;
 force source.scan_found_valid=0;force source.scan_done=1;
 wait(source.load_busy);repeat(5)tick;
 if(pending_page!=0) $fatal(1,"first load not P1");
 // EOF alone cannot stage or publish a frame until SDRAM completion.
 force source.bmp_load_done=1;tick;force source.bmp_load_done=0;repeat(8)tick;
 if(req || source.present_pending || valid) $fatal(1,"EOF alone prematurely published");
 complete_load;wait(valid && stable);repeat(6)tick;
 if(shown!=0) $fatal(1,"P1 missing");
 repeat(2900)tick;if(source.load_busy) $fatal(1,"P1 hold too short");
 wait(source.load_busy);if(pending_page!=1) $fatal(1,"P1 must request P2");
 complete_load;wait(shown==1 && stable);repeat(6)tick;
 repeat(7900)tick;if(source.load_busy) $fatal(1,"daily dwell counted before full brightness");
 expect_daily_load_soon;if(pending_page!=2) $fatal(1,"P2 must request P3");
 // An emergency during disk IO waits for complete transfer, then discards it.
 press2;if(!emergency_request) $fatal(1,"KEY2 did not set priority");
 complete_load;
 wait(!source.load_busy);repeat(3)tick;wait(source.load_busy);
 if(pending_page!=3 || shown!=1) $fatal(1,"obsolete P3 shown or P4 request lost");
 complete_load;wait(shown==3);repeat(12)tick;
 if(!emerg || video.gain!=64 || auto_active) $fatal(1,"P4 must be full/no auto");
 press4;repeat(17000)tick;if(source.load_busy) $fatal(1,"KEY4/timer escaped P4");
 press2;wait(source.load_busy);if(pending_page!=1) $fatal(1,"exit must restore actual last daily page");
 complete_load;wait(shown==1);repeat(12)tick;
 if(!stable || video.gain!=64 || !auto_active) $fatal(1,"exit not direct/daily resumed");
 repeat(7900)tick;if(source.load_busy) $fatal(1,"exit did not restart full dwell");
 press4;repeat(17000)tick;if(source.load_busy || auto_active) $fatal(1,"pause failed");
 press4;wait(source.load_busy);complete_load;wait(shown==2 && stable);
 // Fresh boot: KEY2 during first-frame loading must not create a P1 retry loop.
 rst=1;force source.scan_done=0;repeat(5)tick;rst=0;repeat(6)tick;
 force source.scan_found_valid=1;force source.scan_found_sector=32'd100;tick;
 force source.scan_found_sector=32'd200;tick;
 force source.scan_found_sector=32'd300;tick;
 force source.scan_found_sector=32'd400;tick;
 force source.scan_found_valid=0;force source.scan_done=1;
 wait(source.load_busy);press2;complete_load;
 wait(!source.load_busy);repeat(3)tick;wait(source.load_busy);
 if(pending_page!=3 || valid) $fatal(1,"boot emergency request retry failed");
 complete_load;wait(valid && shown==3);repeat(10)tick;
 if(video.gain!=64) $fatal(1,"boot emergency faded");
 $display("PASS async SD/video pipeline: startup3s/daily8s after fade with deadline, double completion, mailbox ownership, emergency during load, P4 isolation, direct exit/dwell reset, KEY4 pause/resume.");$finish;
end
initial begin #4000000;$fatal(1,"pipeline watchdog shown=%0d stable=%b busy=%b pending=%b req/ack=%b%b auto=%b cnt=%0d",shown,stable,source.load_busy,source.present_pending,req,ack,auto_active,source.auto_cnt);end
endmodule
