-- Memory Controller

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;
use IEEE.std_logic_arith.all;


entity memory_controller is 
  Port (
  
  --INPUTS
  
  clk : in std_logic;
  data_in : in std_logic_vector(107 downto 0);
  data_rdy : in std_logic;
  
	--OUTPUTS
	
	address_out : out std_logic_vector(13 downto 0);
	wren_out : out std_logic;
	data_out : out std_logic_vector(107 downto 0);
	memory_full : out std_logic
    
   );
end memory_controller;

architecture Behavioral of memory_controller is

--signals

 signal tmp : std_logic := '0';
 signal clk_divider: integer:=1; -- divider from 50MHz to spi clock
 signal clk_div2: std_logic := '0'; -- spi_clock

 
begin --architecture begins 

slow_clk : process (clk)

	begin
		if(clk'event and clk='1') then
			clk_divider <= clk_divider+1;		
			if (clk_divider = 2) then
				tmp <= NOT tmp;
				clk_divider <= 1;
			end if;
		end if;
	clk_div2 <= tmp;
	
end process slow_clk;

logic : process(clk_div2)

--variables for logic
variable address_counter : natural range 0 to 16383 := 0;
variable clk_div4 : std_logic := '0';
variable flag : std_logic := '0';

	begin
	
		
		if rising_edge(clk_div2) then
		
			clk_div4 := NOT clk_div4;
			
			if data_rdy = '0' then
				flag := '0';
			end if;
			
			if data_rdy = '1' AND clk_div4 = '1' then
				address_out <= conv_std_logic_vector(address_counter, 14);
				data_out <= data_in;	
				wren_out <= '1';
			end if; --data_rdy
			
			if clk_div4 = '0' AND data_rdy = '1' AND flag = '0' then
				wren_out <= '0';
				flag := '1';
				if address_counter < 16383 then
					address_counter := address_counter + 1;
					memory_full <= '0';
				else
					memory_full <= '1';
					--address_counter := 0;
				end if; -- address overflow check
			end if; --clkdiv4


		end if; --rising edge
		
			
end process logic;



end Behavioral;