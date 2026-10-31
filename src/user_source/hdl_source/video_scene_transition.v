// 单帧信箱：源侧保持page/buffer直到ACK；数据稳定两拍后经三级同步进视频域。
// 提交发生在VS负沿起始处（早于frame_read_write采样其延迟读请求）；OSD用同一消隐期更晚的VS正沿。
module video_scene_transition #(
    parameter integer FADE_OUT_FRAMES = 24,
    parameter integer FADE_IN_FRAMES = 36
)(
    input wire I_clk, I_rst, I_vs,
    input wire [23:0] I_rgb,
    input wire I_req_toggle,
    input wire [1:0] I_page, I_buffer,
    input wire I_emergency_request,
    output reg O_ack_toggle, O_accept,
    output reg [1:0] O_page, O_buffer,
    output reg O_valid,
    output wire O_emergency, O_stable,
    output wire [23:0] O_rgb
);
localparam READY=2'd0, OUT=2'd1, IN=2'd2;
reg [1:0] phase;
reg [7:0] frame_count;
reg [6:0] gain;
reg vs_d;
(* async_reg = "true" *) reg [2:0] req_sync;
(* async_reg = "true" *) reg [1:0] page_meta, page_sync, buf_meta, buf_sync;
(* async_reg = "true" *) reg emerg_meta, emerg_sync;
wire boundary = vs_d && !I_vs;
wire pending = req_sync[2] != O_ack_toggle;
wire wrong_target = pending && ((page_sync==3) != emerg_sync);
wire direct = O_valid && (O_page==3 || page_sync==3);
assign O_emergency=O_valid && O_page==3;
assign O_stable=O_valid && phase==READY && gain==64 && ((O_page==3)==emerg_sync);
function [7:0] scaled;
    input [7:0] c; input [6:0] g;
    reg [14:0] product;
    begin product=c*g; scaled=product[13:6]; end
endfunction
assign O_rgb=!O_valid ? 24'd0 : gain==64 ? I_rgb :
    {scaled(I_rgb[23:16],gain),scaled(I_rgb[15:8],gain),scaled(I_rgb[7:0],gain)};

always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        vs_d<=1; req_sync<=0; page_meta<=0; page_sync<=0; buf_meta<=0; buf_sync<=0;
        emerg_meta<=0; emerg_sync<=0;
        O_ack_toggle<=0; O_accept<=0; O_page<=0; O_buffer<=0; O_valid<=0;
        phase<=READY; frame_count<=0; gain<=0;
    end else begin
        vs_d<=I_vs;
        req_sync<={req_sync[1:0],I_req_toggle};
        page_meta<=I_page;page_sync<=page_meta;buf_meta<=I_buffer;buf_sync<=buf_meta;
        emerg_meta<=I_emergency_request;emerg_sync<=emerg_meta;
        if(boundary) begin
            // 丢弃已完成但过时的日常/应急加载：SD生产者可立即把非显示缓冲复用给优先目标；
            // 不中断未完成的SDRAM写入。
            if(wrong_target) begin
                O_ack_toggle<=req_sync[2];O_accept<=0;
                gain<=O_valid ? 7'd64 : 7'd0; phase<=READY;frame_count<=0;
            end else if(pending && direct) begin
                // P4进出均绕过全部淡入淡出阶段。
                O_page<=page_sync;O_buffer<=buf_sync;O_valid<=1;
                O_ack_toggle<=req_sync[2];O_accept<=1;
                gain<=64;phase<=READY;frame_count<=0;
            end else if(O_valid && ((O_page==3)!=emerg_sync)) begin
                // 应急意图在目标图加载完成前即可取消进行中的转场，当前完整帧保持可读。
                gain<=64;phase<=READY;frame_count<=0;
            end else if(!O_valid && pending) begin
                O_page<=page_sync;O_buffer<=buf_sync;O_valid<=1;
                O_ack_toggle<=req_sync[2];O_accept<=1;
                gain<=page_sync==3 ? 7'd64 : 7'd0;
                phase<=page_sync==3 ? READY : IN;frame_count<=0;
            end else case(phase)
                READY: if(pending) begin
                    gain<=(64*(FADE_OUT_FRAMES-1))/FADE_OUT_FRAMES;
                    frame_count<=1;phase<=OUT;
                end
                OUT: begin
                    if(frame_count>=FADE_OUT_FRAMES) begin
                        // 提交新缓冲前先以一帧黑场结束淡出，增益仍为零。
                        if(pending) begin
                            O_page<=page_sync;O_buffer<=buf_sync;
                            O_ack_toggle<=req_sync[2];O_accept<=1;
                            phase<=IN;frame_count<=0;gain<=0;
                        end else begin phase<=READY;frame_count<=0;gain<=64;end
                    end else begin
                        frame_count<=frame_count+1'b1;
                        gain<=(64*(FADE_OUT_FRAMES-(frame_count+1)))/FADE_OUT_FRAMES;
                    end
                end
                IN: begin
                    if(frame_count>=FADE_IN_FRAMES-1) begin
                        frame_count<=0;phase<=READY;gain<=64;
                    end else begin
                        frame_count<=frame_count+1'b1;
                        gain<=(64*(frame_count+1))/FADE_IN_FRAMES;
                    end
                end
                default: begin phase<=READY;gain<=64;frame_count<=0;end
            endcase
        end
    end
end
endmodule
