--debugger for LEDS

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;
use IEEE.std_logic_arith.all;


entity debugger is 
  Port (
  
  --INPUTS
  
  address : in std_logic_vector(13 downto 0);
  data_in : in std_logic_vector(107 downto 0);
  clk : in std_logic;
  
	--OUTPUTS
	
	led_out : out std_logic_vector (19 downto 0)
    
   );
end debugger;

architecture Behavioral of debugger is

--signals

 
begin --architecture begins 

logic : process(clk)

--variables for logic

	begin
	
	if rising_edge(clk) AND address = "00000000000001" then
		led_out <= data_in(23 downto 4);
	end if;
	
		
			
end process logic;



end Behavioral;