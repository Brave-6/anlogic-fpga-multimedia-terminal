// 第三扩展分支：像素域亮度/对比度调节。
// 中性值为8：亮度0..15对应-128..+112偏移（步进16）；对比度0..15对应0.5x..1.4375x（围绕中灰）。
module video_brightness_contrast (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire [3:0]  I_brightness,
    input  wire [3:0]  I_contrast,
    output reg  [23:0] O_rgb,
    output reg         O_vs,
    output reg         O_de
);

(* async_reg = "true" *) reg [3:0] brightness_meta;
(* async_reg = "true" *) reg [3:0] brightness_sync;
(* async_reg = "true" *) reg [3:0] contrast_meta;
(* async_reg = "true" *) reg [3:0] contrast_sync;
reg [23:0] rgb_in_reg;
reg        vs_in_reg;
reg        de_in_reg;

function [7:0] adjust_channel;
    input [7:0] channel;
    input [3:0] brightness;
    input [3:0] contrast;
    reg signed [10:0] centered;
    reg signed [11:0] scaled;
    reg signed [12:0] result;
    reg signed [7:0]  offset;
    begin
        centered = $signed({1'b0, channel}) - 11'sd128;
        offset   = ($signed({1'b0, brightness}) - 5'sd8) <<< 4;

        // 八档移位/加法增益（0.50x~1.375x），像素通路保持查表实现，不用可变乘除法器。
        case (contrast[3:1])
            3'd0: scaled = centered >>> 1;
            3'd1: scaled = centered - (centered >>> 2) - (centered >>> 3);
            3'd2: scaled = centered - (centered >>> 2);
            3'd3: scaled = centered - (centered >>> 3);
            3'd4: scaled = centered;
            3'd5: scaled = centered + (centered >>> 3);
            3'd6: scaled = centered + (centered >>> 2);
            default: scaled = centered + (centered >>> 2) + (centered >>> 3);
        endcase

        result = 13'sd128 + scaled + offset;
        if (result < 0)
            result = 0;
        else if (result > 255)
            result = 255;
        adjust_channel = result[7:0];
    end
endfunction

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        brightness_meta <= 4'd8;
        brightness_sync <= 4'd8;
        contrast_meta   <= 4'd8;
        contrast_sync   <= 4'd8;
        rgb_in_reg      <= 24'd0;
        vs_in_reg       <= 1'b0;
        de_in_reg       <= 1'b0;
    end else begin
        brightness_meta <= I_brightness;
        brightness_sync <= brightness_meta;
        contrast_meta   <= I_contrast;
        contrast_sync   <= contrast_meta;
        rgb_in_reg      <= I_rgb;
        vs_in_reg       <= I_vs;
        de_in_reg       <= I_de;
    end
end

always @* begin
    O_vs = vs_in_reg;
    O_de = de_in_reg;
    if (!de_in_reg) begin
        O_rgb = rgb_in_reg;
    end else begin
        O_rgb = {
            adjust_channel(rgb_in_reg[23:16], brightness_sync, contrast_sync),
            adjust_channel(rgb_in_reg[15:8],  brightness_sync, contrast_sync),
            adjust_channel(rgb_in_reg[7:0],   brightness_sync, contrast_sync)
        };
    end
end

endmodule
