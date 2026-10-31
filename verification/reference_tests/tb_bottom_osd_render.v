`timescale 1ns/1ps
module tb_bottom_osd_render;
reg clk=0,rst=1,vs=0,de=0,key=1;
always #5 clk=~clk;
reg [1:0] page=0;
reg emergency=0;
reg [23:0] input_pixel=0;
wire [23:0] adjusted,out_rgb;
wire out_vs,out_de,content;
wire [2:0] level;
reg [23:0] pixels[0:307199];
integer fd=0,count=0;
reg recording=0;
video_brightness_five adjuster(.I_rgb(input_pixel),.I_level(level),.I_enable(content),.O_rgb(adjusted));
video_bottom_osd #(.KEY_STABLE_CYCLES(3)) dut(
 .I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),.I_rgb(adjusted),
 .I_image_idx(page),.I_display_valid(1'b1),.I_auto_play(1'b1),
 .I_emergency(emergency),.I_key3(key),.O_rgb(out_rgb),.O_vs(out_vs),.O_de(out_de),
 .O_brightness_level(level),.O_content_active(content),.O_frame_valid());
always @(posedge clk) begin
 #2;
 if(recording && out_de) begin
   $fwrite(fd,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
   count=count+1;
 end
end
task tick;begin @(negedge clk);end endtask
task capture;
 input [1023:0] source_path;
 input [1023:0] target_path;
 integer x,y;
 begin
  de=0; repeat(10) tick;
  $readmemh(source_path,pixels);
  fd=$fopen(target_path,"wb"); if(!fd) $fatal(1,"cannot open render output");
  $fwrite(fd,"P6\n640 480\n255\n");count=0;recording=1;
  vs=1;tick;vs=0;repeat(4)tick;
  for(y=0;y<480;y=y+1) begin
   for(x=0;x<640;x=x+1) begin de=1;input_pixel=pixels[y*640+x];tick;end
   de=0; repeat(160)tick;
  end
  repeat(5)tick;recording=0;$fclose(fd);
  if(count!=307200) $fatal(1,"render pixel count %0d",count);
 end
endtask
initial begin
 repeat(5)tick;rst=0;repeat(10)tick;
 capture("P1.mem","P1.ppm");
 page=1;capture("P2.mem","P2.ppm");
 key=0;repeat(8)tick;key=1;repeat(8)tick;
 capture("P2.mem","P2_adjust.ppm");
 // Wait virtual frames for the real popup counter, no force on UI state.
 repeat(120) begin vs=1;tick;vs=0;repeat(4)tick;end
 page=2;capture("P3.mem","P3.ppm");
 page=3;emergency=1;capture("P4.mem","P4.ppm");
 $display("PASS: five full RTL rendered frames, exactly 307200 pixels each.");$finish;
end
initial begin #100000000;$fatal(1,"render watchdog");end
endmodule
