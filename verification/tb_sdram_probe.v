`timescale 1ns/1ps
module tb_sdram_probe;
reg clk=0,rst=1,we=0,re=0;
always #12.5 clk=~clk;
wire init,refv,busy,valid,sclk,ras,cas,we_n;
wire [31:0] data;
wire [1:0] ba;
wire [10:0] addr;
wire [3:0] dm;
wire [31:0] dq;
reg [20:0] a=0;
integer count=0,commands=0,i;
assign dq = we ? 32'bz : 32'ha5a5a5a5;
sdr_as_ram dut(.Sdr_clk(clk),.Sdr_clk_sft(~clk),.Rst(rst),
 .Sdr_init_done(init),.Sdr_init_ref_vld(refv),.Sdr_busy(busy),.App_ref_req(1'b0),
 .App_wr_en(we),.App_wr_addr(a),.App_wr_dm(4'b0),.App_wr_din({11'b0,a}),
 .App_rd_en(re),.App_rd_addr(a),.Sdr_rd_en(valid),.Sdr_rd_dout(data),
 .SDRAM_CLK(sclk),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we_n),
 .SDR_BA(ba),.SDR_ADDR(addr),.SDR_DM(dm),.SDR_DQ(dq));
always @(posedge sclk) if({ras,cas,we_n}!==3'b111 && commands<25)begin
 $display("SDR cmd=%b bank=%d addr=%h t=%t",{ras,cas,we_n},ba,addr,$time);commands=commands+1;
end
always @(posedge clk) if(valid)begin
 count=count+1;
 if(data!==32'ha5a5a5a5)$fatal(1,"return data mismatch %h",data);
end
initial begin
 repeat(10)@(negedge clk);rst=0;wait(init);$display("init t=%t",$time);
 repeat(20)@(negedge clk);
 for(i=0;i<256;i=i+1)begin re=1;a=i;@(negedge clk);end
 re=0;repeat(30)@(negedge clk);
 if(count!=256)$fatal(1,"read count=%d",count);
 $display("PASS: encrypted SDR controller at 40MHz returns 256 words.");$finish;
end
initial begin #10000000;$fatal(1,"watchdog");end
endmodule
