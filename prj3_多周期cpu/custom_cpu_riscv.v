`timescale 10ns / 1ns
`define sign 1
`define logic 0
`define DATA_WIDTH 32
`define ADD 4'b0010
`define SUB 4'b0110
`define AND 4'b0000
`define OR 4'b0001
`define SLT 4'b0111
`define XOR 4'b0100
`define NOR  4'b0101
`define SLTU 4'b0011
`define MUL 4'b1000
`define left_shift 2'b00
`define ari_right 2'b11
`define logic_right 2'b10
`define nothing  2'b01

// 【修改点1】：将状态机拓展为9位，以容纳 TRAP 状态
`define INIT 10'b0000000001
`define IF   10'b0000000010
`define ID   10'b0000000100
`define EX   10'b0000001000
`define IW   10'b0000010000
`define WB   10'b0000100000
`define LD   10'b0001000000
`define RDW  10'b0010000000
`define ST   10'b0100000000
`define TRAP 10'b1000000000 // 新增：中断响应状态，现在是标准的独热码了

`define RDATA 2'b00
`define four 2'b01
`define onlyext 2'b10
`define frompc 1
`define fromaluout 0
`define pcfromaluout 1
`define pcfromresult 0
`define afromoldpc 2'b01
`define afromnewpc  2'b10
`define afromrs 2'b00

module custom_cpu(
	input         clk,
	input         rst,

	//Instruction request channel
	output [31:0] PC,
	output        Inst_Req_Valid,
	input         Inst_Req_Ready,

	//Instruction response channel
	input  [31:0] Instruction,
	input         Inst_Valid,
	output        Inst_Ready,

	//Memory request channel
	output [31:0] Address,
	output        MemWrite,
	output [31:0] Write_data,
	output [ 3:0] Write_strb,
	output        MemRead,
	input         Mem_Req_Ready,

	//Memory data response channel
	input  [31:0] Read_data,
	input         Read_data_Valid,
	output        Read_data_Ready,

	input         intr, // 中断信号接入

	output reg [31:0] cpu_perf_cnt_0,
	output reg [31:0] cpu_perf_cnt_1,
	output reg [31:0] cpu_perf_cnt_2,
	output reg [31:0] cpu_perf_cnt_3,
	output reg [31:0] cpu_perf_cnt_4,
	output reg [31:0] cpu_perf_cnt_5,
	output reg [31:0] cpu_perf_cnt_6,
	output reg [31:0] cpu_perf_cnt_7,
	output reg [31:0] cpu_perf_cnt_8,
	output reg [31:0] cpu_perf_cnt_9,
	output reg [31:0] cpu_perf_cnt_10,
	output reg [31:0] cpu_perf_cnt_11,
	output reg [31:0] cpu_perf_cnt_12,
	output reg [31:0] cpu_perf_cnt_13,
	output reg [31:0] cpu_perf_cnt_14,
	output reg [31:0] cpu_perf_cnt_15,

	output [69:0] inst_retire
);

	wire			RF_wen;
	wire [4:0]		RF_waddr;
	wire [31:0]		RF_wdata;

	reg [31:0] Ins;
	reg [31:0] new_PC;
	
	wire [31:0] imm;
	reg PCWrite;
	reg IorD;
	wire MemtoReg;
	wire IRWrite;
	wire PCSource;
	wire [3:0] ALUop;
	reg [1:0]ALUSrcB;
	reg [1:0]ALUSrcA;
	wire RegWrite;
	wire eq ; 
	wire lt  ;
	wire ltu  ;
	wire branch_taken;

	wire [31:0] rdata1;
	wire [31:0] rdata2;
	wire [31:0] next_PC;
	wire [31:0] jalr_target; 
	//center
	reg [31:0]memory_data_register;
	wire [4:0] shift_bits;
	wire [1:0] byte_offset;
	wire [1:0] Shiftop;
	wire [`DATA_WIDTH - 1:0] shift_A;
	wire [4:0] shift_B;
	wire [`DATA_WIDTH - 1:0] shift_result;
	reg  [31:0]ALUout;
	wire [`DATA_WIDTH - 1:0] A;
	wire [`DATA_WIDTH - 1:0] B;
	
	wire Overflow;
	wire CarryOut;
	wire Zero;
	wire [`DATA_WIDTH - 1:0] Result;
	wire is_shift;
	wire [7:0] byte_read;
	
	wire [15:0] half_read;
	wire [31:0] load_data;

	// 指令类型解码信号
	wire [6:0]  opcode;
	wire [4:0]  rd;
	wire [2:0]  funct3;
	wire [4:0]  rs1;
	wire [4:0]  rs2;
	wire [6:0]  funct7;
	wire is_R;
	wire is_I;
	wire is_L;
	wire is_S;
	wire is_B;
	wire is_U_LUI;
	wire is_U_AUIPC;
	wire is_J_JAL;
	wire is_J_JALR;
	
	// 【修改点2】：新增 SYSTEM 类型指令解码，用于中断返回 (MRET) 和读写 CSR (CSRRW)
	wire is_SYSTEM;
	wire is_MRET;
	wire is_CSRRW;

	// 立即数扩展信号
	wire [31:0] imm_I;
	wire [31:0] imm_S;
	wire [31:0] imm_B;
	wire [31:0] imm_U;
	wire [31:0] imm_J;
	
	// 状态机变量：拓展到 9 位
	reg [9:0] current_state;

	reg [31:0] next_pc_4;
	reg [31:0] old_pc;

	// =========================================================================
	// 【新增】：CSR 寄存器及中断控制逻辑
	// =========================================================================
	reg [31:0] mepc;          // Machine Exception Program Counter
	reg [31:0] mtvec;         // Machine Trap-Vector Base-Address
	reg        mstatus_mie;   // Machine Interrupt Enable
	reg        mstatus_mpie;  // Machine Previous Interrupt Enable

	// 核心判定条件：当有中断请求且全局中断使能开启时
	//wire take_intr = intr && mstatus_mie;
	// wire take_intr = intr && mstatus_mie;
	wire take_intr = 1'b0; // 调试：强制关闭中断响应
	always @(posedge clk) begin
		if (rst) begin
			mstatus_mie  <= 1'b1;  // 默认开中断
			mstatus_mpie <= 1'b1;
			mtvec        <= 32'h0000001C; // 默认的中断向量地址，可通过 CSRRW 动态修改
			mepc         <= 32'b0;
		end else begin
			if (current_state == `TRAP) begin
				// 发生中断：保存PC，保存并关闭MIE
				mepc         <= new_PC;
				mstatus_mpie <= mstatus_mie;
				mstatus_mie  <= 1'b0;
			end else if (is_MRET && current_state == `EX) begin
				// 中断返回：恢复MIE
				mstatus_mie  <= mstatus_mpie;
				mstatus_mpie <= 1'b1;
			end else if (is_CSRRW && current_state == `WB) begin
				// 处理CSRRW写入
				case (Ins[31:20])
					12'h305: mtvec <= rdata1; // 写 mtvec
					12'h341: mepc  <= rdata1; // 写 mepc
					12'h300: begin            // 写 mstatus (MIE位为3，MPIE位为7)
						mstatus_mie  <= rdata1[3];
						mstatus_mpie <= rdata1[7];
					end
				endcase
			end
		end
	end

	// CSR读取MUX
	wire [31:0] csr_rdata;
	assign csr_rdata = (Ins[31:20] == 12'h305) ? mtvec :
	                   (Ins[31:20] == 12'h341) ? mepc :
	                   (Ins[31:20] == 12'h300) ? {24'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0} : 32'b0;
	// =========================================================================


	// 状态机
	always @(posedge clk ) begin
		if (rst) begin
			current_state <= `INIT;
			cpu_perf_cnt_0 <= 32'd0; 
			cpu_perf_cnt_1 <= 32'd0; 
			cpu_perf_cnt_2 <= 32'd0; 
			cpu_perf_cnt_3 <= 32'd0; 
			cpu_perf_cnt_4 <= 32'd0;	
			cpu_perf_cnt_5 <= 32'd0;	
			cpu_perf_cnt_6 <= 32'd0; 
			cpu_perf_cnt_7 <= 32'd0; 
			cpu_perf_cnt_8 <= 32'd0; 
			cpu_perf_cnt_9 <= 32'd0; // 我们将使用 cnt_9 记录触发 TRAP 的总次数
			cpu_perf_cnt_10<= 32'd0;
			cpu_perf_cnt_11<= 32'd0;
			cpu_perf_cnt_12<= 32'd0;
			cpu_perf_cnt_13<= 32'd0;
			cpu_perf_cnt_14<= 32'd0;
			cpu_perf_cnt_15<= 32'd0;
		end else begin
			cpu_perf_cnt_0 <= cpu_perf_cnt_0 + 1;
			case (current_state)
				`INIT:begin
					current_state <= `IF;
				end

				`IF: begin
					if (Inst_Req_Ready)begin
						current_state <= `IW;
					end else begin
						cpu_perf_cnt_2 <= cpu_perf_cnt_2 + 1; //取指原地打转
					end
				end
				
				`IW: begin
					if (Inst_Valid)begin
						current_state <= `ID;
					end else begin
						cpu_perf_cnt_8 <= cpu_perf_cnt_8 + 1;
					end
				end
				
				`ID:begin
					current_state <= `EX;
				end

				`EX: begin
					if (is_L ) begin
						current_state <= `LD;
						cpu_perf_cnt_6 <= cpu_perf_cnt_6 + 1;
					end
					// 【修改点3】：加入 is_CSRRW 到写回级，is_MRET 则直接返回或陷入 TRAP
					else if (is_R || is_I || is_U_AUIPC || is_U_LUI || is_J_JAL || is_J_JALR || is_CSRRW) begin
						current_state <= `WB;
					end
					else if (is_B) begin
						// 【修改点4】：指令边界处（即将回IF时），检查中断，有中断则去 TRAP
						current_state <= take_intr ? `TRAP : `IF;
						cpu_perf_cnt_1 <= cpu_perf_cnt_1 + 1;
					end
					else if (is_S) begin
						current_state <= `ST;
						cpu_perf_cnt_7 <= cpu_perf_cnt_7 + 1;
					end
					else if (is_MRET) begin
						current_state <= take_intr ? `TRAP : `IF;
						cpu_perf_cnt_1 <= cpu_perf_cnt_1 + 1;
					end
					else begin
						current_state <= take_intr ? `TRAP : `IF;
					end
				end
				
				`ST: begin
					if((Mem_Req_Ready))begin
						// 【修改点4】
						current_state <= take_intr ? `TRAP : `IF;
						cpu_perf_cnt_1 <= cpu_perf_cnt_1 +1;
					end
					else begin
						cpu_perf_cnt_3 <= cpu_perf_cnt_3 + 1; //写原地打转
					end
				end
					
				`LD: begin
					if(Mem_Req_Ready)begin
						current_state <= `RDW;
					end else begin
						cpu_perf_cnt_4 <= cpu_perf_cnt_4 + 1; //load 原地打转
					end
				end

				`WB: begin
					// 【修改点4】
					current_state <= take_intr ? `TRAP : `IF;
					cpu_perf_cnt_1 <= cpu_perf_cnt_1 + 1;	
				end

				`RDW:begin
					if(Read_data_Valid)begin
						current_state <= `WB;
					end else begin
						cpu_perf_cnt_5 <= cpu_perf_cnt_5 + 1;	//read data waiting
					end 
				end

				// 【新增】：TRAP 状态逻辑，耗费一拍进行跳转
				`TRAP: begin
					current_state <= `IF;
					cpu_perf_cnt_9 <= cpu_perf_cnt_9 + 1; // 记录发生中断的次数
				end

				default: begin
					current_state <= `IF;
				end
			endcase
		end
	end
	
	//驱动信号
	assign Inst_Req_Valid =(rst) ? 1'b0 :( current_state == `IF)	;//指令请求有效
	assign Read_data_Ready = (current_state == `INIT) || (current_state == `RDW);
	assign Inst_Ready = (current_state == `INIT) || (current_state == `IW);
	
	// 一、 指令类型解码赋值
	assign opcode = Ins[6:0];
	assign rd     = Ins[11:7];
	assign funct3 = Ins[14:12];
	assign rs1    = Ins[19:15];
	assign rs2    = Ins[24:20];
	assign funct7 = Ins[31:25];

	assign is_R       = (opcode == 7'b0110011);
	assign is_I       = (opcode == 7'b0010011); // 算术逻辑 I 型
	assign is_L       = (opcode == 7'b0000011); // Load
	assign is_S       = (opcode == 7'b0100011); // Store
	assign is_B       = (opcode == 7'b1100011); // Branch
	assign is_U_LUI   = (opcode == 7'b0110111);
	assign is_U_AUIPC = (opcode == 7'b0010111);
	assign is_J_JAL   = (opcode == 7'b1101111);
	assign is_J_JALR  = (opcode == 7'b1100111);

	// 【修改点2】：系统指令解码
	assign is_SYSTEM  = (opcode == 7'b1110011);
	assign is_MRET    = is_SYSTEM && (funct3 == 3'b000) && (Ins[31:20] == 12'b001100000010);
	assign is_CSRRW   = is_SYSTEM && (funct3 == 3'b001);

	// 二、 立即数生成（符号扩展）
	assign imm_I = {{20{Ins[31]}}, Ins[31:20]};
	assign imm_S = {{20{Ins[31]}}, Ins[31:25], Ins[11:7]};
	assign imm_B = {{20{Ins[31]}}, Ins[7], Ins[30:25], Ins[11:8], 1'b0};
	assign imm_U = {Ins[31:12], 12'b0};
	assign imm_J = {{12{Ins[31]}}, Ins[19:12], Ins[20], Ins[30:21], 1'b0};

	assign imm = ((is_I || is_L || is_J_JALR) ) ? imm_I :
             is_S                        ? imm_S :
             is_B                        ? imm_B :
             (is_U_LUI || is_U_AUIPC)    ? imm_U :
             is_J_JAL                    ? imm_J : 32'b0;

	//3.控制引脚
	
	//3.1 regwrite
	assign RegWrite = (current_state == `WB) && (!is_B) && (!is_S);

	//3.2 ALU
	assign ALUop = 
		(current_state == `IF||current_state == `IW)? `ADD: //算PC
		(is_R && funct7 == 7'b0000001) ? `MUL : //MUL
		(is_B)&&((funct3 == 3'b110)||(funct3 == 3'b111 ) )&&(current_state == `EX)? `SLTU :// BGEU/BEU
		(is_B && (funct3 == 3'b100 || funct3 == 3'b101)) &&(current_state == `EX)? `SLT  : // BLT, BGE 
		(is_L || is_S || is_U_AUIPC) ? `ADD :                 // 访存地址计算 / AUIPC
		(is_B && (current_state ==`ID)) ? `ADD :                      //算地址
		(is_B && (current_state == `EX)) ? `SUB :                      //算地址
		((is_R || is_I) && funct3 == 3'b000) ? ((is_R && Ins[30]) ? `SUB : `ADD) : // add/sub (仅R型有sub)
		((is_R || is_I) && funct3 == 3'b010) ? `SLT :         // slt
		((is_R || is_I) && funct3 == 3'b011) ? `SLTU :        // sltu
		((is_R || is_I) && funct3 == 3'b100) ? `XOR :         // xor
		((is_R || is_I) && funct3 == 3'b110) ? `OR  :         // or
		((is_R || is_I) && funct3 == 3'b111) ? `AND :         // and
		(is_R && funct7 == 7'b0000001)? `MUL:
		(is_J_JAL||is_J_JALR)? `ADD:
		`ADD; // default，这样平时PC+4也会合理

	//Asrc Bsrc
	always @(*)begin
		case (current_state)
			`IF: ALUSrcA = `afromnewpc;
			`IW: ALUSrcA = `afromnewpc;
			`ID: ALUSrcA = `afromoldpc;
			`EX: begin
				if(is_U_AUIPC || is_J_JAL) ALUSrcA = `afromoldpc;
				else ALUSrcA = `afromrs;
			end
			default: ALUSrcA = `afromrs;
		endcase
	end

	always @(*)begin
		case (current_state)
			`IF: ALUSrcB = `four;
			`IW: ALUSrcB = `four;
			`ID: ALUSrcB = `onlyext;
			`EX: begin
				if(is_L||is_S||is_I||is_U_AUIPC||is_J_JAL) ALUSrcB = `onlyext;
				else if (is_R||is_B) ALUSrcB = `RDATA;
				else ALUSrcB = `onlyext ;
			end
			default: ALUSrcB = `RDATA;
		endcase
	end

	assign eq = Zero;
	assign lt = Result[0];	//符号小于
	assign ltu = Result[0];	//无符号小于
	
	assign branch_taken = 
		(funct3 == 3'b000) ? eq  :       // BEQ
		(funct3 == 3'b001) ? !eq :       // BNE
		(funct3 == 3'b100) ? lt  :       // BLT
		(funct3 == 3'b101) ? !lt :       // BGE
		(funct3 == 3'b110) ? ltu :       // BLTU
		(funct3 == 3'b111) ? !ltu :      // BGEU
		1'b0;

	always @(*)begin
		case (current_state)
			`IW: PCWrite = Inst_Valid; 
			`EX:
				if(is_J_JAL||is_J_JALR) PCWrite = 1;
				else if (is_B) PCWrite = branch_taken;
				else PCWrite = 0;
			default: PCWrite = 0;
		endcase
	end

	//3.4 IorD
	always @(*)begin
		case(current_state)
			`IF, `IW, `TRAP: IorD = `frompc; // TRAP 时防止访存错乱
			default: IorD = `fromaluout;
		endcase
	end

	//3.5 MemRead Memtoreg Memwrite
	assign MemWrite = (current_state == `ST) && (is_S);
	assign MemRead  = ((current_state == `LD) && (is_L)); 
	assign MemtoReg = is_L;

	//3.6 IRWrite
	assign IRWrite = (current_state == `IF);

	//3.7 PCSource
	assign PCSource = (current_state == `IF ||is_J_JAL||current_state == `IW)? `pcfromresult : `pcfromaluout;


	// 4、各个部件
	//4.1 instruction register
	always @(posedge clk)begin
		if (rst == 1'b1) begin
			Ins <= 32'h00000013; //NOP
		end
		else if  ((current_state == `IW) && (Inst_Valid))begin
			Ins <= Instruction;
		end
	end

	// 4.2 data register
	assign RF_wen   = RegWrite;
	assign RF_waddr = rd;
	
	assign Write_data = 
		(funct3 == 3'b000) ? ( {24'b0, rdata2[7:0]}  << shift_bits ) : 
		(funct3 == 3'b001) ? ( {16'b0, rdata2[15:0]} << shift_bits ) : 
		rdata2;                                                                         

	assign Write_strb = 
		(~is_S) ? 4'b0000 :
		(funct3 == 3'b010) ? 4'b1111 :                               
		(funct3 == 3'b001) ? (byte_offset[1] ? 4'b1100 : 4'b0011) :  
		(funct3 == 3'b000) ? (4'b0001 << byte_offset) :              
		4'b0000;

	// 读取格式化，处理小端序
	assign byte_read =
		(byte_offset == 2'b00) ? memory_data_register[7:0] :
		(byte_offset == 2'b01) ? memory_data_register[15:8] :
		(byte_offset == 2'b10) ? memory_data_register[23:16] :
		memory_data_register[31:24];

	assign half_read =
		(byte_offset[1] == 1'b0) ? memory_data_register[15:0] :	
		memory_data_register[31:16];
	
	assign load_data =
		(funct3 == 3'b000) ? {{24{byte_read[7]}}, byte_read} :       
		(funct3 == 3'b100) ? {24'b0, byte_read} :                    
		(funct3 == 3'b001) ? {{16{half_read[15]}}, half_read} :      
		(funct3 == 3'b101) ? {16'b0, half_read} :                    
		memory_data_register;                                                   

	// 写回寄存器数据选择 
	assign is_shift = (is_I && (funct3 == 3'b001 || funct3 == 3'b101)) ||
                  (is_R && (funct3 == 3'b001 || funct3 == 3'b101) && (funct7 == 7'b0000000 || funct7 == 7'b0100000));

	assign RF_wdata = 
		(is_U_LUI) ? imm_U :                                 
		(is_J_JAL || is_J_JALR) ? next_pc_4 :                   
		(is_L) ? load_data :                                 
		is_shift ? shift_result :                            
		is_CSRRW ? csr_rdata : // 【修改点5】：支持读出 CSR 到目的寄存器rd                      
		ALUout;                                              

	reg_file Reg_file(
		.clk(clk),
		.waddr(RF_waddr),
		.raddr1(rs1),
		.raddr2(rs2),
		.wen(RF_wen),
		.rdata1(rdata1),
		.rdata2(rdata2),
		.wdata(RF_wdata)
	);

	//4.3 memory
	assign shift_bits = {byte_offset, 3'b000}; 
	assign byte_offset = ALUout[1:0];	
	assign Address  = (IorD==`frompc)?new_PC:{ALUout[31:2], 2'b00};

	always @(posedge clk)begin
		if ((current_state == `RDW) && (Read_data_Valid))begin
			memory_data_register <= Read_data;
		end
	end

	// 4.4 ALU 控制与实例化
	assign A = (ALUSrcA == `afromnewpc) ? new_PC : 
		(ALUSrcA == `afromoldpc)? old_pc:
		rdata1;
	
	assign B = (ALUSrcB == `RDATA)? rdata2:
		   (ALUSrcB == `onlyext)? imm :
		   (ALUSrcB == `four)? 4:0;

	alu my_alu(
		.A(A),
		.B(B),
		.ALUop(ALUop),
		.Overflow(Overflow),
		.CarryOut(CarryOut),
		.Zero(Zero),
		.Result(Result)
	);

	always @(posedge clk) begin
		if (current_state == `ID || current_state == `EX) begin
			ALUout <= Result;
		end
	end

	// 4.5 Shifter 实例化 
	assign Shiftop = (funct3 == 3'b001) ? `left_shift : 
	                 (funct3 == 3'b101 && Ins[30] == 1'b1) ? `ari_right : 
	                 (funct3 == 3'b101 && Ins[30] == 1'b0) ? `logic_right : `nothing;
	assign shift_A = rdata1;
	assign shift_B = is_R ? rdata2[4:0] : rs2;

	shifter real_shifter(
		.A(shift_A),
		.B(shift_B),
		.Shiftop(Shiftop),
		.Result(shift_result)
	);

	// 4.6 PC 更新逻辑
	assign jalr_target= (Result) & ~32'b1; 

	assign next_PC = (PCSource == `pcfromresult)?Result:
			  (is_J_JALR==1)?jalr_target:
			  ALUout;

	// 【修改点6】：融入 TRAP 和 MRET 的强制跳址逻辑
	always @(posedge clk) begin
		if (rst == 1'b1) begin
			new_PC <= 32'h00000000;
		end else begin
			if (current_state == `TRAP) begin
				new_PC <= mtvec;        // 进入中断处理程序
			end else if (is_MRET && current_state == `EX) begin
				new_PC <= mepc;         // 从中断返回原程序
			end else if(PCWrite == 1) begin
				new_PC <= next_PC;      // 正常流程与跳转
			end
		end
	end

	always @(posedge clk)begin
		if (current_state ==`ID)begin
			next_pc_4 <= new_PC;
		end
	end

	always @(posedge clk)begin
		if ((current_state == `IF) && (Inst_Req_Ready))begin	
			old_pc <= new_PC;
		end
	end
	
	assign inst_retire = {RegWrite,RF_waddr,RF_wdata,old_pc};

	assign PC = (current_state == `IF) ? new_PC : old_pc;

endmodule
