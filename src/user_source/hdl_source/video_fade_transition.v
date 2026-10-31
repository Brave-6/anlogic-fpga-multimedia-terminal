// 第二扩展分支：经黑场淡入淡出。
//
// 新图提交（或首次display_valid）从黑场起按帧渐亮；
// 帧缓存、TF/SDRAM链路、同步信号与音频通路不变。
module video_fade_transition (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire [1:0]  I_image_idx,
    input  wire        I_display_valid,
    output reg  [23:0] O_rgb
);

reg vs_d;
(* async_reg = "true" *) reg [1:0] image_idx_meta;
(* async_reg = "true" *) reg [1:0] image_idx_sync;
(* async_reg = "true" *) reg       valid_meta;
(* async_reg = "true" *) reg       valid_sync;

reg [1:0] image_idx_frame;
reg [1:0] image_idx_prev;
reg       valid_frame;
reg       valid_prev;
reg [4:0] fade_level; // 0..16, 16 = full brightness

function [7:0] scale_channel;
    input [7:0] channel;
    input [4:0] level;
    reg [12:0] product;
    begin
        product = channel * level;
        scale_channel = product[11:4];
    end
endfunction

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        vs_d          <= 1'b0;
        image_idx_meta<= 2'd0;
        image_idx_sync<= 2'd0;
        valid_meta    <= 1'b0;
        valid_sync    <= 1'b0;
        image_idx_frame <= 2'd0;
        image_idx_prev  <= 2'd0;
        valid_frame     <= 1'b0;
        valid_prev      <= 1'b0;
        fade_level      <= 5'd0;
    end else begin
        vs_d           <= I_vs;
        image_idx_meta <= I_image_idx;
        image_idx_sync <= image_idx_meta;
        valid_meta     <= I_display_valid;
        valid_sync     <= valid_meta;

        if (!vs_d && I_vs) begin
            image_idx_frame <= image_idx_sync;
            valid_frame     <= valid_sync;

            if (!valid_sync) begin
                fade_level <= 5'd0;
            end else if (!valid_prev || (image_idx_sync != image_idx_prev)) begin
                fade_level <= 5'd0;
            end else if (fade_level < 5'd16) begin
                fade_level <= fade_level + 1'b1;
            end

            image_idx_prev <= image_idx_sync;
            valid_prev     <= valid_sync;
        end
    end
end

always @* begin
    if (!I_de || !valid_frame) begin
        O_rgb = I_rgb;
    end else if (fade_level >= 5'd16) begin
        O_rgb = I_rgb;
    end else begin
        O_rgb = {
            scale_channel(I_rgb[23:16], fade_level),
            scale_channel(I_rgb[15:8],  fade_level),
            scale_channel(I_rgb[7:0],   fade_level)
        };
    end
end

endmodule
