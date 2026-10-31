`timescale 1ns/1ps
module tb_hdmi_audio_chain;
reg mclk=0,video_clk=0,rst=1;
always #40.690104 mclk=~mclk; // nominal 12.288 MHz
always #20 video_clk=~video_clk; // 25 MHz pixel domain
wire bclk,lrck,dout,audio_valid,acr_valid;
wire [23:0] left,right;
wire [19:0] cts,n;
integer video_cycles=0,last_valid_cycle=-1,valid_count=0,acr_count=0;
integer nonzero_count=0,min_interval=999999,max_interval=0,interval;
integer mclk_cycles=0,last_lr_rise=-1,lr_period_errors=0;

hdmi_audio_tone_i2s_64fs #(.AMP(24'sd2000000),.NOTE_HOLD_FRAMES(32)) tone(
 .I_mclk(mclk),.I_rst(rst),.O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
I2S_receiver receiver(.I_clk(video_clk),.I_rst(rst),.I_i2s_BCLK(bclk),
 .I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),.O_audio_valid(audio_valid),
 .O_audio_left_data(left),.O_audio_right_data(right));
audio_arc_calculate #(.ACR_N(6144)) acr(.I_clk(video_clk),.I_rst(rst),
 .I_audio_valid(audio_valid),.O_acr_valid(acr_valid),.O_acr_cts(cts),.O_acr_n(n));

reg lrck_d=0;
always @(posedge mclk) begin
 mclk_cycles=mclk_cycles+1;
 lrck_d<=lrck;
 if(!rst && lrck && !lrck_d) begin
  if(last_lr_rise>=0 && mclk_cycles-last_lr_rise!=256)lr_period_errors=lr_period_errors+1;
  last_lr_rise=mclk_cycles;
 end
end

always @(posedge video_clk) begin
 video_cycles=video_cycles+1;
 if(audio_valid===1'b1) begin
  valid_count=valid_count+1;
  if(last_valid_cycle>=0) begin
   interval=video_cycles-last_valid_cycle;
   if(interval<min_interval)min_interval=interval;
   if(interval>max_interval)max_interval=interval;
   if(interval<515 || interval>527)$fatal(1,"audio_valid cadence outside 48k tolerance");
  end
  last_valid_cycle=video_cycles;
  if(left!==right)$fatal(1,"stereo test tone channels differ");
  if(left!=0)nonzero_count=nonzero_count+1;
 end
 if(acr_valid===1'b1) begin
  acr_count=acr_count+1;
  if(n!==20'd6144)$fatal(1,"ACR N mismatch");
  if(cts<20'd24800 || cts>20'd25200)$fatal(1,"ACR CTS outside expected 25MHz/48k range");
 end
end

initial begin
 repeat(20)@(negedge video_clk);rst=0;
 wait(valid_count>=120);
 repeat(20)@(negedge video_clk);
 if(nonzero_count<100)$fatal(1,"test tone remained zero");
 if(acr_count<2)$fatal(1,"insufficient ACR packets");
 if(lr_period_errors!=0 || last_lr_rise<0)$fatal(1,"LRCK is not mclk/256");
 $display("PASS: 120 stereo PCM samples, valid cadence %0d..%0d video clocks (~48k), LRCK=mclk/256, ACR N=6144, CTS near25000, nonzero tone.",min_interval,max_interval);
 $display("NOTE: generator BCLK is mclk/2=128fs because this design serializes 64 bits per channel; stereo frame/LRCK remains 48k.");
 $finish;
end
initial begin #5000000;$fatal(1,"watchdog");end
endmodule
