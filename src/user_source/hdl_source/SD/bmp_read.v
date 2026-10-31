module bmp_read #(
    parameter integer FAST_SCAN_ENABLE = 0,
    parameter integer PAUSE_AFTER_FIRST = 0,
    parameter [31:0] FAST_SECTOR0 = 0, FAST_SECTOR1 = 0,
    parameter [31:0] FAST_SECTOR2 = 0, FAST_SECTOR3 = 0,
    parameter [31:0] FAST_CRC0 = 0, FAST_CRC1 = 0,
    parameter [31:0] FAST_CRC2 = 0, FAST_CRC3 = 0
)(
    input                       clk,
    input                       rst,
    output                      ready,
    output reg                  load_done,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    input                       scan_resume,
    output reg                  scan_paused,
    output reg                  fast_scan_verified,
    output reg                  fast_scan_fallback,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input                       load_abort,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);

localparam ST_IDLE      = 3'd0;
localparam ST_SCAN      = 3'd1;
localparam ST_LOAD_HDR  = 3'd2;
localparam ST_LOAD_WAIT = 3'd3;
localparam ST_LOAD_DATA = 3'd4;
localparam ST_FAST_VERIFY = 3'd5;
localparam ST_FAST_PUBLISH = 3'd6;

reg [2:0]  state;
reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [15:0] bit_count;
reg [31:0] compression;

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;

reg header_match;
reg [1:0] fast_index;
reg [31:0] sector_crc;

function [31:0] fast_sector;
    input [1:0] index;
    begin
        case (index)
            0: fast_sector=FAST_SECTOR0;
            1: fast_sector=FAST_SECTOR1;
            2: fast_sector=FAST_SECTOR2;
            3: fast_sector=FAST_SECTOR3;
        endcase
    end
endfunction

function [31:0] fast_crc;
    input [1:0] index;
    begin
        case (index)
            0: fast_crc=FAST_CRC0;
            1: fast_crc=FAST_CRC1;
            2: fast_crc=FAST_CRC2;
            3: fast_crc=FAST_CRC3;
        endcase
    end
endfunction

// 对全部512字节做CRC32/ISO-HDLC校验（含扇区起始的像素数据）。
function [31:0] crc32_byte;
    input [31:0] crc;
    input [7:0] data_byte;
    reg [31:0] next_crc;
    integer bit_index;
    begin
        next_crc=crc ^ {24'd0,data_byte};
        for(bit_index=0;bit_index<8;bit_index=bit_index+1)
            next_crc=next_crc[0] ? (next_crc>>1)^32'hEDB88320 : next_crc>>1;
        crc32_byte=next_crc;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if(rst) sector_crc<=32'hFFFFFFFF;
    else if(state!=ST_FAST_VERIFY) sector_crc<=32'hFFFFFFFF;
    else if(sd_sec_read_data_valid)
        sector_crc<=crc32_byte(rd_cnt==0 ? 32'hFFFFFFFF : sector_crc,sd_sec_read_data);
end
wire bmp_data_valid;
wire [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_match;
wire [31:0] next_scan_sector_if_miss;

assign ready = (state == ST_IDLE);
// 文件头字段在字节33结束，判定结果在512字节扇区末尾使用；
// 其余字节期间寄存校验结果，把宽比较移出扇区地址使能路径。
always @(posedge clk or posedge rst) begin
    if (rst)
        header_match <= 1'b0;
    else
        header_match <= (header_0 == "B") &&
                        (header_1 == "M") &&
                        (width[15:0]  == bmp_width) &&
                        (height[15:0] == bmp_height) &&
                        (bit_count    == 16'd24) &&
                        (compression  == 32'd0);
end
assign bmp_data_valid = (sd_sec_read_data_valid == 1'b1) &&
                        (bmp_len_cnt >= pixel_offset) &&
                        (bmp_len_cnt <  file_len);
assign file_sector_count = (file_len == 32'd0) ? 32'd1 : ((file_len + 32'd511) >> 9);
assign next_scan_sector_if_match = scan_sector + file_sector_count;
assign next_scan_sector_if_miss  = scan_sector + 32'd1;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR) || (state == ST_FAST_VERIFY)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR) || (state == ST_FAST_VERIFY)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : header_0 <= sd_sec_read_data;
            10'd1 : header_1 <= sd_sec_read_data;

            10'd2 : file_len[7:0] <= sd_sec_read_data;
            10'd3 : file_len[15:8] <= sd_sec_read_data;
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;

            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: height[23:16] <= sd_sec_read_data;
            10'd25: height[31:24] <= sd_sec_read_data;

            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;

            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_byte_idx <= 2'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid)
            bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : (bmp_byte_idx + 2'd1);
    end else begin
        bmp_byte_idx <= 2'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid) begin
            case (bmp_byte_idx)
                2'd0: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[7:0]  <= sd_sec_read_data;
                end
                2'd1: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[15:8] <= sd_sec_read_data;
                end
                2'd2: begin
                    bmp_data_wr_en  <= 1'b1;
                    bmp_data[23:16] <= sd_sec_read_data;
                end
                default: begin
                    bmp_data_wr_en <= 1'b0;
                end
            endcase
        end else begin
            bmp_data_wr_en <= 1'b0;
        end
    end else begin
        bmp_data_wr_en <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_paused       <= 1'b0;
        fast_scan_verified<= 1'b0;
        fast_scan_fallback<= 1'b0;
        fast_index        <= 2'd0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        load_done          <= 1'b0;
    end else if (!sd_init_done) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_paused       <= 1'b0;
        fast_scan_verified<= 1'b0;
        fast_scan_fallback<= 1'b0;
        fast_index        <= 2'd0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        load_done          <= 1'b0;
    end else if (load_abort) begin
        // 只中止当前加载，保留已完成扫描结果与图片计数，后续按键/自动请求可直接重试。
        state             <= ST_IDLE;
        state_code        <= 4'd1;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_found_valid  <= 1'b0;
        load_sector_latched <= 32'd0;
        load_done          <= 1'b0;
    end else begin
        scan_found_valid <= 1'b0;
        load_done         <= 1'b0;

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_paused      <= 1'b0;
                    fast_scan_verified <= 1'b0;
                    fast_scan_fallback <= 1'b0;
                    fast_index       <= 2'd0;
                    scan_found_total <= 3'd0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                    if(FAST_SCAN_ENABLE && scan_target_count==4 &&
                       FAST_SECTOR0>=scan_start_sector && FAST_SECTOR3<=scan_max_sector &&
                       FAST_SECTOR0<FAST_SECTOR1 && FAST_SECTOR1<FAST_SECTOR2 && FAST_SECTOR2<FAST_SECTOR3) begin
                        sd_sec_read_addr <= FAST_SECTOR0;
                        state <= ST_FAST_VERIFY;
                    end
                end else if (scan_paused && scan_resume) begin
                    scan_paused <= 1'b0;
                    sd_sec_read_addr <= scan_sector;
                    state <= fast_scan_verified ? ST_FAST_PUBLISH : ST_SCAN;
                end else if (load_start) begin
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end
            end

            // 发布任何地址前校验全部四个提示；过时提示不得进入有效映射。
            ST_FAST_VERIFY: begin
                state_code <= 4'd2;
                sd_sec_read <= 1'b1;
                if(sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if(header_match && rd_cnt==10'd512 &&
                       (sector_crc ^ 32'hFFFFFFFF)==fast_crc(fast_index)) begin
                        if(fast_index==3) begin
                            fast_scan_verified<=1'b1;
                            fast_index<=0;
                            state<=ST_FAST_PUBLISH;
                        end else begin
                            fast_index<=fast_index+1'b1;
                            sd_sec_read_addr<=fast_sector(fast_index+1'b1);
                        end
                    end else begin
                        fast_scan_fallback<=1'b1;
                        fast_scan_verified<=1'b0;
                        scan_sector<=scan_start_sector;
                        sd_sec_read_addr<=scan_start_sector;
                        state<=ST_SCAN;
                    end
                end
            end

            ST_FAST_PUBLISH: begin
                sd_sec_read<=1'b0;
                scan_found_valid<=1'b1;
                scan_found_sector<=fast_sector(fast_index);
                scan_found_total<=scan_found_total+1'b1;
                if(scan_found_total+1'b1>=scan_target_count) begin
                    scan_done<=1'b1;
                    state<=ST_IDLE;
                end else begin
                    fast_index<=fast_index+1'b1;
                    if(PAUSE_AFTER_FIRST && scan_found_total==0) begin
                        scan_paused<=1'b1;
                        state<=ST_IDLE;
                    end
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;

                    if (header_match) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 3'd1;

                        if ((scan_found_total + 3'd1 >= scan_target_count) || (next_scan_sector_if_match > scan_max_sector)) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                            if(PAUSE_AFTER_FIRST && scan_found_total==0) begin
                                scan_paused<=1'b1;
                                state<=ST_IDLE;
                            end
                        end
                    end else begin
                        if (scan_sector >= scan_max_sector) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                        end
                    end
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_match) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        state <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_req_ack) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;
                end
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (bmp_len_cnt >= file_len) begin
                        state     <= ST_IDLE;
                        load_done <= 1'b1;
                    end else begin
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end
                end
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule
