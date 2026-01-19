library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- UART 发送模块：
-- 1) 接收 tx_start 脉冲与 tx_data 字节。
-- 2) 输出完整的 8N1 帧：起始位、8 数据位、停止位。
-- 3) tx_busy 为发送期间有效，空闲时 tx_line 拉高。
entity uart_tx is
  generic (
    CLK_FREQ_HZ : integer := 50000000;
    BAUD_RATE   : integer := 115200
  );
  port (
    clk      : in  std_logic;
    rst_n    : in  std_logic;
    tx_start : in  std_logic;
    tx_data  : in  std_logic_vector(7 downto 0);
    tx_line  : out std_logic;
    tx_busy  : out std_logic
  );
end entity;

architecture rtl of uart_tx is
  -- 波特率分频计数：每个 UART 比特持续 BAUD_DIV 个 clk
  constant BAUD_DIV : integer := CLK_FREQ_HZ / BAUD_RATE;

  -- 发送状态机
  type tx_state_t is (IDLE, START, DATA, STOP);
  signal state      : tx_state_t := IDLE;
  -- 波特率计数器与位计数器
  signal baud_cnt   : integer range 0 to BAUD_DIV := 0;
  signal bit_idx    : integer range 0 to 7 := 0;
  -- 数据移位寄存器
  signal data_shift : std_logic_vector(7 downto 0) := (others => '0');
  -- 输出寄存器与忙标志
  signal tx_line_reg: std_logic := '1';
  signal tx_busy_reg: std_logic := '0';
begin
  tx_line <= tx_line_reg;
  tx_busy <= tx_busy_reg;

  process (clk, rst_n)
  begin
    if rst_n = '0' then
      -- 异步复位：发送器回到空闲态
      state       <= IDLE;
      baud_cnt    <= 0;
      bit_idx     <= 0;
      data_shift  <= (others => '0');
      tx_line_reg <= '1';
      tx_busy_reg <= '0';
    elsif rising_edge(clk) then
      case state is
        when IDLE =>
          -- 空闲态：等待 tx_start
          tx_line_reg <= '1';
          tx_busy_reg <= '0';
          if tx_start = '1' then
            data_shift  <= tx_data;
            baud_cnt    <= BAUD_DIV - 1;
            tx_line_reg <= '0';
            tx_busy_reg <= '1';
            state       <= START;
          end if;

        when START =>
          -- 起始位持续一个波特周期后发送 bit0
          if baud_cnt = 0 then
            baud_cnt    <= BAUD_DIV - 1;
            bit_idx     <= 0;
            tx_line_reg <= data_shift(0);
            state       <= DATA;
          else
            baud_cnt <= baud_cnt - 1;
          end if;

        when DATA =>
          -- 数据位发送：LSB 先行
          if baud_cnt = 0 then
            if bit_idx = 7 then
              tx_line_reg <= '1';
              state       <= STOP;
            else
              bit_idx     <= bit_idx + 1;
              tx_line_reg <= data_shift(bit_idx + 1);
            end if;
            baud_cnt <= BAUD_DIV - 1;
          else
            baud_cnt <= baud_cnt - 1;
          end if;

        when STOP =>
          -- 停止位发送完成后回到空闲
          if baud_cnt = 0 then
            tx_line_reg <= '1';
            tx_busy_reg <= '0';
            state       <= IDLE;
          else
            baud_cnt <= baud_cnt - 1;
          end if;
      end case;
    end if;
  end process;
end architecture;
