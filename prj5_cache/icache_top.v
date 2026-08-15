`timescale 10ns / 1ns

`define CACHE_SET	8
`define CACHE_WAY	4
`define TAG_LEN		24
`define LINE_LEN	256

module icache_top (
	input	      clk,
	input	      rst,
	
	//CPU interface
	input         from_cpu_inst_req_valid,
	input  [31:0] from_cpu_inst_req_addr,
	output        to_cpu_inst_req_ready,
	
	output        to_cpu_cache_rsp_valid,
	output [31:0] to_cpu_cache_rsp_data,
	input	      from_cpu_cache_rsp_ready,

	//Memory interface (32 byte aligned address)
	output        to_mem_rd_req_valid,
	output [31:0] to_mem_rd_req_addr,
	input         from_mem_rd_req_ready,

	input         from_mem_rd_rsp_valid,
	input  [31:0] from_mem_rd_rsp_data,
	input         from_mem_rd_rsp_last,
	output        to_mem_rd_rsp_ready
);

	
	// 1. 地址锁存与解析
	
	reg [31:0] req_addr_latch;
	
	// cache空闲并且此时cpu的请求有效，那么立即将地址锁存
	always @(posedge clk) begin
		if (rst) 
			req_addr_latch <= 32'b0; 
		else if (state == IDLE && from_cpu_inst_req_valid) 
			req_addr_latch <= from_cpu_inst_req_addr;
	end

	// 解析地址
	wire [4:0]  req_offset   = req_addr_latch[4:0];	
	wire [2:0]  req_index    = req_addr_latch[7:5];	//8个组的哪一个
	wire [23:0] req_tag      = req_addr_latch[31:8]; //和对应的值进行比较，代表命中成功 
	wire [2:0]  req_word_idx = req_offset[4:2];  //8个字中哪一个字

	
	// 2. Cache 存储阵列定义:不用dirty,因为只读
	
	reg         valid_array [0:`CACHE_SET-1][0:`CACHE_WAY-1];
	reg  [23:0] tag_array   [0:`CACHE_SET-1][0:`CACHE_WAY-1];
	// 32 Byte = 8 Words. 按 [Set][Way][Word] 组织
	reg  [31:0] data_array  [0:`CACHE_SET-1][0:`CACHE_WAY-1][0:7];

	// 计数器和对应的应该去处理哪一个道
	reg  [1:0] replace_cnt [0:`CACHE_SET-1];
	wire [1:0] evict_way = replace_cnt[req_index]; 

	
	// 3. 命中逻辑判断：tag对应的是对的，并且其有效
	
	wire hit_w0 = valid_array[req_index][0] && (tag_array[req_index][0] == req_tag);
	wire hit_w1 = valid_array[req_index][1] && (tag_array[req_index][1] == req_tag);
	wire hit_w2 = valid_array[req_index][2] && (tag_array[req_index][2] == req_tag);
	wire hit_w3 = valid_array[req_index][3] && (tag_array[req_index][3] == req_tag);
	wire cache_hit = hit_w0 | hit_w1 | hit_w2 | hit_w3;

	wire [1:0] hit_way = hit_w0 ? 2'd0 : 
	                     hit_w1 ? 2'd1 : 
	                     hit_w2 ? 2'd2 : 
	                     hit_w3 ? 2'd3 : 2'd0;

	
	// 4. 状态机定义
	
	localparam IDLE         = 3'd0;
	localparam COMPARE      = 3'd1;  // 判断命中
	localparam REFILL_REQ   = 3'd2;  // 重填读请求（从内存）
	localparam REFILL_DATA  = 3'd3;  // 重填数据突发接收（从内存）
	localparam RESP         = 3'd4;  // 给CPU返回指令结果

	reg [2:0] state, next_state;
	reg [2:0] burst_cnt; // 记录突发传输的拍数 (0~7)

	always @(posedge clk) begin
		if (rst) state <= IDLE;
		else state <= next_state;
	end

	always @(*) begin
		next_state = state;
		case (state)
			IDLE: begin
				if (from_cpu_inst_req_valid) next_state = COMPARE; //cpu传来信号
			end
			COMPARE: begin
				if (cache_hit) next_state = RESP; //直接写回
				else next_state = REFILL_REQ; // Miss重填
			end
			REFILL_REQ: begin
				if (from_mem_rd_req_ready) next_state = REFILL_DATA; //发出信号了，准备接受
			end
			REFILL_DATA: begin
				if (from_mem_rd_rsp_valid && from_mem_rd_rsp_last) next_state = COMPARE; 
				//回来的数据有效，并且是8拍中的最后一拍
			end
			RESP: begin
				if (from_cpu_cache_rsp_ready) next_state = IDLE;
				//cpu已经能够接受数据，空闲了
			end
			default: next_state = IDLE;
		endcase
	end

	
	// 5. 数据通路与内部状态控制
	
	integer i, j;
	always @(posedge clk) begin
		if (rst) begin //全部清零啦
			burst_cnt <= 3'd0;
			for (i = 0; i < `CACHE_SET; i = i + 1) begin
				replace_cnt[i] <= 2'd0;
				for (j = 0; j < `CACHE_WAY; j = j + 1) begin
					valid_array[i][j] <= 1'b0;
				end
			end
		end else begin
			case (state)
				COMPARE: begin
					// 在判断出Miss并准备向cpu发请求时，直接更新对应组的轮询指针，直接在这一组中递增到下一way
					if (!cache_hit) replace_cnt[req_index] <= replace_cnt[req_index] + 1'b1;
				end
				REFILL_DATA: begin
					if (from_mem_rd_rsp_valid) begin
						// 将内存发来的数据写入 Cache Array
						data_array[req_index][evict_way][burst_cnt] <= from_mem_rd_rsp_data;
						burst_cnt <= burst_cnt + 1'b1; //下一个数据
						
						if (from_mem_rd_rsp_last) begin //最后一个数据了
							valid_array[req_index][evict_way] <= 1'b1; //数据有效
							tag_array[req_index][evict_way]   <= req_tag; //tag设置，这样下一步就可以进入compare命中
						end
					end
				end
				default:begin


				end
				
			endcase
		end
	end

	
	// 6.接口驱动
	
	// CPU 
	assign to_cpu_inst_req_ready  = (state == IDLE); //cache可以处理cpu的指令
	assign to_cpu_cache_rsp_valid = (state == RESP); //cache准备好数据了
	assign to_cpu_cache_rsp_data  = data_array[req_index][hit_way][req_word_idx]; //对应的数据

	// Memory Read
	assign to_mem_rd_req_valid = (state == REFILL_REQ); //请求数据时
	assign to_mem_rd_req_addr  = {req_addr_latch[31:5], 5'b0}; // 使用锁存后的地址,并且32位对齐
	assign to_mem_rd_rsp_ready = (state == REFILL_DATA); //准备填充数据了

endmodule
