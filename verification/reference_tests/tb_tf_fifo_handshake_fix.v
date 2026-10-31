`timescale 1ns/1ps
module tb_tf_fifo_handshake_fix;
reg write_clk=0,mem_clk=0,rst=1;
always #5 write_clk=~write_clk;
always #4 mem_clk=~mem_clk;
reg write_req=0,write_en=0;
reg [31:0] write_data=0;
reg [1:0] write_index=0;
wire write_ack,write_finish,fifo_aclr,app_write,full,empty;
wire [8:0] fifo_used;
wire [31:0] fifo_data;
wire [20:0] app_addr;
integer frame,i,guard,accepted,rejected,dequeued,commands,finishes;
reg saw_assert,saw_release_before_ack,done;

wfifo_32_32_512 fifo(
 .rst(fifo_aclr),.clkw(write_clk),.clkr(mem_clk),.we(write_en),.di(write_data),
 .re(app_write),.dout(fifo_data),.valid(),.full_flag(full),.empty_flag(empty),
 .afull(),.aempty(),.wrusedw(),.rdusedw(fifo_used));

frame_fifo_write #(
 .BURST_BITS(9),.BURST_SIZE(64),.WRITE_V_FLIP(0),
 .FIFO_RESET_ASSERT_CYCLES(8),.FIFO_RESET_RELEASE_CYCLES(8)
) dut(
 .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(1'b0),.App_rd_busy(1'b0),.O_wr_busy(),.App_wr_en(app_write),
 .App_wr_addr(app_addr),.write_req(write_req),.write_req_ack(write_ack),
 .write_finish(write_finish),.write_addr_0(21'd0),.write_addr_1(21'd2048),
 .write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(write_index),
 .write_len(21'd1024),.fifo_aclr(fifo_aclr),.rdusedw({1'b0,fifo_used}));

always @(posedge write_clk) if(!rst) begin
 if(fifo.wr_en_s && !fifo.wr_rst) accepted=accepted+1;
 if(write_en && !(fifo.wr_en_s && !fifo.wr_rst)) rejected=rejected+1;
end
always @(posedge mem_clk) if(!rst) begin
 if(fifo.rd_en_s && !fifo.rd_rst) dequeued=dequeued+1;
 if(app_write) commands=commands+1;
 if(write_finish) begin finishes=finishes+1;done=1;end
 if(fifo_aclr) saw_assert=1;
 if(saw_assert && !fifo_aclr && fifo.wr_rst==0 && fifo.rd_rst==0)
  saw_release_before_ack=1;
 if(write_ack && (fifo_aclr || fifo.wr_rst || fifo.rd_rst || !saw_release_before_ack))
  $fatal(1,"write ack preceded complete FIFO reset release");
end

initial begin
 accepted=0;rejected=0;dequeued=0;commands=0;finishes=0;
 repeat(5) @(negedge write_clk);rst=0;
 for(frame=0;frame<6;frame=frame+1) begin
  accepted=0;rejected=0;dequeued=0;commands=0;finishes=0;
  saw_assert=0;saw_release_before_ack=0;done=0;write_index=frame[0];
  write_req=1;guard=0;
  while(write_ack!==1 && guard<200)begin @(negedge write_clk);guard=guard+1;end
  if(write_ack!==1)$fatal(1,"write request was not acknowledged");
  if(!saw_assert || !saw_release_before_ack)$fatal(1,"reset phases not observed");
  write_req=0;
  repeat(5)@(negedge write_clk);
  for(i=0;i<1024;i=i+1)begin
   write_en=1;write_data={frame[7:0],i[23:0]};@(negedge write_clk);
   write_en=0;repeat(2)@(negedge write_clk);
  end
  guard=0;
  while(!done && guard<10000)begin @(negedge write_clk);guard=guard+1;end
  repeat(8)@(negedge write_clk);
  if(!done || accepted!=1024 || rejected!=0 || dequeued!=1024 || commands!=1024 || finishes!=1)
   $fatal(1,"multi-frame transfer count mismatch");
  $display("PASS frame %0d: reset-before-ack, accepted/dequeued/AppWrite=1024, rejected=0, finish=1",frame+1);
 end
 $display("PASS: six consecutive frames use explicit FIFO reset assert/release before source acknowledgement.");
 $finish;
end
initial begin #10000000;$fatal(1,"watchdog");end
endmodule
