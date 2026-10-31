// 底部产品化OSD（状态栏/滚动通知/亮度弹窗），绘制状态全部在场消隐期切换。
// 两级像素寄存（ROM读出、合成），VS/DE延迟一致；KEY3在本时钟域内消抖。
module video_bottom_osd #(
    parameter integer KEY_STABLE_CYCLES = 500000,
    parameter integer POPUP_FRAMES = 119
)(
    input wire I_clk, I_rst, I_vs, I_de,
    input wire [23:0] I_rgb,
    input wire [1:0] I_image_idx,
    input wire I_display_valid, I_auto_play, I_emergency, I_key3,
    output reg [23:0] O_rgb,
    output reg O_vs, O_de,
    output reg [2:0] O_brightness_level,
    output wire O_content_active,
    output wire O_frame_valid
);
`include "osd/osd_layout.vh"
reg [9:0] x_pos;
reg [8:0] y_pos;
reg de_d, vs_d;
wire frame_start = I_vs && !vs_d;
(* async_reg = "true" *) reg [1:0] page_meta, page_sync;
(* async_reg = "true" *) reg valid_meta, valid_sync;
(* async_reg = "true" *) reg auto_meta, auto_sync, emerg_meta, emerg_sync;
(* async_reg = "true" *) reg key_meta, key_sync;
reg [1:0] page_frame;
reg valid_frame, auto_frame, emerg_frame;
reg key_stable, press_pending;
reg [19:0] key_count;
wire key_change = key_sync != key_stable && key_count >= KEY_STABLE_CYCLES-1;
wire key_press = key_change && !key_sync;
reg [7:0] popup_count;
reg [12:0] scroll_offset;
reg [1:0] scroll_fraction;
wire [12:0] ticker_width = page_frame == 2'd3 ? TICK_P4_WIDTH :
                         page_frame == 2'd2 ? TICK_P3_WIDTH : TICK_P2_WIDTH;
wire [12:0] ticker_base = page_frame == 2'd3 ? TICK_P4_START :
                        page_frame == 2'd2 ? TICK_P3_START : TICK_P2_START;
wire [12:0] scroll_step = scroll_fraction == 2'd3 ? 13'd2 : 13'd1;
assign O_content_active = valid_frame && page_frame != 0;
assign O_frame_valid = valid_frame;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        x_pos<=0; y_pos<=0; de_d<=0; vs_d<=0;
        page_meta<=0; page_sync<=0; page_frame<=0;
        valid_meta<=0; valid_sync<=0; valid_frame<=0;
        auto_meta<=0; auto_sync<=0; auto_frame<=0;
        emerg_meta<=0; emerg_sync<=0; emerg_frame<=0;
        key_meta<=1; key_sync<=1; key_stable<=1; key_count<=0;
        press_pending<=0; O_brightness_level<=3'd2;
        popup_count<=0; scroll_offset<=0; scroll_fraction<=0;
    end else begin
        vs_d<=I_vs; de_d<=I_de;
        page_meta<=I_image_idx; page_sync<=page_meta;
        valid_meta<=I_display_valid; valid_sync<=valid_meta;
        auto_meta<=I_auto_play; auto_sync<=auto_meta;
        emerg_meta<=I_emergency; emerg_sync<=emerg_meta;
        key_meta<=I_key3; key_sync<=key_meta;
        if (key_sync==key_stable) key_count<=0;
        else if (key_change) begin key_count<=0; key_stable<=key_sync; end
        else key_count<=key_count+1'b1;
        if (key_press) press_pending<=1;

        if (frame_start) begin
            x_pos<=0; y_pos<=0;
            page_frame<=page_sync; valid_frame<=valid_sync;
            auto_frame<=auto_sync; emerg_frame<=emerg_sync;
            // 按键一次只响应一次，长按不重复。
            if (press_pending || key_press) begin
                O_brightness_level <= O_brightness_level==3'd4 ? 3'd0 : O_brightness_level+1'b1;
                press_pending<=0;
            end
            if (!valid_sync || page_sync==0) popup_count<=0;
            else if (press_pending || key_press) popup_count<=POPUP_FRAMES;
            else if (popup_count!=0) popup_count<=popup_count-1'b1;

            if (!valid_sync || page_sync==0 || page_sync!=page_frame) begin
                scroll_offset<=0; scroll_fraction<=0;
            end else begin
                scroll_fraction<=scroll_fraction+1'b1;
                if (scroll_offset+scroll_step>=ticker_width)
                    scroll_offset<=scroll_offset+scroll_step-ticker_width;
                else scroll_offset<=scroll_offset+scroll_step;
            end
        end else if (I_de) begin
            if (x_pos<639) x_pos<=x_pos+1'b1;
        end else begin
            x_pos<=0;
            if (de_d) y_pos<=y_pos==479 ? 9'd0 : y_pos+1'b1;
        end
    end
end

// 固定alpha混合（分母256），映射资源以TD报告为准。
function [23:0] dark_ticker;
    input [23:0] rgb;
    reg [15:0] r,g,b;
    begin
        r=rgb[23:16]*8'd108; g=rgb[15:8]*8'd108; b=rgb[7:0]*8'd108;
        dark_ticker={r[15:8],g[15:8],b[15:8]};
    end
endfunction
function [23:0] dark_popup;
    input [23:0] rgb;
    reg [15:0] r,g,b;
    begin
        r=rgb[23:16]*8'd81; g=rgb[15:8]*8'd81; b=rgb[7:0]*8'd81;
        dark_popup={r[15:8],g[15:8],b[15:8]};
    end
endfunction
function [7:0] glyph_mix;
    input [7:0] bg,fg;
    reg [16:0] sum;
    begin sum=bg*8'd24+fg*8'd232; glyph_mix=sum[15:8]; end
endfunction

reg [12:0] rom_addr;
reg [3:0] rom_row;
reg text_enable;
reg [23:0] background, foreground;
reg [12:0] text_x;
integer i;
wire [15:0] glyph_column;
osd_bitmap_rom u_text_rom(.I_clk(I_clk),.I_addr(rom_addr),.O_data(glyph_column));
always @* begin
    background=I_rgb; foreground=24'hffffff;
    rom_addr=0; rom_row=0; text_enable=0; text_x=0;
    if (O_content_active && I_de) begin
        if (y_pos>=432 && y_pos<454) begin
            background=dark_ticker(I_rgb);
            if (x_pos>=10 && x_pos<74 && y_pos>=435 && y_pos<451)
                background=emerg_frame ? 24'h920c13 : 24'h1f4e9c;
            if (y_pos>=435 && y_pos<451) begin
                rom_row=y_pos-435;
                if (x_pos>=18 && x_pos<18+TAG_NORMAL_WIDTH) begin
                    rom_addr=(emerg_frame ? TAG_EMERG_START : TAG_NORMAL_START)+(x_pos-18);
                    text_enable=1;
                end else if (x_pos>=86 && x_pos<632) begin
                    text_x=scroll_offset+(x_pos-86);
                    if (text_x>=ticker_width) text_x=text_x-ticker_width;
                    rom_addr=ticker_base+text_x; text_enable=1;
                    foreground=emerg_frame ? 24'hffe0e0 : 24'hffffff;
                end
            end
        end
        if (y_pos>=456) begin
            background=24'h1c2c4e;
            for (i=0;i<5;i=i+1) begin
                if (x_pos>=46+i*14 && x_pos<57+i*14 && y_pos>=462 && y_pos<474) begin
                    if (i<=O_brightness_level) background=24'hedeef1;
                    else if (x_pos==46+i*14 || x_pos==56+i*14 || y_pos==462 || y_pos==473)
                        background=24'h6c768c;
                end
            end
            if (popup_count!=0 && x_pos>=8 && x_pos<122 && y_pos>=459 && y_pos<477 &&
                (x_pos<10 || x_pos>=120 || y_pos<461 || y_pos>=475)) background=24'hffffff;
            if (x_pos>=474 && x_pos<484 && y_pos>=464 && y_pos<474 &&
                !((x_pos<476 || x_pos>=482) && (y_pos<466 || y_pos>=472)))
                background=emerg_frame ? 24'hffc400 : 24'h56d668;
            if (y_pos>=460 && y_pos<476) begin
                rom_row=y_pos-460;
                if (x_pos>=14 && x_pos<14+BRIGHT_WIDTH) begin
                    rom_addr=BRIGHT_START+x_pos-14; text_enable=1;
                end else if (x_pos>=320-MODE_WIDTH/2 && x_pos<320-MODE_WIDTH/2+MODE_WIDTH) begin
                    rom_addr=MODE_START+x_pos-(320-MODE_WIDTH/2); text_enable=1; foreground=24'hacb3c2;
                end else if (x_pos>=488 && x_pos<488+(emerg_frame ? EMERG_WIDTH : (auto_frame ? RUN_WIDTH : HOLD_WIDTH))) begin
                    rom_addr=(emerg_frame ? EMERG_START : (auto_frame ? RUN_START : HOLD_START))+x_pos-488;
                    text_enable=1; foreground=emerg_frame ? 24'hffd05c : 24'hffffff;
                end else if (x_pos>=626-PAGE1_WIDTH && x_pos<626) begin
                    case (page_frame)
                        1: rom_addr=PAGE2_START+x_pos-(626-PAGE1_WIDTH);
                        2: rom_addr=PAGE3_START+x_pos-(626-PAGE1_WIDTH);
                        3: rom_addr=PAGE4_START+x_pos-(626-PAGE1_WIDTH);
                        default: rom_addr=PAGE1_START+x_pos-(626-PAGE1_WIDTH);
                    endcase
                    text_enable=1;
                end
            end
        end
        if (popup_count!=0 && x_pos>=220 && x_pos<420 && y_pos>=384 && y_pos<424) begin
            background=dark_popup(I_rgb);
            if (x_pos>=238 && x_pos<238+POP_TOP_WIDTH && y_pos>=392 && y_pos<416) begin
                rom_addr=(y_pos<408 ? POP_TOP_START : POP_BOTTOM_START)+x_pos-238;
                rom_row=y_pos<408 ? y_pos-392 : y_pos-408;
                text_enable=1; foreground=24'hffffff;
            end
            for (i=0;i<5;i=i+1) begin
                if (x_pos>=292+i*21 && x_pos<308+i*21 && y_pos>=394 && y_pos<414) begin
                    if (i<=O_brightness_level) background=24'hf0f0f0;
                    else if (x_pos==292+i*21 || x_pos==307+i*21 || y_pos==394 || y_pos==413)
                        background=24'h808080;
                end
            end
        end
    end
end

reg [23:0] bg_d, fg_d;
reg [3:0] row_d;
reg text_d, vs_pipe, de_pipe;
always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        bg_d<=0; fg_d<=0; row_d<=0; text_d<=0;
        vs_pipe<=0; de_pipe<=0; O_vs<=0; O_de<=0; O_rgb<=0;
    end else begin
        bg_d<=background; fg_d<=foreground; row_d<=rom_row; text_d<=text_enable;
        vs_pipe<=I_vs; de_pipe<=I_de;
        O_vs<=vs_pipe; O_de<=de_pipe;
        if (text_d && glyph_column[row_d])
            O_rgb<={glyph_mix(bg_d[23:16],fg_d[23:16]),
                    glyph_mix(bg_d[15:8],fg_d[15:8]),glyph_mix(bg_d[7:0],fg_d[7:0])};
        else O_rgb<=bg_d;
    end
end
endmodule

// 像素调整位于转场/OSD之前；UI与海报共用帧锁存档位，P1旁路亮度与OSD。
module video_brightness_five(input wire [23:0] I_rgb, input wire [2:0] I_level,
    input wire I_enable, output wire [23:0] O_rgb);
function [7:0] adjust;
    input [7:0] c; input [2:0] level;
    reg signed [9:0] result;
    begin
        case(level)
            0: result=$signed({1'b0,c})-10'sd48;
            1: result=$signed({1'b0,c})-10'sd24;
            3: result=$signed({1'b0,c})+10'sd24;
            4: result=$signed({1'b0,c})+10'sd48;
            default: result=$signed({1'b0,c});
        endcase
        adjust=result<0 ? 8'd0 : result>255 ? 8'd255 : result[7:0];
    end
endfunction
assign O_rgb=I_enable ? {adjust(I_rgb[23:16],I_level),adjust(I_rgb[15:8],I_level),adjust(I_rgb[7:0],I_level)} : I_rgb;
endmodule
