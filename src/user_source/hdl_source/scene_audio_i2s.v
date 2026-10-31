module scene_audio_i2s #(
    parameter integer BOOT_START = 0,
    parameter integer BOOT_LENGTH = 12526,
    parameter integer EMERGENCY_START = 12526,
    parameter integer EMERGENCY_LENGTH = 24000,
    parameter integer CLEAR_START = 36526,
    parameter integer CLEAR_LENGTH = 24000,
    parameter integer TOTAL_SAMPLES = 60526,
    // 0保留原有的显示沿触发，兼容既有单元测试。
    parameter integer BOOT_DELAY_CYCLES = 0,
    parameter INIT_FILE = "audio/scene_audio.mem"
)(
    input  wire I_mclk,
    input  wire I_rst,
    input  wire I_display_valid,
    input  wire I_emergency_active,
    input  wire I_boot_ready,
    output reg  O_i2s_BCLK,
    output reg  O_i2s_LRCK,
    output reg  O_i2s_DOUT
);

(* async_reg = "true" *) reg display_meta, display_sync;
(* async_reg = "true" *) reg emergency_meta, emergency_sync;
reg display_d, emergency_d;
(* async_reg = "true" *) reg boot_ready_meta, boot_ready_sync;
localparam integer BOOT_COUNTER_WIDTH = BOOT_DELAY_CYCLES>1 ? $clog2(BOOT_DELAY_CYCLES) : 1;
reg [BOOT_COUNTER_WIDTH-1:0] boot_delay_count;
reg boot_armed;

reg [5:0]  bit_count;
reg [63:0] shift_reg;
reg signed [23:0] sample_word;
reg [15:0] sample_addr;
reg [15:0] clip_end;
reg [2:0]  repeat_count;
reg        playing;

wire [7:0] rom_sample;
`ifdef SCENE_AUDIO_SIM
reg [7:0] sample_rom [0:TOTAL_SAMPLES-1];
initial $readmemh(INIT_FILE, sample_rom);
assign rom_sample = sample_rom[sample_addr];
`else
scene_audio_rom u_scene_audio_rom(
    .I_clk  (I_mclk),
    .I_addr (sample_addr),
    .O_data (rom_sample)
);
`endif

wire boot_event = boot_armed && display_sync && !emergency_sync &&
                  (BOOT_DELAY_CYCLES==0 ? !display_d :
                   (boot_ready_sync && boot_delay_count>=BOOT_DELAY_CYCLES-1));
wire emergency_event = emergency_sync && !emergency_d;
wire clear_event = !emergency_sync && emergency_d;

function signed [23:0] expand_sample;
    input [7:0] sample;
    reg signed [8:0] centered;
    begin
        centered = $signed({1'b0, sample}) - 9'sd128;
        expand_sample = {{15{centered[8]}}, centered} <<< 16;
    end
endfunction

wire signed [23:0] next_pcm_sample = expand_sample(rom_sample);

// 视频/应急/解除事件不做延迟；启动提示音为一次性播放。
always @(posedge I_mclk or posedge I_rst) begin
    if(I_rst) begin
        boot_ready_meta<=1'b0;
        boot_ready_sync<=1'b0;
        boot_delay_count<=0;
        boot_armed<=1'b1;
    end else begin
        boot_ready_meta<=I_boot_ready;
        boot_ready_sync<=boot_ready_meta;
        if(emergency_sync || clear_event || boot_event) begin
            boot_armed<=1'b0;
            boot_delay_count<=0;
        end else if(!boot_armed || !display_sync || !boot_ready_sync) begin
            boot_delay_count<=0;
        end else if(BOOT_DELAY_CYCLES>0 && boot_delay_count<BOOT_DELAY_CYCLES-1) begin
            boot_delay_count<=boot_delay_count+1'b1;
        end
    end
end

always @(posedge I_mclk or posedge I_rst) begin
    if (I_rst) begin
        display_meta   <= 1'b0;
        display_sync   <= 1'b0;
        emergency_meta <= 1'b0;
        emergency_sync <= 1'b0;
        display_d      <= 1'b0;
        emergency_d    <= 1'b0;
        O_i2s_BCLK     <= 1'b0;
        O_i2s_LRCK     <= 1'b0;
        O_i2s_DOUT     <= 1'b0;
        bit_count      <= 6'd0;
        shift_reg      <= 64'd0;
        sample_word    <= 24'sd0;
        sample_addr    <= 16'd0;
        clip_end       <= 16'd0;
        repeat_count   <= 3'd0;
        playing        <= 1'b0;
    end else begin
        display_meta   <= I_display_valid;
        display_sync   <= display_meta;
        emergency_meta <= I_emergency_active;
        emergency_sync <= emergency_meta;
        display_d      <= display_sync;
        emergency_d    <= emergency_sync;

        O_i2s_BCLK <= ~O_i2s_BCLK;
        if (O_i2s_BCLK) begin
            O_i2s_DOUT <= shift_reg[63];
            shift_reg  <= {shift_reg[62:0], 1'b0};
            if (bit_count == 6'd63) begin
                bit_count <= 6'd0;
                if (!O_i2s_LRCK) begin
                    O_i2s_LRCK <= 1'b1;
                    shift_reg  <= {sample_word, 40'd0};
                end else begin
                    O_i2s_LRCK <= 1'b0;
                    shift_reg  <= {sample_word, 40'd0};
                    if (!boot_event && !emergency_event && !clear_event) begin
                        if (playing) begin
                            // LRCK下降沿开始下一左声道：下一采样同时装入采样寄存器与移位器，保证接收端左右声道对齐。
                            shift_reg   <= {next_pcm_sample, 40'd0};
                            sample_word <= next_pcm_sample;
                            if (repeat_count == 3'd5) begin
                                repeat_count <= 3'd0;
                                if (sample_addr + 1'b1 >= clip_end) begin
                                    playing <= 1'b0;
                                end else begin
                                    sample_addr <= sample_addr + 1'b1;
                                end
                            end else begin
                                repeat_count <= repeat_count + 1'b1;
                            end
                        end else begin
                            shift_reg  <= 64'd0;
                            sample_word <= 24'sd0;
                        end
                    end
                end
            end else begin
                bit_count <= bit_count + 1'b1;
            end
        end

        // 新场景事件可抢占当前音频。
        if (emergency_event) begin
            sample_addr  <= EMERGENCY_START;
            clip_end     <= EMERGENCY_START + EMERGENCY_LENGTH;
            repeat_count <= 3'd0;
            sample_word  <= 24'sd0;
            playing      <= 1'b1;
        end else if (clear_event) begin
            sample_addr  <= CLEAR_START;
            clip_end     <= CLEAR_START + CLEAR_LENGTH;
            repeat_count <= 3'd0;
            sample_word  <= 24'sd0;
            playing      <= 1'b1;
        end else if (boot_event) begin
            sample_addr  <= BOOT_START;
            clip_end     <= BOOT_START + BOOT_LENGTH;
            repeat_count <= 3'd0;
            sample_word  <= 24'sd0;
            playing      <= 1'b1;
        end
    end
end

endmodule

module scene_audio_rom(
    input  wire        I_clk,
    input  wire [15:0] I_addr,
    output reg  [7:0]  O_data
);

wire [7:0] q00, q01, q02, q03, q04, q05, q06, q07;
wire [7:0] q08, q09, q10, q11, q12, q13, q14;

`define SCENE_ROM_BANK(INST, Q, FILE) \
EG_LOGIC_BRAM #( \
    .DATA_WIDTH_A(8), .ADDR_WIDTH_A(12), .DATA_DEPTH_A(4096), \
    .DATA_WIDTH_B(8), .ADDR_WIDTH_B(12), .DATA_DEPTH_B(4096), \
    .MODE("SP"), .REGMODE_A("NOREG"), .IMPLEMENT("32K"), \
    .DEBUGGABLE("NO"), .PACKABLE("NO"), .INIT_FILE(FILE), .FILL_ALL("NONE") \
) INST ( \
    .dia(8'd0), .dib(8'd0), .addra(I_addr[11:0]), .addrb(12'd0), \
    .cea(1'b1), .ceb(1'b0), .ocea(1'b0), .oceb(1'b0), \
    .clka(I_clk), .clkb(1'b0), .wea(1'b0), .web(1'b0), \
    .bea(1'b0), .beb(1'b0), .rsta(1'b0), .rstb(1'b0), .doa(Q), .dob() \
)

`SCENE_ROM_BANK(bank00, q00, "audio/scene_audio_bank00.mif");
`SCENE_ROM_BANK(bank01, q01, "audio/scene_audio_bank01.mif");
`SCENE_ROM_BANK(bank02, q02, "audio/scene_audio_bank02.mif");
`SCENE_ROM_BANK(bank03, q03, "audio/scene_audio_bank03.mif");
`SCENE_ROM_BANK(bank04, q04, "audio/scene_audio_bank04.mif");
`SCENE_ROM_BANK(bank05, q05, "audio/scene_audio_bank05.mif");
`SCENE_ROM_BANK(bank06, q06, "audio/scene_audio_bank06.mif");
`SCENE_ROM_BANK(bank07, q07, "audio/scene_audio_bank07.mif");
`SCENE_ROM_BANK(bank08, q08, "audio/scene_audio_bank08.mif");
`SCENE_ROM_BANK(bank09, q09, "audio/scene_audio_bank09.mif");
`SCENE_ROM_BANK(bank10, q10, "audio/scene_audio_bank10.mif");
`SCENE_ROM_BANK(bank11, q11, "audio/scene_audio_bank11.mif");
`SCENE_ROM_BANK(bank12, q12, "audio/scene_audio_bank12.mif");
`SCENE_ROM_BANK(bank13, q13, "audio/scene_audio_bank13.mif");
`SCENE_ROM_BANK(bank14, q14, "audio/scene_audio_bank14.mif");
`undef SCENE_ROM_BANK

always @* begin
    case (I_addr[15:12])
        4'd0: O_data = q00; 4'd1: O_data = q01;
        4'd2: O_data = q02; 4'd3: O_data = q03;
        4'd4: O_data = q04; 4'd5: O_data = q05;
        4'd6: O_data = q06; 4'd7: O_data = q07;
        4'd8: O_data = q08; 4'd9: O_data = q09;
        4'd10: O_data = q10; 4'd11: O_data = q11;
        4'd12: O_data = q12; 4'd13: O_data = q13;
        4'd14: O_data = q14;
        default: O_data = 8'h80;
    endcase
end

endmodule
