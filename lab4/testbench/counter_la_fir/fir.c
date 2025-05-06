#include "fir.h"
#include <stdint.h> 
#include <stdbool.h>
// The base address of user project

/*
User Project Memory Starting: 3800_0000
User Project FIR Base Address : 3000_0000 
0x00 – [0] - ap_start (r/w) 
set, when ap_start signal assert
reset, when start data transfer, i.e. 1st axi-stream data come in
[1] – ap_done (ro) -> when FIR process all the dataset, i.e. receive tlast and last Y generated/transferred
[2] – ap_idle (ro) -> indicate FIR is actively processing data
[3] – Reserved (ro) -> read zero
[4] – X[n]_ready to accept input (ro) -> X[n] is ready to accept input. 
[5] - Y[n] is ready to read -> set when Y[n] is ready, reset when 0x00 is read
0x10-13 - data-length
0x40-7F – Tap parameters, (e.g., 0x40-43 Tap0, in sequence …)
0x80-83 – X[n] input (r/w)
0x84-87 – Y[n] output (ro)
*/




void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
	
	send_wb(mprj_datlen, data_len);
	// send tap data
	for(uint32_t i = 0; i<11; i++){
		send_wb(addr_offset(mprj_tapparam_base,i*4), taps[i]);
	}

	// read back tap data for debugging
	for(uint32_t i = 0; i<11; i++){
		int32_t register tmp =  read_wb(addr_offset(mprj_tapparam_base,i*4));
		send_wb(checkbit, tmp<<16);
	}

	

}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	enum BLKLVL blklvl;
	int32_t rdata = 0;
	rdata =read_wb(axisout_empty);
	
	//***************************************************************//
	// check ap_idle and send ap_start
	send_wb(checkbit, 0x00A50000);
	while( read_wb(mprj_blklvl_base) & (1<<ap_idle ) != 1<<ap_idle);
	send_wb(mprj_blklvl_base,  (1 << ap_start) );
	int8_t register i,j = 0;
	int32_t is_full = 0;
	while(j<data_len){
		if(read_wb(axisin_full) == 0x00000000 && i<data_len){
			send_wb(fir_axisin, i++);
		}
		if(read_wb(axisout_empty) == 0x00000000){
			int register tmp = read_wb(fir_axisout);
			outputsignal[j++] = tmp;
		}
	}
	while( read_wb(mprj_blklvl_base) & (1<<ap_done ) != 1<<ap_done);
	while( read_wb(mprj_blklvl_base) & (1<<ap_idle ) != 1<<ap_idle);
	send_wb(checkbit, outputsignal[63]<<24 | 0x005A0000);
	//***************************************************************//


	//***************************************************************//
	send_wb(checkbit, 0x00A50000);
	send_wb(mprj_blklvl_base,  (1 << ap_start) );
	i = 0;
	j = 0;
	while(j<data_len){
		if(read_wb(axisin_full) == 0x00000000 && i<data_len){
			send_wb(fir_axisin, i++);
		}
		if(read_wb(axisout_empty) == 0x00000000){
			int register tmp = read_wb(fir_axisout);
			outputsignal[j++] = tmp;
		}
	}
	while( read_wb(mprj_blklvl_base) & (1<<ap_done ) != 1<<ap_done);
	while( read_wb(mprj_blklvl_base) & (1<<ap_idle ) != 1<<ap_idle);
	send_wb(checkbit, outputsignal[63]<<24 | 0x005A0000);
	//***************************************************************//

	//***************************************************************//
	send_wb(checkbit, 0x00A50000);
	send_wb(mprj_blklvl_base,  (1 << ap_start) );
	i = 0;
	j = 0;
	while(j<data_len){
		if(read_wb(axisin_full) == 0x00000000 && i<data_len){
			send_wb(fir_axisin, i++);
		}
		if(read_wb(axisout_empty) == 0x00000000){
			int register tmp = read_wb(fir_axisout);
			outputsignal[j++] = tmp;
		}
	}
	while( read_wb(mprj_blklvl_base) & (1<<ap_done ) != 1<<ap_done);
	while( read_wb(mprj_blklvl_base) & (1<<ap_idle ) != 1<<ap_idle);
	send_wb(checkbit, outputsignal[63]<<24 | 0x005A0000);
	//***************************************************************//
	// finish
	return outputsignal;
}
		
