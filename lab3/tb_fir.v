`timescale 1ns / 1ps

module tb_fir;

    // 参数定义
    parameter pDATA_WIDTH = 32;
    parameter pADDR_WIDTH = 12;
    parameter Tape_Num = 11;
    
    // 时钟和复位信号
    reg clk;
    reg rst_n;
    
    // AXI-Lite接口信号
    reg [pADDR_WIDTH-1:0] s_axil_awaddr;
    reg s_axil_awvalid;
    wire s_axil_awready;
    reg [pDATA_WIDTH-1:0] s_axil_wdata;
    reg s_axil_wvalid;
    wire s_axil_wready;
    wire [1:0] s_axil_bresp;
    wire s_axil_bvalid;
    reg s_axil_bready;
    reg [pADDR_WIDTH-1:0] s_axil_araddr;
    reg s_axil_arvalid;
    wire s_axil_arready;
    wire [pDATA_WIDTH-1:0] s_axil_rdata;
    wire [1:0] s_axil_rresp;
    wire s_axil_rvalid;
    reg s_axil_rready;
    
    // AXI-Stream接口信号
    reg [pDATA_WIDTH-1:0] ss_tdata;
    reg ss_tvalid;
    wire ss_tready;
    reg ss_tlast;
    
    wire [pDATA_WIDTH-1:0] sm_tdata;
    wire sm_tvalid;
    reg sm_tready;
    wire sm_tlast;
    
    // BRAM接口信号
    wire [3:0] tap_WE;
    wire tap_EN;
    wire [pDATA_WIDTH-1:0] tap_Di;
    wire [pADDR_WIDTH-1:0] tap_A;
    reg [pDATA_WIDTH-1:0] tap_Do;
    
    wire [3:0] data_WE;
    wire data_EN;
    wire [pDATA_WIDTH-1:0] data_Di;
    wire [pADDR_WIDTH-1:0] data_A;
    reg [pDATA_WIDTH-1:0] data_Do;
    
    // 文件句柄
    integer input_file;
    integer output_file;
    integer coef_file;
    integer scan_file;
    integer i;
    
    // 数据存储
    reg [pDATA_WIDTH-1:0] input_data [0:1023];
    reg [pDATA_WIDTH-1:0] coef_data [0:Tape_Num-1];
    reg [pDATA_WIDTH-1:0] output_data [0:1023];
    integer data_count = 0;
    integer output_count = 0;
    
    // 实例化FIR模块
    fir #(
        .pADDR_WIDTH(pADDR_WIDTH),
        .pDATA_WIDTH(pDATA_WIDTH),
        .Tape_Num(Tape_Num)
    ) fir_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        // AXI-Lite接口
        .awaddr(s_axil_awaddr),
        .awvalid(s_axil_awvalid),
        .awready(s_axil_awready),
        .wdata(s_axil_wdata),
        .wvalid(s_axil_wvalid),
        .wready(s_axil_wready),
        .bresp(s_axil_bresp),
        .bvalid(s_axil_bvalid),
        .bready(s_axil_bready),
        .araddr(s_axil_araddr),
        .arvalid(s_axil_arvalid),
        .arready(s_axil_arready),
        .rdata(s_axil_rdata),
        .rresp(s_axil_rresp),
        .rvalid(s_axil_rvalid),
        .rready(s_axil_rready),
        
        // AXI-Stream接口
        .ss_tdata(ss_tdata),
        .ss_tvalid(ss_tvalid),
        .ss_tready(ss_tready),
        .ss_tlast(ss_tlast),
        
        .sm_tdata(sm_tdata),
        .sm_tvalid(sm_tvalid),
        .sm_tready(sm_tready),
        .sm_tlast(sm_tlast),
        
        // BRAM接口
        .tap_WE(tap_WE),
        .tap_EN(tap_EN),
        .tap_Di(tap_Di),
        .tap_A(tap_A),
        .tap_Do(tap_Do),
        
        .data_WE(data_WE),
        .data_EN(data_EN),
        .data_Di(data_Di),
        .data_A(data_A),
        .data_Do(data_Do)
    );
    
    // 实例化系数BRAM
    bram11 #(
        .ADDR_WIDTH(pADDR_WIDTH),
        .DATA_WIDTH(pDATA_WIDTH)
    ) tap_RAM (
        .clk(clk),
        .wea(tap_WE),
        .en(tap_EN),
        .di(tap_Di),
        .addr(tap_A),
        .dout(tap_Do)
    );
    
    // 实例化数据BRAM
    bram11 #(
        .ADDR_WIDTH(pADDR_WIDTH),
        .DATA_WIDTH(pDATA_WIDTH)
    ) data_RAM (
        .clk(clk),
        .wea(data_WE),
        .en(data_EN),
        .di(data_Di),
        .addr(data_A),
        .dout(data_Do)
    );
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // 测试过程
    initial begin
        // 初始化信号
        rst_n = 0;
        s_axil_awaddr = 0;
        s_axil_awvalid = 0;
        s_axil_wdata = 0;
        s_axil_wvalid = 0;
        s_axil_bready = 0;
        s_axil_araddr = 0;
        s_axil_arvalid = 0;
        s_axil_rready = 0;
        ss_tdata = 0;
        ss_tvalid = 0;
        ss_tlast = 0;
        sm_tready = 1;
        
        // 读取输入数据文件
        input_file = $fopen("samples_triangular_wave.dat", "r");
        if (input_file == 0) begin
            $display("Error: 无法打开输入数据文件");
            $finish;
        end
        
        i = 0;
        while (!$feof(input_file)) begin
            scan_file = $fscanf(input_file, "%d\n", input_data[i]);
            i = i + 1;
        end
        data_count = i;
        $fclose(input_file);
        $display("读取了 %d 个输入数据样本", data_count);
        
        // 读取系数文件
        coef_file = $fopen("coefficients.dat", "r");
        if (coef_file == 0) begin
            $display("Error: 无法打开系数文件");
            $finish;
        end
        
        i = 0;
        while (!$feof(coef_file) && i < Tape_Num) begin
            scan_file = $fscanf(coef_file, "%d\n", coef_data[i]);
            i = i + 1;
        end
        $fclose(coef_file);
        $display("读取了 %d 个滤波器系数", i);
        
        // 创建输出文件
        output_file = $fopen("output_results.dat", "w");
        if (output_file == 0) begin
            $display("Error: 无法创建输出文件");
            $finish;
        end
        
        // 复位系统
        #100;
        rst_n = 1;
        #100;
        
        // 配置滤波器系数
        for (i = 0; i < Tape_Num; i = i + 1) begin
            write_axil(i*4, coef_data[i]);
            #20;
        end
        
        // 发送输入数据
        for (i = 0; i < data_count; i = i + 1) begin
            send_data(input_data[i], (i == data_count-1));
            #20;
        end
        
        // 等待所有数据处理完成
        wait(output_count == data_count);
        
        // 关闭输出文件
        $fclose(output_file);
        
        $display("仿真完成，共处理 %d 个数据样本", output_count);
        $finish;
    end
    
    // 监控输出数据
    always @(posedge clk) begin
        if (sm_tvalid && sm_tready) begin
            output_data[output_count] = sm_tdata;
            $fdisplay(output_file, "%d", $signed(sm_tdata));
            output_count = output_count + 1;
        end
    end
    
    // AXI-Lite写任务
    task write_axil;
        input [pADDR_WIDTH-1:0] addr;
        input [pDATA_WIDTH-1:0] data;
        begin
            // 地址阶段
            @(posedge clk);
            s_axil_awaddr = addr;
            s_axil_awvalid = 1;
            s_axil_wdata = data;
            s_axil_wvalid = 1;
            s_axil_bready = 1;
            
            // 等待地址就绪
            wait(s_axil_awready);
            @(posedge clk);
            s_axil_awvalid = 0;
            
            // 等待数据就绪
            wait(s_axil_wready);
            @(posedge clk);
            s_axil_wvalid = 0;
            
            // 等待响应
            wait(s_axil_bvalid);
            @(posedge clk);
            s_axil_bready = 0;
        end
    endtask
    
    // AXI-Stream发送数据任务
    task send_data;
        input [pDATA_WIDTH-1:0] data;
        input last;
        begin
            @(posedge clk);
            ss_tdata = data;
            ss_tvalid = 1;
            ss_tlast = last;
            
            wait(ss_tready);
            @(posedge clk);
            ss_tvalid = 0;
            ss_tlast = 0;
        end
    endtask
    
endmodule 