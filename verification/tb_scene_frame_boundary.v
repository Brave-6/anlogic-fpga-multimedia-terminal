`timescale 1ns/1ps
// Exercise real 640x480 timing and real memory read-controller CDC. No SDRAM
// electrical model: verify frame-buffer address is selected before read ACK.
module tb_scene_frame_boundary;
reg vclk=0,mclk=0,rst=1,req=0,emergency=0;
always #20 vclk=~vclk;
always #12.5 mclk=~mclk;
wire hs,vs,de,read_req,read_ack,valid,stable,emerg;
wire [1:0] page,bufidx;
reg [1:0] offered_page=0,offered_buffer=0;
wire ack,accepted;
wire [20:0] address;
reg [7:0] req_pipe=0;
always @(posedge vclk) if(rst)req_pipe<=0;else req_pipe<={req_pipe[6:0],read_req};
video_timing_data timing(.video_clk(vclk),.rst(rst),.read_req(read_req),.read_req_ack(read_ack),.hs(hs),.vs(vs),.de(de));
video_scene_transition #(.FADE_OUT_FRAMES(2),.FADE_IN_FRAMES(2)) scene(
 .I_clk(vclk),.I_rst(rst),.I_vs(vs),.I_rgb(24'hffffff),
 .I_req_toggle(req),.I_page(offered_page),.I_buffer(offered_buffer),.I_emergency_request(emergency),
 .O_ack_toggle(ack),.O_accept(accepted),.O_page(page),.O_buffer(bufidx),.O_valid(valid),
 .O_emergency(emerg),.O_stable(stable),.O_rgb());
frame_fifo_read reader(.rst(rst),.mem_clk(mclk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(1'b0),.Sdr_rd_en(1'b0),.App_wr_busy(1'b0),.O_rd_busy(),.App_rd_en(),.App_rd_addr(address),
 .read_req(req_pipe[7]),.read_req_ack(read_ack),.read_finish(),.read_addr_0(21'd0),.read_addr_1(21'd307200),
 .read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(bufidx),.read_len(21'd307200),
 .fifo_aclr(),.wrusedw(10'd512));
reg ack_d=0,commit_edge;
reg [1:0] last_page,last_buffer;
integer frames_checked=0;
always @(posedge mclk) begin
 ack_d<=read_ack;
 if(!rst && read_ack && !ack_d) begin
   if(address !== (bufidx==0 ? 21'd0 : 21'd307200)) $fatal(1,"new frame selected old buffer");
   frames_checked=frames_checked+1;
 end
end
always @(posedge vclk) begin
 commit_edge=scene.boundary;last_page=page;last_buffer=bufidx;
 #1;
 if(!rst && (last_page!=page || last_buffer!=bufidx) && (!commit_edge || de))
   $fatal(1,"page/bank changed during active pixels or outside commit boundary");
end
task request;
 input [1:0] p,b;
 begin @(negedge vclk);offered_page=p;offered_buffer=b;req=~req; end
endtask
initial begin
 repeat(10)@(negedge vclk);rst=0;
 request(0,0);wait(valid && stable);
 request(1,1);wait(page==1 && stable);
 @(negedge vclk);emergency=1;request(3,0);wait(page==3);
 if(scene.gain!=64)$fatal(1,"emergency not full brightness");
 @(negedge de);@(negedge vclk);emergency=0;request(1,1);wait(page==1);
 if(scene.gain!=64)$fatal(1,"exit not full brightness");
 wait(read_ack);repeat(30)@(negedge vclk);
 if(frames_checked<7)$fatal(1,"not enough real frame handshakes");
 $display("PASS: real 800x525 video timing, 25/40MHz CDC, buffer address before read ACK, %0d frame handshakes.",frames_checked);$finish;
end
initial begin #250000000;$fatal(1,"frame boundary watchdog");end
endmodule
