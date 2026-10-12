module top_module(
    //system
    input        i_clk   ,
    input        i_rst_n ,
    //with pc
    input        i_rxd   ,
    output logic o_txd   ,
    //with slave
    input        MISO    ,
    output logic MOSI    ,
    output logic o_CS_n  ,
    output logic o_sclk 
);

logic status_rd_active ;
logic c_done;
logic tx_busy;

// 声明区加一根线
logic m_rd_byte_valid_to_tx ;

// ctrl_fsm例化完之后,加这一行组合逻辑
// RD_STATUS轮询期间的回传字节,绝不能流向PC
assign m_rd_byte_valid_to_tx = m_rd_byte_valid & ~status_rd_active;

//wires in modules
//master and ctrl_fsm
//use the m/c to describe the source of the signal
logic [7:0]  m_rd_byte         ;//1 master with tx
logic        m_rd_byte_valid   ;//2
logic        m_wr_fifo_full    ;
logic        m_busy            ;
logic [15:0] c_rd_len          ;
logic [23:0] c_addr            ;
logic [7:0]  c_cmd             ;
logic [7:0]  c_wr_data         ;
logic        c_wr_en           ;
logic        c_start           ;

//rx with ctrl_fsm
logic [7:0]  rx_byte           ;
logic        rx_byte_valid     ;

//ctrl_fsm with tx
logic [7:0]  c_done_byte       ;
logic        c_done_byte_valid ;


//instantiation of all modules
//spi_master
spi_master #(
    .SPI_MODE    (0)  ,
    .CLK_DIV     (25) ,
    .DUMMY_CYCLE (8)
)spi_flash_master( 
    .i_clk           (i_clk)             ,
    .i_rst_n         (i_rst_n)           ,
    //ctrl_fsm to master
    .i_start         (c_start)           ,
    .i_cmd           (c_cmd)             ,
    .i_addr          (c_addr)            ,
    .i_wr_data       (c_wr_data)         ,
    .i_rd_bytes_num  (c_rd_len)          ,
    .i_wr_en         (c_wr_en)           ,
    //master to ctrl_fsm / tx
    .o_rd_byte       (m_rd_byte)         ,
    .o_rd_byte_valid (m_rd_byte_valid)   ,//to tx and ctrl_fsm
    .o_busy          (m_busy)            ,
    .o_wr_fifo_full  (m_wr_fifo_full)    ,
    //with slave
    .o_CS_n          (o_CS_n)            ,
    .o_sclk          (o_sclk)            ,
    .MOSI            (MOSI)            ,
    .MISO            (MISO)
);

//ctrl_fsm
ctrl_fsm spi_flash_ctrl_fsm(
    .i_clk                (i_clk)            ,
    .i_rst_n              (i_rst_n)          ,
    //from rx
    .i_rx_byte            (rx_byte)        ,
    .i_rx_byte_valid      (rx_byte_valid)  ,
    //expose
    .o_done               (c_done),
    //to tx
    .o_done_byte          (c_done_byte)    ,
    .o_done_byte_valid    (c_done_byte_valid)   ,
    //with master
    .i_m_rd_byte          (m_rd_byte)        ,
    .i_m_rd_byte_valid    (m_rd_byte_valid)  ,
    .i_m_wr_fifo_full     (m_wr_fifo_full)   ,
    .i_m_busy             (m_busy)           , 
    .o_m_rd_len           (c_rd_len)   ,
    .o_m_wr_en            (c_wr_en)          ,
    .o_m_addr             (c_addr)           ,
    .o_m_cmd              (c_cmd)            ,
    .o_m_wr_data          (c_wr_data)        ,
    .o_m_start            (c_start)          ,
    //expose
    .o_status_read_active (status_rd_active)
);

//uart_tx
uart_tx #(
    .CLK_FREQ(50_000_000) ,
    .UART_BPS(115200)    
)spi_flash_uart_tx(
    .i_clk               (i_clk)                   ,
    .i_rst_n             (i_rst_n)                 ,
    //from master
    .i_m_rd_byte         (m_rd_byte)               ,
    .i_m_rd_byte_valid   (m_rd_byte_valid_to_tx)   ,
    //from ctrl_fsm
    .i_c_done_byte       (c_done_byte)             ,
    .i_c_done_byte_valid (c_done_byte_valid)       ,
    //to pc
    .o_txd               (o_txd)                   ,
    //expose
    .o_tx_busy           (tx_busy)
);

//uart_rx
uart_rx #(
    .CLK_FREQ(50_000_000),
    .UART_BPS(115200)
)spi_flash_uart_rx(
    .i_clk           (i_clk)           ,
    .i_rst_n         (i_rst_n)         ,
    //from pc
    .i_rxd           (i_rxd)           ,
    //to ctrl_fsm
    .o_rx_byte       (rx_byte)       ,
    .o_rx_byte_valid (rx_byte_valid)
);

endmodule
