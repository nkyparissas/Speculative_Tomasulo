-- Computer Architecture - Technical University of Crete
-- Speculative Tomasulo’s Algorithm
-- N. Kyparissas, A. Kampylafkas

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY REGISTER_FILE IS
PORT( 
	CLK : IN STD_LOGIC;
	RST : IN STD_LOGIC;
	-- ROB
	ROB_RD : IN STD_LOGIC_VECTOR(4 DOWNTO 0); 
	ROB_V : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
	ROB_WE : IN STD_LOGIC;
	-- RF PORTS
	RS : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
	RT : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
	DATA_RS : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
	DATA_RT : OUT STD_LOGIC_VECTOR(31 DOWNTO 0));
		
END REGISTER_FILE;

ARCHITECTURE BEHAVIORAL OF REGISTER_FILE IS	
	TYPE REGISTER_V IS ARRAY(31 DOWNTO 0) OF STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL V : REGISTER_V := (OTHERS => (OTHERS => '0'));
    
BEGIN

	PROCESS
	BEGIN
	
		WAIT UNTIL RISING_EDGE(CLK);
		
		IF (RST = '1') THEN
			V <= (OTHERS => (OTHERS => '0'));
			-- THE FIRST REGISTERS ARE INITIALIZED WITH A VALUE
			-- FOR TESTING, BECAUSE OF THE LACK OF LOAD/STORE FUNCTIONALITY
			L_X: FOR I IN 0 TO 10 LOOP 
				V(I) <= STD_LOGIC_VECTOR(TO_UNSIGNED(I, V(I)'LENGTH));      
			END LOOP L_X; 
		ELSE
			-- ROB COMMIT
			IF ROB_WE = '1' THEN
				V(TO_INTEGER(UNSIGNED(ROB_RD))) <= ROB_V;
			END IF;			
			-- WRITE-FIRST RS PORT
			IF ROB_RD = RS THEN
				DATA_RS <= ROB_V;
			ELSE 
				DATA_RS <= V(TO_INTEGER(UNSIGNED(RS)));
			END IF;			
			-- WRITE-FIRST RT PORT
			IF ROB_RD = RT THEN
				DATA_RT <= ROB_V;
			ELSE 
				DATA_RT <= V(TO_INTEGER(UNSIGNED(RT)));
			END IF;
		END IF;
	
	END PROCESS;
	
END BEHAVIORAL;
