module video_brightness (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_rgb,
    input  wire [1:0]  I_level,
    output reg  [23:0] O_rgb,
    output reg         O_vs,
    output reg         O_de
);

(* async_reg = "true" *) reg [1:0] level_meta;
(* async_reg = "true" *) reg [1:0] level_sync;
reg [23:0] rgb_in_reg;
reg        vs_in_reg;
reg        de_in_reg;

function [7:0] adjust_channel;
    input [7:0] channel;
    input [1:0] level;
    reg signed [9:0] result;
    begin
        case (level)
            2'd0: result = $signed({1'b0, channel}) - 10'sd48;
            2'd1: result = $signed({1'b0, channel}) - 10'sd16;
            2'd2: result = $signed({1'b0, channel});
            default: result = $signed({1'b0, channel}) + 10'sd48;
        endcase
        if (result < 0)
            adjust_channel = 8'd0;
        else if (result > 255)
            adjust_channel = 8'd255;
        else
            adjust_channel = result[7:0];
    end
endfunction

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        level_meta <= 2'd2;
        level_sync <= 2'd2;
        rgb_in_reg <= 24'd0;
        vs_in_reg  <= 1'b0;
        de_in_reg  <= 1'b0;
    end else begin
        level_meta <= I_level;
        level_sync <= level_meta;
        rgb_in_reg <= I_rgb;
        vs_in_reg  <= I_vs;
        de_in_reg  <= I_de;
    end
end

always @* begin
    O_vs = vs_in_reg;
    O_de = de_in_reg;
    if (!de_in_reg)
        O_rgb = rgb_in_reg;
    else
        O_rgb = {
            adjust_channel(rgb_in_reg[23:16], level_sync),
            adjust_channel(rgb_in_reg[15:8], level_sync),
            adjust_channel(rgb_in_reg[7:0], level_sync)
        };
end

endmodule
