`timescale 1ns / 1ps

module fir
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    // 系统信号
    input  wire                     clk,
    input  wire                     rst_n,

    // AXI-Lite接口 - 写地址通道
    output wire                     awready,
    input  wire                     awvalid,
    input  wire [(pADDR_WIDTH-1):0] awaddr,
    
    // AXI-Lite接口 - 写数据通道
    output wire                     wready,
    input  wire                     wvalid,
    input  wire [(pDATA_WIDTH-1):0] wdata,
    
    // AXI-Lite接口 - 写响应通道
    output wire [1:0]               bresp,
    output wire                     bvalid,
    input  wire                     bready,
    
    // AXI-Lite接口 - 读地址通道
    output wire                     arready,
    input  wire                     arvalid,
    input  wire [(pADDR_WIDTH-1):0] araddr,
    
    // AXI-Lite接口 - 读数据通道
    input  wire                     rready,
    output wire                     rvalid,
    output wire [(pDATA_WIDTH-1):0] rdata,
    output wire [1:0]               rresp,
    
    // AXI-Stream接口 - 输入
    input  wire                     ss_tvalid,
    input  wire [(pDATA_WIDTH-1):0] ss_tdata,
    input  wire                     ss_tlast,
    output wire                     ss_tready,
    
    // AXI-Stream接口 - 输出
    input  wire                     sm_tready,
    output wire                     sm_tvalid,
    output wire [(pDATA_WIDTH-1):0] sm_tdata,
    output wire                     sm_tlast,
    
    // BRAM接口 - 抽头系数
    output wire [3:0]               tap_WE,
    output wire                     tap_EN,
    output wire [(pDATA_WIDTH-1):0] tap_Di,
    output wire [(pADDR_WIDTH-1):0] tap_A,
    input  wire [(pDATA_WIDTH-1):0] tap_Do,
    
    // BRAM接口 - 数据
    output wire [3:0]               data_WE,
    output wire                     data_EN,
    output wire [(pDATA_WIDTH-1):0] data_Di,
    output wire [(pADDR_WIDTH-1):0] data_A,
    input  wire [(pDATA_WIDTH-1):0] data_Do
);

    // 寄存器地址映射
    localparam ADDR_AP_CTRL        = 12'h00; // 控制寄存器: bit0 - ap_start, bit1 - ap_done, bit2 - ap_idle
    localparam ADDR_DATA_LENGTH    = 12'h10; // 数据长度寄存器
    localparam ADDR_COEF_BASE      = 12'h20; // 抽头系数基地址
    
    // 状态机定义
    localparam IDLE = 2'b00;
    localparam BUSY = 2'b01;
    localparam DONE = 2'b10;
    
    // 控制寄存器
    reg ap_start, ap_done, ap_idle;
    reg [31:0] data_length;
    
    // 状态机
    reg [1:0] state, next_state;
    
    // AXI-Lite接口寄存器
    reg awready_reg, wready_reg;
    reg arready_reg, rvalid_reg;
    reg [31:0] rdata_reg;
    
    // AXI-Stream接口寄存器
    reg ss_tready_reg;
    reg sm_tvalid_reg, sm_tlast_reg;
    reg [31:0] sm_tdata_reg;
    
    // 数据处理计数器和控制信号
    reg [31:0] data_count;
    reg [3:0] tap_index;
    reg [3:0] calc_count;
    reg calc_done;
    
    // 数据路径信号
    reg [31:0] mult_a, mult_b;
    reg [31:0] acc;
    
    // BRAM控制信号
    reg [3:0] tap_WE_reg;
    reg tap_EN_reg;
    reg [31:0] tap_Di_reg;
    reg [11:0] tap_A_reg;
    
    reg [3:0] data_WE_reg;
    reg data_EN_reg;
    reg [31:0] data_Di_reg;
    reg [11:0] data_A_reg;
    
    // 数据移位寄存器索引
    reg [3:0] data_index;
    reg [3:0] data_index_old;
    
    // 输入数据缓存
    reg [31:0] input_data;
    
    // 乘法结果
    wire [31:0] mult_result;
    assign mult_result = mult_a * mult_b;
    
    // 添加AXI-Lite写响应通道寄存器
    reg bvalid_reg;
    reg [1:0] bresp_reg;
    
    // 添加AXI-Lite读响应寄存器
    reg [1:0] rresp_reg;
    
    // 状态机 - 时序逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // 状态机 - 组合逻辑
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (ap_start) begin
                    next_state = BUSY;
                end
            end
            
            BUSY: begin
                if (data_count >= data_length && calc_done) begin
                    next_state = DONE;
                end
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // AXI-Lite写地址通道
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awready_reg <= 1'b0;
        end else begin
            if (awvalid && !awready_reg) begin
                awready_reg <= 1'b1;
            end else begin
                awready_reg <= 1'b0;
            end
        end
    end
    
    // AXI-Lite写数据通道
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wready_reg <= 1'b0;
            ap_start <= 1'b0;
            ap_done <= 1'b0;
            ap_idle <= 1'b1;
            data_length <= 32'h0;
        end else begin
            if (wvalid && awvalid && !wready_reg) begin
                wready_reg <= 1'b1;
                
                // 写入寄存器
                case (awaddr)
                    ADDR_AP_CTRL: begin
                        ap_start <= wdata[0];
                        if (wdata[0]) begin
                            ap_done <= 1'b0;
                            ap_idle <= 1'b0;
                        end
                    end
                    
                    ADDR_DATA_LENGTH: begin
                        data_length <= wdata;
                    end
                    
                    default: begin
                        // 写入抽头系数到BRAM
                        if (awaddr >= ADDR_COEF_BASE && awaddr < ADDR_COEF_BASE + (Tape_Num * 4)) begin
                            // 写入操作由BRAM接口处理
                        end
                    end
                endcase
            end else begin
                wready_reg <= 1'b0;
                
                // ap_start是一个脉冲信号，只持续一个时钟周期
                if (ap_start) begin
                    ap_start <= 1'b0;
                end
                
                // 当状态机进入DONE状态时，设置ap_done和ap_idle
                if (state == DONE) begin
                    ap_done <= 1'b1;
                    ap_idle <= 1'b1;
                end
            end
        end
    end
    
    // AXI-Lite读地址通道
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arready_reg <= 1'b0;
        end else begin
            if (arvalid && !arready_reg) begin
                arready_reg <= 1'b1;
            end else begin
                arready_reg <= 1'b0;
            end
        end
    end
    
    // AXI-Lite读数据通道
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_reg <= 1'b0;
            rdata_reg <= 32'h0;
        end else begin
            if (arvalid && arready_reg && !rvalid_reg) begin
                rvalid_reg <= 1'b1;
                
                // 读取寄存器
                case (araddr)
                    ADDR_AP_CTRL: begin
                        rdata_reg <= {29'b0, ap_idle, ap_done, ap_start};
                    end
                    
                    ADDR_DATA_LENGTH: begin
                        rdata_reg <= data_length;
                    end
                    
                    default: begin
                        // 读取抽头系数从BRAM
                        if (araddr >= ADDR_COEF_BASE && araddr < ADDR_COEF_BASE + (Tape_Num * 4)) begin
                            // 读取操作由BRAM接口处理
                            rdata_reg <= tap_Do;
                        end else begin
                            rdata_reg <= 32'h0;
                        end
                    end
                endcase
            end else if (rready && rvalid_reg) begin
                rvalid_reg <= 1'b0;
            end
        end
    end
    
    // BRAM接口 - 抽头系数
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tap_WE_reg <= 4'b0000;
            tap_EN_reg <= 1'b0;
            tap_Di_reg <= 32'h0;
            tap_A_reg <= 12'h0;
        end else begin
            // 默认值
            tap_WE_reg <= 4'b0000;
            tap_EN_reg <= 1'b1;
            
            // 写入抽头系数
            if (wvalid && awvalid && !wready_reg && awaddr >= ADDR_COEF_BASE && awaddr < ADDR_COEF_BASE + (Tape_Num * 4)) begin
                tap_WE_reg <= 4'b1111;
                tap_Di_reg <= wdata;
                tap_A_reg <= (awaddr - ADDR_COEF_BASE) >> 2;
            end
            // 读取抽头系数
            else if (arvalid && !arready_reg && araddr >= ADDR_COEF_BASE && araddr < ADDR_COEF_BASE + (Tape_Num * 4)) begin
                tap_WE_reg <= 4'b0000;
                tap_A_reg <= (araddr - ADDR_COEF_BASE) >> 2;
            end
            // 计算过程中读取抽头系数
            else if (state == BUSY && !calc_done) begin
                tap_WE_reg <= 4'b0000;
                tap_A_reg <= tap_index;
            end
        end
    end
    
    // BRAM接口 - 数据
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_WE_reg <= 4'b0000;
            data_EN_reg <= 1'b0;
            data_Di_reg <= 32'h0;
            data_A_reg <= 12'h0;
        end else begin
            // 默认值
            data_WE_reg <= 4'b0000;
            data_EN_reg <= 1'b1;
            
            // 写入新数据到移位寄存器
            if (state == BUSY && ss_tvalid && ss_tready_reg) begin
                data_WE_reg <= 4'b1111;
                data_Di_reg <= ss_tdata;
                data_A_reg <= data_index;
            end
            // 计算过程中读取数据
            else if (state == BUSY && !calc_done && calc_count > 0) begin
                data_WE_reg <= 4'b0000;
                data_A_reg <= data_index_old;
            end
        end
    end
    
    // AXI-Stream接口 - 输入
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ss_tready_reg <= 1'b0;
            input_data <= 32'h0;
        end else begin
            if (state == BUSY && !calc_done && calc_count == 0) begin
                ss_tready_reg <= 1'b1;
                if (ss_tvalid && ss_tready_reg) begin
                    input_data <= ss_tdata;
                    ss_tready_reg <= 1'b0; // 接收到数据后，暂时不再接收
                end
            end else begin
                ss_tready_reg <= 1'b0;
            end
        end
    end
    
    // AXI-Stream接口 - 输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sm_tvalid_reg <= 1'b0;
            sm_tlast_reg <= 1'b0;
            sm_tdata_reg <= 32'h0;
        end else begin
            if (calc_done && !sm_tvalid_reg) begin
                sm_tvalid_reg <= 1'b1;
                sm_tdata_reg <= acc;
                sm_tlast_reg <= (data_count == data_length - 1);
            end else if (sm_tready && sm_tvalid_reg) begin
                sm_tvalid_reg <= 1'b0;
            end
        end
    end
    
    // 数据处理逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_count <= 32'h0;
            tap_index <= 4'h0;
            calc_count <= 4'h0;
            calc_done <= 1'b0;
            mult_a <= 32'h0;
            mult_b <= 32'h0;
            acc <= 32'h0;
            data_index <= 4'h0;
            data_index_old <= 4'h0;
        end else begin
            case (state)
                IDLE: begin
                    data_count <= 32'h0;
                    tap_index <= 4'h0;
                    calc_count <= 4'h0;
                    calc_done <= 1'b0;
                    data_index <= 4'h0;
                end
                
                BUSY: begin
                    // 当输入有效且我们准备好接收时，处理新数据
                    if (ss_tvalid && ss_tready_reg && calc_count == 0) begin
                        // 开始计算
                        calc_count <= 4'h1; // 开始计算第一个系数
                        tap_index <= 4'h0;
                        acc <= 32'h0;
                        calc_done <= 1'b0;
                        
                        // 第一个抽头系数与当前输入相乘
                        mult_a <= ss_tdata;
                        mult_b <= tap_Do;
                        
                        // 更新数据索引
                        data_index <= (data_index == Tape_Num - 2) ? 4'h0 : (data_index + 1);
                        data_index_old <= data_index;
                    end
                    // 计算过程
                    else if (calc_count > 0 && calc_count < Tape_Num && !calc_done) begin
                        // 累加上一次的乘法结果
                        if (calc_count > 1) begin
                            acc <= acc + mult_result;
                        end
                        
                        // 准备下一次乘法
                        tap_index <= calc_count;
                        
                        if (calc_count == 1) begin
                            // 第一次累加，使用输入数据
                            mult_a <= input_data;
                            mult_b <= tap_Do;
                        end else begin
                            // 其他抽头系数与移位寄存器中的数据相乘
                            mult_a <= data_Do;
                            mult_b <= tap_Do;
                            
                            // 更新数据索引
                            data_index_old <= (data_index_old == 0) ? (Tape_Num - 2) : (data_index_old - 1);
                        end
                        
                        calc_count <= calc_count + 1;
                    end
                    // 最后一次计算
                    else if (calc_count == Tape_Num && !calc_done) begin
                        // 累加最后一次乘法结果
                        acc <= acc + mult_result;
                        calc_done <= 1'b1;
                        data_count <= data_count + 1;
                        calc_count <= 4'h0; // 重置计数器，准备下一次计算
                    end
                    // 输出结果被接收后，重置状态
                    else if (sm_tready && sm_tvalid_reg) begin
                        calc_done <= 1'b0;
                    end
                end
                
                DONE: begin
                    // 重置状态
                    data_count <= 32'h0;
                    tap_index <= 4'h0;
                    calc_count <= 4'h0;
                    calc_done <= 1'b0;
                end
            endcase
        end
    end
    
    // 在AXI-Lite写数据通道逻辑中添加写响应处理
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bvalid_reg <= 1'b0;
            bresp_reg <= 2'b00;
        end else begin
            if (wvalid && wready_reg && !bvalid_reg) begin
                bvalid_reg <= 1'b1;
                bresp_reg <= 2'b00; // OKAY响应
            end else if (bready && bvalid_reg) begin
                bvalid_reg <= 1'b0;
            end
        end
    end
    
    // 在AXI-Lite读数据通道逻辑中添加读响应
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rresp_reg <= 2'b00;
        end else begin
            if (arvalid && arready_reg && !rvalid_reg) begin
                rresp_reg <= 2'b00; // OKAY响应
            end
        end
    end
    
    // 输出赋值
    assign awready = awready_reg;
    assign wready = wready_reg;
    assign arready = arready_reg;
    assign rvalid = rvalid_reg;
    assign rdata = rdata_reg;
    
    assign ss_tready = ss_tready_reg;
    assign sm_tvalid = sm_tvalid_reg;
    assign sm_tdata = sm_tdata_reg;
    assign sm_tlast = sm_tlast_reg;
    
    assign tap_WE = tap_WE_reg;
    assign tap_EN = tap_EN_reg;
    assign tap_Di = tap_Di_reg;
    assign tap_A = tap_A_reg;
    
    assign data_WE = data_WE_reg;
    assign data_EN = data_EN_reg;
    assign data_Di = data_Di_reg;
    assign data_A = data_A_reg;
    
    assign bresp = bresp_reg;
    assign bvalid = bvalid_reg;
    assign rresp = rresp_reg;

endmodule 
