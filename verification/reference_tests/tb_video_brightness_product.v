`timescale 1ns/1ps
module tb_video_brightness_product;
reg clk = 0, rst = 1, vs = 0, de = 1;
reg [23:0] rgb = 24'h4060F0;
reg [1:0] level = 2'd2;
wire [23:0] adjusted;
wire out_vs, out_de;
always #5 clk = ~clk;

video_brightness dut(.I_clk(clk), .I_rst(rst), .I_vs(vs), .I_de(de),
    .I_rgb(rgb), .I_level(level), .O_rgb(adjusted), .O_vs(out_vs), .O_de(out_de));

task settle; begin repeat (4) @(negedge clk); end endtask
initial begin
    repeat (2) @(negedge clk); rst = 0; settle;
    if (adjusted !== 24'h4060F0) $fatal(1, "standard level changed pixel: %h", adjusted);
    level = 2'd3; settle;
    if (adjusted !== 24'h7090FF) $fatal(1, "daylight level/clamp mismatch: %h", adjusted);
    level = 2'd0; settle;
    if (adjusted !== 24'h1030C0) $fatal(1, "night level mismatch: %h", adjusted);
    de = 0; rgb = 24'h123456; settle;
    if (adjusted !== 24'h123456 || out_de !== 0) $fatal(1, "blanking path changed");
    $display("PASS: four-level brightness standard, daylight clamp, night offset, and blanking pass-through.");
    $finish;
end
initial begin #10000; $fatal(1, "watchdog"); end
endmodule
