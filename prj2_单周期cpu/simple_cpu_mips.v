`timescale 10ns / 1ns
`define sign 1
`define logic 0
`define nothing 2'b00
`define DATA_WIDTH 32
`define ADD 3'b010
`define SUB 3'b110
`define AND 3'b000
`define OR 3'b001
`define SLT 3'b111
`define XOR 3'b100
`define NOR  3'b101
`define SLTU 3'b011
`define left_shift 2'b00
`define ari_right 2'b11
`define logic_right 2'b10
`define IF 3'b000
`define ID 3'b001
`define EX 3'b010
`define MEM 3'b011
`define WB 3'b100
`define RDATA 2'b00
`define four 2'b01
`define onlyext 2'b10
// 不存在，是RISCV，里面的<<2 都自动在imm里面做了`define extandshift 2'b11
`define frompc 1
`define fromaluout 0
`define pcfromaluout 1
`define pcfromresult 0
`define afromoldpc 2'b01
`define afromnewpc  2'b10
`define afromrs 2'b00
module simple_cpu(
	input             clk,
	input             rst,

	output reg [31:0] PC,
	input  [31:0]     Instruction,

	output [31:0]     Address,
	output            MemWrite,
	output [31:0]     Write_data,
	output [ 3:0]     Write_strb, 

	input  [31:0]     Read_data,
	output            MemRead
);

wire			RF_wen;
	wire [4:0]		RF_waddr;
	wire[31:0]		RF_wdata;

	reg [31:0] Ins;
	
	

	

	wire [31:0] imm;
	reg PCWrite;
	reg IorD;
	wire MemtoReg;
	wire IRWrite;
	wire PCSource;
	wire [2:0] ALUop;
	reg [1:0]ALUSrcB;
	reg [1:0]ALUSrcA;
	wire RegWrite;
	wire eq ; 
	wire lt  ;
	wire ltu  ;
	wire branch_taken;

	wire [31:0] rdata1;
	wire[31:0] rdata2;
	wire [31:0] next_PC;
	wire [31:0] jalr_target ; 
	//center
	reg [31:0]memory_data_register;
	wire [4:0] shift_bits ;
	wire [1:0] byte_offset ;
	wire [              1:0] Shiftop;
	wire[`DATA_WIDTH - 1:0] shift_A;
	wire [              4:0] shift_B;
	wire [`DATA_WIDTH - 1:0] shift_result;
	reg [31:0]ALUout;
	wire[`DATA_WIDTH - 1:0] A;
	wire [`DATA_WIDTH - 1:0] B;
	
	wire                     Overflow;
	wire                     CarryOut;
	wire                     Zero;
	wire [`DATA_WIDTH - 1:0] Result;
	wire is_shift ;
	wire [7:0] byte_read ;
	

	wire [15:0] half_read ;
	wire[31:0] load_data ;
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

	// 立即数扩展信号
	wire [31:0] imm_I;
	wire [31:0] imm_S;
	wire [31:0] imm_B;
	wire [31:0] imm_U;
	wire [31:0] imm_J;
	
	//状态机

	reg [3:0] current_state;


	// next_pc_4
	reg [31:0] next_pc_4;
	reg [31:0] old_pc;

	always @(posedge clk ) begin
    if (rst) begin
        
        current_state <= `IF;
    end 
    else begin
        case (current_state)
            `IF: begin
                current_state <= `ID;
            end
            
            `ID: begin
                current_state <= `EX;
            end
            
            `EX: begin
                
                if (is_L || is_S) begin
                    current_state <= `MEM;
                end
                
                else if (is_R || is_I || is_U_AUIPC || is_U_LUI || is_J_JAL || is_J_JALR) begin
                    current_state <= `WB;
                end
                
                else if (is_B) begin
                    current_state <= `IF;
                end
                else begin
                    current_state <= `IF;
                end
            end
            
            `MEM: begin
               
                if (is_L) begin
                    current_state <= `WB;
                end
                
                else begin 
                    current_state <= `IF;
                end
            end
            
            `WB: begin
                
                current_state <= `IF;
            end
            default: begin
                current_state <= `IF;
            end
        endcase
    end
end

	
	
	
	//2.译码
	
	


	// 一、 指令类型解码赋值
	assign opcode =Ins [6:0];
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

	// 二、 立即数生成（符号扩展）
	assign imm_I = {{20{Ins[31]}}, Ins[31:20]};
	assign imm_S = {{20{Ins[31]}}, Ins[31:25], Ins[11:7]};
	assign imm_B = {{20{Ins[31]}}, Ins[7], Ins[30:25], Ins[11:8], 1'b0};
	assign imm_U = {Ins[31:12], 12'b0};
	assign imm_J = {{12{Ins[31]}}, Ins[19:12], Ins[20], Ins[30:21], 1'b0};

	assign imm = ((is_I || is_L || is_J_JALR) ) ? imm_I :
             is_S                          ? imm_S :
             is_B                         ? imm_B :
             (is_U_LUI || is_U_AUIPC)    ? imm_U :
             is_J_JAL                           ? imm_J : 32'b0;


	//3.控制引脚
	//wire PCWRITECond;
	

	// 根本没有wire RegDst，全是rd
	//3.1 regwrite
	assign RegWrite = (current_state == `WB)&&(!is_B);
	//3.2 ALU
	// ALU 操作码映射 (RISC-V 严格按照 funct3 来定义类型)
	assign ALUop = 
		(current_state == `IF)? `ADD:
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
		(is_J_JAL||is_J_JALR)? `ADD:
		`ADD; // default，这样平时PC+4也会合理

	//Asrc Bsrc
	always @(*)begin
		case (current_state)
			`IF:begin
				ALUSrcA = `afromnewpc;
			end
			`ID:begin
				ALUSrcA = `afromoldpc;
			end
			`EX: begin
				if(is_U_AUIPC || is_J_JAL)begin
					ALUSrcA = `afromoldpc;
				end
				else begin
					ALUSrcA = `afromrs;
				end
			end
			default:
				ALUSrcA = `afromrs;

		endcase
	end
	always @(*)begin
		case (current_state)
			`IF:begin
				ALUSrcB = `four;
			end
			`ID:begin
				ALUSrcB = `onlyext;
			end
			`EX:begin
				if(is_L||is_S||is_I||is_U_AUIPC||is_J_JAL)begin
					ALUSrcB = `onlyext;
				end
				else if (is_R||is_B)begin	//branch判断需要
					ALUSrcB = `RDATA;
				end
				else begin
					ALUSrcB = `onlyext ;
				end
			end
			default:
				begin
					ALUSrcB = `RDATA;
				end

			
		endcase
	end

	//3.3wire PCWrite;
	
	assign eq = Zero;


	
	assign lt= Result[0];	//符号小于


	
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
			`IF:
				PCWrite = 1;
			`EX:
				if(is_J_JAL||is_J_JALR)begin
					PCWrite =1;
				end
				else if (is_B)begin
					PCWrite = branch_taken;
				end
				else begin
					PCWrite = 0;
				end
			default:
					PCWrite = 0;
		endcase
	end
	//3.4 IorD
	always @(*)begin
		case(current_state)
			`IF:
				IorD = `frompc;
			default:
				IorD = `fromaluout;
		endcase
	end
	//3.5MemRead Memtoreg emwrite
	assign MemWrite = (current_state == `MEM) && (is_S);
	assign MemRead = ((current_state == `MEM) && (is_L )) ;// 错误的|| (current_state == `IF);
	assign Memtoreg = is_L;
	//3.6 IRWrite
	assign IRWrite = (current_state == `IF) ;
	//3.7wire PCSource;
	assign PCSource = (current_state == `IF ||is_J_JAL)? `pcfromresult :
						`pcfromaluout;




	// 4、各个部件
	//4.1 instruction register
	always @(posedge clk)begin
		if (rst == 1'b1) begin
			Ins <= 32'h00000013;
		end
		else if (current_state == `IF)begin
			Ins <= Instruction;
		end
	end


	// 4.2 data register
	
	
	assign RF_wen   = RegWrite;
	assign RF_waddr = rd;
	
	
	
	

	

	assign Write_data = 
		(funct3 == 3'b000) ? ( {24'b0, rdata2[7:0]}  << shift_bits ) : // SB: 取低8位，并移位
		(funct3 == 3'b001) ? ( {16'b0, rdata2[15:0]} << shift_bits ) : // SH: 取低16位，并移位
		rdata2;                                                        // SW: 原样输出                 


	assign Write_strb = 
		(~is_S) ? 4'b0000 :
		(funct3 == 3'b010) ? 4'b1111 :                               // SW
		(funct3 == 3'b001) ? (byte_offset[1] ? 4'b1100 : 4'b0011) :  // SH
		(funct3 == 3'b000) ? (4'b0001 << byte_offset) :              // SB
		4'b0000;

	// 读取格式化，处理小端序
	
	assign byte_read =
		(byte_offset == 2'b00) ? memory_data_register[7:0] :
		(byte_offset == 2'b01) ? memory_data_register[15:8] :
		(byte_offset == 2'b10) ? memory_data_register[23:16] :
		memory_data_register[31:24];
	assign half_read =
		(byte_offset[1] == 1'b0) ? memory_data_register[15:0] :	//看是10还是00
		memory_data_register[31:16];

	
	assign load_data =
		(funct3 == 3'b000) ? {{24{byte_read[7]}}, byte_read} :       // LB
		(funct3 == 3'b100) ? {24'b0, byte_read} :                    // LBU
		(funct3 == 3'b001) ? {{16{half_read[15]}}, half_read} :      // LH
		(funct3 == 3'b101) ? {16'b0, half_read} :                    // LHU
		memory_data_register;                                                   // LW

	// 写回寄存器数据选择 
	
	assign is_shift = (is_R || is_I) && (funct3 == 3'b001 || funct3 == 3'b101);	//来自于shifter的数据

	assign RF_wdata = 
		(is_U_LUI) ? imm_U :                                 // LUI
		(is_J_JAL || is_J_JALR) ? next_pc_4 :                   // JAL, JALR，写入PC+4（这个时候的PC已经更新了）
		(is_L) ? load_data :                                 // 从内存来的数据，load
		is_shift ? shift_result :                            // SLL/SRL/SRA，从shifter来的
		ALUout;                                              // 常规算术、逻辑运算及 AUIPC 计算(PC+imm)
	//memory data register

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
	assign shift_bits = {byte_offset, 3'b000}; //移位
	assign byte_offset = ALUout[1:0];	//低两位
	assign Address  = (IorD==`frompc)?PC:{ALUout[31:2], 2'b00};


	always @(posedge clk)begin
		if (MemRead)begin
			memory_data_register <= Read_data;
		end

	end



	// 4.4ALU 控制与实例化
	

	// AUIPC 使用 PC 作为 A 端操作数（将高位立即数加到程序计数器（PC）上），其余均使用 rdata1(地址计算跳转和ALU是独立的)
	assign A = (ALUSrcA == `afromnewpc) ? PC : 
		(ALUSrcA == `afromoldpc)? old_pc:
		rdata1;
	// 算术R型和分支使用 rdata2 进行运算/比较，其余大部分使用立刻数
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
    // 只有在 ID 和 EX 阶段才需要更新 ALUout
    // 这样它在 MEM 和 WB 阶段，aluout里面才不会被错误的值更新
    if (current_state == `ID || current_state == `EX) begin
        ALUout <= Result;
    end
end





	// 4.5Shifter 实例化 
	

	// RISC-V 中 funct3 决定移位方向，Instruction[30] 决定逻辑/算术
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

	
	
	

	// 4.6PC 更新逻辑
	 
	assign jalr_target= (Result) & ~32'b1; // JALR 需要把最低位清零，并且在执行阶段的最后一拍就跳转，说明这个时候应该直接把Result当做地址


	assign next_PC = (PCSource == `pcfromresult)?Result:
			  (is_J_JALR==1)?jalr_target:
			  ALUout;

	always @(posedge clk) begin
		if (rst == 1'b1) begin
			PC <= 32'h00000000;
		end else begin
			if(PCWrite==1)begin
				PC<=next_PC;
			end
		end
	end
	//因为Jal/jalr更新了PC之后才存入，所以PC+4应该在算好之后就存入
	always @(posedge clk)begin
		if (current_state ==`ID)begin
			next_pc_4 <=PC;
		end

	end
	// 因为还要根据当前地址进行计算呢，所以要存起来
	always @(posedge clk)begin
		if (current_state == `IF)begin
			old_pc <= PC;
		end

	end
	/*
	always @(*)begin
	$display("PC=%h ins=%h imm_B=%h imm=%h", PC, Ins,imm_B,imm);
	// 假设这里是你执行比较的地方
if (opcode == 7'b1100011) begin // 如果是 Branch 指令
	
    $display("Branch Check at PC=%x: rs1_val=%x, rs2_val=%x", PC, rdata1, rdata2);
end
	end
	always @(posedge clk) begin
    if(RegWrite == 1)begin
        $display("RegWrite: x%0d = %x", rd, RF_wdata);
    end

end
*/
endmodule
