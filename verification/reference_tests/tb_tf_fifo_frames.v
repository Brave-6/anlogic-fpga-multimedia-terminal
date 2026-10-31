`timescale 1ns/1ps
// Real generated FIFO + real frame-write controller, ideal clocks.
// No SDRAM model; verifies handshake/reset/accepted counts, not electrical timing.
module tb_tf_fifo_frames;
reg wc=0,mc=0,rst=1;
always #5 wc=~wc;
always #4 mc=~mc;
reg req=0,we=0;
reg [31:0] data=0;
reg [1:0] idx=0;
wire ack,finish,aclr,appwr,busy,full,empty,waccept,raccept,rreset;
wire [8:0] used;
wire [31:0] dout;
wire [20:0] addr;
wire [3:0] state;
wire [19:0] control_count;
integer phase=0,frame=0,produced=0,accepted=0,rejected=0,drained=0,commands=0,completed=0;
integer i,n;
reg finished=0;
always @(posedge mc)begin
 if(rst)phase<=0;else if(phase==199)phase<=0;else phase<=phase+1;
 if(!rst)begin
  if(appwr)commands=commands+1;
  if(raccept)drained=drained+1;
  if(finish)begin completed=completed+1;finished=1;end
 end
end
always @(posedge wc)if(!rst)begin
 if(we)produced=produced+1;
 if(waccept)accepted=accepted+1;
 if(we&&!waccept)rejected=rejected+1;
end
wfifo_32_32_512 fifo(.rst(aclr),.clkw(wc),.clkr(mc),.we(we),.di(data),.re(appwr),.dout(dout),
 .valid(),.full_flag(full),.empty_flag(empty),.afull(),.aempty(),.wrusedw(),.rdusedw(used),
 .debug_write_accept(waccept),.debug_read_accept(raccept),.debug_read_reset(rreset));
frame_fifo_write #(.BURST_BITS(9),.BURST_SIZE(256)) ctl(
 .rst(rst),.mem_clk(mc),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .App_rd_busy(phase<40),.O_wr_busy(busy),.App_wr_en(appwr),.App_wr_addr(addr),
 .write_req(req),.write_req_ack(ack),.write_finish(finish),
 .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd0),.write_addr_3(21'd0),
 .write_addr_index(idx),.write_len(21'd307200),.fifo_aclr(aclr),.rdusedw({1'b0,used}),
 .debug_state(state),.debug_count(control_count));
initial begin
 repeat(5)@(negedge wc);rst=0;
 for(frame=0;frame<5;frame=frame+1)begin
  repeat(8)@(negedge wc);
  produced=0;accepted=0;rejected=0;drained=0;commands=0;completed=0;finished=0;
  idx=frame%2;req=1;n=0;
  while(ack!==1 && n<100)begin @(negedge wc);n=n+1;end
  if(ack!==1)$fatal(1,"write handshake timeout");
  req=0;
  repeat(12)@(negedge wc);
  if(full!==0 || empty!==1 || fifo.wr_rst!==0 || rreset!==0)
   $fatal(1,"FIFO did not reset/release cleanly");
  for(i=0;i<307200;i=i+1)begin
   we=1;data=i;@(negedge wc);we=0;
   repeat(4)@(negedge wc);
  end
  n=0;
  while(!finished && n<20000)begin @(negedge wc);n=n+1;end
  repeat(8)@(negedge wc);
  if(!finished || produced!=307200 || accepted!=307200 || rejected!=0 || commands!=307200 || drained!=307200 || completed!=1)
   $fatal(1,"frame counts/completion failed");
  $display("PASS frame %0d: produced=307200 FIFOaccepted=307200 rejected=0 AppWrites=307200 dequeued=307200 finish=1",frame+1);
 end
 $display("PASS: real FIFO/controller completed five frames with per-frame FIFO reset and intermittent read-side arbitration blocking.");
 $display("LIMIT: ideal RTL clocks and RAM model; no proof of board CDC/reset timing or SDRAM correctness.");
 $finish;
end
initial begin #100000000; $fatal(1,"watchdog");end
endmodule
