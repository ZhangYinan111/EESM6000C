
`default_nettype wire

`define MPRJ_IO_PADS_1 19	/* number of user GPIO pads on user1 side */
`define MPRJ_IO_PADS_2 19	/* number of user GPIO pads on user2 side */
`define MPRJ_IO_PADS (`MPRJ_IO_PADS_1 + `MPRJ_IO_PADS_2)

module user_proj_example #(
    parameter BITS = 32,
    parameter DELAYS=10
)(
//`ifdef USE_POWER_PINS
//    inout vccd1, // User area 1 1.8V supply
//    inout vssd1, // User area 1 digital ground
//`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);
    wire clk;
    wire rst;

    wire [`MPRJ_IO_PADS-1:0] io_in;
    wire [`MPRJ_IO_PADS-1:0] io_out;
    wire [`MPRJ_IO_PADS-1:0] io_oeb;

    wire [31:0] rdata; 
    wire [31:0] wdata;
    wire [BITS-1:0] count;

    wire valid;
    wire [3:0] wstrb;
    wire [31:0] la_write;
    reg  [1:0] decoded;

    reg  ready;
    reg  [BITS-17:0] delayed_count;
    reg  [31:0] decoded_output_data;
    wire [31:0] BRAM_Do;
    wire [31:0] output_data_WB_FIR;

    //ack decode
    reg decoded_output_ACK;
    wire wbs_ack_BRAM;
    wire wbs_ack_WB_FIR;

    //BRAM wstrb
    wire [3:0] BRAM_WE; 
    
    //wishbone write enable
    wire wbs_we_BRAM;
    wire wbs_we_WB_FIR;
    assign wbs_we_BRAM=wbs_we_i;
    assign wbs_we_WB_FIR=wbs_we_i;

    //wishbone select
    wire [3:0] wbs_sel_BRAM;
    wire [3:0] wbs_sel_WB_FIR;

    //Bram , FIR address
    wire [31:0] BRAM_adr;
    wire [31:0] WB_FIR_adr; 

    //Bram , FIR data in
    wire [31:0] BRAM_Di;
    wire [31:0] WB_FIR_Di;

    //cyc ,stb decoded signal
    reg wbs_stb_BRAM;
    reg wbs_cyc_BRAM;
    reg WB_FIR_stb;
    reg WB_FIR_cyc;

    /////////////////////sub module//////////////////////////////////
    bram user_bram (
        .CLK(clk),
        .WE0(BRAM_WE),
        .EN0(valid),
        .Di0(BRAM_Di),
        .Do0(BRAM_Do),
        .A0 (BRAM_adr)
    );

    //0x3000_0000

    WB_AXI wb_axi(
        //wb
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),
        .wbs_stb_i(WB_FIR_stb),
        .wbs_cyc_i(WB_FIR_cyc),
        .wbs_we_i(wbs_we_WB_FIR),
        .wbs_sel_i(wbs_sel_WB_FIR),
        .wbs_dat_i(WB_FIR_Di),
        .wbs_adr_i(WB_FIR_adr),
        .wbs_ack_o(wbs_ack_WB_FIR),
        .wbs_dat_o(output_data_WB_FIR)
    );


    //////////////////////////////////////////////////////////////////////////////////////

    // WB MI A
    assign valid = wbs_cyc_i && wbs_stb_i && (decoded==2'd2); //decode==2'd2 為0x380
    assign wstrb = wbs_sel_i & {4{wbs_we_i}};
    assign wbs_dat_o = rdata;
    assign wdata = wbs_dat_i;


    // IO
    assign io_out = decoded_output_data;
    assign io_oeb = {(`MPRJ_IO_PADS-1){rst}};

    // IRQ
    assign irq = 3'b000; // Unused
    
    ////////////////////////// interface output //////////////////////////
    assign wbs_dat_o = decoded_output_data;


    // LA
    assign la_data_out = {{(127-BITS){1'b0}},  decoded_output_data};
    // Assuming LA probes [63:32] are for controlling the count register  
    assign la_write = ~la_oenb[63:32] & ~{BITS{valid}};
    // Assuming LA probes [65:64] are for controlling the count clk & reset  
    assign clk = (~la_oenb[64]) ? la_data_in[64]: wb_clk_i;
    assign rst = (~la_oenb[65]) ? la_data_in[65]: wb_rst_i;

 

    //decode select
    //12'h380 for BRAM
    //12'h300 for FIR
    always @* begin
        case(wbs_adr_i[31:20])
        12'h380: decoded=2'b10;
        12'h300: decoded=2'b11;
        default: decoded=2'b00;
        endcase
    end


    //*****************************************************//
    // exmen                                               //
    //*****************************************************//

    always @(posedge clk) begin
        if (rst) begin
            ready <= 1'b0;
            delayed_count <= 16'b0;
        end else begin
            ready <= 1'b0;
            if ( valid && !ready ) begin
                if ( delayed_count == DELAYS ) begin
                    delayed_count <= 16'b0;
                    ready <= 1'b1;
                end else begin
                    delayed_count <= delayed_count + 1;
                end
            end
        end
    end

///////////////////////////////// decode /////////////////////////////////

    //stb decode

    always @* begin
        case(decoded)
        2'b10:begin
            wbs_stb_BRAM=wbs_stb_i;
            WB_FIR_stb=0;
        end
        2'b11:begin
            wbs_stb_BRAM=0;
            WB_FIR_stb=wbs_stb_i;
        end
        default:begin
            wbs_stb_BRAM=0;
            WB_FIR_stb=0;
        end
        endcase
    end

    //cyc decode
    always @* begin
        case(decoded)
        2'b10:begin
            wbs_cyc_BRAM=wbs_cyc_i;
            WB_FIR_cyc=0;
        end
        2'b11:begin
            wbs_cyc_BRAM=0;
            WB_FIR_cyc=wbs_cyc_i;
        end
        default:begin
            wbs_cyc_BRAM=0;
            WB_FIR_cyc=0;
        end
        endcase
    end

    
    //wbs_adr_i
    assign BRAM_adr   = (decoded==2'b10)?wbs_adr_i:32'd0;
    assign WB_FIR_adr = (decoded==2'b11)?wbs_adr_i:32'd0;

    //wbs_data_in
    assign BRAM_Di    = (decoded==2'b10)?wbs_dat_i:32'd0;
    assign WB_FIR_Di  = (decoded==2'b11)?wbs_dat_i:32'd0;
    
    //decode for decoded_output
    always @* begin
        case(decoded)
        2'b10:begin
            decoded_output_data = BRAM_Do;
        end
        2'b11:begin
            decoded_output_data = output_data_WB_FIR;
        end
        default:begin
            decoded_output_data = 0;
        end
        endcase
    end


        //decode for decoded_output
    always @* begin
        case(decoded)
        2'b10:begin
            decoded_output_ACK  = wbs_ack_BRAM;
        end
        2'b11:begin
            decoded_output_ACK  = wbs_ack_WB_FIR;
        end
        default:begin
            decoded_output_ACK  = 0;
        end
        endcase
    end

    ////////////////////////// output interface //////////////////////////
    assign wbs_dat_o = decoded_output_data;
    assign wbs_ack_o = decoded_output_ACK;

    // IO
    assign io_out = decoded_output_data;
    assign io_oeb = {(`MPRJ_IO_PADS-1){rst}};

    // IRQ
    assign irq = 3'b000;	// Not implemented here

    // WB MI A
    assign valid = wbs_cyc_BRAM && wbs_stb_BRAM && (decoded==2'b10); 
    assign BRAM_WE = wbs_sel_BRAM & {4{wbs_we_BRAM}};
    assign wbs_ack_BRAM = ready;
    //wbs_sel
    assign wbs_sel_BRAM=wbs_sel_i;
    assign wbs_sel_WB_FIR=wbs_sel_i;



endmodule



