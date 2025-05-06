module WB_AXILITE
#(
    parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    
     // Wishbone Slave ports (WB MI A)===============
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input wire [3:0] wbs_sel_i,
    input wire [31:0] wbs_dat_i,
    input wire [31:0] wbs_adr_i,
    output reg wbs_ack_o,
    output reg [31:0] wbs_dat_o,
    //axilite ports=================================
    //write(input)--
    input    wire                     awready,
    output   reg                     awvalid,
    output   reg [(pADDR_WIDTH-1):0] awaddr,
    input    wire                     wready,
    output   reg                     wvalid,
    output   reg [(pDATA_WIDTH-1):0] wdata,
    //read(output)---
    input    wire                     arready,
    output   reg                     arvalid,
    output   reg [(pADDR_WIDTH-1):0] araddr,
    output   reg                     rready,
    input    wire                     rvalid,
    input    wire [(pDATA_WIDTH-1):0] rdata
);

always @(*) begin
    case (wbs_we_i)
        1'b0 :begin
            awvalid = 1'b0;
            wvalid = 1'b0;
            awaddr = 32'd0;
            wdata = 32'd0;
            wbs_ack_o = rready;
            wbs_dat_o = rdata;
            arvalid = wbs_stb_i;
            araddr = wbs_adr_i[7:0];
            rready = wbs_stb_i;
        end
        1'b1 :begin
            awvalid = wbs_stb_i;
            wvalid = wbs_stb_i;
            awaddr = wbs_adr_i[7:0];
            wdata = wbs_dat_i;
            wbs_ack_o = wready;
            wbs_dat_o = 32'd0;
            arvalid = 1'b0;
            araddr = 32'd0;
            rready = 1'b0;
        end
    endcase
end

endmodule
