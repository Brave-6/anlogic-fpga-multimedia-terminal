module brightness_ctrl #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire       I_clk,
    input  wire       I_rst,
    input  wire       I_key,
    output reg  [1:0] O_level
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg key_meta;
reg key_sync;
reg key_stable;
reg [31:0] debounce_count;

always @(posedge I_clk or posedge I_rst) begin
    if (I_rst) begin
        key_meta       <= 1'b1;
        key_sync       <= 1'b1;
        key_stable     <= 1'b1;
        debounce_count <= 32'd0;
        O_level        <= 2'd2;
    end else begin
        key_meta <= I_key;
        key_sync <= key_meta;

        if (key_sync == key_stable) begin
            debounce_count <= 32'd0;
        end else if (debounce_count >= DEBOUNCE_CYCLES - 1) begin
            debounce_count <= 32'd0;
            key_stable     <= key_sync;
            if (key_stable && !key_sync)
                O_level <= O_level + 2'd1;
        end else begin
            debounce_count <= debounce_count + 1'b1;
        end
    end
end

endmodule
