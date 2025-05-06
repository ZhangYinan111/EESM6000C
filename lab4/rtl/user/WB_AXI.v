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

0x88 axis_in status
0x89 axis_out status

*/

module WB_AXI
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)(
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
    output [31:0] wbs_dat_o
);
// state machine for wb interface.
/*
The state machine is neccessary when wb READ transaction 
is initiated. 

When it is wb write, the host is waiting for ack, this module has to
send the ack signal back to host. The module has to send the ack back 
from the source that the host is waiting for.

When it is wb read, the host is waiting for not only the ack but the dat_o from axilite or
axi stream. The module has to send the dat_o back from the appopriate source.
*/
reg [2:0]state, next_state;
localparam WBAXI_IDLE = 3'd0;
localparam WBAXI_LITE = 3'd1;
localparam WBAXI_SIN = 3'd2;
localparam WBAXI_SOUT = 3'd3;


// clk reset
wire clk = wb_clk_i;
wire rst_n = ~wb_rst_i;

// wbbone interface for axilite
wire wbs_stb_lite;
wire wbs_cyc_lite;
wire wbs_we_lite;
wire [3:0]wbs_sel_lite;
wire [31:0]wbs_dat_lite_i;
wire [31:0]wbs_dat_lite_o;
wire [31:0]wbs_adr_lite;
wire wbs_ack_lite;
// wb interface for axis
wire wbs_stb_axisin, wbs_stb_axisout_out;
wire wbs_cyc_axisin, wbs_cyc_axisout;
wire wbs_we_axisin, wbs_we_axisout;
wire [3:0]wbs_sel_axisin, wbs_sel_axisout;
wire [31:0]wbs_dat_axisin_i, wbs_dat_axisout_i;
wire [31:0]wbs_dat_axisin_o, wbs_dat_axisout_o;
wire [31:0]wbs_adr_axisin, wbs_adr_axisout;
wire wbs_ack_axisin, wbs_ack_axisout;

reg ack_o;
reg [31:0]dat_o;
// axi interface for fir
// axilite
wire                     awready;
wire                     wready;
wire                     awvalid;
wire [(pADDR_WIDTH-1):0] awaddr;
wire                     wvalid;
wire [(pDATA_WIDTH-1):0] wdata;
//read(output)---
wire                     arready;
wire                     rready;
wire                     arvalid;
wire [(pADDR_WIDTH-1):0] araddr;
wire                     rvalid;
wire [(pDATA_WIDTH-1):0] rdata;

//axisin---
wire                     ss_tvalid;
wire [(pDATA_WIDTH-1):0] ss_tdata;
wire                     ss_tlast; 
wire                     ss_tready; 
//axisout---
wire                     sm_tready; 
wire                     sm_tvalid; 
wire [(pDATA_WIDTH-1):0] sm_tdata;
wire                     sm_tlast; 


//bram
// ram for tap
wire [3:0]               tap_WE;
wire                     tap_EN;
wire [(pDATA_WIDTH-1):0] tap_Di;
wire [(pADDR_WIDTH-1):0] tap_A;
wire [(pDATA_WIDTH-1):0] tap_Do;

// ram for data RAM
wire [3:0]               data_WE;
wire                     data_EN;
wire [(pDATA_WIDTH-1):0] data_Di;
wire [(pADDR_WIDTH-1):0] data_A;
wire [(pDATA_WIDTH-1):0] data_Do;
//*************//
//decoder      //
//*************//

//input 
assign wbs_stb_lite = (next_state == WBAXI_LITE)? wbs_stb_i:1'b0;
assign wbs_cyc_lite = (next_state == WBAXI_LITE)? wbs_cyc_i:1'b0;
assign wbs_we_lite =  (next_state == WBAXI_LITE)? wbs_we_i:1'b0;
assign wbs_sel_lite = (next_state == WBAXI_LITE)? wbs_sel_i:4'd0;
assign wbs_dat_lite_i=(next_state == WBAXI_LITE)? wbs_dat_i:32'd0;
assign wbs_adr_lite = (next_state == WBAXI_LITE)? wbs_adr_i:32'd0;

assign wbs_stb_axisin = (next_state == WBAXI_SIN)? wbs_stb_i:1'b0;
assign wbs_cyc_axisin = (next_state == WBAXI_SIN)? wbs_cyc_i:1'b0;
assign wbs_we_axisin =  (next_state == WBAXI_SIN)? wbs_we_i:1'b0;
assign wbs_sel_axisin = (next_state == WBAXI_SIN)? wbs_sel_i:4'd0;
assign wbs_dat_axisin_i=(next_state == WBAXI_SIN)? wbs_dat_i:32'd0;
assign wbs_adr_axisin = (next_state == WBAXI_SIN)? wbs_adr_i:32'd0;


assign wbs_stb_axisout = (next_state == WBAXI_SOUT)? wbs_stb_i:1'b0;
assign wbs_cyc_axisout = (next_state == WBAXI_SOUT)? wbs_cyc_i:1'b0;
assign wbs_we_axisout =  (next_state == WBAXI_SOUT)? wbs_we_i:1'b0;
assign wbs_sel_axisout = (next_state == WBAXI_SOUT)? wbs_sel_i:4'd0;
assign wbs_dat_axisout_i=(next_state == WBAXI_SOUT)? wbs_dat_i:32'd0;
assign wbs_adr_axisout = (next_state == WBAXI_SOUT)? wbs_adr_i:32'd0;
//output
assign wbs_dat_o = dat_o;
assign wbs_ack_o = ack_o;

always@* 
    case(state)
        WBAXI_IDLE:begin
            ack_o = 1'b0;
            dat_o = 32'd0;
        end
        WBAXI_LITE:begin
            ack_o = wbs_ack_lite;
            dat_o = wbs_dat_lite_o;
        end
        WBAXI_SIN:begin
            ack_o = wbs_ack_axisin;
            dat_o = wbs_dat_axisin_o;
        end
        WBAXI_SOUT:begin
            ack_o = wbs_ack_axisout;
            dat_o = wbs_dat_axisout_o;
        end
        default:begin
            ack_o = 1'b0;
            dat_o = 32'd0;
        end
    endcase



//*************//
//FSM          //
//*************//
always@*begin
    case(state)
        WBAXI_IDLE:
            if(wbs_cyc_i && 
                (wbs_adr_i[7:0] >= 8'h00 && wbs_adr_i[7:0] < 8'h80 && wbs_adr_i[7:0]!=8'h10)   
            )
                next_state = WBAXI_LITE;
            else if(wbs_cyc_i && 
                ((wbs_adr_i[7:0] >= 8'h80 && wbs_adr_i[7:0] < 8'h84) || wbs_adr_i[7:0] == 8'h88 || wbs_adr_i[7:0]==8'h10)
            )
                next_state = WBAXI_SIN;
            else if(wbs_cyc_i && 
                ((wbs_adr_i[7:0] >= 8'h84 && wbs_adr_i[7:0] < 8'h88) || wbs_adr_i[7:0] == 8'h90)
            )
                next_state = WBAXI_SOUT;
            else
                next_state = WBAXI_IDLE;
        WBAXI_LITE:
            if(~wbs_cyc_i)
                next_state = WBAXI_IDLE;
            else
                next_state = WBAXI_LITE;
        WBAXI_SIN:
            if(~wbs_cyc_i)
                next_state = WBAXI_IDLE;
            else
                next_state =  WBAXI_SIN;
        WBAXI_SOUT:
            if(~wbs_cyc_i)
                next_state = WBAXI_IDLE;
            else
                next_state = WBAXI_SOUT;
        default:
            next_state = WBAXI_IDLE;
    endcase
end
always@(posedge wb_clk_i or posedge wb_rst_i)
    if(wb_rst_i)
        state <= WBAXI_IDLE;
    else
        state <= next_state;
// record the last addr

       

//**************//
//axi interface //
//**************//
WB_AXILITE wb_lite(
    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),
    .wbs_stb_i(wbs_stb_lite),
    .wbs_cyc_i(wbs_cyc_lite),
    .wbs_we_i(wbs_we_lite),
    .wbs_sel_i(wbs_sel_lite),
    .wbs_dat_i(wbs_dat_lite_i),
    .wbs_adr_i(wbs_adr_lite),
    .wbs_ack_o(wbs_ack_lite),
    .wbs_dat_o(wbs_dat_lite_o),
    //axilite ports=================================
    //write(input)--
    .awready(awready),
    .wready(wready),
    .awvalid(awvalid),
    .awaddr(awaddr),
    .wvalid(wvalid),
    .wdata(wdata),
    //read(output)---
    .arready(arready),
    .rready(rready),
    .arvalid(arvalid),
    .araddr(araddr),
    .rvalid(rvalid),
    .rdata(rdata)
);



//耀明=============================
WB_AXISIN wb_axisin(
    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),
    .wbs_stb_i(wbs_stb_axisin),
    .wbs_cyc_i(wbs_cyc_axisin),
    .wbs_we_i(wbs_we_axisin),
    .wbs_sel_i(wbs_sel_axisin),
    .wbs_dat_i(wbs_dat_axisin_i),
    .wbs_adr_i(wbs_adr_axisin),
    .wbs_ack_o(wbs_ack_axisin),
    .wbs_dat_o(wbs_dat_axisin_o),

    .ss_tvalid(ss_tvalid),
    .ss_tdata(ss_tdata),
    .ss_tlast(ss_tlast),
    .ss_tready(ss_tready)
);

WB_AXISOUT wb_axisout(
    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),
    .wbs_stb_i(wbs_stb_axisout),
    .wbs_cyc_i(wbs_cyc_axisout),
    .wbs_we_i(wbs_we_axisout),
    .wbs_sel_i(wbs_sel_axisout),
    .wbs_dat_i(wbs_dat_axisout_i),
    .wbs_adr_i(wbs_adr_axisout),
    .wbs_ack_o(wbs_ack_axisout),
    .wbs_dat_o(wbs_dat_axisout_o),

    .sm_tvalid(sm_tvalid),
    .sm_tdata(sm_tdata),
    .sm_tlast(sm_tlast),
    .sm_tready(sm_tready)
);

//**************//
//lab 3         //
//**************//
fir fir_U(
//axilite ports
    //write(input)--
    .awready(awready),
    .wready(wready),
    .awvalid(awvalid),
    .awaddr(awaddr),
    .wvalid(wvalid),
    .wdata(wdata),
    //read(output)---
    .arready(arready),
    .rready(rready),
    .arvalid(arvalid),
    .araddr(araddr),
    .rvalid(rvalid),
    .rdata(rdata),
//axistream ports
    .ss_tvalid(ss_tvalid),
    .ss_tdata(ss_tdata),
    .ss_tlast(ss_tlast),
    .ss_tready(ss_tready),

    .sm_tvalid(sm_tvalid),
    .sm_tdata(sm_tdata),
    .sm_tlast(sm_tlast),
    .sm_tready(sm_tready),

    // ram for tap
    .tap_WE(tap_WE),
    .tap_EN(tap_EN),
    .tap_Di(tap_Di),
    .tap_A(tap_A),
    .tap_Do(tap_Do),

    // ram for data
    .data_WE(data_WE),
    .data_EN(data_EN),
    .data_Di(data_Di),
    .data_A(data_A),
    .data_Do(data_Do),

    .axis_clk(clk),
    .axis_rst_n(rst_n)
);

bram11 tap_RAM (
    .clk(clk),
    .we(|tap_WE & tap_EN),
    .re(~(|tap_WE) & tap_EN),
    .waddr(tap_A),
    .raddr(tap_A),
    .wdi(tap_Di),
    .rdo(tap_Do)
);

bram11 data_RAM(
    .clk(clk),
    .we(|data_WE & data_EN),
    .re(~(|data_WE) & data_EN),
    .waddr(data_A),
    .raddr(data_A),
    .wdi(data_Di),
    .rdo(data_Do)
);

endmodule