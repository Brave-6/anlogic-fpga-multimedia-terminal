`timescale 1ns/1ps
module tb_bottom_osd;
reg clk=0,rst=1,vs=0,de=0,key=1;
reg [23:0] rgb=24'ha0b0c0;
reg [1:0] page=0;
reg valid=0,auto_play=1,emergency=0;
wire [23:0] out_rgb;
wire out_vs,out_de,content;
wire [2:0] level;
always #5 clk=~clk;
video_bottom_osd #(.KEY_STABLE_CYCLES(3),.POPUP_FRAMES(3)) dut(
 .I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),.I_rgb(rgb),
 .I_image_idx(page),.I_display_valid(valid),.I_auto_play(auto_play),
 .I_emergency(emergency),.I_key3(key),.O_rgb(out_rgb),.O_vs(out_vs),.O_de(out_de),
 .O_brightness_level(level),.O_content_active(content),.O_frame_valid());
wire [23:0] adjusted;
reg [2:0] test_level=2;
video_brightness_five adjustment(.I_rgb(24'h1030f0),.I_level(test_level),.I_enable(1'b1),.O_rgb(adjusted));

reg prev_de=0,prev_vs=0,prev_hidden=1;
reg [23:0] prev_rgb=0;
reg [9:0] prev_x=0;
reg [8:0] prev_y=0;
reg current_de,current_vs,current_hidden;
reg [23:0] current_rgb;
reg [9:0] current_x;
reg [8:0] current_y;
integer checks=0,glyph_pixels=0,pixels=0;
integer warmup=0;
// Check actual full-stream pixel coordinates, not forced internal counters.
always @(posedge clk) begin
 current_de=de; current_vs=vs; current_rgb=rgb;
 current_x=dut.x_pos; current_y=dut.y_pos;
 current_hidden=!content;
 #1;
 if(rst) warmup=0;
 else warmup=warmup+1;
 if(!rst && warmup>2) begin
   if(out_de!==prev_de || out_vs!==prev_vs) $fatal(1,"VS/DE latency mismatch");
   if(prev_hidden || !prev_de) begin
     if(out_rgb!==prev_rgb) $fatal(1,"P1/blanking/invalid pixel modified");
   end else begin
     if(prev_x==200 && prev_y==468 && out_rgb!==24'h1c2c4e)
       $fatal(1,"status background mismatch %h",out_rgb);
     if(prev_x==2 && prev_y==433 && out_rgb!==24'h434a51)
       $fatal(1,"ticker alpha mismatch %h",out_rgb);
     if(prev_x==50 && prev_y==468 && out_rgb!==24'hedeef1)
       $fatal(1,"first brightness block missing");
     if(prev_x==100 && prev_y==100 && out_rgb!==prev_rgb)
       $fatal(1,"old upper-left panel remains");
     if(prev_x>=86 && prev_x<632 && prev_y>=435 && prev_y<451 && out_rgb!=24'h434a51)
       glyph_pixels=glyph_pixels+1;
   end
   checks=checks+1;
 end
 prev_de=current_de; prev_vs=current_vs; prev_rgb=current_rgb;
 prev_x=current_x; prev_y=current_y; prev_hidden=current_hidden;
end

task tick; begin @(negedge clk); end endtask
task frame_edge;
 begin
   de=0; vs=0; repeat(5) tick;
   vs=1; tick; vs=0; repeat(4) tick;
 end
endtask
task scan;
 integer x,y;
 begin
   frame_edge;
   for(y=0;y<480;y=y+1) begin
     for(x=0;x<640;x=x+1) begin de=1; tick; end
     de=0; repeat(160) tick;
   end
   repeat(5) tick;
 end
endtask
task press;
 begin key=0;repeat(8) tick;key=1;repeat(8) tick;end
endtask
integer n;
reg [12:0] saved_scroll;
initial begin
 repeat(5) tick;rst=0;
 scan; // invalid frame
 valid=1;page=0; scan; // P1 absolutely no overlay
 page=1;scan;
 if(!content || level!=2 || glyph_pixels<100) $fatal(1,"P2 UI incomplete");
 // Reject a short bounce and defer accepted level until blanking.
 key=0;tick;key=1;repeat(8) tick;frame_edge;
 if(level!=2) $fatal(1,"bounce changed brightness");
 press;
 if(level!=2) $fatal(1,"brightness changed mid-frame");
 frame_edge;
 if(level!=3 || dut.popup_count!=3) $fatal(1,"brightness popup not armed");
 // The same level drives both sets of blocks.
 scan;
 press;frame_edge;if(level!=4) $fatal(1,"level 5 missing");
 press;frame_edge;if(level!=0) $fatal(1,"level 5 wrap failed");
 press;frame_edge;if(level!=1) $fatal(1,"level 2 missing");
 press;frame_edge;if(level!=2) $fatal(1,"default recovery failed");
 repeat(3) frame_edge;
 if(dut.popup_count!=0) $fatal(1,"popup did not expire");
 key=0;repeat(8) tick;frame_edge;
 repeat(4) frame_edge;
 if(level!=3) $fatal(1,"held key repeated");
 key=1;repeat(8) tick;
 page=0;scan;
 if(content || dut.popup_count!=0) $fatal(1,"P1 popup not hidden");
 page=2;scan;
 if(dut.ticker_base!=dut.TICK_P3_START) $fatal(1,"P3 text selection failed");
 auto_play=0;frame_edge;
 if(dut.auto_frame!=0) $fatal(1,"HOLD state not latched");
 page=3;emergency=1;frame_edge;
 if(dut.scroll_offset!=0 || dut.ticker_base!=dut.TICK_P4_START || !dut.emerg_frame)
   $fatal(1,"emergency text switch did not reset scroll");
 scan;
 for(n=0;n<1600;n=n+1) begin
   saved_scroll=dut.scroll_offset; frame_edge;
   if(dut.scroll_offset>=dut.ticker_width) $fatal(1,"scroll out of bounds");
 end
 test_level=0;#1;if(adjusted!==24'h0000c0) $fatal(1,"low clamp failed");
 test_level=1;#1;if(adjusted!==24'h0018d8) $fatal(1,"low offset failed");
 test_level=2;#1;if(adjusted!==24'h1030f0) $fatal(1,"neutral failed");
 test_level=3;#1;if(adjusted!==24'h2848ff) $fatal(1,"high offset failed");
 test_level=4;#1;if(adjusted!==24'h4060ff) $fatal(1,"high clamp failed");
 $display("PASS bottom OSD: %0d stream checks; P1/invalid bypass, alpha, glyphs, five levels, bounce/hold, frame latch, popup and scrolling.",checks);
 $finish;
end
initial begin #100000000;$fatal(1,"watchdog");end
endmodule
