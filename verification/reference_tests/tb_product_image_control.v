`timescale 1ns/1ps
module tb_product_image_control;
reg clk = 0, rst = 1, key_emergency = 1, key_auto = 1;
reg finish_toggle = 0;
wire [1:0] image_idx;
wire auto_active, emergency_active, display_valid;
always #5 clk = ~clk;

sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut(
    .clk(clk), .rst(rst), .key_next(key_emergency), .key_auto(key_auto),
    .state_code(), .bmp_width(16'd640), .bmp_height(16'd480),
    .display_valid(display_valid), .write_finish_toggle(finish_toggle),
    .write_buf_idx(), .disp_buf_idx(), .image_idx(image_idx),
    .auto_play_active(auto_active), .emergency_active(emergency_active),
    .write_req(), .write_req_ack(1'b0), .write_en(), .write_data(),
    .SD_nCS(), .SD_DCLK(), .SD_MOSI(), .SD_MISO(1'b1));

task press_emergency;
begin key_emergency = 0; repeat (25) @(negedge clk); key_emergency = 1; repeat (25) @(negedge clk); end
endtask
task press_auto;
begin key_auto = 0; repeat (25) @(negedge clk); key_auto = 1; repeat (25) @(negedge clk); end
endtask
task commit_load;
begin
    wait(dut.load_busy === 1'b1);
    force dut.source_done_seen = 1'b1;
    force dut.write_done_seen = 1'b1;
    repeat (2) @(negedge clk);
    release dut.source_done_seen;
    release dut.write_done_seen;
    repeat (3) @(negedge clk);
end
endtask

initial begin
    force dut.sd_init_done = 1'b1;
    force dut.scan_done = 1'b1;
    force dut.bmp_ready = 1'b1;
    repeat (4) @(negedge clk); rst = 0; repeat (4) @(negedge clk);
    dut.scan_kicked = 1'b1;
    dut.first_image_committed = 1'b1;
    dut.display_valid = 1'b1;
    dut.img_found_count = 3'd4;
    dut.img_sector0 = 32'd10; dut.img_sector1 = 32'd20;
    dut.img_sector2 = 32'd30; dut.img_sector3 = 32'd40;
    dut.img_idx = 2'd0; dut.normal_idx = 2'd1;

    repeat (1010) @(negedge clk);
    if (!dut.load_busy || dut.load_idx !== 2'd1) $fatal(1, "P1 did not advance to P2");
    commit_load;
    if (image_idx !== 2'd1 || !auto_active) $fatal(1, "P2 daily mode did not commit");

    repeat (1010) @(negedge clk);
    if (!dut.load_busy || dut.load_idx !== 2'd2) $fatal(1, "daily playlist did not select P3");
    commit_load;

    press_emergency;
    wait(dut.load_busy === 1'b1);
    if (dut.load_idx !== 2'd3) $fatal(1, "KEY2 did not select P4");
    commit_load;
    if (!emergency_active || auto_active) $fatal(1, "P4 emergency mode flags incorrect");

    press_auto; repeat (1100) @(negedge clk);
    if (dut.load_busy) $fatal(1, "KEY4 or timer changed image during emergency");

    press_emergency;
    wait(dut.load_busy === 1'b1);
    if (dut.load_idx !== 2'd2) $fatal(1, "all-clear did not restore prior daily page");
    commit_load;
    if (emergency_active || !auto_active || image_idx !== 2'd2)
        $fatal(1, "daily mode did not resume after all-clear");
    $display("PASS: P1->P2, P2/P3-only auto, P4 emergency isolation, and daily resume.");
    $finish;
end
initial begin #200000; $fatal(1, "watchdog"); end
endmodule
