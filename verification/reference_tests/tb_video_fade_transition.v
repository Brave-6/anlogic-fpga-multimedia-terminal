`timescale 1ns/1ps

module tb_video_fade_transition;
reg clk = 1'b0;
always #5 clk = ~clk;

reg rst = 1'b1;
reg vs = 1'b0;
reg de = 1'b0;
reg [23:0] rgb = 24'h804020;
reg [1:0] image_idx = 2'd0;
reg display_valid = 1'b0;
wire [23:0] faded;

video_fade_transition dut (
    .I_clk(clk),
    .I_rst(rst),
    .I_vs(vs),
    .I_de(de),
    .I_rgb(rgb),
    .I_image_idx(image_idx),
    .I_display_valid(display_valid),
    .O_rgb(faded)
);

task frame_start;
    begin
        @(negedge clk); de = 1'b0; vs = 1'b1;
        @(negedge clk); vs = 1'b0;
        repeat (3) @(negedge clk);
    end
endtask

task active_sample;
    input [23:0] expected;
    begin
        @(negedge clk); de = 1'b1;
        #1;
        if (faded !== expected)
            $fatal(1, "fade mismatch: got %h expected %h at %0t", faded, expected, $time);
    end
endtask

integer i;
integer rr;
integer gg;
integer bb;
reg [23:0] expected;
initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;

    // Before the first committed image, the source is transparent.
    active_sample(rgb);
    @(negedge clk); de = 1'b0;
    frame_start;
    active_sample(rgb);

    // Let the synchronized valid flag settle, then start first-image fade.
    display_valid = 1'b1;
    repeat (4) @(negedge clk);
    frame_start;

    active_sample(24'h000000);
    for (i = 1; i <= 15; i = i + 1) begin
        frame_start;
        rr = (8'h80 * i) / 16;
        gg = (8'h40 * i) / 16;
        bb = (8'h20 * i) / 16;
        expected = {rr[7:0], gg[7:0], bb[7:0]};
        active_sample(expected);
    end
    frame_start;
    active_sample(rgb);

    // Changing the committed image index restarts the fade.
    image_idx = 2'd1;
    repeat (4) @(negedge clk);
    frame_start;
    active_sample(24'h000000);
    frame_start;
    active_sample(24'h080402);

    // Blanking must not synthesize a black pixel or modify the source bus.
    @(negedge clk); de = 1'b0;
    #1;
    if (faded !== rgb)
        $fatal(1, "fade modified blanking pixel");

    $display("PASS: fade-through-black first-image start, 16-frame ramp, image-change restart, full-bright pass-through, and blanking.");
    $finish;
end

initial begin
    #1000000;
    $fatal(1, "fade simulation timeout");
end
endmodule
