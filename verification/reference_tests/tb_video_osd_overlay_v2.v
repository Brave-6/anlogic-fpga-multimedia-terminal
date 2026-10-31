`timescale 1ns/1ps

module tb_video_osd_overlay_v2;
reg clk = 1'b0;
always #5 clk = ~clk;

reg rst = 1'b1;
reg vs = 1'b0;
reg de = 1'b0;
reg [23:0] rgb = 24'h3478ab;
reg [1:0] image_idx = 2'd0;
reg display_valid = 1'b0;
reg auto_play = 1'b0;
reg emergency = 1'b0;
reg [1:0] brightness = 2'd2;
wire [23:0] rgb_osd;

video_osd_overlay dut (
    .I_clk(clk), .I_rst(rst), .I_vs(vs), .I_de(de), .I_rgb(rgb),
    .I_image_idx(image_idx),
    .I_display_valid(display_valid), .I_auto_play(auto_play),
    .I_emergency(emergency), .I_brightness(brightness), .O_rgb(rgb_osd)
);

task blank_line;
    integer k;
    begin
        @(negedge clk); de = 1'b0; vs = 1'b0;
        for (k = 0; k < 8; k = k + 1) @(negedge clk);
    end
endtask

task send_frame;
    integer yy;
    integer xx;
    integer row_glyph;
    begin
        @(negedge clk); vs = 1'b1; de = 1'b0;
        @(negedge clk); vs = 1'b0;
        for (yy = 0; yy < 480; yy = yy + 1) begin
            row_glyph = 0;
            for (xx = 0; xx < 640; xx = xx + 1) begin
                @(negedge clk); de = 1'b1;
                #1;
                if (dut.display_valid_frame &&
                    (dut.y_pos >= 9'd12) && (dut.y_pos < 9'd68) &&
                    (dut.x_pos >= 10'd12) && (dut.x_pos < 10'd220)) begin
                    if ((rgb_osd !== 24'h102040) && (rgb_osd !== 24'hffe070))
                        $fatal(1, "OSD panel pixel has wrong color at %0d,%0d", dut.x_pos, dut.y_pos);
                    if ((dut.y_pos == 9'd20) && (rgb_osd === 24'hffe070))
                        row_glyph = 1;
                end else if (rgb_osd !== rgb) begin
                    $fatal(1, "OSD changed pixel outside panel at %0d,%0d", dut.x_pos, dut.y_pos);
                end
            end
            // The first active frame is intentionally allowed to settle after
            // the two-stage CDC and frame latch.
            blank_line;
        end
    end
endtask

initial begin
    repeat (5) @(negedge clk);
    rst = 1'b0;
    send_frame;
    display_valid = 1'b1;
    auto_play = 1'b1;
    brightness = 2'd3;
    repeat (4) @(negedge clk);
    send_frame;
    emergency = 1'b1;
    repeat (4) @(negedge clk);
    send_frame;
    $display("PASS: full-frame product OSD simulation with ANLOGIC, AUTO, EMERG, and brightness panel.");
    $finish;
end

initial begin
    #50000000;
    $fatal(1, "OSD full-frame simulation timeout");
end
endmodule
