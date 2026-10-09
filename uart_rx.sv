module uart_rx #(
    parameter CLK_FREQ = 50_000_000 ,
    parameter UART_BPS = 115200     
)(
    input              i_clk            ,
    input              i_rst_n          ,
    //from pc
    input              i_rxd            ,
    //
    output logic [7:0] o_rx_byte        ,
    output logic       o_rx_byte_valid 
);
localparam BAUD_MAX = CLK_FREQ / UART_BPS;

logic        r0_rxd     ;
logic        r1_rxd     ;
logic        r2_rxd     ;
logic        r_rx_busy  ;//keep high during working
logic [15:0] r_baud_cnt ;
logic [3:0]  r_num_cnt  ;
logic [7:0]  r_rx_byte  ;
logic        w_rx_en    ;
assign       w_rx_en = (~r1_rxd && r2_rxd) && (~r_rx_busy);

//cdc
always_ff @(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        r0_rxd <= '0 ;
        r1_rxd <= '0 ;
        r2_rxd <= '0 ;
    end
    else
    begin
        r0_rxd <= i_rxd  ;
        r1_rxd <= r0_rxd ;
        r2_rxd <= r1_rxd ;
    end
end
//baud_cnt
always_ff@(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        r_baud_cnt <= '0;
    end
    else if(r_rx_busy)
    begin
        if(r_baud_cnt == BAUD_MAX - 1'b1)
          r_baud_cnt <= '0;
        else
          r_baud_cnt <= r_baud_cnt + 1'b1;
    end
    else
      r_baud_cnt <= '0;
end
//num_cnt
always_ff@(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        r_num_cnt <= '0;
    end
    else if(r_rx_busy)
    begin
        if(r_num_cnt == 'd9 && r_baud_cnt == BAUD_MAX - 1'b1)
          r_num_cnt <= '0;
        else if(r_baud_cnt == BAUD_MAX - 1'b1)
          r_num_cnt <= r_num_cnt + 1'b1;
    end
    else
      r_num_cnt <= '0 ;
end
//busy
always_ff@(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
      r_rx_busy <= '0 ;
    else if(w_rx_en)
      r_rx_busy <= '1 ;
    else if(r_baud_cnt == BAUD_MAX/2 - 1'b1 && r_num_cnt == 'd9)
      r_rx_busy <= '0 ;
    else
      r_rx_busy <= r_rx_busy ;
end

//rcv data

always_ff@(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
      r_rx_byte <= '0;
    else if(r_baud_cnt == BAUD_MAX/2 - 1'b1)
    begin
        case(r_num_cnt)
        4'd1:r_rx_byte[0] <= r2_rxd ;
        4'd2:r_rx_byte[1] <= r2_rxd ;
        4'd3:r_rx_byte[2] <= r2_rxd ;
        4'd4:r_rx_byte[3] <= r2_rxd ;
        4'd5:r_rx_byte[4] <= r2_rxd ;
        4'd6:r_rx_byte[5] <= r2_rxd ;
        4'd7:r_rx_byte[6] <= r2_rxd ;
        4'd8:r_rx_byte[7] <= r2_rxd ;
        default:;
        endcase
    end
    else
      r_rx_byte <= r_rx_byte ;
end

always_ff@(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        o_rx_byte       <= '0 ;
        o_rx_byte_valid <= '0 ;
    end
    else if((r_num_cnt == 'd9) && (r_baud_cnt == BAUD_MAX/2 - 1'b1))
    begin
        o_rx_byte       <= r_rx_byte ;
        o_rx_byte_valid <= '1        ;
    end
    else
    begin
        o_rx_byte       <= o_rx_byte ;
        o_rx_byte_valid <= '0        ;
    end
end

endmodule