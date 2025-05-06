module WB_AXISIN
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
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
    // axis interfacce
    output   wire                     ss_tvalid, 
    output   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    output   wire                     ss_tlast, 
    input    wire                     ss_tready 
);

//state machine---------------
reg [2:0] state, next_state;
localparam STRMIN_IDLE = 3'd0;
localparam STRMIN_DATLEN = 3'd1;
localparam STRMIN_CKFULL = 3'd2;
localparam STRMIN_SEND = 3'd3;
localparam STRMIN_READ = 3'd4;

localparam InputFiFoDepth = 5'd2;
wire decoded = (wbs_adr_i[31:24] == 8'h30)? 1'b1: 1'b0;
//wb_receiver==========================
wire valid = wbs_stb_i & wbs_we_i & wbs_cyc_i & decoded;//wb write 
wire ready = wbs_stb_i & ~wbs_we_i & wbs_cyc_i & decoded;//wb read
reg wb_ack_reg;
reg[32-1:0] data_len, data_len_next;
// to queue
reg wb_valid;
reg[32-1:0] wb_data;
//to isfull
reg[32-1:0] dat_o_reg;

//queue=========================
reg[4:0] queue_cnt,queue_cnt_next; 
wire is_full = (queue_cnt == InputFiFoDepth)?1'b1:1'b0;
wire is_empty = (queue_cnt == 0)? 1'b1:1'b0;
wire axis_ready = ss_tready; 
reg [32-1:0] queue [0:InputFiFoDepth-1];
//axi_sender===============
/*
assign ss_tdata = queue[0];
assign ss_tvalid = ~is_empty;
*/
reg [32-1:0] tlast_cnt, tlast_cnt_next;
//***********//
//fsm        //
//***********//
always@*
    case(state)
        STRMIN_IDLE:
            if(  wbs_adr_i[8-1:0] == 8'h88 &&  ready  )
                next_state = STRMIN_CKFULL;
            else if( wbs_adr_i[8-1:0] == 8'h80 &&  valid ) 
                next_state = STRMIN_SEND;
            else if( wbs_adr_i[8-1:0] == 8'h80 &&  ready)
                next_state = STRMIN_READ;
            else if(wbs_adr_i[8-1:0] == 8'h10 &&  valid )
                next_state = STRMIN_DATLEN;
            else
                next_state = STRMIN_IDLE;
        STRMIN_READ:
            next_state = STRMIN_IDLE;
        STRMIN_DATLEN:
            next_state = STRMIN_IDLE;
        STRMIN_SEND:
            if(~is_full & ~(~is_empty & axis_ready))
                next_state = STRMIN_IDLE;
            else
                next_state = STRMIN_SEND;
        STRMIN_CKFULL:
            next_state = STRMIN_IDLE;
        default:
            next_state = STRMIN_IDLE;
    endcase

always@(posedge wb_clk_i or posedge wb_rst_i)
    if(wb_rst_i)
        state <= STRMIN_IDLE;
    else
        state <= next_state;

//***********//
//wb-receiver//
//***********//
assign wbs_ack_o = wb_ack_reg;
always@*
    case(state)
        STRMIN_IDLE:
           wb_ack_reg = 1'b0;
        STRMIN_DATLEN:
            wb_ack_reg = 1'b1;
        STRMIN_SEND:
            if(~is_full & ~(~is_empty & axis_ready) )
                wb_ack_reg = 1'b1;
            else
                 wb_ack_reg = 1'b0;
        STRMIN_READ:
            wb_ack_reg = 1'b1;
        STRMIN_CKFULL:
            wb_ack_reg = 1'b1;
        default:
            wb_ack_reg = 1'b0;
    endcase
// for data_length
always@(posedge wb_clk_i or posedge wb_rst_i)
    if(wb_rst_i)
        data_len <= 32'd0;
    else
        data_len <= data_len_next;
always@*
    case(state)
        STRMIN_DATLEN:
            data_len_next = wbs_dat_i;
        default:
            data_len_next = data_len;
    endcase
// for queue
always@*
    if(state == STRMIN_SEND && (~is_full &   ~(~is_empty & axis_ready)   ) )begin
        wb_valid = valid & wbs_ack_o;
        wb_data = wbs_dat_i;
    end
    else begin
        wb_valid = 1'b0;
        wb_data = 32'd0;
    end

// for isfull
assign wbs_dat_o = dat_o_reg;
always@(*)
    if(state == STRMIN_CKFULL)
        dat_o_reg <= { {31{1'b0}} ,is_full};
    else if(state == STRMIN_READ)
        dat_o_reg <= (queue_cnt > 5'd0)?queue[queue_cnt-5'd1]:32'd0;
    else
        dat_o_reg <= 32'd0;
//***********//
//queue      //
//***********//
always@(posedge wb_clk_i or posedge wb_rst_i)
    if(wb_rst_i)
        queue_cnt <= 5'd0;
    else
        queue_cnt <= queue_cnt_next;
always@*
    if(axis_ready & ~is_empty & ss_tvalid)
        queue_cnt_next = queue_cnt - 5'd1; 
    else if (wb_valid & wbs_adr_i[7:0] == 8'h80)
        queue_cnt_next = queue_cnt + 5'd1;
    else
        queue_cnt_next = queue_cnt;

integer IHateSOC;
integer shift_index;
always@(posedge wb_clk_i or posedge wb_rst_i)
    if(wb_rst_i) begin
        for(IHateSOC = 0; IHateSOC < InputFiFoDepth; IHateSOC = IHateSOC + 1)
            queue[IHateSOC] <= 32'd0;
    end
    else begin
        for(IHateSOC = 0; IHateSOC < InputFiFoDepth; IHateSOC = IHateSOC + 1)
            queue[IHateSOC] <= queue[IHateSOC];
        if(axis_ready & ~is_empty & ss_tvalid)begin
            for(shift_index = 1; shift_index < InputFiFoDepth; shift_index = shift_index + 1)
                queue[shift_index-1] <= queue[shift_index];
                
            queue[InputFiFoDepth-1] <= 32'd0;
        end
        else if (wb_valid )
            queue[queue_cnt] <= wb_data;
    end

//***********//
//axis-sender//
//***********//
assign ss_tdata = queue[0];
assign ss_tvalid = ~is_empty;
assign ss_tlast = (tlast_cnt == data_len - 32'd1)? 1'b1: 1'b0;

always@(posedge wb_clk_i or posedge wb_rst_i)
    if(wb_rst_i)
        tlast_cnt <= 32'd0;
    else
        tlast_cnt <= tlast_cnt_next;

always@*
    if(ss_tvalid & ss_tready & ~ss_tlast)
        tlast_cnt_next =  tlast_cnt + 32'd1;
    else if(ss_tvalid & ss_tready & ss_tlast)
        tlast_cnt_next = 32'd0;
    else
        tlast_cnt_next = tlast_cnt;
endmodule