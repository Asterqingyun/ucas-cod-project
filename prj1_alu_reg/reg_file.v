`timescale 10 ns / 1 ns

`define DATA_WIDTH 32
`define ADDR_WIDTH 5

module reg_file(
	input                       clk,
	input  [`ADDR_WIDTH - 1:0]  waddr,
	input  [`ADDR_WIDTH - 1:0]  raddr1,
	input  [`ADDR_WIDTH - 1:0]  raddr2,
	input                       wen,
	input  [`DATA_WIDTH - 1:0]  wdata,
	output [`DATA_WIDTH - 1:0]  rdata1,
	output [`DATA_WIDTH - 1:0]  rdata2
);

	reg [`DATA_WIDTH-1:0] reg_dump [`DATA_WIDTH-1:0]; //定义寄存器堆
	assign rdata1 = {`DATA_WIDTH{(raddr1 != 0)}} & reg_dump[raddr1];
	assign rdata2 = {`DATA_WIDTH{(raddr2 != 0)}} & reg_dump[raddr2];
	always @(posedge clk) begin
		if (wen) begin
			if (waddr != `ADDR_WIDTH'b0)begin
				reg_dump[waddr]<=wdata;
			end

		end
	end
	
	
	// TODO: Please add your logic design here
	
endmodule
