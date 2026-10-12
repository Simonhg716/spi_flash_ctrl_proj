module spi_master
#(
    parameter SPI_MODE      = 0     ,
    parameter CLK_DIV       = 25    ,//SCLK分频数，2-->4分频
    parameter DUMMY_CYCLE   = 8     ,//dummy cycle num
    parameter CMD_READ      = 8'h03 ,//supported cmds
    parameter CMD_FAST_READ = 8'h0B ,
    parameter CMD_WRITE     = 8'h02 , 
    parameter CMD_ERASE     = 8'h20 ,
    parameter CMD_RD_STATUS = 8'h05 
)
(
    input               i_clk           ,
    input               i_rst_n         ,
    //FPGA upper logic to master
    input               i_start         ,//enable signal informs the whole module to start working
    input        [7:0]  i_cmd           ,
    input        [23:0] i_addr          ,
    input        [7:0]  i_wr_data       ,//input to fifo
    input        [15:0] i_rd_bytes_num  ,
    input               i_wr_en         ,//work with wr_data
    //master to FPGA upper logic
    output logic [7:0]  o_rd_byte       ,
    output logic        o_rd_byte_valid ,
    output              o_busy          ,//?
    output              o_wr_fifo_full  ,
    //master & slave
    input  logic        MISO            ,
    output logic        MOSI            ,
    output              o_CS_n          ,
    output logic        o_sclk
);


logic  CPOL ;
logic  CPHA ;

assign CPOL = SPI_MODE?1:0 ;
assign CPHA = SPI_MODE?1:0 ;


//sclk generate
//clk_div = 4
logic [1:0] div_cnt  ;
logic       sclk_run ;
always_ff @(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        o_sclk  <= CPOL         ;
        div_cnt <= '0           ;
    end
    else if(o_CS_n || !sclk_run)
    begin
        o_sclk  <= CPOL         ;
        div_cnt <= '0           ;
    end
    else if(div_cnt == CLK_DIV - 1)
    begin
        o_sclk  <= ~ o_sclk     ;
        div_cnt <= '0           ;
    end
    else
        div_cnt <= div_cnt + 1  ;
end

wire sclk_posedge_pulse     , 
     sclk_negedge_pulse     , 
     sample_edge_pulse      ,
     shift_edge_pulse       ;
logic        rd_en          ;//rd enable
logic [7:0]  r_dout         ;//wr_data(buffer)
logic        empty          ;//wr_fifo empty
logic        r_rd_valid     ;

/*think about the o_CS_n signal
It's not a necessary condition 
  for these assignments
But we still keep it in case
  people set the CLK_DIV = 1 
*/
assign sclk_posedge_pulse = (div_cnt == CLK_DIV-1) && !o_CS_n && !o_sclk;// be about to flip and the current level is low
assign sclk_negedge_pulse = (div_cnt == CLK_DIV-1) && !o_CS_n &&  o_sclk;//be opposite to above
assign sample_edge_pulse  = sclk_posedge_pulse;
assign shift_edge_pulse   = sclk_negedge_pulse;

//FSM part define
typedef enum logic[3:0]{
    IDLE          ,
    CMD_RCV       ,
    CMD_SD        ,
    ADDR_SD       ,
    DATA_SD       ,
    DATA_RCV      ,
    DATA_RCV_WAIT ,
    DATA_RD       ,
    DUMMY         ,
    DONE
} state_t;

state_t state ;
assign sclk_run = (state == CMD_SD)  || (state == ADDR_SD) || (state == DUMMY) ||
                  (state == DATA_SD) || (state == DATA_RD);

//intantiation of sync_fifo
/*
for cmd & addr
use flip_flop to latch their values
but for wr_data
we use fifo to act as a buffer
which makes the transfer more smooth and reliable
*/   

sync_fifo #(
    .BITWID(8),
    .DEEPWID(8)
)wr_fifo_in_master
(
    //upper logic
    .i_clk           (i_clk)          ,
    .i_rst_n         (i_rst_n)        ,
    .i_wr_data       (i_wr_data)      ,
    .i_wr_en         (i_wr_en)        ,
    .i_rd_en         (rd_en)          ,

    //
    .o_rd_data       (r_dout)         ,
    .o_rd_data_valid (r_rd_valid)     ,
    .o_full          (o_wr_fifo_full) ,
    .o_empty         (empty)
) ;

logic [7:0]  cmd_shift_r    ;
logic [23:0] addr_shift_r   ;
logic [7:0]  rd_shift_r     ;
logic [7:0]  wr_shift_r     ;
logic [4:0]  r_bit_cnt      ;
logic [15:0] rd_bytes_cnt   ;
logic [23:0] r_addr         ;
logic [7:0]  r_cmd          ;
logic [15:0] r_len          ;//rd_num reg


always_ff @(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        state           <= IDLE ;
        r_bit_cnt       <= '0   ;
        cmd_shift_r     <= '0   ;
        addr_shift_r    <= '0   ;
        rd_shift_r      <= '0   ;
        wr_shift_r      <= '0   ;
        rd_bytes_cnt    <= '0   ;
        r_addr          <= '0   ;
        r_cmd           <= '0   ;
        r_len           <= '0   ;
        rd_en           <= '0   ;
        o_rd_byte       <= '0   ;
        o_rd_byte_valid <= '0   ;
    end
    else
    begin
        o_rd_byte_valid <= '0 ;//默认每个主时钟周期清零 o_rd_byte_valid，确保单周期
        if(state == IDLE)
        begin
            if(i_start)
            begin
                state  <= CMD_RCV        ;
                r_cmd  <= i_cmd          ;
                r_addr <= i_addr         ;
                r_len  <= i_rd_bytes_num ;//if i_start latch the cmd,addr and rd_num state switch to CMD_RCV
            end
        end

        else if(state == CMD_RCV)
        begin
            cmd_shift_r <= r_cmd  ;
            state       <= CMD_SD ;
        end

        else if(state == DATA_RCV)
        begin
            rd_en <= 1'b1          ;
            state <= DATA_RCV_WAIT ;
        end
        else if(state == DATA_RCV_WAIT)
        begin
            rd_en <= '0 ;
            if(r_rd_valid)
            begin
                state      <= DATA_SD ;
                wr_shift_r <= r_dout  ;
            end
        end

        else if(state == DONE)//单独拆出来
        begin
            state <= IDLE ;
        end

        //-------shift status------execute each sclk sample edge----------//
        else if(sample_edge_pulse)
        begin
            case(state)
            CMD_SD :
            begin
                if(r_bit_cnt == 7)
                begin
                    r_bit_cnt   <= '0     ;
                    if(r_cmd == CMD_RD_STATUS)
                    begin
                        state <= DATA_RD ;
                    end
                    else if(r_cmd == 8'h06)
                    begin
                        state <= DONE ;
                    end
                    else
                    begin
                        state        <= ADDR_SD ;
                        addr_shift_r <= r_addr  ;
                    end
                end
                else
                begin
                    r_bit_cnt   <= r_bit_cnt + 1'b1 ;
                    cmd_shift_r <= cmd_shift_r << 1  ;
                end
            end
            ADDR_SD:
            begin
                if(r_bit_cnt == 23)
                begin
                    case(r_cmd)
                    CMD_READ     : state <= DATA_RD  ;
                    CMD_WRITE    : state <= DATA_RCV ; 
                    CMD_ERASE    : state <= DONE     ;
                    CMD_FAST_READ: state <= DUMMY    ;
                    default      : state <= DONE     ;
                    endcase
                    r_bit_cnt <= '0 ;
                end
                else
                begin
                    r_bit_cnt <= r_bit_cnt + 1'b1     ;
                    addr_shift_r <= addr_shift_r << 1 ;
                end
            end
            DUMMY:
            begin
                if(r_bit_cnt == DUMMY_CYCLE - 1)
                begin
                    state     <= DATA_RD ;
                    r_bit_cnt <= '0      ;
                end
                else
                    r_bit_cnt <= r_bit_cnt + 1'b1 ;
            end
            DATA_RD:
            begin
                rd_shift_r <= {rd_shift_r[6:0],MISO} ;
                if(r_bit_cnt == 7)
                begin
                    r_bit_cnt       <= '0                     ;
                    o_rd_byte_valid <= 1'b1                   ;
                    o_rd_byte       <= {rd_shift_r[6:0],MISO} ;
                    if(rd_bytes_cnt == r_len - 1)
                    begin
                        state        <= DONE ;
                        rd_bytes_cnt <= '0   ;
                    end
                    else
                    begin
                        rd_bytes_cnt <= rd_bytes_cnt + 1'b1 ;
                    end
                end
                else
                begin
                    r_bit_cnt       <= r_bit_cnt + 1'b1 ;
                    o_rd_byte_valid <= 1'b0             ;
                end
            end
            DATA_SD:
            begin
                if(r_bit_cnt == 7)
                begin
                    r_bit_cnt <= '0 ;
                    if(empty)
                      state <= DONE ;
                    else
                      state <= DATA_RCV ;
                end
                else
                begin
                    r_bit_cnt  <= r_bit_cnt + 1'b1 ;
                    wr_shift_r <= wr_shift_r << 1  ;
                end
            end
            default: state <= IDLE ;
            endcase
        end
    end
end

//MOSI
always_ff @(posedge i_clk or negedge i_rst_n)
begin
    if(!i_rst_n)
    begin
        MOSI <= '0;
    end
    else if(state == DATA_RCV_WAIT && r_rd_valid)
    begin
        MOSI <= r_dout[7] ;
    end
    else if(state == CMD_RCV)
    begin
        MOSI <= r_cmd[7] ;  //work for MODE 0,send the first word out ahead of the first posedge
    end
    else if(shift_edge_pulse)
    begin
        case(state)
        CMD_SD:  MOSI <= cmd_shift_r[7]   ;
        ADDR_SD: MOSI <= addr_shift_r[23] ;
        DATA_SD: MOSI <= wr_shift_r[7]    ;
        default: MOSI <= 1'b0             ;
        endcase
    end
end

//cs_n 
assign o_CS_n = (state == IDLE)?1:0 ;
assign o_busy = (state == IDLE)?0:1 ;

endmodule
