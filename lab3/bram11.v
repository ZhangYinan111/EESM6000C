`timescale 1ns / 1ps

module bram11 #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32
)(
    input  wire                     clk,
    input  wire [3:0]              wea,
    input  wire                     en,
    input  wire [(DATA_WIDTH-1):0]  di,
    input  wire [(ADDR_WIDTH-1):0]  addr,
    output reg  [(DATA_WIDTH-1):0]  dout
);

    // 存储器数组
    reg [DATA_WIDTH-1:0] ram [0:2**ADDR_WIDTH-1];
    
    // 写入操作
    always @(posedge clk) begin
        if (en) begin
            if (wea[0]) ram[addr][7:0]   <= di[7:0];
            if (wea[1]) ram[addr][15:8]  <= di[15:8];
            if (wea[2]) ram[addr][23:16] <= di[23:16];
            if (wea[3]) ram[addr][31:24] <= di[31:24];
        end
    end
    
    // 读取操作
    always @(posedge clk) begin
        if (en) begin
            dout <= ram[addr];
        end
    end

endmodule 