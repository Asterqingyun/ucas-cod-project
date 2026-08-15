`timescale 10 ns / 1 ns

`define DATA_WIDTH 32
`define ADD 4'b0010
`define SUB 4'b0110
`define AND 4'b0000
`define OR  4'b0001
`define SLT 4'b0111
`define XOR 4'b0100
`define NOR 4'b0101
`define SLTU 4'b0011
`define MUL 4'b1000

module alu(
	input  [`DATA_WIDTH - 1:0]  A,
	input  [`DATA_WIDTH - 1:0]  B,
	input  [              3:0]  ALUop,
	output                      Overflow,
	output                      CarryOut,
	output                      Zero,
	output [`DATA_WIDTH - 1:0]  Result
);

	wire [`DATA_WIDTH-1:0] B_change;
	wire c_in;
	wire [32:0] sum;
	wire [`DATA_WIDTH-1:0] add_sub_result;
	wire cout;
	
	wire slt_result;
	wire sltu_result;
	wire [`DATA_WIDTH-1:0] mul_res;

	// 加减法预处理
	assign B_change = (ALUop == `ADD) ? B : ~B;
	assign c_in     = (ALUop == `ADD) ? 1'b0 : 1'b1;

	// 单一的核心加法器 (32位+32位+1位进位)，Vivado 会自动映射为最优的 CARRY8 链
	assign sum = {1'b0, A} + {1'b0, B_change} + c_in;
	assign add_sub_result = sum[31:0];
	assign cout = sum[32]; 
	assign CarryOut = cout;

	// 溢出与比较逻辑
	assign Overflow = (A[31] == B_change[31]) && (add_sub_result[31] != A[31]);
	assign slt_result = add_sub_result[31] ^ Overflow; // 有符号比较
	
	// 【核心优化】：A < B (无符号) 的本质就是 A - B 发生了借位（即加法没有进位）
	// 这样可以省去一个32位的比较器硬件！
	assign sltu_result = ~cout; 

	// 乘法器：只取低32位，有符号和无符号乘法低32位是一样的，直接乘最省资源
	// 1. 声明屏蔽信号
wire [31:0] mul_A;
wire [31:0] mul_B;

// 2. 只有在执行乘法时，才把真实的数据放进乘法器；否则强行给 0
assign mul_A = (ALUop == `MUL) ? A : 32'b0;
assign mul_B = (ALUop == `MUL) ? B : 32'b0;

// 3. 计算乘法
assign mul_res = mul_A * mul_B;

	// 结果输出
	assign Result = (ALUop == `ADD) ? add_sub_result :
			(ALUop == `SUB) ? add_sub_result :
			(ALUop == `AND) ? A & B :
			(ALUop == `OR)  ? A | B :
			(ALUop == `XOR) ? A ^ B :
			(ALUop == `NOR) ? ~(A | B):
			(ALUop == `SLT) ? {31'b0, slt_result}:
			(ALUop == `SLTU)? {31'b0, sltu_result}:
			(ALUop == `MUL) ? mul_res:
			32'b0;

	assign Zero = (Result == 32'b0) ? 1'b1 : 1'b0;

endmodule
