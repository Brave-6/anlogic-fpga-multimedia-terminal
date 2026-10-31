`timescale 1ns/1ps
module tb_video_osd_overlay;
reg clk = 0, rst = 1, vs = 0, de = 1;
reg [23:0] rgb = 24'h3478AB;
reg [1:0] image_idx = 2'd2;
reg display_valid = 1, auto_play = 1, emergency = 0;
reg [1:0] brightness = 2'd2;
wire [23:0] rgb_osd;
always #5 clk = ~clk;

video_osd_overlay dut(
    .I_clk(clk), .I_rst(rst), .I_vs(vs), .I_de(de), .I_rgb(rgb),
    .I_image_idx(image_idx), .I_display_valid(display_valid),
    .I_auto_play(auto_play), .I_emergency(emergency),
    .I_brightness(brightness), .O_rgb(rgb_osd));

task check_pixel;
    input [9:0] x;
    input [8:0] y;
    input [23:0] expected;
    begin
        force dut.x_pos = x; force dut.y_pos = y; #1;
        if (rgb_osd !== expected)
            $fatal(1, "OSD mismatch at %0d,%0d: got %h expected %h", x, y, rgb_osd, expected);
        release dut.x_pos; release dut.y_pos;
    end
endtask

initial begin
    repeat (3) @(negedge clk); rst = 0; repeat (4) @(negedge clk);
    force dut.display_valid_frame = 1'b1;
    force dut.image_idx_frame = 2'd2;
    force dut.auto_play_frame = 1'b1;
    force dut.emergency_frame = 1'b0;
    force dut.brightness_frame = 2'd2;

    check_pixel(10'd12, 9'd12, 24'h102040);
    check_pixel(10'd22, 9'd20, 24'hFFE070); // A in ANLOGIC
    check_pixel(10'd20, 9'd34, 24'hFFE070); // P in P3
    check_pixel(10'd54, 9'd34, 24'hFFE070); // A in AUTO
    check_pixel(10'd20, 9'd50, 24'hFFE070); // B in B3

    force dut.emergency_frame = 1'b1;
    check_pixel(10'd52, 9'd34, 24'hFFE070); // E in EMERG

    de = 0; check_pixel(10'd22, 9'd20, rgb);
    de = 1; force dut.display_valid_frame = 1'b0; check_pixel(10'd22, 9'd20, rgb);
    $display("PASS: product OSD panel, ANLOGIC, page, AUTO/EMERG, brightness, blanking, and first-frame gating.");
    $finish;
end
initial begin #10000; $fatal(1, "watchdog"); end
endmodule
