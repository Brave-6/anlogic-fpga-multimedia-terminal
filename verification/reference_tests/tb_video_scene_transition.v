`timescale 1ns/1ps
module tb_video_scene_transition;
reg clk=0,rst=1,vs=1,req=0,emergency=0;
reg [1:0] page=0,buffer=0;
wire ack,accept,valid,stable,emerg;
wire [1:0] shown,bank;
wire [23:0] rgb;
always #20 clk=~clk;
video_scene_transition dut(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_rgb(24'h804020),
 .I_req_toggle(req),.I_page(page),.I_buffer(buffer),.I_emergency_request(emergency),
 .O_ack_toggle(ack),.O_accept(accept),.O_page(shown),.O_buffer(bank),.O_valid(valid),
 .O_emergency(emerg),.O_stable(stable),.O_rgb(rgb));
task tick;begin @(negedge clk);end endtask
task frame;begin vs=1;repeat(5)tick;vs=0;repeat(3)tick;vs=1;repeat(5)tick;end endtask
task offer;
 input [1:0] p,b;
 begin page=p;buffer=b;req=~req;repeat(6)tick;end
endtask
reg [1:0] old_page,old_bank;
reg [6:0] old_gain;
reg edge_sample;
integer i,prev_gain,commits=0;
always @(posedge clk) begin
 edge_sample=dut.boundary;old_page=shown;old_bank=bank;old_gain=dut.gain;
 #1;
 if(!rst && !edge_sample && (shown!==old_page || bank!==old_bank || dut.gain!==old_gain))
   $fatal(1,"visible state changed away from vertical sync");
 if(!rst && edge_sample && (shown!=old_page || bank!=old_bank)) commits=commits+1;
end
task finish_in;
 begin
  prev_gain=dut.gain;
  for(i=0;i<36;i=i+1) begin
   frame;
   if(dut.gain<prev_gain) $fatal(1,"nonmonotonic fade-in");prev_gain=dut.gain;
  end
  if(!stable || dut.gain!=64 || rgb!==24'h804020) $fatal(1,"fade-in not full after 36 frames");
 end
endtask
initial begin
 repeat(4)tick;rst=0;repeat(6)tick;
 offer(0,0);frame;
 if(!valid || ack!=req || !accept || dut.gain!=0) $fatal(1,"startup handshake failed");
 finish_in;
 offer(1,1);prev_gain=64;
 for(i=0;i<24;i=i+1) begin
  frame;
  if(shown!=0 || ack==req || dut.gain>=prev_gain) $fatal(1,"fade-out sequence failed");
  prev_gain=dut.gain;
 end
 if(rgb!=0) $fatal(1,"fade-out must reach black");
 frame;
 if(shown!=1 || bank!=1 || ack!=req || !accept || dut.gain!=0) $fatal(1,"black commit failed");
 finish_in;
 // Cancel a daily fade-out; its staged image must never be shown.
 offer(2,0);repeat(7)frame;
 if(shown!=1 || dut.gain==64) $fatal(1,"daily fade did not start");
 emergency=1;repeat(5)tick;frame;
 if(ack!=req || accept || shown!=1 || dut.gain!=64) $fatal(1,"emergency did not discard staged daily fade");
 offer(3,0);frame;
 if(shown!=3 || !emerg || !accept || rgb!==24'h804020) $fatal(1,"P4 not immediate/full bright");
 repeat(40)frame;if(dut.gain!=64) $fatal(1,"P4 faded");
 emergency=0;repeat(5)tick;offer(1,1);frame;
 if(shown!=1 || emerg || !stable || rgb!==24'h804020) $fatal(1,"P4 exit must direct-cut");
 // Cancel during fade-in without waiting its remaining 36 frames.
 offer(2,0);repeat(25)frame;repeat(4)frame;
 if(shown!=2 || dut.gain==64) $fatal(1,"test failed to enter daily fade-in");
 emergency=1;repeat(5)tick;frame;
 if(dut.gain!=64 || shown!=2) $fatal(1,"fade-in not interrupted");
 offer(3,1);frame;if(shown!=3 || !emerg || !accept || dut.gain!=64) $fatal(1,"emergency after fade-in failed");
 // An exit load cancelled by a second press cannot flash a daily page.
 emergency=0;repeat(5)tick;offer(2,0);emergency=1;repeat(5)tick;frame;
 if(accept || shown!=3 || !emerg || rgb!==24'h804020) $fatal(1,"cancelled exit displayed obsolete page");
 // No request is acknowledged twice; displayed bank stays protected.
 repeat(5)frame;if(ack!=req || bank!=1) $fatal(1,"mailbox duplicated");
 rst=1;repeat(4)tick;rst=0;req=0;emergency=0;repeat(6)tick;
 if(valid || stable || rgb!=0) $fatal(1,"reset failed");
 $display("PASS: 24-frame fade-out, 36-frame fade-in, atomic commit, P4 entry/exit direct, fade interruption, stale-target rejection, reset. Commits=%0d",commits);
 $finish;
end
initial begin #1000000;$fatal(1,"scene watchdog");end
endmodule
