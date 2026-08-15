`timescale 10ns / 1ns

`define CACHE_SET	8
`define CACHE_WAY	4
`define TAG_LEN		24
`define LINE_LEN	256

module dcache_top (
	input	      clk,
	input	      rst,
  
	//CPU interface
	input         from_cpu_mem_req_valid,
	input         from_cpu_mem_req, // 0: read, 1: write
	input  [31:0] from_cpu_mem_req_addr,
	input  [31:0] from_cpu_mem_req_wdata,
	input  [ 3:0] from_cpu_mem_req_wstrb,
	output        to_cpu_mem_req_ready,
		
	output        to_cpu_cache_rsp_valid,
	output [31:0] to_cpu_cache_rsp_data,
	input         from_cpu_cache_rsp_ready,
		
	//Memory/IO read interface
	output        to_mem_rd_req_valid,
	output [31:0] to_mem_rd_req_addr,
	output [ 7:0] to_mem_rd_req_len,
	input	      from_mem_rd_req_ready,

	input	      from_mem_rd_rsp_valid,
	input  [31:0] from_mem_rd_rsp_data,
	input	      from_mem_rd_rsp_last,
	output        to_mem_rd_rsp_ready,

	//Memory/IO write interface
	output        to_mem_wr_req_valid,
	output [31:0] to_mem_wr_req_addr,
	output [ 7:0] to_mem_wr_req_len,
	input         from_mem_wr_req_ready,

	output        to_mem_wr_data_valid,
	output [31:0] to_mem_wr_data,
	output [ 3:0] to_mem_wr_data_strb,
	output        to_mem_wr_data_last,
	input	      from_mem_wr_data_ready
);

	
	// 1. 请求信号锁存与解析 
	
	reg [31:0] req_addr_latch;  //地址锁存
	reg        req_op_latch;     // 读写标志0: read, 1: write
	reg [31:0] req_wdata_latch; //写入数据
	reg [ 3:0] req_wstrb_latch; //写入掩码

	always @(posedge clk) begin
		if (rst) begin
			req_addr_latch  <= 32'b0;
			req_op_latch    <= 1'b0;
			req_wdata_latch <= 32'b0;
			req_wstrb_latch <= 4'b0;
		end else if (state == IDLE && from_cpu_mem_req_valid) begin
			// IDLE且ccpu发出请求，锁存所有的请求信息
			req_addr_latch  <= from_cpu_mem_req_addr;
			req_op_latch    <= from_cpu_mem_req;
			req_wdata_latch <= from_cpu_mem_req_wdata;
			req_wstrb_latch <= from_cpu_mem_req_wstrb;
		end
	end

	
	wire [4:0]  req_offset   = req_addr_latch[4:0];
	wire [2:0]  req_index    = req_addr_latch[7:5];
	wire [23:0] req_tag      = req_addr_latch[31:8]; 
	wire [2:0]  req_word_idx = req_offset[4:2]; // 包含 8 个字，32个字节

	// 旁路判断：0x00~0x1F 或 >= 0x4000_0000 (使用锁存地址)
	wire is_bypass = (req_addr_latch < 32'h0000_0020) || (req_addr_latch >= 32'h4000_0000);

	
	// 2. Cache 存储阵列定义
	
	reg         valid_array [0:`CACHE_SET-1][0:`CACHE_WAY-1];
	reg         dirty_array [0:`CACHE_SET-1][0:`CACHE_WAY-1];
	reg  [23:0] tag_array   [0:`CACHE_SET-1][0:`CACHE_WAY-1];
	reg  [31:0] data_array  [0:`CACHE_SET-1][0:`CACHE_WAY-1][0:7];

	reg  [1:0] replace_cnt [0:`CACHE_SET-1];
	wire [1:0] evict_way = replace_cnt[req_index];

	
	// 3. 命中逻辑判断 (组合逻辑)
	
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
	
	localparam IDLE         = 4'd0;
	localparam COMPARE      = 4'd1;  
	localparam EVICT_REQ    = 4'd2;  
	localparam EVICT_DATA   = 4'd3;  
	localparam REFILL_REQ   = 4'd4;  
	localparam REFILL_DATA  = 4'd5;  
	localparam BYPASS_RREQ  = 4'd6;  
	localparam BYPASS_RDAT  = 4'd7;  
	localparam BYPASS_WREQ  = 4'd8;  
	localparam BYPASS_WDAT  = 4'd9;  
	localparam RESP         = 4'd10; 

	reg [3:0] state, next_state;
	reg [2:0] burst_cnt;
	reg [31:0] bypass_rdata_reg;

	always @(posedge clk) begin
		if (rst) state <= IDLE;
		else state <= next_state;
	end

	always @(*) begin
		next_state = state;
		case (state)
			IDLE: begin
				if (from_cpu_mem_req_valid) next_state = COMPARE;
			end
			COMPARE: begin
				if (is_bypass) begin
					// 使用锁存的读写请求类型
					next_state = req_op_latch ? BYPASS_WREQ : BYPASS_RREQ;
				end else if (cache_hit) begin
					next_state = RESP;
				end else begin
					if (valid_array[req_index][evict_way] && dirty_array[req_index][evict_way])
						next_state = EVICT_REQ;
					else
						next_state = REFILL_REQ;
				end
			end
			EVICT_REQ: begin
				if (from_mem_wr_req_ready) next_state = EVICT_DATA;
			end
			EVICT_DATA: begin
				if (from_mem_wr_data_ready && burst_cnt == 3'd7) next_state = REFILL_REQ;
			end
			REFILL_REQ: begin
				if (from_mem_rd_req_ready) next_state = REFILL_DATA;
			end
			REFILL_DATA: begin
				if (from_mem_rd_rsp_valid && from_mem_rd_rsp_last) next_state = COMPARE; 
			end
			BYPASS_RREQ: begin
				if (from_mem_rd_req_ready) next_state = BYPASS_RDAT;
			end
			BYPASS_RDAT: begin
				if (from_mem_rd_rsp_valid) next_state = RESP;
			end
			BYPASS_WREQ: begin
				if (from_mem_wr_req_ready) next_state = BYPASS_WDAT;
			end
			BYPASS_WDAT: begin
				if (from_mem_wr_data_ready) next_state = RESP;
			end
			RESP: begin
				// 读请求等ready，写请求直接结束
				if (from_cpu_cache_rsp_ready || req_op_latch) 
					next_state = IDLE;
			end
			default: next_state = IDLE;
		endcase
	end

	
	// 5. 数据通路与内部状态控制
	
	integer i, j;
	always @(posedge clk) begin
		if (rst) begin
			burst_cnt <= 3'd0;
			for (i = 0; i < `CACHE_SET; i = i + 1) begin
				replace_cnt[i] <= 2'd0;
				for (j = 0; j < `CACHE_WAY; j = j + 1) begin
					valid_array[i][j] <= 1'b0;
					dirty_array[i][j] <= 1'b0;
				end
			end
		end else begin
			case (state)
				IDLE: begin
					burst_cnt <= 3'd0;
				end
				COMPARE: begin
					
					// Write Hit：修改 Cache 内的数据并标记 Dirty (使用锁存的写数据和写掩码)
					if (!is_bypass && cache_hit && req_op_latch) begin
						if (req_wstrb_latch[0]) data_array[req_index][hit_way][req_word_idx][7:0]   <= req_wdata_latch[7:0];
						if (req_wstrb_latch[1]) data_array[req_index][hit_way][req_word_idx][15:8]  <= req_wdata_latch[15:8];
						if (req_wstrb_latch[2]) data_array[req_index][hit_way][req_word_idx][23:16] <= req_wdata_latch[23:16];
						if (req_wstrb_latch[3]) data_array[req_index][hit_way][req_word_idx][31:24] <= req_wdata_latch[31:24];
						dirty_array[req_index][hit_way] <= 1'b1;
					end
				end
				EVICT_DATA: begin
					if (from_mem_wr_data_ready) begin
						burst_cnt <= burst_cnt + 1'b1;
					end
				end
				REFILL_DATA: begin
					if (from_mem_rd_rsp_valid) begin
						data_array[req_index][evict_way][burst_cnt] <= from_mem_rd_rsp_data;
						burst_cnt <= burst_cnt + 1'b1;
						if (from_mem_rd_rsp_last) begin
							valid_array[req_index][evict_way] <= 1'b1;
							tag_array[req_index][evict_way]   <= req_tag; //下一轮直接命中
							dirty_array[req_index][evict_way] <= 1'b0; //从未被cpu修改过，是新数据
							
							replace_cnt[req_index] <= replace_cnt[req_index] + 1'b1;
					
						end
					end
				end
				BYPASS_RDAT: begin
					if (from_mem_rd_rsp_valid) bypass_rdata_reg <= from_mem_rd_rsp_data; 
				end
				default:begin

				end
			endcase
		end
	end

	// ---------------------------------------------------------
	// 6. 接口驱动输出
	// ---------------------------------------------------------
	// CPU Interface
	assign to_cpu_mem_req_ready   = (state == IDLE);
	assign to_cpu_cache_rsp_valid = (state == RESP);
	assign to_cpu_cache_rsp_data  = is_bypass ? bypass_rdata_reg : data_array[req_index][hit_way][req_word_idx];

	// Memory Read Interface
	assign to_mem_rd_req_valid = (state == REFILL_REQ) || (state == BYPASS_RREQ);
	assign to_mem_rd_req_addr  = (state == BYPASS_RREQ) ? req_addr_latch : {req_addr_latch[31:5], 5'b0}; // 32B对齐
	assign to_mem_rd_req_len   = (state == BYPASS_RREQ) ? 8'd0 : 8'd7;
	assign to_mem_rd_rsp_ready = (state == REFILL_DATA) || (state == BYPASS_RDAT);  //准备接受主存的数据了

	// Memory Write Interface
	assign to_mem_wr_req_valid = (state == EVICT_REQ) || (state == BYPASS_WREQ); //给主存的数据是有效的
	// 回写时，写地址是原Cache块的tag+index拼接；旁路写时直接使用锁存地址
	assign to_mem_wr_req_addr  = (state == BYPASS_WREQ) ? req_addr_latch : {tag_array[req_index][evict_way], req_index, 5'b0};
	assign to_mem_wr_req_len   = (state == BYPASS_WREQ) ? 8'd0 : 8'd7;

	assign to_mem_wr_data_valid= (state == EVICT_DATA) || (state == BYPASS_WDAT);
	assign to_mem_wr_data      = (state == BYPASS_WDAT) ? req_wdata_latch : data_array[req_index][evict_way][burst_cnt];
	assign to_mem_wr_data_strb = (state == BYPASS_WDAT) ? req_wstrb_latch : 4'b1111; //cache对主存是整片修改
	assign to_mem_wr_data_last = (state == BYPASS_WDAT) ? 1'b1 : (burst_cnt == 3'd7);

endmodule
