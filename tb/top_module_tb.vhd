library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench：
-- 1) Case1：发送 7E 7E AA AA，期望收到 7E 7E BB BB。
-- 2) Case2：发送 7E 7E 12 34，期望收到 7E 7E CC CC。
entity top_module_tb is
end entity;

architecture sim of top_module_tb is
  -- 50 MHz 时钟周期
  constant CLK_PERIOD  : time := 20 ns;
  -- UART 比特周期
  constant BAUD_PERIOD : time := 1 sec / 115200;

  -- DUT 端口信号
  signal clk     : std_logic := '0';
  signal rst_n   : std_logic := '0';
  signal rx_line : std_logic := '1';
  signal tx_line : std_logic;

  -- 4 字节数组，用于缓存回复帧
  type byte_array_t is array (0 to 3) of std_logic_vector(7 downto 0);

  -- UART 发送过程：产生 8N1 帧
  procedure uart_send(signal line: out std_logic; data: std_logic_vector(7 downto 0)) is
  begin
    line <= '0';
    wait for BAUD_PERIOD;
    for i in 0 to 7 loop
      line <= data(i);
      wait for BAUD_PERIOD;
    end loop;
    line <= '1';
    wait for BAUD_PERIOD;
  end procedure;

  -- UART 接收过程：等待起始位，按位采样
  procedure uart_recv(signal line: in std_logic; variable data: out std_logic_vector(7 downto 0)) is
  begin
    wait until line = '0';
    wait for BAUD_PERIOD + BAUD_PERIOD / 2;
    for i in 0 to 7 loop
      data(i) := line;
      wait for BAUD_PERIOD;
    end loop;
    wait for BAUD_PERIOD;
  end procedure;

  -- 接收 4 字节回复
  procedure recv_reply(signal line: in std_logic; variable resp: out byte_array_t) is
    variable temp : std_logic_vector(7 downto 0);
  begin
    for idx in 0 to 3 loop
      uart_recv(line, temp);
      resp(idx) := temp;
    end loop;
  end procedure;

begin
  -- 产生系统时钟
  clk <= not clk after CLK_PERIOD / 2;

  -- DUT 实例化
  dut : entity work.top_module
    port map (
      clk     => clk,
      rst_n   => rst_n,
      rx_line => rx_line,
      tx_line => tx_line
    );

  -- 激励与检查
  stim : process
    variable reply : byte_array_t;
  begin
    -- 复位释放
    rst_n <= '0';
    wait for 10 * CLK_PERIOD;
    rst_n <= '1';
    wait for 10 * CLK_PERIOD;

    -- Case 1：AA AA -> BB BB
    uart_send(rx_line, x"7E");
    uart_send(rx_line, x"7E");
    uart_send(rx_line, x"AA");
    uart_send(rx_line, x"AA");

    recv_reply(tx_line, reply);

    assert reply(0) = x"7E" report "Case1: header byte0 mismatch" severity error;
    assert reply(1) = x"7E" report "Case1: header byte1 mismatch" severity error;
    assert reply(2) = x"BB" report "Case1: payload byte2 mismatch" severity error;
    assert reply(3) = x"BB" report "Case1: payload byte3 mismatch" severity error;

    wait for 5 * BAUD_PERIOD;

    -- Case 2：非 AA AA -> CC CC
    uart_send(rx_line, x"7E");
    uart_send(rx_line, x"7E");
    uart_send(rx_line, x"12");
    uart_send(rx_line, x"34");

    recv_reply(tx_line, reply);

    assert reply(0) = x"7E" report "Case2: header byte0 mismatch" severity error;
    assert reply(1) = x"7E" report "Case2: header byte1 mismatch" severity error;
    assert reply(2) = x"CC" report "Case2: payload byte2 mismatch" severity error;
    assert reply(3) = x"CC" report "Case2: payload byte3 mismatch" severity error;

    wait;
  end process;
end architecture;
