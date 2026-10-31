`timescale 1ns/1ps

module tb_brightness_contrast_ctrl;
reg clk = 1'b0;
always #5 clk = ~clk;
reg rst = 1'b1;
reg key1 = 1'b1;
reg key2 = 1'b1;
wire key1_sd, key2_sd;
wire [3:0] brightness, contrast;
wire adjust_mode;

brightness_contrast_ctrl #(
    .CLK_FREQ_HZ(1000),
    .HOLD_MS(3),
    .DEBOUNCE_MS(1)
) dut (
    .I_clk(clk), .I_rst(rst), .I_key1(key1), .I_key2(key2),
    .O_key1_to_sd(key1_sd), .O_key2_to_sd(key2_sd),
    .O_brightness(brightness), .O_contrast(contrast), .O_adjust_mode(adjust_mode)
);

task cycles;
    input integer count;
    begin repeat (count) @(posedge clk); end
endtask

initial begin
    cycles(3);
    rst = 1'b0;
    cycles(3);
    if (adjust_mode !== 1'b0 || key1_sd !== 1'b1 || key2_sd !== 1'b1)
        $fatal(1, "reset/idle state invalid");

    // Hold both keys long enough to enter adjustment mode.
    key1 = 1'b0;
    key2 = 1'b0;
    cycles(12);
    if (adjust_mode !== 1'b1 || key1_sd !== 1'b1 || key2_sd !== 1'b1)
        $fatal(1, "long-hold did not enter adjustment mode or mask SD keys");
    key1 = 1'b1;
    key2 = 1'b1;
    cycles(4);

    // One debounced KEY1 press increments brightness while KEY2 is masked.
    key1 = 1'b0;
    cycles(4);
    key1 = 1'b1;
    cycles(4);
    if (brightness !== 4'd9 || key1_sd !== 1'b1 || key2_sd !== 1'b1)
        $fatal(1, "brightness adjustment failed: b=%0d k1=%b k2=%b", brightness, key1_sd, key2_sd);

    // One debounced KEY2 press increments contrast.
    key2 = 1'b0;
    cycles(4);
    key2 = 1'b1;
    cycles(4);
    if (contrast !== 4'd9)
        $fatal(1, "contrast adjustment failed: c=%0d", contrast);

    // Hold both again to leave adjustment mode; ordinary button pass-through resumes.
    key1 = 1'b0;
    key2 = 1'b0;
    cycles(12);
    key1 = 1'b1;
    key2 = 1'b1;
    cycles(4);
    if (adjust_mode !== 1'b0 || key1_sd !== 1'b1 || key2_sd !== 1'b1)
        $fatal(1, "long-hold did not leave adjustment mode");

    key1 = 1'b0;
    #1;
    if (key1_sd !== 1'b0 || key2_sd !== 1'b1)
        $fatal(1, "normal mode did not pass KEY1 to SD controller");

    $display("PASS: both-key mode entry/exit, SD-key masking, brightness/contrast adjustment, and normal pass-through.");
    $finish;
end

initial begin
    #10000;
    $fatal(1, "brightness/contrast control simulation timeout");
end
endmodule
