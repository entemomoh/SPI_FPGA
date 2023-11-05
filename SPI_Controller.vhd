----------------------------------------------------------------------------------
-- Author: Sven Thiele 
-- Contact: thiele61@gmx.de
-- 
-- Create Date: 10/17/2023 05:55:16 PM
-- Design Name: 
-- Module Name: SPI_Controller - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- SPI Controller for interfacing between the FPGA and SPI devices (sensors)
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;
use IEEE.std_logic_arith.all;

entity SPI_Controller is
Port ( 
    
    clk: in std_logic;
    enable_pin: in std_logic;
    data_out : out std_logic_vector (127 downto 0);
    data_rdy : out std_logic;
    
    miso : in std_logic;
    mosi : out std_logic;
    sclk : out std_logic := '0';
	ss : out std_logic;
	data_in : std_logic_vector (15 downto 0); -- initialize sensor
	
	byte_num : in std_logic_vector(3 downto 0) --how many byte should be transmitted or recieved?

);
end SPI_Controller;

architecture Behavioral of SPI_Controller is

  -- states of  SPI state machine
 type state is (st_idle, st0_txAddress, st1_txValue, st2_rxData, st3_wait);
 signal present_state, next_state: state;-- one variable holds present state, second hold next state
 
 signal data_read: std_logic_vector(63 downto 0); -- buffer for data obtained via SPI,  to this signal bit after bit is wrriten from miso
 signal value: std_logic_vector(7 downto 0); -- signal holds value to be written to sensor register
 signal address: std_logic_vector(7 downto 0); -- this signal holds the address of register in sensor to be written or read
	

 
 signal byte_num_int : integer := 1;

 constant max_length: natural:=65535; -- define maximal leangth in bits of data to be transmitet or recived by signle read or write request or define maximal number or clokcs for execution the longest state in state machine
 signal data_index: natural range 0 to max_length -1; -- count transmitted bits or received bits via spi (it is equal to counting numebr raising edges in clock)
 signal timer: natural range 0 to max_length; -- set limit for numeber of clocks in specifc state (eg. transmitting 8 bits -> timer =8, receiving 32 bits -> timer = 32 )
 signal clk_count: natural := 0; -- number of clock cycles counted since last sample
 signal count_flag: std_logic := '0'; -- enable of clock counting / init reset of count
  
 signal tmp : std_logic := '0';
 signal clk_divider: integer:= 25; -- divider from 100MHz to spi clock (1MHz)
 signal clk_sig: std_logic := '0'; -- spi_clock
 signal clk_div_counter: integer := 1;

 
begin --architecture begins 

spi_clk_gen : process (clk)

	begin
		if(clk'event and clk='1') then
			clk_div_counter <=clk_div_counter + 1;		
			if (clk_div_counter = clk_divider) then
				tmp <= NOT tmp;
				clk_div_counter <= 1;
			end if;
		end if;
	clk_sig <= tmp;
	
	if (count_flag = '1') then
		clk_count <= clk_count + 1;
	else
		clk_count <= 0;
	end if;
	
end process spi_clk_gen;

spi_comms : process(clk_sig) --main process for SPI comunication
variable first_edge: std_logic; -- variables holds info, about raisnig and falling edge of clock
variable second_edge: std_logic;
variable virtual_clk: std_logic := '0';
variable enable_measurement : std_logic := '0';

   begin
        if rising_edge(clk_sig) then 
        
                virtual_clk := not virtual_clk; -- provide clock for SPI clock line
					 				 
                if (virtual_clk = '1') then
                first_edge := '1'; -- update edge info
                second_edge := '0';
                   if(data_index >= timer-1) then -- the if statements controll how long (how many clocks) process stays is in specific state, each state has a different time of execution
                           present_state <= next_state; -- jump to next state
                           data_index <= 0; --reset data index
                     else
                            data_index <= data_index +1; -- else update data index
                     end if;
                else
                    first_edge := '0'; -- update edge info
                    second_edge := '1';   
                end if ;
                
          case present_state is -- begin state machine
            when st_idle =>  -- state idle , process do nothing and wait for permission to start comunnication
                sclk <= '0'; -- clock is disabled
                ss <= '1'; -- idle state of ss is high
                mosi<='X'; -- mosi undefined
                timer<=1;
                byte_num_int <= CONV_INTEGER(byte_num);
                data_read <= (others => '0'); -- data read,  very important step
                address <= data_in (15 downto 8); -- get address of sensors register from PS (for both operations read and write)
                value <= data_in (7 downto 0); -- if writing to the sensor will be chosen, get value which will be written to sensor register, the value is get from PS  
					 if(enable_pin = '1') then -- chcek if SPI communication is enabled, mode is set from PS, 
					    data_rdy <= '0';
                        next_state<= st0_txAddress; -- SPI enabled go to next state
                        count_flag <= '1';
                        ss <= '0'; -- ss goes low
                else
                    next_state<= st_idle; -- SPI disabled stay in idle
                end if; 
                
 
            when st0_txAddress => -- transmit addres of the register to SPI slave device
                sclk <= virtual_clk;
                ss <= '0'; -- ss goes low
                timer <= 8; -- addres has 8 bit therefore timer is set to 8
                if (second_edge = '1') then-- in SPI mode 0 slave reads on rising edge but master change mosi on falling edge (refer to SPI documentation)
                   mosi<= address(7- data_index);
                end if;
                if(address (7) = '1') then -- first address bit decides about read or write operation
                    next_state<= st2_rxData;
                    --next_state <= st1_txValue;
                else -- if write operation is chosen jump to transmission state
                    next_state <= st1_txValue;
                    --next_state<= st2_rxData;
                end if;

                 
            when st1_txValue => -- state for writing one byte to chosen register in SPI slave device
                sclk <= virtual_clk;
                ss<='0';
                timer<=8;-- transmit one byte so timer is set to 8
                if (second_edge = '1') then -- in SPI mode 0 slave reads on rising edge but master change mosi on falling edge (refer to SPI documentation) 
                   mosi<= value(7- data_index);
                end if;
                next_state<= st3_wait;
                 
            when st2_rxData => -- state for reading one byte from the chosen register in SPI slave device
                sclk <= virtual_clk;
                mosi <= '0';
                ss<='0';
                timer<=8 * byte_num_int;
                if(first_edge = '1') then -- in SPI mode 0 master reads miso on rising edge (refer to SPI documentation)
                   data_read((byte_num_int*8)- 1 - data_index) <= miso;
                end if;
                next_state<= st3_wait;
                
                
            when st3_wait => -- after each request (read or write) the adxl355 have to wait for time specified in data sheet
                mosi <= '0';
                ss <= '1'; -- while waitng ss line has to be high
                sclk <= '0';
                count_flag <= '0';
                byte_num_int <= CONV_INTEGER(byte_num);
                timer <= 625;
                data_out(63 downto 0) <= conv_std_logic_vector(clk_count,64);
                data_out(127 downto 64) <= data_read;
                --data_rdy <= '1';
					 
                if (enable_pin = '1') then -- depending on mode PS can set continus transmission or halt the tranmission after each write or read request      
                    next_state <= st_idle; -- jump to idle
                    data_rdy <= '1';
                else
                    next_state<= st3_wait; -- else wait for permission from PS to continue SPI comunication
                    data_rdy <= '0';
               end if;
                

            end case;
		  end if;
           
        
  
end process spi_comms;


end Behavioral;
