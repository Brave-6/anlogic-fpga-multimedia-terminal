`timescale 1ns/1ps

module tb_sd_write_req_ack_cdc;
reg clk = 1'b0;
reg mem_clk = 1'b0;
reg rst = 1'b1;
always #5 clk = ~clk;
always #12.5 mem_clk = ~mem_clk;

wire write_req;
wire write_req_ack;
wire [3:0] state_code;
reg req_meta = 1'b0;
reg req_sync = 1'b0;
reg ack_mem = 1'b0;

// Model the memory-side level handshake: acknowledge only after the request
// crosses into mem_clk, and keep ACK asserted until the request returns low.
always @(posedge mem_clk or posedge rst) begin
    if (rst) begin
        req_meta <= 1'b0;
        req_sync <= 1'b0;
        ack_mem  <= 1'b0;
    end else begin
        req_meta <= write_req;
        req_sync <= req_meta;
        ack_mem  <= req_sync;
    end
end

assign write_req_ack = ack_mem;

sd_card_bmp_scene #(
    .CLK_FREQ_HZ(100_000_000),
    .SCAN_START_SECTOR(32'd0),
    .SCAN_MAX_SECTOR(32'd131071),
    .SCAN_TARGET_COUNT(3'd4)
) dut (
    .clk(clk),
    .rst(rst),
    .key_next(1'b1),
    .key_auto(1'b1),
    .state_code(state_code),
    .bmp_width(16'd640),
    .bmp_height(16'd480),
    .display_valid(),
    .write_finish_toggle(1'b0),
    .write_buf_idx(),
    .disp_buf_idx(),
    .write_req(write_req),
    .write_req_ack(write_req_ack),
    .write_en(),
    .write_data(),
    .SD_nCS(),
    .SD_DCLK(),
    .SD_MOSI(),
    .SD_MISO(1'b1),
    .present_ack_toggle(1'b0),.present_accept(1'b1),.scene_stable(1'b1)
);

integer cycles;
initial begin
    // Keep SD initialization and the one-shot image-load request deterministic;
    // this test isolates the real BMP wait-state and ACK synchronizer.
    force dut.sd_init_done = 1'b1;
    force dut.scan_kicked = 1'b1;
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    force dut.load_start_pulse = 1'b1;
    @(posedge clk);
    #1 release dut.load_start_pulse;
    @(negedge clk);
    if (dut.bmp_read_m0.state !== 3'd2)
        $fatal(1, "BMP reader did not enter header-read state");

    force dut.bmp_read_m0.header_match = 1'b1;
    force dut.sd_sec_read_end = 1'b1;
    @(posedge clk);
    #1;
    release dut.bmp_read_m0.header_match;
    release dut.sd_sec_read_end;
    if (write_req !== 1'b1 || dut.bmp_read_m0.state !== 3'd3)
        $fatal(1, "BMP reader did not hold request in ACK-wait state");
    if (write_req_ack !== 1'b0)
        $fatal(1, "memory model acknowledged before request crossed domains");

    // The memory-domain response is asynchronous to clk and is level-held.
    wait (write_req_ack === 1'b1);
    #1;
    if (write_req !== 1'b1)
        $fatal(1, "request dropped before the synchronized ACK reached bmp_read");

    // Two synchronizer stages plus the consumer state transition must keep the
    // request asserted through both sampling edges.
    repeat (2) begin
        @(posedge clk);
        #1;
        if (write_req !== 1'b1)
            $fatal(1, "request was not held across the ACK synchronizer latency");
    end

    cycles = 0;
    while (write_req !== 1'b0 && cycles < 5) begin
        @(posedge clk);
        #1;
        cycles = cycles + 1;
    end
    if (write_req !== 1'b0)
        $fatal(1, "synchronized ACK did not release the request");
    if (write_req_ack !== 1'b1)
        $fatal(1, "memory ACK was not held until request deassertion");

    cycles = 0;
    while (write_req_ack !== 1'b0 && cycles < 8) begin
        @(posedge mem_clk);
        #1;
        cycles = cycles + 1;
    end
    if (write_req_ack !== 1'b0)
        $fatal(1, "memory ACK did not clear after request deassertion crossed back");

    repeat (4) @(posedge clk);
    #1;
    if (dut.write_req_ack_sync !== 1'b0)
        $fatal(1, "ACK deassertion did not propagate through both sync stages");

    $display("PASS: asynchronous level ACK crosses two clk stages; BMP write request is held until synchronized ACK, and ACK clears after request deassertion.");
    $finish;
end

initial begin
    #10000;
    $fatal(1, "watchdog timeout");
end
endmodule
