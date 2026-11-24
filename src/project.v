library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tt_um_example is
    generic (
        CLK_HZ : integer := 50_000_000
    );
    port (
        ui_in   : in  std_logic_vector(7 downto 0);
        uo_out  : out std_logic_vector(7 downto 0);
        uio_in  : in  std_logic_vector(7 downto 0);
        uio_out : out std_logic_vector(7 downto 0);
        uio_oe  : out std_logic_vector(7 downto 0);
        ena     : in  std_logic;
        clk     : in  std_logic;
        rst_n   : in  std_logic
    );
end entity;

architecture rtl of tt_um_example is
    signal pwm_in        : std_logic;
    signal pwm_ff1       : std_logic := '0';
    signal pwm_ff2       : std_logic := '0';
    signal level_0_9     : integer range 0 to 9 := 0;
    signal active_on     : std_logic := '0';
    signal inj_reg       : std_logic_vector(5 downto 0) := (others => '0');
    signal ch_idx        : integer range 0 to 5 := 0;
    signal period_cnt    : integer := 0;
    signal pulse_cnt     : integer := 0;
    signal relay_bomba   : std_logic := '0';
    signal seg7          : std_logic_vector(6 downto 0);
    signal unused_acc    : std_logic;

    constant PWM_WIN_TICKS : integer := CLK_HZ / 20;
    constant PULSE_TICKS   : integer := CLK_HZ / 50;
begin

    pwm_in <= ui_in(0);
    uio_oe <= "01111111"; -- uio(6 downto 0) como salida; uio(7) como entrada
    unused_acc <= ena or uio_in(0) or ui_in(1);

    process(clk, rst_n)
        variable high_cnt : integer := 0;
        variable win_cnt  : integer := 0;
        variable calc_lvl : integer;
    begin
        if rst_n = '0' then
            pwm_ff1   <= '0';
            pwm_ff2   <= '0';
            level_0_9 <= 0;
            active_on <= '0';
            high_cnt  := 0;
            win_cnt   := 0;
        elsif rising_edge(clk) then
            pwm_ff1 <= pwm_in;
            pwm_ff2 <= pwm_ff1;

            if pwm_ff2 = '1' then
                high_cnt := high_cnt + 1;
            end if;

            if win_cnt >= PWM_WIN_TICKS - 1 then
                calc_lvl := (high_cnt * 10) / PWM_WIN_TICKS;
                if high_cnt = 0 then
                    level_0_9 <= 0;
                    active_on <= '0';
                else
                    active_on <= '1';
                    if calc_lvl > 9 then
                        level_0_9 <= 9;
                    elsif calc_lvl < 1 then
                        level_0_9 <= 1;
                    else
                        level_0_9 <= calc_lvl;
                    end if;
                end if;
                high_cnt := 0;
                win_cnt  := 0;
            else
                win_cnt := win_cnt + 1;
            end if;
        end if;
    end process;

    relay_bomba <= '1' when (rst_n = '1' and active_on = '1') else '0';

    process(clk, rst_n)
        variable period_target : integer;
    begin
        if rst_n = '0' then
            period_cnt <= 0;
            pulse_cnt  <= 0;
            ch_idx     <= 0;
            inj_reg    <= (others => '0');
        elsif rising_edge(clk) then
            if (active_on = '0') or (level_0_9 = 0) then
                period_cnt <= 0;
                pulse_cnt  <= 0;
                ch_idx     <= 0;
                inj_reg    <= (others => '0');
            else
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

    uo_out <= '0' & relay_bomba & inj_reg;

    process(level_0_9)
    begin
        case level_0_9 is
            when 0      => seg7 <= "1000000";
            when 1      => seg7 <= "1111001";
            when 2      => seg7 <= "0100100";
            when 3      => seg7 <= "0110000";
            when 4      => seg7 <= "0011001";
            when 5      => seg7 <= "0010010";
            when 6      => seg7 <= "0000010";
            when 7      => seg7 <= "0111000";
            when 8      => seg7 <= "0000000";
            when 9      => seg7 <= "0010000";
            when others => seg7 <= "1000000";
        end case;
    end process;

    uio_out <= '0' & seg7;

end architecture;
