library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity banco_inyectores_fpga is
    generic (
        CLK_HZ : integer := 50_000_000 -- Ajusta al reloj de tu tarjeta FPGA
    );
    port (
        clk_sys : in  std_logic;
        rst_n   : in  std_logic;
        sw      : in  std_logic_vector(9 downto 0); -- SW0 a SW9 simulan nivel/PWM 0..9
        ldr     : out std_logic_vector(5 downto 0); -- LDR0 a LDR5 -> inyector0 a inyector5
        ldg7    : out std_logic;                    -- LDG7 -> relay_bomba
        seg7    : out std_logic_vector(6 downto 0)  -- 7 segmentos (a..g, activo en '1')
    );
end entity;

architecture rtl of banco_inyectores_fpga is
    signal level_0_9  : integer range 0 to 9 := 0;
    signal active_on  : std_logic := '0';
    signal inj_reg    : std_logic_vector(5 downto 0) := (others => '0');
    signal ch_idx     : integer range 0 to 5 := 0;
    signal period_cnt : integer := 0;
    signal pulse_cnt  : integer := 0;

    -- Ancho de pulso visible en LEDs y seguro para pruebas (~20 ms)
    constant PULSE_TICKS : integer := CLK_HZ / 50;
begin

    -- 1. Traducción de SW0..SW9 a nivel 0..9 (cantidad de switches en '1', máx. 9)
    process(sw)
        variable cnt : integer range 0 to 10;
    begin
        cnt := 0;
        for i in 0 to 9 loop
            if sw(i) = '1' then
                cnt := cnt + 1;
            end if;
        end loop;

        if cnt = 0 then
            active_on <= '0';
            level_0_9 <= 0;
        else
            active_on <= '1';
            if cnt > 9 then
                level_0_9 <= 9;
            else
                level_0_9 <= cnt;
            end if;
        end if;
    end process;

    -- 2. Relevador de bomba en LDG7
    ldg7 <= '1' when (rst_n = '1' and active_on = '1') else '0';

    -- 3. Generación secuencial en LDR0..LDR5 a velocidad dictada por level_0_9 (1..9)
    process(clk_sys, rst_n)
        variable period_target : integer;
    begin
        if rst_n = '0' then
            period_cnt <= 0;
            pulse_cnt  <= 0;
            ch_idx     <= 0;
            inj_reg    <= (others => '0');
        elsif rising_edge(clk_sys) then
            if (active_on = '0') or (level_0_9 = 0) then
                period_cnt <= 0;
                pulse_cnt  <= 0;
                ch_idx     <= 0;
                inj_reg    <= (others => '0');
            else
                -- A mayor level_0_9 (1..9), menor periodo entre disparos (más rápido)
                -- Nivel 1 -> ~1.0 s entre pasos; Nivel 9 -> ~0.11 s entre pasos
                period_target := CLK_HZ / level_0_9;
                if period_target < (PULSE_TICKS + 10) then
                    period_target := PULSE_TICKS + 10;
                end if;

                if period_cnt >= period_target then
                    period_cnt <= 0;
                    pulse_cnt  <= PULSE_TICKS;
                    inj_reg    <= (others => '0');
                    inj_reg(ch_idx) <= '1';

                    if ch_idx = 5 then
                        ch_idx <= 0;
                    else
                        ch_idx <= ch_idx + 1;
                    end if;
                else
                    period_cnt <= period_cnt + 1;
                    if pulse_cnt > 0 then
                        pulse_cnt <= pulse_cnt - 1;
                    else
                        inj_reg <= (others => '0');
                    end if;
                end if;
            end if;
        end if;
    end process;

    ldr <= inj_reg;

    -- 4. Decodificador a 7 segmentos - ANODO COMUN ('0' = encendido, '1' = apagado)
    -- Orden de bits en seg7: (6=>a, 5=>b, 4=>c, 3=>d, 2=>e, 1=>f, 0=>g)
    process(level_0_9)
    begin
        case level_0_9 is
            when 0      => seg7 <= "1000000"; -- 0
            when 1      => seg7 <= "1111001"; -- 1
            when 2      => seg7 <= "0100100"; -- 2
            when 3      => seg7 <= "0110000"; -- 3
            when 4      => seg7 <= "0011001"; -- 4
            when 5      => seg7 <= "0010010"; -- 5
            when 6      => seg7 <= "0000010"; -- 6
            when 7      => seg7 <= "0111000"; -- 7
            when 8      => seg7 <= "0000000"; -- 8
            when 9      => seg7 <= "0010000"; -- 9
            when others => seg7 <= "0010000";
        end case;
    end process;

end architecture;
