library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;
use IEEE.std_logic_arith.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity SPI_Routine is 
  Port (
    --interfaces to PS, comuniaction via GPIO
    --data_in : in std_logic_vector (15 downto 0); -- data input form PS, MSB provide register adress in SPI slave and deterimnate is operation write or read (ref to master thesis or AXDL355 data sheet), LSB provide vallue which will be written to register when write operation is chosen
    data_out : out std_logic_vector (107 downto 0); -- transfer data obtained from sensor to PS,  this port can transmit any data from sensors depending on chosen adress, or data from X axis of sensor (depending on chosen mode)
    data_rdy : out std_logic;
	 
    -- clocks
    clk : in std_logic; -- 50MHz
    
    -- reset line
    rst: in std_logic;
    
    -- SPI interface  
    --miso : in std_logic_vector (3 downto 0);
	 miso : in std_logic;
    mosi : out std_logic;
    sclk : out std_logic := '0';
	 ss : out std_logic;
    --ss : out std_logic_vector (3 downto 0);

    --HW
	 buttons : in std_logic_vector(3 downto 0);
    leds : out std_logic_vector (19 downto 0);
	 memory_full : in std_logic

    
   );
end SPI_Routine;

architecture Behavioral of SPI_Routine is

  -- states of  SPI state machine
 type state is (st_idle, st0_txAddress, st1_txValue, st2_rxData, st3_rxMultiData, st4_rxAllAxis, st5_wait);
 signal present_state, next_state: state;-- one variable holds present state, second hold next state
 
 signal data_read: std_logic_vector(71 downto 0); -- buffer for data obtained via SPI,  to this signal bit after bit is wrriten from miso
 signal value: std_logic_vector(7 downto 0); -- signal holds value to be written to sensor register
 signal address: std_logic_vector(7 downto 0); -- this signal holds the address of register in sensor to be written or read
	
 signal mode: std_logic_vector(7 downto 0) := x"00"; --both signals for testing
 signal data_in : std_logic_vector (15 downto 0) := x"0000";

 constant max_length: natural:=65535; -- define maximal leangth in bits of data to be transmitet or recived by signle read or write request or define maximal number or clokcs for execution the longest state in state machine
 signal data_index: natural range 0 to max_length -1; -- count transmitted bits or received bits via spi (it is equal to counting numebr raising edges in clock)
 signal timer: natural range 0 to max_length; -- set limit for numeber of clocks in specifc state (eg. transmitting 8 bits -> timer =8, receiving 32 bits -> timer = 32 )
 signal clk_count: natural := 0; -- number of clock cycles counted since last sample
 signal count_flag: std_logic := '0'; -- enable of clock counting / init reset of count
  
 signal tmp : std_logic := '0';
 signal clk_divider: integer:=1; -- divider from 50MHz to spi clock
 signal clk_sig: std_logic := '0'; -- spi_clock

 
begin --architecture begins 

spi_clk_gen : process (clk)

	begin
		if(clk'event and clk='1') then
			clk_divider <=clk_divider+1;		
			if (clk_divider = 12) then
				tmp <= NOT tmp;
				clk_divider <= 1;
			end if;
		end if;
	clk_sig <= tmp;
	
	if count_flag = '1' then
		clk_count <= clk_count + 1;
	else
		clk_count <= 0;
	end if;
	
end process spi_clk_gen;


spi_com : process(clk_sig) --main process for SPI comunication

variable first_edge: std_logic; -- variables holds info, about raisnig and falling edge od clock
variable second_edge: std_logic;
variable virtual_clk: std_logic := '0';
variable enable_measurement : std_logic := '0';

   begin
        if rising_edge(clk_sig) then 
        
                virtual_clk := not virtual_clk; -- provide clock for SPI clock line
					 
					 if (buttons(0) = '0') then -- initialize sensor
						mode <= x"0F"; -- 0x05 for one byte read, 0x07 for 3 byte read, 0x0F for all axis read
						data_in <= x"5A06"; --enable measure mode on the sensor
 					 end if;
					 
					 if (buttons(1) = '0') then --measure 4k samples
						data_in <= x"1100"; --0x1100 x axis start for readout of all axes; adress for z-axis: 0x1D00
						enable_measurement := '1';
					 end if;
--					 
--					  if (buttons(2) = '0') then 
--					 end if;
--					 
--					 if (buttons(3) = '0') then
--					 end if;
--					 
                if (virtual_clk = '1') then
                first_edge := '1'; -- update edge info
                second_edge := '0';
                   if(data_index >= timer-1) then -- the if statments cntroll how long (how many clocks) process stays is in specific state, each state has diffrent time of execution
                           present_state <= next_state; -- jump to next state
                           data_index <= 0; --reset data index
									data_rdy <= '0';	
                     else
                            data_index <= data_index +1; -- else update data index
                     end if;
                else
                    first_edge := '0'; -- update edge info
                    second_edge := '1';   
                end if ;
                
          case present_state is -- begin state machine
            when st_idle =>  -- state idle , process do nothing and wait for permission to start comunnication
					 count_flag <= '0';
                sclk <= '0'; -- clock is disabled
                ss <= '1'; -- idle state of ss is high
                mosi<='X'; -- mosi undefined
                timer<=1;
                data_read <= (others => '0'); -- data read,  very important step
                address <= data_in (15 downto 8); -- get address of sensors register from PS (for both operations read and write)
                value <= data_in (7 downto 0); -- if writing to the sensor will be chosen, get value which will be written to sensor register, the value is get from PS  
					 if(mode (0) ='1') then -- chcek if SPI communication is enabled, mode is set from PS, 
                        next_state<= st0_txAddress; -- SPI enabled go to next state
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
                if(address (0) ='1') then -- in axdl355 last bit of adress define if it is write or read operatio (refer to axdl355 documentation)
                -- if read operation is chosen check mode to define if it is read of one byte, 3 bytes or 9 bytes and write to appropirate state
                   if mode (1) = '0' then 
                       next_state<= st2_rxData;
                   else
                       if (mode (3)= '0' ) then
                           next_state<= st3_rxMultiData;
                       else
                           next_state<= st4_rxAllAxis;
									count_flag <= '1'; --start couting clocks once full data acquistition is initated
                       end if;
                   end if;
                else -- if write operation is chosen jump to transmission state
                    next_state <= st1_txValue;
                end if;

                 
            when st1_txValue => -- state for writing one byte to chosen register in SPI slave device
                sclk <= virtual_clk;
                ss<='0';
                timer<=8;-- transmit one byte so timer is set to 8
                if (second_edge = '1') then -- in SPI mode 0 slave reads on rising edge but master change mosi on falling edge (refer to SPI documentation) 
                   mosi<= value(7- data_index);
                end if;
                next_state<= st5_wait;
                 
            when st2_rxData => -- state for reading one byte from the chosen register in SPI slave device
                sclk <= virtual_clk;
                mosi <= '0';
                ss<='0';
                timer<=8;-- read one byte so timer is set to 8
                if(first_edge = '1') then -- in SPI mode 0 master reads miso on rising edge (refer to SPI documentation)
                   data_read(7- data_index) <= miso;
                end if;
                next_state<= st5_wait;
                
            
            when st3_rxMultiData =>  -- state for reading 3 bytes, each reagister in adxl355 holds on byte data, the reading starts from the register chosen by addres, next the sensor autmaticlly iterate adding 1 to address after each itteration 
                sclk <= virtual_clk;
                mosi <= '0';
                ss<='0';
                timer<=24;-- read 3 bytes so timer is set to 24
                if(first_edge = '1') then -- in SPI mode 0 master reads miso on rising edge (refer to SPI documentation)
                   data_read(23 - data_index) <= miso;
                end if;
                next_state<= st5_wait;

                
            when st4_rxAllAxis =>-- state for reading 3 bytes, each reagister in adxl355 holds on byte data, the reading starts from the register chosen by addres, next the sensor automaticlly iterate adding 1 to address after each itteration 
                sclk <= virtual_clk;
                mosi <= '0';
                ss<='0';
                timer<=72;-- read 3 bytes so timer is set to 24
                if(first_edge = '1') then-- in SPI mode 0 master reads miso on rising edge (refer to SPI documentation)
                   data_read(71- data_index) <= miso;
                end if;
                next_state<= st5_wait;
            
                
            when st5_wait => -- after each request (read or write) the adxl355 have to wait for time specified in data sheet
                mosi <= '0';
                ss <= '1'; -- while waitng ss line has to be high
                sclk <= '0';
					 
					
					 if (mode (3)= '1' AND enable_measurement = '1' AND memory_full = '0') then --when measuring all axes
							timer <= 200;					 
							data_out(107 downto 36) <= data_read(71 downto 0);
							data_out(35 downto 0) <= conv_std_logic_vector(clk_count, 36);
							count_flag <= '0';
							data_rdy <= '1';
				    else
							timer <= 1;
					 end if;
					 
					 
					 if(memory_full = '1') then
						enable_measurement := '0';
						mode <= x"00";
						next_state <= st_idle;
					 end if;

                if (mode(2)='1') then -- depending on mode PS can set continus transmission or halt the tranmission after each write or read request      
                    next_state <= st_idle; -- jump to idle
                else
                    next_state<= st5_wait; -- else wait for permission from PS to continue SPI comunication
                end if;
                

            end case;
		  end if;
           
        
  
      
end process spi_com;

    
end Behavioral;


