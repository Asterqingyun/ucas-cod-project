`timescale 10 ns / 1 ns

`define DATA_WIDTH 32
`define left_shift 2'b00
`define ari_right 2'b11
`define logic_right 2'b10
`define nothing 2'b01
module shifter (
	input  [`DATA_WIDTH - 1:0] A,
	input  [              4:0] B,
	input  [              1:0] Shiftop,
	output [`DATA_WIDTH - 1:0] Result
);
	
	wire [31:0] sll_res = A << B[4:0];
	wire [31:0] srl_res = A >> B[4:0];


	wire signed[31:0] signed_A   = A;                                // 强制赋予符号,无敌了这个符号，如果放在一个多目运算符里面sign都没用
	wire signed [31:0] signed_res = signed_A >>> B[4:0];             

//最后再用多路选择器进行分配
	assign Result = (Shiftop == `left_shift)  ? sll_res :
                (Shiftop == `ari_right)   ? signed_res :          // 此时 signed_res 已经是正确算出 0xfc... 的结果了
                (Shiftop == `logic_right) ? srl_res :
                A;
	
endmodule
