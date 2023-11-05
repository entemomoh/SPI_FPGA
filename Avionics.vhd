----------------------------------------------------------------------------------
-- Author: Sven Thiele
-- 
-- Create Date: 22.09.2023 14:12:54
-- Design Name: 
-- Module Name: Avionics - Behavioral
-- Project Name: 
-- Target Devices: PYNQ
-- Tool Versions: 
-- Description: 
-- This module provides function for the Avionics sensors on the Pioneer EM 
--
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;
use IEEE.std_logic_arith.all;
use ieee.numeric_std.all;  

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Avionics is
Port ( 
 
 --inputs
 clk : in std_logic;
 light_sensor_in : in std_logic_vector (3 downto 0);
 gyro_data_in : in std_logic_vector(127 downto 0);
 data_rdy_in : in std_logic;
 
 --outputs
 light_sensor_out : out std_logic_vector (3 downto 0);
 gyro_data_out : out std_logic_vector(15 downto 0); -- output gyro data
 byte_num : out std_logic_vector(3 downto 0);
 gyro_enable : out std_logic;
 RW_enable : out std_logic
 
 
 );
end Avionics;

architecture Behavioral of Avionics is

 signal gyro_data_buf : std_logic_vector(63 downto 0);
 signal gyro_clock_buf : std_logic_vector(63 downto 0);
 signal gyro_data_rdy : std_logic := '0';
 
 signal gyro_z_bin : std_logic_vector (15 downto 0);
 signal gyro_z : natural;
 
 signal light_sensor_buf : std_logic_vector(3 downto 0);
 
-- Clock divider signals
 signal tmp : std_logic := '0';
 signal clk_divider: integer:= 62500; -- divider from 100MHz to 1600Hz)
 signal gyro_clk: std_logic := '0'; -- spi_clock
 signal clk_div_counter: integer := 1;
 signal spi_byte_num : natural range 1 to 8 := 8;
 


begin
-------------------------
gyro_clk_gen : process (clk) -- break 100MHz clock down to 1600Hz (2xODR of Gyro)
	begin
		if(clk'event and clk='1') then
			clk_div_counter <=clk_div_counter + 1;		
			if (clk_div_counter = clk_divider) then
				tmp <= NOT tmp;
				clk_div_counter <= 1;
			end if;
		end if;
	gyro_clk <= tmp;
end process gyro_clk_gen;
-------------------------
gyro_data : process(gyro_clk) -- gather gyro data
variable init_flag : std_logic := '0';
begin
    if rising_edge(gyro_clk) then
        if init_flag = '0' then
            init_flag := '1';
            gyro_data_out <= x"20EF";
            gyro_enable <= '1';
        elsif init_flag = '1' then
            gyro_data_out <= x"E8FF";
            byte_num <= "0110";
            gyro_enable <= '1';
            if data_rdy_in = '1' then
                gyro_enable <= '0';
                gyro_data_rdy <= '0';
                gyro_data_buf <= gyro_data_in(127 downto 64);
                gyro_clock_buf <= gyro_data_in(63 downto 0);
                gyro_data_rdy <= '1';
            end if;
        end if;    
    end if;
    --gyro_enable <= '0'; 
    

end process gyro_data;
---------------------------
light_sens_loop : process(clk) --gather light sens data @ 100MHz
 -- variables for light_sens_loop here
begin
    if rising_edge (clk) then
    light_sensor_out <= light_sensor_in;
    light_sensor_buf <= light_sensor_in;
    end if;
end process light_sens_loop;
---------------------------
control_loop : process (clk)
    variable gyro_flag : std_logic := '1'; --flag to only execute control logic once per data packet
    begin
        if gyro_data_rdy = '1' and gyro_flag = '1' then
            gyro_flag := '0';
            gyro_z_bin <= gyro_data_buf(23 downto 16) &  gyro_data_buf(31 downto 24);
            gyro_z <= CONV_INTEGER(gyro_z_bin);
            if gyro_z > 32767 then
                gyro_z <= gyro_z - 65534;
            end if;
            if (light_sensor_buf = "0000" and gyro_z < 7000) then --faster spin than 53dps and signle lightr sensor on
                RW_enable <= '1';
            else
                RW_enable <= '0';
            end if;
        end if;
        
        if gyro_data_rdy = '0' then -- reset flag when new data is being read
            gyro_flag := '1';
        end if;
   
end process control_loop;

end Behavioral;
