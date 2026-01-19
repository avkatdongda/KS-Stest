library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- UART 接收模块：
-- 1) 以系统时钟采样 RX 线，检测起始位。
-- 2) 在起始位中点采样后，按位间隔采集 8 位数据。
-- 3) 采集停止位后输出 rx_data，并给出单周期 rx_done 脉冲。
entity uart_rx is
  generic (
    CLK_FREQ_HZ : integer := 50000000;
    BAUD_RATE   : integer := 115200
  );
  port (
    clk     : in  std_logic;
    rst_n   : in  std_logic;
    rx_line : in  std_logic;
    rx_data : out std_logic_vector(7 downto 0);
    rx_done : out std_logic
  );
end entity;

architecture rtl of uart_rx is
  -- 波特率分频计数：每个 UART 比特持续 BAUD_DIV 个 clk
  constant BAUD_DIV  : integer := CLK_FREQ_HZ / BAUD_RATE;
  -- 起始位中点采样，用于提高抗抖动能力
  constant HALF_DIV  : integer := BAUD_DIV / 2;

  -- 接收状态机
  type rx_state_t is (IDLE, START, DATA, STOP);
  signal state       : rx_state_t := IDLE;
  -- 波特率计数器与位计数器
  signal baud_cnt    : integer range 0 to BAUD_DIV := 0;
  signal bit_idx     : integer range 0 to 7 := 0;
  -- 数据移位寄存器
  signal data_shift  : std_logic_vector(7 downto 0) := (others => '0');
  -- 输出脉冲寄存器
  signal rx_done_reg : std_logic := '0';
  -- 两级同步器，降低异步输入的亚稳态风险
  signal rx_sync     : std_logic := '1';
  signal rx_sync2    : std_logic := '1';
begin
  rx_done <= rx_done_reg;

  process (clk, rst_n)
  begin
    if rst_n = '0' then
      -- 异步复位：同步器复位为高电平
      rx_sync  <= '1';
      rx_sync2 <= '1';
    elsif rising_edge(clk) then
      -- 两级同步采样
      rx_sync  <= rx_line;
      rx_sync2 <= rx_sync;
    end if;
  end process;

  process (clk, rst_n)
  begin
    if rst_n = '0' then
      -- 异步复位：清空状态和寄存器
      state       <= IDLE;
      baud_cnt    <= 0;
      bit_idx     <= 0;
      data_shift  <= (others => '0');
      rx_done_reg <= '0';
      rx_data     <= (others => '0');
    elsif rising_edge(clk) then
      -- 默认：rx_done 仅保持一个时钟周期
      rx_done_reg <= '0';
      case state is
        when IDLE =>
          -- 空闲态：等待起始位（低电平）
          if rx_sync2 = '0' then
            baud_cnt <= HALF_DIV;
            state    <= START;
          end if;

        when START =>
          -- 起始位中点采样：确认仍为低电平
          if baud_cnt = 0 then
            if rx_sync2 = '0' then
              baud_cnt <= BAUD_DIV - 1;
              bit_idx  <= 0;
              state    <= DATA;
            else
              -- 起始位不成立，回到空闲
              state <= IDLE;
            end if;
          else
            baud_cnt <= baud_cnt - 1;
          end if;

        when DATA =>
          -- 数据采样：LSB 先行
          if baud_cnt = 0 then
            data_shift(bit_idx) <= rx_sync2;
            if bit_idx = 7 then
              state    <= STOP;
            else
              bit_idx <= bit_idx + 1;
            end if;
            baud_cnt <= BAUD_DIV - 1;
          else
            baud_cnt <= baud_cnt - 1;
          end if;

        when STOP =>
          -- 停止位结束后，输出数据并拉高 rx_done
          if baud_cnt = 0 then
            rx_data     <= data_shift;
            rx_done_reg <= '1';
            state       <= IDLE;
          else
            baud_cnt <= baud_cnt - 1;
          end if;
      end case;
    end if;
  end process;
end architecture;
