module uart_tx #(
    parameter CLK_FREQ = 50_000_000 , //50MHz
    parameter UART_BPS = 115200     
)(
    input              i_clk               ,
    input              i_rst_n             ,
    //from master
    input        [7:0] i_m_rd_byte         ,
    input              i_m_rd_byte_valid   ,
    //from ctrl_fsm
    input        [7:0] i_c_done_byte       ,
    input              i_c_done_byte_valid ,
    //to PC
    output logic       o_txd               ,
    //feedback
    output logic       o_tx_busy          
);
localparam BAUD_MAX = CLK_FREQ/UART_BPS ;
logic [2:0]  bit_cnt         ;
logic [7:0]  r_tx_byte       ;//latch data 
logic [3:0]  r_tx_posi       ;
logic [15:0] r_baud_cnt      ;

logic        tx_fifo_full    ;//can be extended to a output port later
logic        tx_fifo_empty   ;
logic        wr_en           ;
logic        rd_en           ;
logic [7:0]  wr_tx_fifo_data ;
logic [7:0]  rd_tx_fifo_data ;  
logic        tx_fifo_rdv     ;


assign rd_en = (~tx_fifo_empty) & (~o_tx_busy) & (~tx_fifo_rdv);
//if necessary?
assign wr_en           = (((i_c_done_byte_valid) || (i_m_rd_byte_valid)) && (!tx_fifo_full))?1:0;
assign wr_tx_fifo_data = (i_c_done_byte_valid) ? i_c_done_byte : i_m_rd_byte ;

sync_fifo #(
    .BITWID(8),
    .DEEPWID(8)
)tx_fifo(
    .i_clk          (i_clk)            ,
    .i_rst_n        (i_rst_n)          ,

    .i_wr_en         (wr_en)           ,
    .i_wr_data       (wr_tx_fifo_data) ,
    .o_full          (tx_fifo_full)    ,

    .i_rd_en         (rd_en)           ,
    .o_rd_data       (rd_tx_fifo_data) ,
    .o_rd_data_valid (tx_fifo_rdv)     ,
    .o_empty         (tx_fifo_empty)
);


//bps div
always_ff @(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        r_baud_cnt <= '0;
    end
    else if(o_tx_busy)
    begin
        if(r_baud_cnt == BAUD_MAX - 1'b1)
          r_baud_cnt <= '0                ;
        else
          r_baud_cnt <= r_baud_cnt + 1'b1 ;
    end
    else
      r_baud_cnt <= '0;
end

//posi cnt
always_ff @(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        r_tx_posi <= '0;
    end
    else if(o_tx_busy)
    begin
        if(r_baud_cnt == BAUD_MAX - 1'b1)
          r_tx_posi <= r_tx_posi + 1'b1;
    end
    else
      r_tx_posi <= '0;
end

//latch data
//busy
always_ff@(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        o_tx_busy <= '0 ;
    end
    else if(tx_fifo_rdv && !o_tx_busy)
    begin
        o_tx_busy <= '1              ;
        r_tx_byte <= rd_tx_fifo_data ;
    end
    else if(r_tx_posi == 'd9 && r_baud_cnt == BAUD_MAX - 1'b1)
    begin
        o_tx_busy <= '0 ;
        r_tx_byte <= '0 ;
    end
    else
    begin
        o_tx_busy <= o_tx_busy ;
        r_tx_byte <= r_tx_byte ;
    end
end

always_ff@(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        o_txd <= 1'b1 ;
    end
    else if(o_tx_busy)
    begin
        case(r_tx_posi)
        4'd0   : o_txd <= 1'b0         ;
        4'd1   : o_txd <= r_tx_byte[0] ;
        4'd2   : o_txd <= r_tx_byte[1] ;
        4'd3   : o_txd <= r_tx_byte[2] ;
        4'd4   : o_txd <= r_tx_byte[3] ;
        4'd5   : o_txd <= r_tx_byte[4] ;
        4'd6   : o_txd <= r_tx_byte[5] ;
        4'd7   : o_txd <= r_tx_byte[6] ;
        4'd8   : o_txd <= r_tx_byte[7] ;
        4'd9   : o_txd <= 1'b1         ;
        default: o_txd <= 1'b1         ;
        endcase
    end
    else
      o_txd <= 1'b1 ;
end
endmodule