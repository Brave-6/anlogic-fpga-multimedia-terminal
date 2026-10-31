// 第一扩展分支：像素域OSD。
//
// 位置：video_delay之后、video_rgb_to_axis_640x480之前；不改hs/vs/de与音频通路，
// 状态输入来自SD卡时钟域，在本模块内同步。
module video_osd_overlay (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire [1:0]  I_image_idx,
    input  wire        I_display_valid,
    input  wire        I_auto_play,
    input  wire        I_emergency,
    input  wire [1:0]  I_brightness,
    output reg  [23:0] O_rgb
);

localparam [9:0] SCREEN_W = 10'd640;
localparam [8:0] SCREEN_H = 9'd480;

reg [9:0] x_pos;
reg [8:0] y_pos;
reg       de_d;
reg       vs_d;

(* async_reg = "true" *) reg [1:0] image_idx_meta;
(* async_reg = "true" *) reg [1:0] image_idx_sync;
(* async_reg = "true" *) reg       display_valid_meta;
(* async_reg = "true" *) reg       display_valid_sync;
(* async_reg = "true" *) reg       auto_play_meta;
(* async_reg = "true" *) reg       auto_play_sync;
(* async_reg = "true" *) reg       emergency_meta;
(* async_reg = "true" *) reg       emergency_sync;
(* async_reg = "true" *) reg [1:0] brightness_meta;
(* async_reg = "true" *) reg [1:0] brightness_sync;

function [7:0] glyph_row;
    input [7:0] ch;
    input [2:0] row;
    begin
        glyph_row = 8'b0;
        case (ch)
            "L": case (row)
                3'd0: glyph_row = 8'b1100_0000;
                3'd1: glyph_row = 8'b1100_0000;
                3'd2: glyph_row = 8'b1100_0000;
                3'd3: glyph_row = 8'b1100_0000;
                3'd4: glyph_row = 8'b1100_0000;
                3'd5: glyph_row = 8'b1100_0000;
                3'd6: glyph_row = 8'b1111_1111;
                default: glyph_row = 8'b0;
            endcase
            "G": case (row)
                3'd0: glyph_row = 8'b0011_1110;
                3'd1: glyph_row = 8'b0110_0000;
                3'd2: glyph_row = 8'b1100_0000;
                3'd3: glyph_row = 8'b1100_1110;
                3'd4: glyph_row = 8'b1100_0110;
                3'd5: glyph_row = 8'b0110_0110;
                3'd6: glyph_row = 8'b0011_1110;
                default: glyph_row = 8'b0;
            endcase
            "I": case (row)
                3'd0: glyph_row = 8'b1111_1111;
                3'd1: glyph_row = 8'b0001_1000;
                3'd2: glyph_row = 8'b0001_1000;
                3'd3: glyph_row = 8'b0001_1000;
                3'd4: glyph_row = 8'b0001_1000;
                3'd5: glyph_row = 8'b0001_1000;
                3'd6: glyph_row = 8'b1111_1111;
                default: glyph_row = 8'b0;
            endcase
            "F": case (row)
                3'd0: glyph_row = 8'b1111_1111;
                3'd1: glyph_row = 8'b1100_0000;
                3'd2: glyph_row = 8'b1100_0000;
                3'd3: glyph_row = 8'b1111_1100;
                3'd4: glyph_row = 8'b1100_0000;
                3'd5: glyph_row = 8'b1100_0000;
                3'd6: glyph_row = 8'b1100_0000;
                default: glyph_row = 8'b0;
            endcase
            "P": case (row)
                3'd0: glyph_row = 8'b1111_1100;
                3'd1: glyph_row = 8'b1100_0110;
                3'd2: glyph_row = 8'b1100_0110;
                3'd3: glyph_row = 8'b1111_1100;
                3'd4: glyph_row = 8'b1100_0000;
                3'd5: glyph_row = 8'b1100_0000;
                3'd6: glyph_row = 8'b1100_0000;
                default: glyph_row = 8'b0;
            endcase
            "S": case (row)
                3'd0: glyph_row = 8'b0011_1110;
                3'd1: glyph_row = 8'b0110_0000;
                3'd2: glyph_row = 8'b0110_0000;
                3'd3: glyph_row = 8'b0011_1100;
                3'd4: glyph_row = 8'b0000_0110;
                3'd5: glyph_row = 8'b0000_0110;
                3'd6: glyph_row = 8'b0111_1100;
                default: glyph_row = 8'b0;
            endcase
            "0": case (row)
                3'd0: glyph_row = 8'b0011_1100;
                3'd1: glyph_row = 8'b0110_0110;
                3'd2: glyph_row = 8'b1100_0011;
                3'd3: glyph_row = 8'b1100_0011;
                3'd4: glyph_row = 8'b1100_0011;
                3'd5: glyph_row = 8'b0110_0110;
                3'd6: glyph_row = 8'b0011_1100;
                default: glyph_row = 8'b0;
            endcase
            "1": case (row)
                3'd0: glyph_row = 8'b0001_1000;
                3'd1: glyph_row = 8'b0011_1000;
                3'd2: glyph_row = 8'b0001_1000;
                3'd3: glyph_row = 8'b0001_1000;
                3'd4: glyph_row = 8'b0001_1000;
                3'd5: glyph_row = 8'b0001_1000;
                3'd6: glyph_row = 8'b0111_1110;
                default: glyph_row = 8'b0;
            endcase
            "2": case (row)
                3'd0: glyph_row = 8'b0011_1100;
                3'd1: glyph_row = 8'b0110_0110;
                3'd2: glyph_row = 8'b0000_0110;
                3'd3: glyph_row = 8'b0001_1100;
                3'd4: glyph_row = 8'b0110_0000;
                3'd5: glyph_row = 8'b1100_0000;
                3'd6: glyph_row = 8'b1111_1110;
                default: glyph_row = 8'b0;
            endcase
            "3": case (row)
                3'd0: glyph_row = 8'b0011_1100;
                3'd1: glyph_row = 8'b0110_0110;
                3'd2: glyph_row = 8'b0000_0110;
                3'd3: glyph_row = 8'b0001_1100;
                3'd4: glyph_row = 8'b0000_0110;
                3'd5: glyph_row = 8'b0110_0110;
                3'd6: glyph_row = 8'b0011_1100;
                default: glyph_row = 8'b0;
            endcase
            "4": case (row)
                3'd0: glyph_row = 8'b0000_1100;
                3'd1: glyph_row = 8'b0001_1100;
                3'd2: glyph_row = 8'b0011_1100;
                3'd3: glyph_row = 8'b0110_1100;
                3'd4: glyph_row = 8'b1111_1110;
                3'd5: glyph_row = 8'b0000_1100;
                3'd6: glyph_row = 8'b0000_1100;
                default: glyph_row = 8'b0;
            endcase
            "A": case (row)
                3'd0: glyph_row = 8'b0011_1100;
                3'd1: glyph_row = 8'b0110_0110;
                3'd2: glyph_row = 8'b1100_0011;
                3'd3: glyph_row = 8'b1111_1111;
                3'd4: glyph_row = 8'b1100_0011;
                3'd5: glyph_row = 8'b1100_0011;
                3'd6: glyph_row = 8'b1100_0011;
                default: glyph_row = 8'b0;
            endcase
            "U": case (row)
                3'd0: glyph_row = 8'b1100_0011;
                3'd1: glyph_row = 8'b1100_0011;
                3'd2: glyph_row = 8'b1100_0011;
                3'd3: glyph_row = 8'b1100_0011;
                3'd4: glyph_row = 8'b1100_0011;
                3'd5: glyph_row = 8'b0110_0110;
                3'd6: glyph_row = 8'b0011_1100;
                default: glyph_row = 8'b0;
            endcase
            "T": case (row)
                3'd0: glyph_row = 8'b1111_1111;
                3'd1: glyph_row = 8'b0001_1000;
                3'd2: glyph_row = 8'b0001_1000;
                3'd3: glyph_row = 8'b0001_1000;
                3'd4: glyph_row = 8'b0001_1000;
                3'd5: glyph_row = 8'b0001_1000;
                3'd6: glyph_row = 8'b0001_1000;
                default: glyph_row = 8'b0;
            endcase
            "M": case (row)
                3'd0: glyph_row = 8'b1100_0011;
                3'd1: glyph_row = 8'b1110_0111;
                3'd2: glyph_row = 8'b1111_1111;
                3'd3: glyph_row = 8'b1101_1011;
                3'd4: glyph_row = 8'b1100_0011;
                3'd5: glyph_row = 8'b1100_0011;
                3'd6: glyph_row = 8'b1100_0011;
                default: glyph_row = 8'b0;
            endcase
            "N": case (row)
                3'd0: glyph_row = 8'b1100_0011;
                3'd1: glyph_row = 8'b1110_0011;
                3'd2: glyph_row = 8'b1111_0011;
                3'd3: glyph_row = 8'b1101_1111;
                3'd4: glyph_row = 8'b1100_1111;
                3'd5: glyph_row = 8'b1100_0111;
                3'd6: glyph_row = 8'b1100_0011;
                default: glyph_row = 8'b0;
            endcase
            "O": case (row)
                3'd0: glyph_row = 8'b0011_1100;
                3'd1: glyph_row = 8'b0110_0110;
                3'd2: glyph_row = 8'b1100_0011;
                3'd3: glyph_row = 8'b1100_0011;
                3'd4: glyph_row = 8'b1100_0011;
                3'd5: glyph_row = 8'b0110_0110;
                3'd6: glyph_row = 8'b0011_1100;
                default: glyph_row = 8'b0;
            endcase
            "D": case (row)
                3'd0: glyph_row = 8'b1111_1100;
                3'd1: glyph_row = 8'b1100_0110;
                3'd2: glyph_row = 8'b1100_0011;
                3'd3: glyph_row = 8'b1100_0011;
                3'd4: glyph_row = 8'b1100_0011;
                3'd5: glyph_row = 8'b1100_0110;
                3'd6: glyph_row = 8'b1111_1100;
                default: glyph_row = 8'b0;
            endcase
            "E": case (row)
                3'd0: glyph_row = 8'b1111_1111;
                3'd1: glyph_row = 8'b1100_0000;
                3'd2: glyph_row = 8'b1100_0000;
                3'd3: glyph_row = 8'b1111_1100;
                3'd4: glyph_row = 8'b1100_0000;
                3'd5: glyph_row = 8'b1100_0000;
                3'd6: glyph_row = 8'b1111_1111;
                default: glyph_row = 8'b0;
            endcase
            "R": case (row)
                3'd0: glyph_row = 8'b1111_1100;
                3'd1: glyph_row = 8'b1100_0110;
                3'd2: glyph_row = 8'b1100_0110;
                3'd3: glyph_row = 8'b1111_1100;
                3'd4: glyph_row = 8'b1101_1000;
                3'd5: glyph_row = 8'b1100_1100;
                3'd6: glyph_row = 8'b1100_0110;
                default: glyph_row = 8'b0;
            endcase
            "J": case (row)
                3'd0: glyph_row = 8'b0001_1110;
                3'd1: glyph_row = 8'b0000_1100;
                3'd2: glyph_row = 8'b0000_1100;
                3'd3: glyph_row = 8'b0000_1100;
                3'd4: glyph_row = 8'b1100_1100;
                3'd5: glyph_row = 8'b0110_0110;
                3'd6: glyph_row = 8'b0011_1100;
                default: glyph_row = 8'b0;
            endcase
            "B": case (row)
                3'd0: glyph_row = 8'b1111_1100;
                3'd1: glyph_row = 8'b1100_0110;
                3'd2: glyph_row = 8'b1100_0110;
                3'd3: glyph_row = 8'b1111_1100;
                3'd4: glyph_row = 8'b1100_0110;
                3'd5: glyph_row = 8'b1100_0110;
                3'd6: glyph_row = 8'b1111_1100;
                default: glyph_row = 8'b0;
            endcase
            "C": case (row)
                3'd0: glyph_row = 8'b0011_1110;
                3'd1: glyph_row = 8'b0110_0000;
                3'd2: glyph_row = 8'b1100_0000;
                3'd3: glyph_row = 8'b1100_0000;
                3'd4: glyph_row = 8'b1100_0000;
                3'd5: glyph_row = 8'b0110_0000;
                3'd6: glyph_row = 8'b0011_1110;
                default: glyph_row = 8'b0;
            endcase
            default: glyph_row = 8'b0;
        endcase
    end
endfunction

function [7:0] title_char;
    input [2:0] index;
    begin
        case (index)
            3'd0: title_char = "A";
            3'd1: title_char = "N";
            3'd2: title_char = "L";
            3'd3: title_char = "O";
            3'd4: title_char = "G";
            3'd5: title_char = "I";
            3'd6: title_char = "C";
            default: title_char = " ";
        endcase
    end
endfunction

function [7:0] digit_char;
    input [3:0] value;
    begin
        case (value)
            4'd0: digit_char = "0";
            4'd1: digit_char = "1";
            4'd2: digit_char = "2";
            4'd3: digit_char = "3";
            4'd4: digit_char = "4";
            default: digit_char = "0";
        endcase
    end
endfunction

function [7:0] hex_char;
    input [3:0] value;
    begin
        case (value)
            4'd0: hex_char = "0";
            4'd1: hex_char = "1";
            4'd2: hex_char = "2";
            4'd3: hex_char = "3";
            4'd4: hex_char = "4";
            4'd5: hex_char = "5";
            4'd6: hex_char = "6";
            4'd7: hex_char = "7";
            4'd8: hex_char = "8";
            4'd9: hex_char = "9";
            default: hex_char = "9";
        endcase
    end
endfunction

reg [7:0] glyph_bits;
reg [7:0] char_code;
reg [2:0] char_index;
reg [2:0] glyph_row_index;
reg [2:0] glyph_col_index;
reg       glyph_on;
reg       panel_on;
reg [1:0] image_idx_frame;
reg       display_valid_frame;
reg       auto_play_frame, emergency_frame;
reg [1:0] brightness_frame;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        x_pos              <= 10'd0;
        y_pos              <= 9'd0;
        de_d               <= 1'b0;
        vs_d               <= 1'b0;
        image_idx_meta     <= 2'd0;
        image_idx_sync     <= 2'd0;
        display_valid_meta <= 1'b0;
        display_valid_sync <= 1'b0;
        auto_play_meta     <= 1'b0;
        auto_play_sync     <= 1'b0;
        emergency_meta     <= 1'b0;
        emergency_sync     <= 1'b0;
        brightness_meta    <= 2'd2;
        brightness_sync    <= 2'd2;
        image_idx_frame    <= 2'd0;
        display_valid_frame<= 1'b0;
        auto_play_frame    <= 1'b0;
        emergency_frame    <= 1'b0;
        brightness_frame   <= 2'd2;
    end else begin
        de_d               <= I_de;
        vs_d               <= I_vs;
        image_idx_meta     <= I_image_idx;
        image_idx_sync     <= image_idx_meta;
        display_valid_meta <= I_display_valid;
        display_valid_sync <= display_valid_meta;
        auto_play_meta     <= I_auto_play;
        auto_play_sync     <= auto_play_meta;
        emergency_meta     <= I_emergency;
        emergency_sync     <= emergency_meta;
        brightness_meta    <= I_brightness;
        brightness_sync    <= brightness_meta;

        if (!vs_d && I_vs) begin
            x_pos <= 10'd0;
            y_pos <= 9'd0;
            image_idx_frame     <= image_idx_sync;
            display_valid_frame <= display_valid_sync;
            auto_play_frame     <= auto_play_sync;
            emergency_frame     <= emergency_sync;
            brightness_frame    <= brightness_sync;
        end else if (I_de) begin
            if (x_pos < SCREEN_W - 1'b1)
                x_pos <= x_pos + 1'b1;
        end else begin
            x_pos <= 10'd0;
            if (de_d)
                y_pos <= (y_pos == SCREEN_H - 1'b1) ? 9'd0 : (y_pos + 1'b1);
        end
    end
end

always @* begin
    panel_on        = 1'b0;
    glyph_on        = 1'b0;
    char_code       = " ";
    char_index      = 3'd0;
    glyph_row_index = 3'd0;
    glyph_col_index = 3'd0;
    glyph_bits      = 8'd0;

    if (display_valid_frame && I_de) begin
        // 画面左上角三行紧凑状态面板。
        if ((x_pos >= 10'd12) && (x_pos < 10'd220) &&
            (y_pos >= 9'd12) && (y_pos < 9'd68))
            panel_on = 1'b1;

        // 固定标题：ANLOGIC。
        if ((x_pos >= 10'd20) && (x_pos < 10'd76) &&
            (y_pos >= 9'd20) && (y_pos < 9'd28)) begin
            char_index      = (x_pos - 10'd20) >> 3;
            glyph_row_index = y_pos - 9'd20;
            glyph_col_index = (x_pos - 10'd20) & 3'b111;
            char_code       = title_char(char_index);
            glyph_bits      = glyph_row(char_code, glyph_row_index);
            glyph_on        = glyph_bits[7 - glyph_col_index];
        end

        // 动态状态为已提交页号，每帧锁存一次。
        if ((x_pos >= 10'd20) && (x_pos < 10'd36) &&
            (y_pos >= 9'd34) && (y_pos < 9'd42)) begin
            char_index      = (x_pos - 10'd20) >> 3;
            glyph_row_index = y_pos - 9'd34;
            glyph_col_index = (x_pos - 10'd20) & 3'b111;
            case (char_index)
                3'd0: char_code = "P";
                3'd1: char_code = digit_char({2'b00, image_idx_frame} + 4'd1);
                default: char_code = " ";
            endcase
            glyph_bits = glyph_row(char_code, glyph_row_index);
            glyph_on   = glyph_bits[7 - glyph_col_index];
        end

        // 产品模式：EMERG/AUTO/MAN。
        if ((x_pos >= 10'd52) && (x_pos < 10'd100) &&
            (y_pos >= 9'd34) && (y_pos < 9'd42)) begin
            char_index      = (x_pos - 10'd52) >> 3;
            glyph_row_index = y_pos - 9'd34;
            glyph_col_index = (x_pos - 10'd52) & 3'b111;
            case (char_index)
                3'd0: char_code = emergency_frame ? "E" : (auto_play_frame ? "A" : "M");
                3'd1: char_code = emergency_frame ? "M" : (auto_play_frame ? "U" : "A");
                3'd2: char_code = emergency_frame ? "E" : (auto_play_frame ? "T" : "N");
                3'd3: char_code = emergency_frame ? "R" : (auto_play_frame ? "O" : " ");
                3'd4: char_code = emergency_frame ? "G" : " ";
                default: char_code = " ";
            endcase
            glyph_bits = glyph_row(char_code, glyph_row_index);
            glyph_on   = glyph_bits[7 - glyph_col_index];
        end

        // 亮度行：B1~B4（夜间/低/标准/日光）。
        if ((x_pos >= 10'd20) && (x_pos < 10'd36) &&
            (y_pos >= 9'd50) && (y_pos < 9'd58)) begin
            char_index      = (x_pos - 10'd20) >> 3;
            glyph_row_index = y_pos - 9'd50;
            glyph_col_index = (x_pos - 10'd20) & 3'b111;
            case (char_index)
                3'd0: char_code = "B";
                3'd1: char_code = digit_char({2'b00, brightness_frame} + 4'd1);
                default: char_code = " ";
            endcase
            glyph_bits = glyph_row(char_code, glyph_row_index);
            glyph_on   = glyph_bits[7 - glyph_col_index];
        end
    end

    if (panel_on)
        O_rgb = 24'h102040;
    else
        O_rgb = I_rgb;

    if (glyph_on)
        O_rgb = 24'hFFE070;
end

endmodule
