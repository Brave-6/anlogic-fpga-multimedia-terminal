`timescale 1ns/1ps
module tb_scene_audio_i2s;
reg mclk = 0, rst = 1, display_valid = 0, emergency = 0;
wire bclk, lrck, dout;
always #5 mclk = ~mclk;

scene_audio_i2s #(
    .INIT_FILE("scene_audio_test.mem"),
    .BOOT_START(0), .BOOT_LENGTH(4),
    .EMERGENCY_START(4), .EMERGENCY_LENGTH(4),
    .CLEAR_START(8), .CLEAR_LENGTH(4), .TOTAL_SAMPLES(12)
) dut(.I_mclk(mclk), .I_rst(rst), .I_display_valid(display_valid),
    .I_emergency_active(emergency), .O_i2s_BCLK(bclk),
    .O_i2s_LRCK(lrck), .O_i2s_DOUT(dout));

initial begin
    repeat (4) @(negedge mclk); rst = 0;
    display_valid = 1; repeat (6) @(negedge mclk);
    if (!dut.playing || dut.sample_addr !== 0) $fatal(1, "boot clip did not start");
    emergency = 1; repeat (6) @(negedge mclk);
    if (!dut.playing || dut.sample_addr !== 4) $fatal(1, "emergency clip did not pre-empt boot");
    emergency = 0; repeat (6) @(negedge mclk);
    if (!dut.playing || dut.sample_addr !== 8) $fatal(1, "all-clear clip did not pre-empt emergency");
    $display("PASS: boot, emergency, and all-clear events select and pre-empt the expected clips.");
    $finish;
end
initial begin #100000; $fatal(1, "watchdog"); end
endmodule
