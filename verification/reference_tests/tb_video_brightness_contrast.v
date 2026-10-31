`timescale 1ns/1ps

module tb_video_brightness_contrast;
reg clk = 1'b0;
always #5 clk = ~clk;
reg rst = 1'b1;
reg de = 1'b0;
reg vs = 1'b0;
reg [23:0] rgb = 24'h804020;
reg [3:0] brightness = 4'd8;
reg [3:0] contrast = 4'd8;
wire [23:0] adjusted;
wire adjusted_vs;
wire adjusted_de;

video_brightness_contrast dut (
    .I_clk(clk), .I_rst(rst), .I_vs(vs), .I_de(de), .I_rgb(rgb),
    .I_brightness(brightness), .I_contrast(contrast), .O_rgb(adjusted),
    .O_vs(adjusted_vs), .O_de(adjusted_de)
);

task settle;
    begin repeat (4) @(posedge clk); end
endtask

initial begin
    repeat (3) @(posedge clk);
    rst = 1'b0;
    de = 1'b1;
    settle;
    if (adjusted !== rgb)
        $fatal(1, "neutral brightness/contrast changed pixel: %h", adjusted);

    brightness = 4'd0;
    contrast   = 4'd8;
    settle;
    if (adjusted !== 24'h000000)
        $fatal(1, "minimum brightness did not clamp black: %h", adjusted);

    brightness = 4'd15;
    contrast   = 4'd8;
    rgb        = 24'h808080;
    settle;
    if (adjusted !== 24'hf0f0f0)
        $fatal(1, "maximum brightness mismatch: %h", adjusted);

    brightness = 4'd8;
    contrast   = 4'd0;
    rgb        = 24'h004080;
    settle;
    if (adjusted !== 24'h406080)
        $fatal(1, "low contrast mismatch: %h", adjusted);

    de = 1'b0;
    settle;
    #1;
    if (adjusted !== rgb)
        $fatal(1, "blanking pixel was modified");

    $display("PASS: brightness/contrast neutral, clamp, contrast scaling, and blanking behavior.");
    $finish;
end

initial begin
    #10000;
    $fatal(1, "brightness/contrast simulation timeout");
end
endmodule
