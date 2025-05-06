#ifndef __FIR_H__
#define __FIR_H__

#define N 64

int taps[11] = {0,-10,-9,23,56,63,56,23,-9,-10,0};
int inputbuffer[N];
int inputsignal[11] = {1,2,3,4,5,6,7,8,9,10,11};
int outputsignal[N];


// wishbone
#define mprj_base_addr      0x30000000
// The offset
#define mprj_blklvl_base 	0x30000000
#define mprj_datlen      	0x30000010
#define mprj_tapparam_base 	0x30000040
#define fir_axisin 	        0x30000080
#define fir_axisout 	    0x30000084
#define checkbit            0x2600000c
#define axisin_full         0x30000088
#define axisout_empty       0x30000090
//wishbone operation
#define addr_offset(target, offset) (target+offset)
#define send_wb(target,data) (*(volatile uint32_t*)(target)) = data // send wishbone signal
#define read_wb(target)  (*(volatile uint32_t*)(target))// wishbone read


// 
#define data_len N
enum BLKLVL 
{
    ap_start, ap_done, ap_idle
};

#endif