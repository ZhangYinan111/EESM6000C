`default_nettype none

`timescale 1 ns / 1 ps

module tbuart (
	input  ser_rx,
	output  ser_tx
);
	reg [3:0] recv_state;
	reg [2:0] recv_divcnt;
	reg [7:0] recv_pattern;
	reg [8*50-1:0] recv_buf_data;	// 50 characters.  Increase as needed for tests.

	reg clk;

	initial begin
		clk <= 1'b0;
		recv_state <= 0;
		recv_divcnt <= 0;
		recv_pattern <= 0;
		recv_buf_data <= 0;
	end

	// NOTE:  Running at 3.0us clock period @ 5 clocks per bit = 15.0us per
	// bit ~= 64 kbaud. Not tuned to any particular UART.  Most run at
	// 9600 baud default and will bounce up to higher baud rates when
	// passed specific command words.

//	always #1500 clk <= (clk === 1'b0);
	always #2650 clk <= (clk === 1'b0);  // working for 9600 baud
//	always #125 clk <= (clk === 1'b0);

	always @(posedge clk) begin
		recv_divcnt <= recv_divcnt + 1;
		case (recv_state)
			0: begin
				if (!ser_rx)
					recv_state <= 1;
				recv_divcnt <= 0;
			end
			1: begin
				if (2*recv_divcnt > 3'd3) begin
					recv_state <= 2;
					recv_divcnt <= 0;
				end
			end
			10: begin
				if (recv_divcnt > 3'd3) begin
					// 0x0a = '\n'
					if (recv_pattern == 8'h0a) begin
						$display("output: %s", recv_buf_data);
					end else begin
						recv_buf_data <= {recv_buf_data, recv_pattern};
					end
					recv_state <= 0;
				end
			end
			default: begin
				if (recv_divcnt > 3'd3) begin
					recv_pattern <= {ser_rx, recv_pattern[7:1]};
					recv_state <= recv_state + 1;
					recv_divcnt <= 0;
				end
			end
		endcase
	end

endmodule
