`timescale 1ns/1ps
module tb_tf_fifo_fullframes_fix;
reg wc=0,mc=0,rst=1,req=0,we=0;
reg [31:0] data=0;
reg [1:0] idx=0;
wire ack,finish,aclr,appwr,full,empty;
wire [8:0] used;
wire [31:0] dout;
integer frame,i,guard,accepted,rejected,dequeued,commands,finishes;
reg done;
always #5 wc=~wc;
always #4 mc=~mc;
wfifo_32_32_512 fifo(.rst(aclr),.clkw(wc),.clkr(mc),.we(we),.di(data),.re(appwr),
 .dout(dout),.valid(),.full_flag(full),.empty_flag(empty),.afull(),.aempty(),
 .wrusedw(),.rdusedw(used));
frame_fifo_write #(.BURST_BITS(9),.BURST_SIZE(256),.WRITE_V_FLIP(1),
 .FRAME_WIDTH(640),.FRAME_HEIGHT(480)) dut(
 .rst(rst),.mem_clk(mc),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(1'b0),.App_rd_busy(1'b0),.O_wr_busy(),.App_wr_en(appwr),.App_wr_addr(),
 .write_req(req),.write_req_ack(ack),.write_finish(finish),
 .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd0),.write_addr_3(21'd0),
 .write_addr_index(idx),.write_len(21'd307200),.fifo_aclr(aclr),.rdusedw({1'b0,used}));
always @(posedge wc)if(!rst)begin
 if(fifo.wr_en_s && !fifo.wr_rst)accepted=accepted+1;
 if(we && !(fifo.wr_en_s && !fifo.wr_rst))rejected=rejected+1;
end
always @(posedge mc)if(!rst)begin
 if(fifo.rd_en_s && !fifo.rd_rst)dequeued=dequeued+1;
 if(appwr)commands=commands+1;
 if(finish)begin finishes=finishes+1;done=1;end
end
initial begin
 repeat(5)@(negedge wc);rst=0;
 for(frame=0;frame<2;frame=frame+1)begin
  accepted=0;rejected=0;dequeued=0;commands=0;finishes=0;done=0;idx=frame[0];
  req=1;guard=0;while(ack!==1 && guard<200)begin @(negedge wc);guard=guard+1;end
  if(ack!==1 || fifo.wr_rst || fifo.rd_rst || aclr)$fatal(1,"bad FIFO ready handshake");
  req=0;repeat(4)@(negedge wc);
  for(i=0;i<307200;i=i+1)begin we=1;data=i;@(negedge wc);we=0;repeat(3)@(negedge wc);end
  guard=0;while(!done && guard<20000)begin @(negedge wc);guard=guard+1;end
  repeat(8)@(negedge wc);
  if(!done || accepted!=307200 || rejected!=0 || dequeued!=307200 || commands!=307200 || finishes!=1)
   $fatal(1,"full-frame counts mismatch");
  $display("PASS full frame %0d: all 307200 words accepted, dequeued and issued once.",frame+1);
 end
 $display("PASS: two complete 640x480 frames survive repeated reset-before-ack handshakes.");
 $finish;
end
initial begin #100000000;$fatal(1,"watchdog");end
endmodule
