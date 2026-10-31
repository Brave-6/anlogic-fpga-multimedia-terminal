`timescale 1ns/1ps
module tb_boot_audio_real_pcm;
reg mclk=0,vclk=0,rst=1,valid=0,ready=0;
always #40.690104 mclk=~mclk;
always #20 vclk=~vclk;
wire bclk,lrck,dout,audio_valid;
wire [23:0] left,right;
integer nonzero=0,samples=0,events=0,before_event=0;
integer clocks=0,last_clock=0,delta;
scene_audio_i2s #(.BOOT_DELAY_CYCLES(1024),
 .INIT_FILE("src/user_source/hdl_source/audio/scene_audio.mem")) player(
 .I_mclk(mclk),.I_rst(rst),.I_display_valid(valid),.I_boot_ready(ready),
 .I_emergency_active(1'b0),.O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
I2S_receiver receiver(.I_clk(vclk),.I_rst(rst),.I_i2s_BCLK(bclk),
 .I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),.O_audio_valid(audio_valid),
 .O_audio_left_data(left),.O_audio_right_data(right));
always @(posedge mclk)if(!rst && player.boot_event)events=events+1;
always @(posedge vclk)begin
 clocks=clocks+1;
 if(!rst && audio_valid)begin
  if(last_clock!=0)begin
   delta=clocks-last_clock;
   if(delta<515 || delta>527)$fatal(1,"bad PCM cadence");
  end
  last_clock=clocks;
  if(!events && (left!==0 || right!==0))before_event=before_event+1;
  if(events)begin
   samples=samples+1;
   if(samples>8 && left!==right)$fatal(1,"stereo mismatch");
   if(left!=0)nonzero=nonzero+1;
  end
 end
end
initial begin
 repeat(20)@(negedge vclk);rst=0;valid=1;
 repeat(2000)@(negedge mclk);
 if(events || player.playing)$fatal(1,"startup before readiness");
 ready=1;
 wait(samples>=6144);
 if(events!=1 || before_event || nonzero<2000)$fatal(1,"real boot PCM missing events=%0d early=%0d nonzero=%0d",events,before_event,nonzero);
 if(player.sample_addr>=12526)$fatal(1,"not playing boot ROM region");
 $display("PASS real boot clip: source ROM -> delayed player -> I2S receiver, 6144 stereo frames at 48kHz, %0d nonzero, silence before ready, one start event.",nonzero);
 $finish;
end
initial begin #150000000;$fatal(1,"real boot PCM watchdog");end
endmodule
