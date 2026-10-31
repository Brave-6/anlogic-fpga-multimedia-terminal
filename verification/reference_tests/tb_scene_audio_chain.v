`timescale 1ns/1ps
module tb_scene_audio_chain;
reg mclk = 0, video_clk = 0, rst = 1;
reg display_valid = 0, emergency = 0;
always #40.690104 mclk = ~mclk;
always #20 video_clk = ~video_clk;

wire bclk, lrck, dout, audio_valid;
wire [23:0] left, right;
integer video_cycles = 0, last_valid = -1, valid_count = 0;
integer min_interval = 999999, max_interval = 0, interval;
integer nonzero = 0;

scene_audio_i2s #(
    .INIT_FILE("scene_audio_test.mem"),
    .BOOT_START(0), .BOOT_LENGTH(4),
    .EMERGENCY_START(4), .EMERGENCY_LENGTH(4),
    .CLEAR_START(8), .CLEAR_LENGTH(4), .TOTAL_SAMPLES(12)
) player(.I_mclk(mclk), .I_rst(rst), .I_display_valid(display_valid),
    .I_emergency_active(emergency), .O_i2s_BCLK(bclk),
    .O_i2s_LRCK(lrck), .O_i2s_DOUT(dout));

I2S_receiver receiver(.I_clk(video_clk), .I_rst(rst),
    .I_i2s_BCLK(bclk), .I_i2s_LRCK(lrck), .I_i2s_DOUT(dout),
    .O_audio_valid(audio_valid), .O_audio_left_data(left),
    .O_audio_right_data(right));

always @(posedge video_clk) begin
    video_cycles = video_cycles + 1;
    if (audio_valid) begin
        valid_count = valid_count + 1;
        if (last_valid >= 0) begin
            interval = video_cycles - last_valid;
            if (interval < min_interval) min_interval = interval;
            if (interval > max_interval) max_interval = interval;
            if (interval < 515 || interval > 527)
                $fatal(1, "48 kHz cadence out of range: %0d", interval);
        end
        last_valid = video_cycles;
        if (valid_count <= 8)
            $display("sample %0d left=%h right=%h", valid_count, left, right);
        if ((valid_count > 4) && (left !== right))
            $fatal(1, "scene audio channels differ after startup: left=%h right=%h", left, right);
        if (left != 0) nonzero = nonzero + 1;
    end
end

initial begin
    repeat (20) @(negedge video_clk); rst = 0;
    display_valid = 1;
    wait(valid_count >= 30);
    if (nonzero < 12) $fatal(1, "scene audio remained silent: %0d", nonzero);
    if (min_interval < 515 || max_interval > 527) $fatal(1, "cadence summary invalid");
    $display("PASS: scene ROM -> I2S -> HDMI receiver produced stereo nonzero PCM at ~48 kHz.");
    $finish;
end
initial begin #2000000; $fatal(1, "watchdog"); end
endmodule
