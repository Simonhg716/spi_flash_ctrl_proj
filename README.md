Profile:

  This project is designed for W25Q series flash chip, user can execute a several commands on pc with this design, 
  including "READ", "FAST_READ","WRITE" and "ERASE". In this project, we used the W25Q64 flash chip. 
  This design is composed of below submodules:
    1. ctrl_fsm.sv
    2. spi_master.sv
    3. uart_tx.sv
    4. uart_rx.sv
    5. sync_fifo.sv
  All these modules work within the same clock domain(i_clk, default frequency:50 MHz)

Profiles of submodules:

  1. ctrl_fsm.sv
     
     This is the most essential part in this design. It receives data from uart_rx module, distinguishes them with inner logic then sends them to spi_master module.
     There's a sync_fifo nested internally, which buffers data from uart_rx module.

     Brief overview:
       sync_fifo buffers fifo from uart_rx module, then it pulls the *empty* low, which function as an enable signal of the fsm(pushes its IDLE to switch).
       data order: cmd(1 byte) + addr(3 bytes) + (if)(rd/wr)len(2 bytes) + (if)data(*len* bytes)
       state line of commands:
       WRITE:
     IDLE --> CMD_FETCH --> ADDR_FETCH(REQ&WAIT) --> LEN_FETCH(REQ&WAIT) --> DATA_FETCH(REQ&WAIT) --> TRIGGER_MASTER --> WAIT_MASTER_BUSY-->                                 RD_STATUS(PRE,WAIT,CHECK&DELAY) --> SD_DONE
     
       READ/FAST_READ:
     IDLE --> CMD_FETCH --> ADDR_FETCH(REQ&WAIT) --> LEN_FETCH(REQ&WAIT) --> TRIGGER_MASTER --> WAIT_MASTER_BUSY --> WAIT_MASTER_DONE--> SD_DONE

       ERASE:
     IDLE --> CMD_FETCH --> ADDR_FETCH(REQ&WAIT) --> TRIGGER_MASTER --> WAIT_MASTER_BUSY --> RD_STATUS(PRE,WAIT,CHECK&DELAY) --> SD_DONE

     **NOTE** before ERASE and WRITE, user need to send 8'h06 as WREN commands, or the chip would ignore your commads and data
     
  2.spi_master.sv
  
    This is the secndary module in this design. In spi, master generate sclk, MOSI, cs_n and receive MISO from the chip
    For W25Q series chip, spi MODE 0/3 is surpported, which means 
     
