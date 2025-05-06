module WB_AXISOUT
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
    input   wire                     sm_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] sm_tdata, 
    input   wire                     sm_tlast, 
    output  wire                     sm_tready
);
//fsm
localparam STRMOUT_IDLE = 3'd0;
localparam STRMOUT_CKEMPTY = 3'd1;
localparam STRMOUT_RECV = 3'd2;
localparam STRMOUT_WRITE = 3'd3;
reg [2:0]state, next_state;

localparam OutputFiFoDepth = 5'd2;
// axis_receiver
wire axis_valid;
wire [32-1:0]axis_data;
wire ready = wbs_cyc_i & wbs_stb_i & ~ wbs_we_i;
wire valid = wbs_cyc_i & wbs_stb_i &   wbs_we_i;
// queue
reg [5-1:0]queue_cnt, queue_cnt_next;
wire is_full = (queue_cnt == OutputFiFoDepth)?1'b1:1'b0;
wire is_empty = (queue_cnt == 0)? 1'b1:1'b0;
reg fir_finish,fir_finish_next;
reg [32-1:0] queue [0:OutputFiFoDepth-1];
// wb_sender
reg ack_o_reg;
reg[31:0] data_o_reg; 

//***********//
//fsm        //
//***********//
always@*
    case(state)
        STRMOUT_IDLE:
            if(wbs_adr_i[7:0] == 8'h84 && ready)
                next_state = STRMOUT_RECV;
            else if(wbs_adr_i[7:0] == 8'h90 && ready)
                next_state = STRMOUT_CKEMPTY;
            else if(wbs_adr_i[7:0] == 8'h90 && valid)
                next_state = STRMOUT_WRITE;
            else
                next_state = STRMOUT_IDLE;
        STRMOUT_WRITE:
            next_state = STRMOUT_IDLE;
        STRMOUT_RECV:
            if(~is_empty & ~(~is_full & sm_tvalid))
                next_state = STRMOUT_IDLE;
            else
                next_state = STRMOUT_RECV;
        STRMOUT_CKEMPTY:
            next_state = STRMOUT_IDLE;
        default:
            next_state = STRMOUT_IDLE;
    endcase
always@(posedge wb_clk_i or posedge wb_rst_i)
    if(wb_rst_i)
        state <= STRMOUT_IDLE;
    else
        state <= next_state;

//*************//
//axis-receiver//
//*************//
assign sm_tready = ~is_full;
assign axis_valid = sm_tvalid;
assign axis_data = sm_tdata;
always@(posedge wb_clk_i or posedge wb_rst_i)
    if(wb_rst_i)
        fir_finish <= 1'b0;
    else
        fir_finish <= fir_finish_next;
always@*
    if((fir_finish & sm_tvalid & sm_tready) && queue_cnt!=5'd0  )
        fir_finish_next = 1'b0;
    else if((fir_finish & ready & wbs_ack_o) && queue_cnt == 5'd1)
        fir_finish_next = 1'b0;
    else
        fir_finish_next = fir_finish;
//***********//
//queue      //
//***********//
always@(posedge wb_clk_i or posedge wb_rst_i)
    if(wb_rst_i)
        queue_cnt <= 5'd0;
    else
        queue_cnt <= queue_cnt_next;
always@*
    if(sm_tvalid & sm_tready & ~fir_finish )
        queue_cnt_next = queue_cnt + 5'd1;
    else if(sm_tvalid & sm_tready & fir_finish )
        queue_cnt_next = 5'd1;
    else if(ready & wbs_ack_o &  wbs_adr_i[7:0] == 8'h84)
        queue_cnt_next = queue_cnt - 5'd1;
    else
        queue_cnt_next = queue_cnt;

integer IHateSOC;
integer shift_index;
always@(posedge wb_clk_i or posedge wb_rst_i)
    if(wb_rst_i) begin
        for(IHateSOC = 0; IHateSOC < OutputFiFoDepth; IHateSOC = IHateSOC + 1)
            queue[IHateSOC] <= 32'd0;
    end
    else begin
        for(IHateSOC = 0; IHateSOC < OutputFiFoDepth; IHateSOC = IHateSOC + 1)
            queue[IHateSOC] <= queue[IHateSOC];
        //輸出
        if(ready & wbs_ack_o &wbs_adr_i[7:0] == 8'h84 )begin
            for(shift_index = 1; shift_index < OutputFiFoDepth; shift_index = shift_index + 1)
                queue[shift_index-1] <= queue[shift_index];
                
            queue[OutputFiFoDepth-1] <= 32'd0;
        end
        else if ( sm_tvalid & sm_tready & ~fir_finish)
            queue[queue_cnt] <= axis_data;
        else if(sm_tvalid & sm_tready & fir_finish )
            queue[0] <= axis_data;
    end

//***********//
//axis-sender//
//***********//
assign wbs_dat_o = data_o_reg;
assign wbs_ack_o = ack_o_reg;
always@*
    case(state)
        STRMOUT_IDLE:
            ack_o_reg = 1'b0;
        STRMOUT_WRITE:
            ack_o_reg = 1'd1;
        STRMOUT_RECV:
            if(~is_empty & ~(~is_full & sm_tvalid))
                ack_o_reg = 1'b1;
            else
                ack_o_reg = 1'b0;
        STRMOUT_CKEMPTY:
            ack_o_reg = 1'b1;
        default:
            ack_o_reg = 1'b0;
    endcase
always@*
    case(state)
        STRMOUT_IDLE:
            data_o_reg = 32'd0;
        STRMOUT_RECV:
            if(~is_empty & ~(~is_full & sm_tvalid))
                data_o_reg = queue[0];
            else
                data_o_reg = 32'd0;
        STRMOUT_CKEMPTY:
            data_o_reg = {{31{1'b0}}, is_empty};
        default:
            data_o_reg = 32'd0;
    endcase
endmodule