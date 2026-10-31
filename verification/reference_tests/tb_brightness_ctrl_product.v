`timescale 1ns/1ps
module tb_brightness_ctrl_product;
reg clk = 0, rst = 1, key = 1;
wire [1:0] level;
always #5 clk = ~clk;

brightness_ctrl #(.CLK_FREQ_HZ(1000), .DEBOUNCE_MS(2)) dut(
    .I_clk(clk), .I_rst(rst), .I_key(key), .O_level(level));

task press_key;
begin
    key = 0; repeat (5) @(negedge clk);
    key = 1; repeat (5) @(negedge clk);
end
endtask

initial begin
    repeat (3) @(negedge clk); rst = 0; repeat (3) @(negedge clk);
    if (level !== 2'd2) $fatal(1, "default brightness is not standard");
    press_key; if (level !== 2'd3) $fatal(1, "standard -> daylight failed");
    press_key; if (level !== 2'd0) $fatal(1, "daylight -> night wrap failed");
    press_key; if (level !== 2'd1) $fatal(1, "night -> low failed");
    press_key; if (level !== 2'd2) $fatal(1, "low -> standard recovery failed");
    $display("PASS: KEY3 cycles standard, daylight, night, low, and back to standard.");
    $finish;
end
initial begin #10000; $fatal(1, "watchdog"); end
endmodule
