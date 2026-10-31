// 第三扩展分支的运行时控制。
//
// 普通模式保持原双键行为；双键长按进入/退出调节模式，调节模式下KEY1加亮度、KEY2加对比度；
// 双键按住或处于调节模式时，对TF控制器屏蔽按键。
module brightness_contrast_ctrl #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer HOLD_MS     = 1_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire       I_clk,
    input  wire       I_rst,
    input  wire       I_key1,
    input  wire       I_key2,
    output reg        O_key1_to_sd,
    output reg        O_key2_to_sd,
    output reg [3:0]  O_brightness,
    output reg [3:0]  O_contrast,
    output reg        O_adjust_mode
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
localparam integer HOLD_CYCLES     = (CLK_FREQ_HZ / 1000) * HOLD_MS;

reg key1_meta, key1_sync;
reg key2_meta, key2_sync;
reg key1_stable, key2_stable;
reg [31:0] key1_count, key2_count;
reg key1_press, key2_press;
reg [31:0] both_count;
reg hold_latched;
wire both_down = !key1_sync && !key2_sync;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        key1_meta    <= 1'b1;
        key1_sync    <= 1'b1;
        key2_meta    <= 1'b1;
        key2_sync    <= 1'b1;
        key1_stable  <= 1'b1;
        key2_stable  <= 1'b1;
        key1_count   <= 32'd0;
        key2_count   <= 32'd0;
        key1_press   <= 1'b0;
        key2_press   <= 1'b0;
        both_count   <= 32'd0;
        hold_latched <= 1'b0;
        O_brightness <= 4'd8;
        O_contrast   <= 4'd8;
        O_adjust_mode<= 1'b0;
    end else begin
        key1_meta <= I_key1;
        key1_sync <= key1_meta;
        key2_meta <= I_key2;
        key2_sync <= key2_meta;
        key1_press <= 1'b0;
        key2_press <= 1'b0;

        if (key1_sync == key1_stable) begin
            key1_count <= 32'd0;
        end else if (key1_count >= DEBOUNCE_CYCLES - 1) begin
            if (key1_stable && !key1_sync)
                key1_press <= 1'b1;
            key1_stable <= key1_sync;
            key1_count  <= 32'd0;
        end else begin
            key1_count <= key1_count + 1'b1;
        end

        if (key2_sync == key2_stable) begin
            key2_count <= 32'd0;
        end else if (key2_count >= DEBOUNCE_CYCLES - 1) begin
            if (key2_stable && !key2_sync)
                key2_press <= 1'b1;
            key2_stable <= key2_sync;
            key2_count  <= 32'd0;
        end else begin
            key2_count <= key2_count + 1'b1;
        end

        if (!both_down) begin
            both_count   <= 32'd0;
            hold_latched <= 1'b0;
        end else if (!hold_latched) begin
            if (both_count >= HOLD_CYCLES - 1) begin
                both_count   <= both_count;
                hold_latched <= 1'b1;
                O_adjust_mode<= ~O_adjust_mode;
            end else begin
                both_count <= both_count + 1'b1;
            end
        end

        if (O_adjust_mode && !both_down) begin
            if (key1_press)
                O_brightness <= (O_brightness == 4'd15) ? 4'd0 : (O_brightness + 1'b1);
            if (key2_press)
                O_contrast <= (O_contrast == 4'd15) ? 4'd0 : (O_contrast + 1'b1);
        end
    end
end

always @* begin
    O_key1_to_sd = I_key1;
    O_key2_to_sd = I_key2;
    if (both_down || O_adjust_mode) begin
        O_key1_to_sd = 1'b1;
        O_key2_to_sd = 1'b1;
    end
end

endmodule
