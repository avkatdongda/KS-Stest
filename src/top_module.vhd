library ieee;
use ieee.std_logic_1164.all;

-- 顶层模块：
-- 连接 UART RX、协议解析器、UART TX。
-- 对外仅暴露 rx_line/tx_line，与系统时钟和复位。
entity top_module is
  port (
    clk     : in  std_logic;
    rst_n   : in  std_logic;
    rx_line : in  std_logic;
    tx_line : out std_logic
  );
end entity;

architecture rtl of top_module is
  -- 内部连线：RX 到 Parser，再到 TX
  signal rx_data  : std_logic_vector(7 downto 0);
  signal rx_done  : std_logic;
  signal tx_start : std_logic;
  signal tx_data  : std_logic_vector(7 downto 0);
  signal tx_busy  : std_logic;
begin
  -- UART 接收实例
  u_rx : entity work.uart_rx
    generic map (
      CLK_FREQ_HZ => 50000000,
      BAUD_RATE   => 115200
    )
    port map (
      clk     => clk,
      rst_n   => rst_n,
      rx_line => rx_line,
      rx_data => rx_data,
      rx_done => rx_done
    );

  -- 协议解析实例
  u_parser : entity work.protocol_parser
    port map (
      clk      => clk,
      rst_n    => rst_n,
      rx_data  => rx_data,
      rx_done  => rx_done,
      tx_start => tx_start,
      tx_data  => tx_data,
      tx_busy  => tx_busy
    );

  -- UART 发送实例
  u_tx : entity work.uart_tx
    generic map (
      CLK_FREQ_HZ => 50000000,
      BAUD_RATE   => 115200
    )
    port map (
      clk      => clk,
      rst_n    => rst_n,
      tx_start => tx_start,
      tx_data  => tx_data,
      tx_line  => tx_line,
      tx_busy  => tx_busy
    );
end architecture;
