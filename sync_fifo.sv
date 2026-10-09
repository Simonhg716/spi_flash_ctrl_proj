module sync_fifo #(
    parameter BITWID  = 8   ,
    parameter DEEPWID = 8 
)(
    //from upper logic
    input                     i_clk     ,
    input                     i_rst_n   ,
    input        [BITWID-1:0] i_wr_data ,
    input                     i_wr_en   ,
    input                     i_rd_en   ,

    //output

    output logic [BITWID-1:0] o_rd_data       ,//dout
    output logic              o_rd_data_valid ,
    output                    o_full          ,
    output                    o_empty         
);

localparam DEEP = 1 << DEEPWID ;

logic [DEEPWID-1:0] wr_ptr     ;
logic [DEEPWID-1:0] rd_ptr     ;

logic [DEEPWID:0]   wr_ptr_exp ;
logic [DEEPWID:0]   rd_ptr_exp ;

logic [BITWID-1:0] r_mem [DEEP-1:0] ;

assign wr_ptr = wr_ptr_exp[DEEPWID-1:0] ;
assign rd_ptr = rd_ptr_exp[DEEPWID-1:0] ;


//wr ptr
always_ff@(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        wr_ptr_exp <= '0;
    end
    else
    begin
        if(i_wr_en & !o_full)//删去了wr_ptr_exp<DEEP+DEEP-1这个条件，当超出范围会自动截掉最高位
        begin
            wr_ptr_exp <= wr_ptr_exp + 1'b1 ;
        end
    end
end

//rd_ptr
always_ff@(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        rd_ptr_exp <= '0 ;
    end
    else
    begin
        if(i_rd_en & !o_empty)
        begin
            rd_ptr_exp <= rd_ptr_exp + 1'b1 ;
        end
    end 
end

//full n empty
assign o_full  = (wr_ptr_exp[DEEPWID] != rd_ptr_exp[DEEPWID]) &&
                 (wr_ptr == rd_ptr) ;
assign o_empty = (wr_ptr_exp == rd_ptr_exp) ;

//wr data
always_ff@(posedge i_clk)
begin
    if(i_wr_en & !o_full)
      r_mem[wr_ptr] <= i_wr_data ;
end

//rd_data
always_ff@(posedge i_clk)
begin
    if(i_rd_en & !o_empty)
      o_rd_data <= r_mem[rd_ptr] ;
end

//rd_data_valid
always_ff@(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
      o_rd_data_valid <= 1'b0;
    else
      o_rd_data_valid <= i_rd_en && !o_empty ;
end

endmodule