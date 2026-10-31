
module sd_card_bmp_scene #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter integer DAILY_HOLD_SECONDS = 8,
    parameter integer BOOT_HOLD_SECONDS = 3,
    parameter integer FAST_SCAN_ENABLE = 0,
    parameter integer FIRST_FRAME_PRIORITY = 1,
    // FAST_MAP_BEGIN：已校验的首扇区提示，不是文件系统元数据。
    parameter [31:0] FAST_SECTOR0 = 32'd32800,
    parameter [31:0] FAST_SECTOR1 = 32'd34608,
    parameter [31:0] FAST_SECTOR2 = 32'd36416,
    parameter [31:0] FAST_SECTOR3 = 32'd38224,
    parameter [31:0] FAST_CRC0 = 32'hE50B1743,
    parameter [31:0] FAST_CRC1 = 32'h1D21DFEC,
    parameter [31:0] FAST_CRC2 = 32'h7AEC90D2,
    parameter [31:0] FAST_CRC3 = 32'hC7B4CD6C,
    // FAST_MAP_END
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input                       present_ack_toggle,
    input                       present_accept,
    input                       scene_stable,
    output reg                  present_req_toggle,
    output [1:0]                present_page,
    output [1:0]                present_buffer,
    output                      emergency_request,
    output [3:0]                state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,
    output [1:0]                image_idx,
    output                      auto_play_active,
    output                      emergency_active,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

wire key_next_press;
wire key_auto_press;

// 存储域ACK保持有效，直到同步后的请求释放。
(* async_reg = "true" *) reg write_req_ack_meta, write_req_ack_sync;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        write_req_ack_meta <= 1'b0;
        write_req_ack_sync <= 1'b0;
    end else begin
        write_req_ack_meta <= write_req_ack;
        write_req_ack_sync <= write_req_ack_meta;
    end
end

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             bmp_load_done;
wire             scan_done;
wire             scan_paused;
wire             fast_scan_verified;
wire             fast_scan_fallback;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;

reg              scan_start_pulse;
reg              scan_resume_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [2:0]        img_found_count;
reg [1:0]        img_idx;              // 当前真正显示中的图片编号
reg [1:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg              emergency_target;
reg              emergency_mode;
reg [1:0]        normal_idx;
reg [31:0]       boot_hold_cnt;
reg              load_busy;
reg [31:0]       load_timeout_cnt;
reg              load_abort;

reg              source_done_seen;
reg              write_done_seen;
reg              present_pending;
(* async_reg = "true" *) reg [2:0] present_ack_sync;
(* async_reg = "true" *) reg accept_meta, accept_sync;
(* async_reg = "true" *) reg stable_meta, stable_sync;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire [1:0] next_daily_image;

assign write_en   = bmp_data_wr_en;
// 信箱数据从EOF到视频应答期间保持不变。
assign present_page = load_idx;
assign present_buffer = pending_buf_idx;
assign emergency_request = emergency_target;
// 输出已提交的图片编号，而非乒乓SDRAM缓冲区编号。
assign image_idx  = img_idx;
assign auto_play_active = auto_play_en && !emergency_mode && !emergency_target;
assign emergency_active = emergency_mode;
assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign auto_tick  = (auto_cnt >= (CLK_FREQ_HZ * DAILY_HOLD_SECONDS - 1));
assign next_daily_image = (img_idx == 2'd1) ? 2'd2 : 2'd1;
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];

scene_key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

scene_key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);

function [31:0] sector_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: sector_lut = img_sector0;
            2'd1: sector_lut = img_sector1;
            2'd2: sector_lut = img_sector2;
            2'd3: sector_lut = img_sector3;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        present_ack_sync <= 0; accept_meta<=0; accept_sync<=0;
        stable_meta<=0; stable_sync<=0;
        present_pending<=0; present_req_toggle<=0;
        scan_start_pulse      <= 1'b0;
        scan_resume_pulse     <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        emergency_target     <= 1'b0;
        emergency_mode       <= 1'b0;
        normal_idx           <= 2'd1;
        boot_hold_cnt        <= 32'd0;
        load_busy             <= 1'b0;
        load_timeout_cnt      <= 32'd0;
        load_abort            <= 1'b0;
        source_done_seen      <= 1'b0;
        write_done_seen       <= 1'b0;
        display_valid         <= 1'b0;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        present_ack_sync <= {present_ack_sync[1:0],present_ack_toggle};
        accept_meta<=present_accept; accept_sync<=accept_meta;
        stable_meta<=scene_stable; stable_sync<=stable_meta;
        scan_start_pulse <= 1'b0;
        scan_resume_pulse<= 1'b0;
        load_start_pulse <= 1'b0;
        load_abort       <= 1'b0;

        if (!sd_init_done) begin
            present_pending<=0; present_req_toggle<=0;
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            emergency_target     <= 1'b0;
            emergency_mode       <= 1'b0;
            normal_idx           <= 2'd1;
            boot_hold_cnt        <= 32'd0;
            load_busy             <= 1'b0;
            load_timeout_cnt      <= 32'd0;
            load_abort            <= 1'b0;
            source_done_seen      <= 1'b0;
            write_done_seen       <= 1'b0;
            display_valid         <= 1'b0;
        end else begin
            // TF先让位给P1加载，之后仅在空闲时恢复目录扫描。
            if(scan_paused && first_image_committed && !load_busy &&
               !present_pending && bmp_ready)
                scan_resume_pulse<=1'b1;
            // 扫描阶段缓存前 4 张图的起始 sector
            if (scan_found_valid) begin
                case (img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    default: ;
                endcase

                if (img_found_count < 3'd4)
                    img_found_count <= img_found_count + 3'd1;
            end

            if (load_busy && bmp_load_done)
                source_done_seen <= 1'b1;

            if (load_busy && write_finish_pulse)
                write_done_seen <= 1'b1;

            if (load_busy && !present_pending && source_done_seen && write_done_seen) begin
                // 先装载完整帧；是否/何时显示由视频逻辑决定。
                present_req_toggle <= ~present_req_toggle;
                present_pending <= 1'b1;
                load_timeout_cnt <= 0;
            end else if (present_pending && present_ack_sync[2] == present_req_toggle) begin
                present_pending <= 1'b0;
                load_busy             <= 1'b0;
                load_timeout_cnt      <= 32'd0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
                auto_cnt <= 0; boot_hold_cnt <= 0;
                if (accept_sync) begin
                    disp_buf_idx          <= pending_buf_idx;
                    img_idx               <= load_idx;
                    display_valid         <= 1'b1;
                    first_image_committed <= 1'b1;
                    emergency_mode        <= (load_idx == 2'd3);
                    if ((load_idx == 2'd1) || (load_idx == 2'd2))
                        normal_idx <= load_idx;
                end
            end else if (load_busy && !present_pending) begin
                if (load_timeout_cnt > 32'd500_000_000) begin
                    load_busy        <= 1'b0;
                    load_timeout_cnt <= 32'd0;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    load_abort       <= 1'b1;
                end else begin
                    load_timeout_cnt <= load_timeout_cnt + 1'b1;
                end
            end else begin
                load_timeout_cnt <= 32'd0;
            end

            // 上电后自动发起一次“扫描前 4 张 BMP”
            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                emergency_target      <= 1'b0;
                emergency_mode        <= 1'b0;
                normal_idx            <= 2'd1;
                boot_hold_cnt         <= 32'd0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
            end else begin
                // KEY2切换请求的产品模式；加载期间到达的请求保留，待该次加载提交后处理。
                if (key_next_press && scan_done && (img_found_count >= 3'd4)) begin
                    emergency_target <= ~emergency_target;
                    auto_cnt         <= 32'd0;
                    boot_hold_cnt    <= 32'd0;
                end

                // KEY4仅控制P2/P3日常播放列表。
                if (key_auto_press && scan_done && !emergency_mode && !emergency_target &&
                    ((img_idx == 2'd1) || (img_idx == 2'd2)) && (img_found_count >= 3'd3)) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                end

                // 达到完整显示后才开始停留计时。
                if (scan_done && display_valid && !load_busy && first_image_committed && stable_sync &&
                    !emergency_mode && !emergency_target && (img_idx == 2'd0)) begin
                    if (boot_hold_cnt < CLK_FREQ_HZ * BOOT_HOLD_SECONDS - 1)
                        boot_hold_cnt <= boot_hold_cnt + 1'b1;
                end else begin
                    boot_hold_cnt <= 32'd0;
                end

                if (scan_done && auto_play_en && display_valid && !load_busy && first_image_committed && stable_sync &&
                    !emergency_mode && !emergency_target && !key_auto_press && !key_next_press &&
                    ((img_idx == 2'd1) || (img_idx == 2'd2)) && (img_found_count >= 3'd3)) begin
                    if (auto_tick)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 首图自动加载到 buffer0
                if ((scan_done || scan_paused) && !first_image_committed && bmp_ready && !load_busy && (img_found_count != 3'd0)) begin
                    // 首图加载期间同样响应应急意图。
                    load_idx         <= emergency_target && img_found_count>=4 ? 2'd3 : 2'd0;
                    load_sector      <= emergency_target && img_found_count>=4 ? img_sector3 : img_sector0;
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 应急模式切换优先于启动/日常加载。
                else if (scan_done && bmp_ready && display_valid && !load_busy &&
                         (emergency_target != emergency_mode) && (img_found_count >= 3'd4)) begin
                    load_idx         <= emergency_target ? 2'd3 : normal_idx;
                    load_sector      <= sector_lut(emergency_target ? 2'd3 : normal_idx);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    auto_cnt         <= 32'd0;
                    if (!emergency_target)
                        auto_play_en <= 1'b1;
                end
                // 离开启动页，从P2开始日常播放。
                else if (scan_done && bmp_ready && display_valid && !load_busy &&
                         !emergency_target && !key_next_press && (img_idx == 2'd0) &&
                         stable_sync && (boot_hold_cnt >= CLK_FREQ_HZ * BOOT_HOLD_SECONDS - 1) && (img_found_count >= 3'd3)) begin
                    load_idx         <= 2'd1;
                    load_sector      <= sector_lut(2'd1);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    auto_play_en     <= 1'b1;
                    auto_cnt         <= 32'd0;
                    boot_hold_cnt    <= 32'd0;
                end
                // 日常自动播放仅在P2与P3间交替。
                else if (scan_done && bmp_ready && display_valid && !load_busy &&
                         auto_play_en && !emergency_mode && !emergency_target && stable_sync &&
                         auto_tick && !key_next_press && !key_auto_press && (img_found_count >= 3'd3)) begin
                    load_idx         <= next_daily_image;
                    load_sector      <= sector_lut(next_daily_image);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
            end
        end
    end
end

bmp_read #(
    .FAST_SCAN_ENABLE(FAST_SCAN_ENABLE), .PAUSE_AFTER_FIRST(FIRST_FRAME_PRIORITY),
    .FAST_SECTOR0(FAST_SECTOR0), .FAST_SECTOR1(FAST_SECTOR1),
    .FAST_SECTOR2(FAST_SECTOR2), .FAST_SECTOR3(FAST_SECTOR3),
    .FAST_CRC0(FAST_CRC0), .FAST_CRC1(FAST_CRC1),
    .FAST_CRC2(FAST_CRC2), .FAST_CRC3(FAST_CRC3)
) bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),
    .load_done              (bmp_load_done),

    .scan_start             (scan_start_pulse),
    .scan_resume            (scan_resume_pulse),
    .scan_paused            (scan_paused),
    .fast_scan_verified     (fast_scan_verified),
    .fast_scan_fallback     (fast_scan_fallback),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_pulse),
    .load_abort             (load_abort),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack_sync),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module scene_key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
