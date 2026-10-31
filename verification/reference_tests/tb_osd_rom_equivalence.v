`timescale 1ns/1ps
module tb_osd_rom_equivalence;
reg clk=0;
always #20 clk=~clk;
reg [12:0] addr=0;
wire [15:0] data;
reg [15:0] expected[0:3071];
osd_bitmap_rom dut(.I_clk(clk),.I_addr(addr),.O_data(data));
`ifdef VENDOR_BIN_INIT
defparam dut.bank0.INIT_FILE="osd_text_bank00.dat";
defparam dut.bank1.INIT_FILE="osd_text_bank01.dat";
defparam dut.bank2.INIT_FILE="osd_text_bank02.dat";
defparam dut.bank3.INIT_FILE="osd_text_bank03.dat";
defparam dut.bank4.INIT_FILE="osd_text_bank04.dat";
defparam dut.bank5.INIT_FILE="osd_text_bank05.dat";
`endif
integer i;
initial begin
 $readmemh("osd_text.mem",expected);
 repeat(10) @(negedge clk);
 for(i=0;i<3072;i=i+1) begin
   addr=i; @(posedge clk);#2;
   if(data!==expected[i]) $fatal(1,"vendor ROM mismatch addr=%0d got=%h expected=%h",i,data,expected[i]);
   @(negedge clk);
 end
 // Nonsequential accesses also verify bank select/data latency alignment.
 for(i=3071;i>=0;i=i-113) begin
   addr=i; @(posedge clk);#2;
   if(data!==expected[i]) $fatal(1,"vendor ROM bank latency mismatch addr=%0d",i);
   @(negedge clk);
 end
 $display("PASS: vendor EG_LOGIC_BRAM matches every text column and bank boundary.");$finish;
end
initial begin #1000000;$fatal(1,"ROM watchdog");end
endmodule
