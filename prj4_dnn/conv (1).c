#include "printf.h"
#include "trap.h"
#include "mul.h"
#include "div.h"
#include <stdlib.h>
#include "perf_cnt.h"
#define FRAC_BIT 10

#define RD_ADDR 135106448
#define RD_SIZE_D0 1
#define RD_SIZE_D1 1
#define RD_SIZE_D2 28
#define RD_SIZE_D3 28

#define WEIGHT_ADDR 134217728
#define WEIGHT_SIZE_D0 20
#define WEIGHT_SIZE_D1 1
#define WEIGHT_SIZE_D2 5
#define WEIGHT_SIZE_D3 5

#define WR_ADDR 135108240
#define WR_SIZE_D0 1
#define WR_SIZE_D1 20
#define WR_SIZE_D2 12
#define WR_SIZE_D3 12

#define KERN_ATTR_CONV_PAD 0
#define KERN_ATTR_CONV_STRIDE 1
#define KERN_ATTR_POOL_PAD 0
#define KERN_ATTR_POOL_KERN_SIZE 2
#define KERN_ATTR_POOL_STRIDE 2

//MMIO register address of DNN accelerator
#define GPIO_START_ADDR    0x60030000
#define GPIO_DONE_ADDR     0x60030008

struct size_vec4
{
	unsigned d0;
	unsigned d1;
	unsigned d2;
	unsigned d3;
};

struct mem_addr
{
	unsigned rd_addr;
	unsigned weight_addr;
	unsigned wr_addr;
};

int mul(short a, short b)
{
#ifndef USE_MUL
	int ans = mul_ll(a, b);
#else
	int ans = a * b;
#endif
	return ans;
}

struct mem_addr addr = {RD_ADDR, WEIGHT_ADDR, WR_ADDR};
struct size_vec4 rd_size = {RD_SIZE_D0, RD_SIZE_D1, RD_SIZE_D2, RD_SIZE_D3};
struct size_vec4 wr_size = {WR_SIZE_D0, WR_SIZE_D1, WR_SIZE_D2, WR_SIZE_D3};
struct size_vec4 weight_size = {WEIGHT_SIZE_D0, WEIGHT_SIZE_D1, WEIGHT_SIZE_D2, WEIGHT_SIZE_D3};

struct size_vec4 conv_size;

extern char _binary_data_result_bin_start[];
extern char _binary_data_result_bin_size[];

/*
void convolution()
{
    short *in = (short *)addr.rd_addr;
    short *weight_base = (short *)addr.weight_addr;
    short *out = (short *)addr.wr_addr;

    unsigned input_fm_w = rd_size.d3;
    unsigned input_fm_h = rd_size.d2;

    unsigned pad = KERN_ATTR_CONV_PAD;
    unsigned stride = KERN_ATTR_CONV_STRIDE;

    unsigned Ic = rd_size.d1;
    unsigned Oc = weight_size.d0;
    unsigned Kh = weight_size.d2;
    unsigned Kw = weight_size.d3;

    unsigned conv_out_w = div(input_fm_w + (pad << 1) - Kw, stride) + 1;
    unsigned conv_out_h = div(input_fm_h + (pad << 1) - Kh, stride) + 1;

    conv_size.d0 = wr_size.d0;
    conv_size.d1 = Oc;
    conv_size.d2 = conv_out_h;
    conv_size.d3 = conv_out_w;

    unsigned Oh = conv_size.d2;
    unsigned Ow = conv_size.d3;

    
     * 实验数据布局：
     *
     * weight_base[0 ... Oc*Ic*Kh*Kw - 1] 是卷积权重
     * 后面 Oc 个 short 是 bias
     
    unsigned weight_num = Oc * Ic * Kh * Kw;
    short *bias_base = weight_base + weight_num;

    for (unsigned no = 0; no < Oc; no++)
    {
        for (unsigned y = 0; y < Oh; y++)
        {
            for (unsigned x = 0; x < Ow; x++)
            {
              
                long long sum = ((long long)bias_base[no]) << FRAC_BIT;

                for (unsigned ni = 0; ni < Ic; ni++)
                {
                    for (unsigned ky = 0; ky < Kh; ky++)
                    {
                        for (unsigned kx = 0; kx < Kw; kx++)
                        {
                            int ih = (int)(y * stride + ky) - (int)pad;
                            int iw = (int)(x * stride + kx) - (int)pad;

                            if (ih >= 0 && ih < (int)input_fm_h &&
                                iw >= 0 && iw < (int)input_fm_w)
                            {
                                unsigned in_idx =
                                    ni * input_fm_h * input_fm_w +
                                    ih * input_fm_w +
                                    iw;

                                unsigned weight_idx =
                                    no * Ic * Kh * Kw +
                                    ni * Kh * Kw +
                                    ky * Kw +
                                    kx;

                                sum += mul(in[in_idx], weight_base[weight_idx]);
                            }
                        }
                    }
                }

              
                long long result_64 = sum >> FRAC_BIT;

                if (result_64 > 32767)
                    result_64 = 32767;
                else if (result_64 < -32768)
                    result_64 = -32768;

                unsigned out_idx =
                    no * Oh * Ow +
                    y * Ow +
                    x;

                out[out_idx] = (short)result_64;
            }
        }
    }
}
*/

void convolution() {
    short *in = (short *)addr.rd_addr;       // 输入地址
    short *weight = (short *)addr.weight_addr; // 权重地址（包含bias）
    short *out = (short *)addr.wr_addr;       // 输出地址

    unsigned input_fm_w = rd_size.d3; 
    unsigned input_fm_h = rd_size.d2; 

    unsigned pad = KERN_ATTR_CONV_PAD;
    unsigned pad_len = pad << 1; 

    unsigned conv_out_w = rd_size.d3 - weight_size.d3 + pad_len;
    unsigned conv_out_h = rd_size.d2 - weight_size.d2 + pad_len;

    unsigned stride = KERN_ATTR_CONV_STRIDE;

    conv_out_w = div(conv_out_w, stride);
    conv_out_h = div(conv_out_h, stride);

    conv_out_w++;
    conv_out_h++;

    conv_size.d0 = wr_size.d0;
    conv_size.d1 = wr_size.d1;
    conv_size.d2 = conv_out_h;
    conv_size.d3 = conv_out_w;

    unsigned Oc = conv_size.d1; 
    unsigned Ic = rd_size.d1; 
    unsigned Oh = conv_size.d2; 
    unsigned Ow = conv_size.d3; 
    unsigned Kh = weight_size.d2; 
    unsigned Kw = weight_size.d3;

    // 每个卷积核包含：1个bias + 25个权重 = 26个short元素
   unsigned elements_per_channel = 1 + Kh * Kw;
    unsigned elements_per_kernel = Ic * elements_per_channel;

    // 1. 遍历输出通道
    for (unsigned no = 0; no < Oc; no++) {
        // 取出当前输出通道的 bias
        short bias_val = weight[no * elements_per_kernel];

        for (unsigned y = 0; y < Oh; y++) {
            for (unsigned x = 0; x < Ow; x++) {

                // 将 bias 左移 10 位（FRAC_BIT），使其小数位从 10 位变成 20 位，与乘法结果对齐
                long long sum = ((long long)bias_val) << FRAC_BIT; 

                for (unsigned ni = 0; ni < Ic; ni++) {
                    for (unsigned ky = 0; ky < Kh; ky++) {
                        for (unsigned kx = 0; kx < Kw; kx++) {
                            
                            unsigned iw = kx + x * stride;
                            unsigned ih = ky + y * stride;

                            if ((iw >= pad) && (iw < input_fm_w + pad) &&
                                (ih >= pad) && (ih < input_fm_h + pad)) {
                                
                                unsigned in_w = iw - pad;
                                unsigned in_h = ih - pad;

                                unsigned in_idx = ni * (input_fm_h * input_fm_w) + in_h * input_fm_w + in_w;
                                
                                // 寻址修正：no * elements_per_kernel 定位到当前通道块
                                // + 1 则是跳过开头的 bias 元素，进入权重区域
                                //unsigned weight_idx = no * elements_per_kernel + 1 + ni * (Kh * Kw) + ky * Kw + kx;
                                unsigned weight_idx = no * elements_per_kernel + ni * elements_per_channel + 1 + ky * Kw + kx;
                                sum += mul(in[in_idx], weight[weight_idx]);
                            }
                        }
                    }
                }

                // 四舍五入还原为 10 位小数
               long long result_64 = sum >> FRAC_BIT;

                // 饱和截断
                if (result_64 > 32767) {
                    result_64 = 32767;
                } else if (result_64 < -32768) {
                    result_64 = -32768;
                }

                unsigned out_idx = no * (Oh * Ow) + y * Ow + x;
                out[out_idx] = (short)result_64; 
            }
        }
    }
}


void pooling()
{
    short *out = (short *)addr.wr_addr;

    unsigned Channels = conv_size.d1;

    unsigned input_fm_h = conv_size.d2;
    unsigned input_fm_w = conv_size.d3;

    unsigned Kh = KERN_ATTR_POOL_KERN_SIZE;
    unsigned Kw = KERN_ATTR_POOL_KERN_SIZE;
    unsigned stride = KERN_ATTR_POOL_STRIDE;

    unsigned Ph = div(input_fm_h - Kh, stride) + 1;
    unsigned Pw = div(input_fm_w - Kw, stride) + 1;

    for (unsigned c = 0; c < Channels; c++)
    {
        for (unsigned py = 0; py < Ph; py++)
        {
            for (unsigned px = 0; px < Pw; px++)
            {
                short max_val = -32768;

                for (unsigned ky = 0; ky < Kh; ky++)
                {
                    for (unsigned kx = 0; kx < Kw; kx++)
                    {
                        unsigned ih = py * stride + ky;
                        unsigned iw = px * stride + kx;

                        unsigned in_idx =
                            c * input_fm_h * input_fm_w +
                            ih * input_fm_w +
                            iw;

                        short val = out[in_idx];

                        if (val > max_val)
                            max_val = val;
                    }
                }

                unsigned out_idx =
                    c * Ph * Pw +
                    py * Pw +
                    px;

                out[out_idx] = max_val;
            }
        }
    }
}

/*
#ifdef USE_HW_ACCEL
void launch_hw_accel()
{
    volatile int* gpio_start = (volatile int*)(GPIO_START_ADDR); // 规范强转
    volatile int* gpio_done  = (volatile int*)(GPIO_DONE_ADDR);

    *gpio_start = 1; // 启动加速器

    // 核心修改：只检查第0位是否为1。如果第0位为0（说明没完成），则继续死循环。
    while ((*gpio_done & 0x1) == 0) {
    }

    *gpio_start = 0; // 停止加速器
}
#endif
*/
#ifdef USE_HW_ACCEL
void launch_hw_accel()
{
        volatile int* gpio_start = (void*)(GPIO_START_ADDR);
        volatile int* gpio_done = (void*)(GPIO_DONE_ADDR);

        // ====== TODO: Hardware Acceleration Start ======
        
        // 1. 向 START 地址写入 1，向硬件发出启动脉冲/信号
        *gpio_start = 1;

        // 2. 轮询（Polling）：死循环检查 DONE 地址的值
        // 当硬件还在计算时，*gpio_done 通常为 0；算完后硬件会把它置为 1
        while (*gpio_done == 0) {
            // 在裸机或嵌入式驱动中，这里可以留空，或者加一个极为短暂的 nop 延时
            // 芯片会在这里挂起，直到硬件加速器把活干完
        }

        // 3. (可选) 清除启动信号或中断，为下一次运行做准备
        *gpio_start = 0;

        // ====== TODO: Hardware Acceleration End ======
}
#endif





/*
int comparing()
{
    unsigned char *out = (unsigned char *)addr.wr_addr;
    unsigned char *result = (unsigned char *)_binary_data_result_bin_start;
    
    int count = (int)_binary_data_result_bin_size;

    for(int i=0;i<count;i++)
    {
        if(out[i]!=result[i])
        {
            printf("Failed\n");

            printf("Index=%d\n",i);

            printf("Out=%x\n",(unsigned)out[i]);

            printf("Gold=%x\n",(unsigned)result[i]);

            return 1;
        }
    }

    printf("Passed!\n");

    return 0;

}
*/


int comparing()
{
	char *out = (char *)addr.wr_addr;
	char *result = (char *)_binary_data_result_bin_start;

#ifdef USE_HW_ACCEL
    // 1. 这里是“计算包含填充（padding）后的 count”的修正逻辑
	int count = (int)_binary_data_result_bin_size + 
		    (16 - WR_SIZE_D3) * 2 * WR_SIZE_D2 * WR_SIZE_D1;
#else
	int count = (int)_binary_data_result_bin_size;
#endif

	for (int i = 0, j = 0; i < count; i++)
	{
#ifdef USE_HW_ACCEL
        // 2. 这里是“通过 int alignment = i & 0x0000001f; 过滤掉硬件对齐产生的多余字节”的逻辑
		int alignment = i & 0x0000001f;
		if (alignment >= (WR_SIZE_D3 << 1))
			continue;
#endif
		if (*(out + i) != *(result + j))
		{
            // 3. 这里是“出错时仅打印单行的错误地址和数据”的逻辑
			printf("Failed! at address %x and %x with data %x and %x\n", out + i, result + j, *(out + i), *(result + j));
			return 1;
		}
		j++;
	}

	printf("Passed!\n");
	return 0;
}

int main()
{
	Result res;
	res.msec = 0;
	res.insnum = 0;
	res.ifcycle = 0;
	res.stcycle = 0;
	res.ldcycle = 0;
	res.rdwcycle = 0;
	res.ldtime = 0;
	res.sttime = 0;
	res.idcycle = 0;
	bench_prepare(&res);  // clean everything, start timer
#ifdef USE_HW_ACCEL
	printf("Launching task...\n");
	launch_hw_accel();
#else
	printf("starting convolution\n");
	convolution();
	printf("starting pooling\n");
	pooling();
#endif
	bench_done(&res);
    /*
	printf("We have total 7 benchmark to see:)\n");
      printf("The first one is the cycle-nume:%u\n",res.msec);
      printf("The second one is the ins num:%u\n",res.insnum);
      printf("The third one is in the IF waiting to be in IW:%u\n",res.ifcycle);
      printf("And when waiting to write :%u\n",res.stcycle);
      printf("And wait to load:%u\n",res.ldcycle);
      printf("How many cycles are needed for waiting to read:%u\n",res.rdwcycle);
      printf("How many load ins:%u\n",res.ldtime);
      printf("How many store ins:%u\n",res.sttime);
      printf("HOW many cycle waiting in id cycle:%u\n",res.idcycle);
  	*/
	int result = comparing();
	printf("benchmark finished\n");

	if (result == 0) {
		hit_good_trap();
	} else {
		nemu_assert(0);
	}

	return 0;
}
