`timescale 1ns/1ps
`include "global_def.v"
// Real encrypted controller, frame arbiters and generated asynchronous FIFOs.
// DQ is a dummy constant: this checks service/refresh/CDC and FIFO acceptance,
// not SDRAM electrical timing or stored pixel content. Hardware test required.
module tb_memory_bandwidth_40;
reg mc=0,wc=0,vc=0,rst=1,vrst=1,wreq=0,we=0;
always #12.5 mc=~mc;
always #5 wc=~wc;
always #20 vc=~vc;
wire init,refv,busy,valid,sclk,ras,cas,wen,ar,aw,rreq,rack,wack,wfinish,de,vs;
wire [20:0] ra,wa;
wire [31:0] din,dout,pixel;
wire [3:0] dm,sdm;
wire [1:0] ba;
wire [10:0] sa;
wire [31:0] dq;
reg [31:0] wdata=0;
integer pixels=0,frames=0,accepted=0,issued=0,refreshes=0,min_level=512,i;
reg checked_frame=0;
reg [7:0] req_pipe=0;
realtime last_refresh=0,max_refresh_gap=0,min_refresh_gap=1000000000;
realtime refresh_history[0:2047];
// SDRAM retention is specified over a rolling 2048-refresh/64ms window.
// A single-gap bound inferred from two bursts is not a controller guarantee.
assign dq=32'ha5a5a5a5;
sdr_as_ram ram(.Sdr_clk(mc),.Sdr_clk_sft(~mc),.Rst(rst),
 .Sdr_init_done(init),.Sdr_init_ref_vld(refv),.Sdr_busy(busy),.App_ref_req(1'b0),
 .App_wr_en(aw),.App_wr_addr(wa),.App_wr_dm(dm),.App_wr_din(din),
 .App_rd_en(ar),.App_rd_addr(ra),.Sdr_rd_en(valid),.Sdr_rd_dout(dout),
 .SDRAM_CLK(sclk),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(wen),
 .SDR_BA(ba),.SDR_ADDR(sa),.SDR_DM(sdm),.SDR_DQ(dq));
video_timing_data timing(.video_clk(vc),.rst(vrst),.read_req(rreq),
 .read_req_ack(rack),.hs(),.vs(vs),.de(de));
always @(posedge vc)if(vrst)req_pipe<=0;else req_pipe<={req_pipe[6:0],rreq};
frame_read_write frames_io(.rst(rst),.mem_clk(mc),.Sdr_init_done(init),
 .Sdr_init_ref_vld(refv),.Sdr_busy(busy),.App_rd_en(ar),.App_rd_addr(ra),
 .Sdr_rd_en(valid),.Sdr_rd_dout(dout),.read_clk(vc),.read_req(req_pipe[7]),
 .read_req_ack(rack),.read_finish(),.read_addr_0(21'd0),.read_addr_1(21'd307200),
 .read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd307200),
 .read_en(de),.read_data(pixel),.App_wr_en(aw),.App_wr_addr(wa),.App_wr_din(din),
 .App_wr_dm(dm),.write_clk(wc),.write_req(wreq),.write_req_ack(wack),
 .write_finish(wfinish),.write_addr_0(21'd0),.write_addr_1(21'd307200),
 .write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd1),
 .write_len(21'd307200),.write_en(we),.write_data(wdata));
always @(posedge sclk)if(init && {ras,cas,wen}===3'b001)begin
 if(last_refresh!=0)begin
  if($realtime-last_refresh>max_refresh_gap)max_refresh_gap=$realtime-last_refresh;
  if($realtime-last_refresh<min_refresh_gap)min_refresh_gap=$realtime-last_refresh;
  // Conservative duplicate-command guard, not a full SDRAM timing model.
  if($realtime-last_refresh<100)
   $fatal(1,"refresh commands less than 100ns apart: gap=%0.1f ns",$realtime-last_refresh);
 end
 if(refreshes>=2048 && $realtime-refresh_history[refreshes%2048]>64000000)
  $fatal(1,"2048 refreshes exceed SDRAM 64ms window: %0.1f ns",$realtime-refresh_history[refreshes%2048]);
 refresh_history[refreshes%2048]=$realtime;
 last_refresh=$realtime;refreshes=refreshes+1;
end
always @(posedge wc)if(!rst && we)begin
 if(!frames_io.write_buf.wr_en_s || frames_io.write_buf.wr_rst)
  $fatal(1,"TF write rejected by FIFO accepted=%d issued=%d state W/R=%d/%d used=%d into=%b busy R/W=%b/%b ref=%b reset=%b",accepted,issued,frames_io.frame_fifo_write_m0.state,frames_io.frame_fifo_read_m0.state,frames_io.rdusedw,frames_io.frame_fifo_write_m0.into_burst,frames_io.App_rd_busy,frames_io.App_wr_busy,refv,frames_io.write_buf.wr_rst);
 accepted=accepted+1;
end
always @(posedge mc)if(!rst)begin
 if(aw)begin
  if(!frames_io.write_buf.rd_en_s || frames_io.write_buf.rd_rst)
   $fatal(1,"memory write FIFO underflow");
  issued=issued+1;
 end
 if(valid && (!frames_io.read_buf.wr_en_s || frames_io.read_buf.wr_rst))
  $fatal(1,"memory read data rejected by FIFO");
end
always @(negedge vs)if(!vrst)begin
 if(checked_frame)begin
  if(pixels!=307200)$fatal(1,"incomplete frame: %d pixels",pixels);
  frames=frames+1;pixels=0;
  $display("Progress: frame=%d accepted=%d issued=%d refreshes=%d t=%t",frames,accepted,issued,refreshes,$time);
 end
 checked_frame=1;
end
always @(posedge vc)if(!vrst && de)begin
 if(frames_io.read_buf.empty_flag || frames_io.read_buf.rd_rst)
  $fatal(1,"display FIFO underflow t=%t pixels=%d",$time,pixels);
 if(frames_io.read_buf.rdusedw<min_level)min_level=frames_io.read_buf.rdusedw;
 if(checked_frame)pixels=pixels+1;
end
initial begin
 if (`SELF_REFRESH_INTERVAL != 1229)$fatal(1,"incorrect refresh macro expansion");
 repeat(10)@(negedge wc);rst=0;wait(init);
 $display("SDRAM initialized at %t, refresh interval=%d cycles",$time,`SELF_REFRESH_INTERVAL+1);
 @(negedge vc);vrst=0;
 @(negedge wc);wreq=1;wait(wack);repeat(3)@(negedge wc);wreq=0;
 repeat(10)@(negedge wc);
 // 4 Mword/s, over 3.8 times the TF SPI wire-rate limit of 25Mb/s / 24.
 for(i=0;i<307200;i=i+1)begin
  we=1;wdata=i;@(negedge wc);we=0;repeat(24)@(negedge wc);
 end
 wait(wfinish);repeat(8)@(negedge wc);
 if(accepted!=307200 || issued!=307200)$fatal(1,"write counts %d/%d",accepted,issued);
 wait(frames>=5);
 if(refreshes<2048)$fatal(1,"insufficient refresh coverage");
 $display("PASS: encrypted 40MHz SDR controller + real FIFOs, %d full video frames, 307200 writes accepted/issued, no FIFO overflow/underflow, min read level=%d, refresh commands=%d, min/max refresh gap=%0.1f/%0.1f ns.",frames,min_level,refreshes,min_refresh_gap,max_refresh_gap);
 $finish;
end
initial begin #150000000;$fatal(1,"bandwidth watchdog frames=%d issued=%d",frames,issued);end
endmodule
