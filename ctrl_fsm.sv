module ctrl_fsm #(
    parameter CMD_READ      = 8'h03    ,//supported cmds
    parameter CMD_FAST_READ = 8'h0B    ,
    parameter CMD_WRITE     = 8'h02    , 
    parameter CMD_ERASE     = 8'h20    ,
    parameter CMD_RD_STATUS = 8'h05    ,
    parameter DELAY_MAX     = 16'd5000 
)
(
    //from system
    input               i_clk               ,
    input               i_rst_n             ,
    //with rx
    input        [7:0]  i_rx_byte           ,
    input               i_rx_byte_valid     ,//只要来了就要接受

    //back to uart_tx
    output logic        o_done              ,
    output logic [7:0]  o_done_byte         ,
    output logic        o_done_byte_valid   ,
    //with master (control only,not receiving rd_data)
    input        [7:0]  i_m_rd_byte         ,
    input               i_m_rd_byte_valid   ,
    input               i_m_wr_fifo_full    ,
    input               i_m_busy            ,
    output logic [15:0] o_m_rd_len          ,
    output logic        o_m_wr_en           ,
    output logic [23:0] o_m_addr            ,
    output logic [7:0]  o_m_cmd             ,
    output logic [7:0]  o_m_wr_data         ,
    output logic        o_m_start           ,
    output logic        o_status_read_active 

);

//inner signal
logic        r_rd_en         ;
logic [7:0]  r_rd_byte       ;
logic        r_rd_byte_valid ;
logic        r_rx_full       ;
logic        r_rx_empty      ;
logic [1:0]  r_len_cnt       ;
logic [16:0] r_data_cnt      ;
logic        rd_fifo_wr_en   ;
logic        r_byte_pending  ;


/*
fifo buffer all the data from uart_rx
and wait for the fsm to fetch
(ofc fifo in its !empty)
*/
sync_fifo #(
    .BITWID  (8) ,
    .DEEPWID (8) 
)rx_fifo (
    //from sys
    .i_clk               (i_clk)           ,
    .i_rst_n             (i_rst_n)         ,
    //with UART_RX
    .i_wr_data           (i_rx_byte)       ,
    .i_wr_en             (i_rx_byte_valid) ,
    .o_full              (r_rx_full)       ,
    //with ctrl fsm
    .o_rd_data           (r_rd_byte)       ,
    .o_rd_data_valid     (r_rd_byte_valid) ,
    .i_rd_en             (r_rd_en)         ,
    .o_empty             (r_rx_empty)
);

typedef enum logic [3:0]{
    IDLE             ,
    CMD_FETCH        ,//fetch cmd from fifo
    ADDR_FETCH_REQ   ,//fetch addr from fifo
    ADDR_FETCH_WAIT  ,
    LEN_FETCH_REQ    ,
    LEN_FETCH_WAIT   ,
    DATA_FETCH_REQ   ,
    DATA_FETCH_WAIT  ,
    RD_STATUS_PRE    ,
    RD_STATUS_WAIT   ,
    RD_STATUS_CHECK  ,
    RD_STATUS_DELAY  ,
    TRIGGER_MASTER   ,
    WAIT_MASTER_BUSY ,
    WAIT_MASTER_DONE ,
    SD_DONE        
}state_t;

state_t state ;

logic   [23:0] r_addr  ;
logic   [15:0] r_len     ;
logic   [1:0]  addr_cnt  ;
logic   [7:0]  r_cmd     ;
logic   [15:0] delay_cnt ;
logic          r_wip     ;

/*data from uart*/

always_ff@(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        state                <= IDLE ;
        r_addr               <= '0   ;
        r_len                <= '0   ;
        r_cmd                <= '0   ;
        addr_cnt             <= '0   ;
        r_len_cnt            <= '0   ;
        r_data_cnt           <= '0   ;
        delay_cnt            <= '0   ;
        r_wip                <= '0   ;
        r_rd_en              <= '0   ;
        o_done               <= '0   ;
        o_m_start            <= '0   ;
        o_m_wr_en            <= '0   ;
        o_status_read_active <= '0   ;
        r_byte_pending       <= '0   ;
    end
    else
    begin
        case(state)
        IDLE:
        begin
            r_rd_en           <= 1'b0 ;
            o_done            <= '0   ;
            o_done_byte_valid <= '0   ;
            if(!r_rx_empty)
            begin
                r_rd_en  <= 1'b1      ;
                state    <= CMD_FETCH ;
            end
        end
        CMD_FETCH:
        begin
            r_rd_en <= 1'b0;
            if(r_rd_byte_valid)
            begin
                r_cmd <= r_rd_byte      ;
                state <= ADDR_FETCH_REQ ;
                addr_cnt <= '0          ;
            end
        end
        ADDR_FETCH_REQ:
        begin
            if(!r_rx_empty)
            begin
                r_rd_en <= 1'b1            ;
                state   <= ADDR_FETCH_WAIT ;
            end
        end
        ADDR_FETCH_WAIT:
        begin
            r_rd_en <= 1'b0;
            if(r_rd_byte_valid)
            begin
                r_addr <= {r_addr[15:0],r_rd_byte} ;
                if(addr_cnt == 2)
                begin
                    state     <= (r_cmd == CMD_ERASE)?TRIGGER_MASTER:LEN_FETCH_REQ ;
                    addr_cnt  <= '0 ;
                    r_len_cnt <= '0 ;
                end
                else
                begin
                    addr_cnt <= addr_cnt + 1'b1 ;
                    state    <= ADDR_FETCH_REQ  ; 
                end
            end
        end
        LEN_FETCH_REQ:
        begin
            if(!r_rx_empty)
            begin
                r_rd_en <= 1'b1           ;
                state   <= LEN_FETCH_WAIT ;
            end
        end
        LEN_FETCH_WAIT:
        begin
            r_rd_en <= 1'b0;
            if(r_rd_byte_valid)
            begin
                r_len <= {r_len[7:0],r_rd_byte} ;
                if(r_len_cnt == 1)
                begin
                    r_len_cnt <= '0;
                    state   <= (r_cmd == CMD_WRITE)?DATA_FETCH_REQ:TRIGGER_MASTER;
                end
                else
                begin
                    r_len_cnt <= r_len_cnt + 1'b1 ;
                    state     <= LEN_FETCH_REQ    ;
                end
            end
        end
        DATA_FETCH_REQ:
        begin
            if(!r_rx_empty)
            begin
                r_rd_en <= 1'b1            ;
                state   <= DATA_FETCH_WAIT ;
            end
            else
              o_m_wr_en <= 1'b0;
        end
        DATA_FETCH_WAIT:
        begin
            r_rd_en   <= 1'b0 ;
            o_m_wr_en <= 1'b0 ;
            if(r_rd_byte_valid || r_byte_pending)
            begin
                r_byte_pending <= 1'b1;
                if(!i_m_wr_fifo_full)
                begin
                    o_m_wr_data    <= r_rd_byte ;
                    o_m_wr_en      <= 1'b1      ;
                    r_byte_pending <= 1'b0      ;
                    if(r_data_cnt == r_len - 1'b1)
                    begin
                        r_data_cnt <= '0             ;
                        state      <= TRIGGER_MASTER ;

                    end
                    else
                    begin
                        r_data_cnt <= r_data_cnt + 1'b1 ;
                        state      <= DATA_FETCH_REQ    ;
                    end
                end
            end
        end
        RD_STATUS_PRE:
        begin
            o_status_read_active <= 1'b1             ;
            o_m_cmd              <= CMD_RD_STATUS    ;
            o_m_rd_len           <= 1'b1             ;
            o_m_start            <= 1'b1             ;
            state                <= RD_STATUS_WAIT   ;
        end
        RD_STATUS_WAIT:
        begin
            o_m_start <= 1'b0;
            if(i_m_rd_byte_valid)
            begin
                r_wip <= i_m_rd_byte[0]    ;
                state <= RD_STATUS_CHECK ;
            end
        end
        RD_STATUS_CHECK:
        begin
            if(r_wip)
              state <= RD_STATUS_DELAY ;
            else
            begin
                state <= SD_DONE;
                o_status_read_active <= '0;
            end
        end
        RD_STATUS_DELAY:
        begin
            if(delay_cnt == DELAY_MAX - 1'd1)
            begin
                state     <= RD_STATUS_PRE ;
                delay_cnt <= '0;
            end
            else
            begin
                delay_cnt <= delay_cnt + 1'b1;
            end
        end
        TRIGGER_MASTER:
        begin
            o_m_cmd          <= r_cmd            ;          
            o_m_addr         <= r_addr           ; 
            if(r_cmd == CMD_READ || r_cmd == CMD_FAST_READ)
            begin        
            o_m_rd_len       <= r_len            ;//send len while it's READ transaction     
            end     
            o_m_start        <= 1'b1             ;  
            o_m_wr_en        <= 1'b0             ;         
            state            <= WAIT_MASTER_BUSY ;
        end
        WAIT_MASTER_BUSY:
        begin
            o_m_start        <= 1'b0             ;
            if(i_m_busy)//This state is make sure that the master was indeed busy once!!!
              state          <= WAIT_MASTER_DONE ;
        end
        WAIT_MASTER_DONE:
        begin
            if(!i_m_busy)
            begin
                if(r_cmd == CMD_ERASE ||r_cmd == CMD_WRITE)
                  state <= RD_STATUS_PRE;
                else
                  state <= SD_DONE;
            end
        end
        SD_DONE:
        begin
            state             <= IDLE  ;
            o_done            <= 1'b1  ;
            o_done_byte       <= 8'hAA ;
            o_done_byte_valid <= 1'b1  ;
        end
        default: state <= IDLE ;
        endcase
    end  
end

endmodule
