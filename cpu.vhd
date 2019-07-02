-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2018 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): xdolej09
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
 
-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet ROM
   CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
   CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_cnt] pokud CODE_EN='1'
   CODE_EN   : out std_logic;                     -- povoleni cinnosti
   
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_cnt] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_cnt] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni z pameti (DATA_RDWR='1') / zapis do pameti (DATA_RDWR='0')
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA obsahuje stisknuty znak klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna pokud IN_VLD='1'
   IN_REQ    : out std_logic;                     -- pozadavek na vstup dat z klavesnice
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- pokud OUT_BUSY='1', LCD je zaneprazdnen, nelze zapisovat,  OUT_WE musi byt '0'
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;
 
 
-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
-- ----------------------------------------------------------------------------
--                      States declaration
-- ----------------------------------------------------------------------------
        type state_t is (
        state_start, state_instr, -- pocatecni stavy
		  state_ptr_inc, state_ptr_dec,state_cell_inc, state_cell_inc2, state_cell_dec, state_cell_dec2, -- inkrementaci / dekrementacni stavy
		  state_decimal, state_hexa, -- stavy pro hexa a desitkove operace
		  state_putchar, state_putchar_2, state_getchar, -- vypis a cteni znaku
		  state_end1, state_end2,state_end3, state_end4, state_end5, state_end6, -- ukonceni cyklu
		  state_while1, state_while2, state_while3, state_while4, -- zacatek cyklu
		  state_null, state_other, -- ostatni
		  state_comment, state_comment1, state_comm_end -- komentare
    );
-- ----------------------------------------------------------------------------
--                      Signals declaration
-- ----------------------------------------------------------------------------
	 
	 signal sel: std_logic_vector(1 downto 0) := "00"; -- dvoubitovy signal pro vstup multiplexoru, ten vybira hodnotu zapisovanych dat
	 
    signal cnt: std_logic_vector(7 downto 0) := (others => '0'); -- CNT registr slouzici k pocitani zavorek, cyklu..
    signal cnt_inc: std_logic := '0'; -- inkrementace CNT registru
    signal cnt_dec: std_logic := '0'; -- dekrementace CNT registru
	 
	 signal tmp: std_logic_vector(7 downto 0) := (others => '0'); -- pomocny signal pro ukladani hexa
	 
	 signal pc: std_logic_vector(11 downto 0) := (others => '0'); -- registr programoveho citace
    signal pc_inc: std_logic := '0'; -- zvyseni programoveho citace
    signal pc_dec: std_logic := '0';-- snizeni programoveho citace
	 signal pcCount: std_logic_vector(11 downto 0) := (others => '0'); --pomocny signal pro vnoreny while cyklus
	 
	 signal next_state: state_t; -- nasledujici stav
	 signal present_state: state_t; -- aktualni stav
	 
	 signal ptr: std_logic_vector(9 downto 0) := (others => '0'); -- registr ukazatele do pameti dat
    signal ptr_inc: std_logic := '0'; -- zvyseni PTR
    signal ptr_dec: std_logic := '0'; -- snizeni PTR
 
begin
	 
-- ----------------------------------------------------------------------------
--                      CNT register
-- ----------------------------------------------------------------------------
    cnt_reg: process(cnt_inc,cnt_dec, RESET, CLK)
    begin
        if(RESET = '1') then
            cnt <= (others => '0');
        elsif rising_edge(CLK) then
            if(cnt_dec = '1') then
                cnt <= cnt - 1;
            elsif(cnt_inc = '1') then
                cnt <= cnt + 1;
            end if;
        end if;
    end process;
	 
-- ----------------------------------------------------------------------------
--                      PTR register
-- ----------------------------------------------------------------------------
    ptr_reg: process(ptr, ptr_inc, ptr_dec, RESET, CLK)
    begin
 
        if(RESET = '1') then
            ptr <= (others => '0');
        elsif rising_edge(CLK) then
            if(ptr_dec = '1') then
                ptr <= ptr - 1;
            elsif(ptr_inc = '1') then
                ptr <= ptr + 1;
            end if;
        end if;
    end process;
    
	 
	 DATA_ADDR <= ptr;
-- ----------------------------------------------------------------------------
--                      States changer
-- ----------------------------------------------------------------------------
    fsm_change: process(RESET, CLK)
    begin
        if(RESET = '1') then
            present_state <= state_start;
        elsif rising_edge(CLK) then
            if(EN = '1') then
                present_state <= next_state;
            end if;
        end if;
    end process;
	 
-- ----------------------------------------------------------------------------
--                      PC register
-- ----------------------------------------------------------------------------
    pc_reg: process(pc, pc_inc, pc_dec, RESET, CLK)
    begin
        if(RESET = '1') then
            pc <= (others => '0');
        elsif rising_edge(CLK) then
            if(pc_dec = '1') then
                pc <= pc - 1;
            elsif(pc_inc = '1') then
                pc <= pc + 1;
            end if;
        end if;

    end process;
 
	 CODE_ADDR <= pc;
-- ----------------------------------------------------------------------------
--                      Multiplexor declaration
-- ----------------------------------------------------------------------------
 
    mux: process(sel, DATA_RDATA, IN_DATA)
    begin
        case(sel) is
            when "11" => DATA_WDATA <= tmp;
            when "10" => DATA_WDATA <= DATA_RDATA - 1;
				when "01" => DATA_WDATA <= DATA_RDATA + 1;
            when "00" => DATA_WDATA <= IN_DATA;
            when others =>
        end case;
    end process;
 
-- ----------------------------------------------------------------------------
--                      Finite state machine
-- ----------------------------------------------------------------------------
    fsm_next_state: process(cnt, present_state, DATA_RDATA, OUT_BUSY, IN_VLD, CODE_DATA)
    begin
 
-- ----------------------------------------------------------------------------
--                      Initial inicialization
-- ----------------------------------------------------------------------------
		  next_state <= state_start;
        CODE_EN <= '1';
        DATA_RDWR <= '0';
		  DATA_EN <= '0';
		  sel <= "00";
		  pc_inc <= '0';
        pc_dec <= '0';
        ptr_inc <= '0';
        ptr_dec <= '0';
		  cnt_inc <= '0';
		  cnt_dec <= '0';
        OUT_WE <= '0';
        IN_REQ <= '0';
       
        case present_state is
            when state_start => CODE_EN <= '1'; -- na startu povolime povoleni cinnosti zapisu a skocime do stavu, kde se vybere instrukce
                next_state <= state_instr;
------------------ instruction < -----------------------------------
            when state_ptr_dec => -- pri dekrementaci hodnoty ukazatele nastavime programovy citac a registr ukazatele do pameti na 1
                pc_inc <= '1';
					 ptr_dec <= '1';
                next_state <= state_start;
------------------ instruction > -----------------------------------	
            when state_ptr_inc => -- same jak pri snizeni
                pc_inc <= '1';
					 ptr_inc <= '1';
                next_state <= state_start;
------------------ instruction - -----------------------------------
            when state_cell_dec => -- dekrementaci hodn. akutalni bunky, povolime cinnost k zapisu a budu cist z pameti
                DATA_RDWR <= '1';
					 DATA_EN <= '1';
                next_state <= state_cell_dec2;
            when state_cell_dec2 => -- pomoci multiplexoru vybere spravnou vetev, zvysime citac a jdeme do pocatecniho stavu
                DATA_RDWR <= '0';    
					 sel <= "10";
                DATA_EN <= '1';
                pc_inc <= '1';
                next_state <= state_start;
------------------ instruction + -----------------------------------
            when state_cell_inc => -- to same jako u dekrementace, multiplexor vybira jinou vetev
               DATA_RDWR <= '1';              
					DATA_EN <= '1';
                next_state <= state_cell_inc2;
            when state_cell_inc2 =>
                sel <= "01";
                DATA_RDWR <= '0';
                DATA_EN <= '1';
                pc_inc <= '1';
                next_state <= state_start;
------------------ instruction , -----------------------------------
            when state_getchar =>
                IN_REQ <= '1';
                if(IN_VLD = '0') then -- pokud nemame platna data, opakujeme
                    next_state <= state_getchar;
                else -- pokud ano, multiplexor nam presmeruje tisknutelny znak na klavesnici do DATA_WDATA
						  sel <= "00";
					     DATA_RDWR <= '0';
                    DATA_EN <= '1';
                    pc_inc <= '1';
                    next_state <= state_start;
                end if;
------------------ instruction . -----------------------------------
            when state_putchar =>
                if(OUT_BUSY = '1') then -- pokud je OUT_BUSY=1, nelze zapisovat, opakujeme tedy
                    next_state <= state_putchar;
                else -- pokud muzeme zapisovat, povlime cinnost a pokracujeme, stejne jako v getchar
					     DATA_RDWR <= '1';
                    DATA_EN <= '1';
                    next_state <= state_putchar_2;
                end if;
            when state_putchar_2 =>
				    pc_inc <= '1';
                OUT_DATA <= DATA_RDATA; -- z pameti nahrajeme do OUT zapisovatelna data
					 OUT_WE <= '1';
                next_state <= state_start;
            when state_instr => case CODE_DATA is
------------------A-F, 0x41-0x46 -----------------------------------				
						when X"41" => next_state <= state_hexa; --A
						when X"42" => next_state <= state_hexa; --B
						when X"43" => next_state <= state_hexa; --C
						when X"44" => next_state <= state_hexa; --D
						when X"45" => next_state <= state_hexa; --E
						when X"46" => next_state <= state_hexa; --F
						
------------------0-9, 0x30-0x39 -----------------------------------
						when X"30" => next_state <= state_decimal; --0
						when X"31" => next_state <= state_decimal; --1
						when X"32" => next_state <= state_decimal; --2
						when X"33" => next_state <= state_decimal; --3
						when X"34" => next_state <= state_decimal; --4
						when X"35" => next_state <= state_decimal; --5
						when X"36" => next_state <= state_decimal; --6
						when X"37" => next_state <= state_decimal; --7
						when X"38" => next_state <= state_decimal; --8
						when X"39" => next_state <= state_decimal; --9
						
------------------All basic Brainfuck instructions -----------------------------------		
						when X"3E" => next_state <= state_ptr_inc; -- inkrementace hodnoty ukazatele
						when X"3C" => next_state <= state_ptr_dec; -- dekrementace hodnoty ukazatele
						when X"2B" => next_state <= state_cell_inc; -- inkrementace hodnoty aktualni bunky
						when X"2D" => next_state <= state_cell_dec; -- dekrementace hodnoty aktualni bunky
						when X"5B" => next_state <= state_while1; -- zacatek while cyklu
						when X"5D" => next_state <= state_end1; -- konec while czklu
						when X"2E" => next_state <= state_putchar; -- vytisknutni hodnoty aktualni bunky
						when X"2C" => next_state <= state_getchar; -- nacteni a ulozeni hodnoty do aktualni bunky
						when X"23" => next_state <= state_comment; -- komentar
						
						when X"00" => next_state <= state_null;
						when others => next_state <= state_other;
					end case;

------------------ instruction [ -----------------------------------
            when state_while1 =>
					 pc_inc <= '1';
				    DATA_EN <= '1';
                DATA_RDWR <= '1';
                next_state <= state_while2;
            when state_while2 =>
                if(DATA_RDATA = X"00") then
                   cnt_inc <= '1';
						 CODE_EN <= '1'; --- pridano!!
                    next_state <= state_while3;
                else
                    next_state <= state_start;
                end if;
            when state_while3 =>
                if(cnt = X"00") then
						 -- cnt_inc <= '1'; odebrano!!
                    next_state <= state_start;
                else
                    if CODE_DATA = X"5B" then
								cnt_inc <= '1';
						   elsif(CODE_DATA = X"5D") then
								cnt_dec <= '1';
							end if;
							pc_inc <= '1';
							next_state <= state_while4;
                end if;
            when state_while4 =>
					CODE_EN <= '1';
                next_state <= state_while3;
------------------ instruction ] -----------------------------------
            when state_end1 =>
					DATA_EN <= '1';   
					DATA_RDWR <= '1';
                 -----
                next_state <= state_end2;
            when state_end2 =>
                if(DATA_RDATA = X"00") then
                    pc_inc <= '1';
                    next_state <= state_start;
                else
						  cnt_inc <= '1';
						  pc_dec <= '1';
                    next_state <= state_end5;
                end if;
            when state_end3 =>
                if(cnt = X"00") then
                    next_state <= state_start;
                else
						 if(CODE_DATA = X"5B") then
							 cnt_dec <= '1';
						 elsif(CODE_DATA = X"5D") then
							  cnt_inc <= '1';
						 end if;
						 next_state <= state_end4;
                end if;
					 
            when state_end4 =>
                if(cnt = X"00")then
                   pc_inc <= '1';
                else
                    pc_dec <= '1';
                end if;
                next_state <= state_end5;
            when state_end5 =>
						CODE_EN <= '1';
					next_state <= state_end3;
------------------ instruction # -----------------------------------
            when state_comment =>
                pc_inc <= '1';
                next_state <= state_comment1;
            when state_comment1 =>
                CODE_EN <= '1';
                next_state <= state_comm_end;
            when state_comm_end =>
                if CODE_DATA = X"23" then
                    pc_inc <= '1';
                    next_state <= state_start;
                else
                    next_state <= state_comment;
                end if;
------------------ instruction null -----------------------------------
            when state_null =>
                next_state <= state_null;
------------------ instructions 0-9 -----------------------------------
            when state_decimal =>
                tmp <= CODE_DATA(3 downto 0) & "0000";
               sel <= "11";
                pc_inc <= '1';
                DATA_EN <= '1';
                next_state <= state_start;
------------------ instruction A-F -----------------------------------
            when state_hexa =>
                tmp <= (CODE_DATA(3 downto 0) + std_logic_vector(conv_unsigned(9, tmp'LENGTH)(3 downto 0))) & "0000";
					 sel <= "11";
                pc_inc <= '1';
                DATA_EN <= '1';
                next_state <= state_start;  
------------------ others -----------------------------------
            when state_other =>
                pc_inc <= '1';
                next_state <= state_start;
            when others => null;
        end case;
    end process;
end behavioral;