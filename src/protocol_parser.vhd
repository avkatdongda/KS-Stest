library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 协议解析模块：
-- 解析 7E 7E [XX] [YY] 帧，并生成对应回复：
--   - 如果 [XX][YY] = AA AA => 回复 7E 7E BB BB
--   - 否则回复 7E 7E CC CC
-- 发送输出采用 tx_start/tx_data + tx_busy 握手，确保逐字节输出。
entity protocol_parser is
  port (
    clk      : in  std_logic;
    rst_n    : in  std_logic;
    rx_data  : in  std_logic_vector(7 downto 0);
    rx_done  : in  std_logic;
    tx_start : out std_logic;
    tx_data  : out std_logic_vector(7 downto 0);
    tx_busy  : in  std_logic
  );
end entity;

architecture rtl of protocol_parser is
  -- 状态机定义
  type parser_state_t is (
    IDLE,
    CHECK_HEAD1,
    CHECK_HEAD2,
    GET_DATA,
    EVAL,
    SEND_REPLY
  );

  -- 4 字节缓冲区，用于存放 payload 和 reply
  type reply_array_t is array (0 to 3) of std_logic_vector(7 downto 0);

  signal state         : parser_state_t := IDLE;
  -- payload 只使用低 2 个元素
  signal payload       : reply_array_t := (others => (others => '0'));
  signal reply_data    : reply_array_t := (others => (others => '0'));
  signal payload_idx   : integer range 0 to 1 := 0;
  signal reply_idx     : integer range 0 to 3 := 0;
  -- 输出寄存器与发送节拍控制（先装载数据，后给出 tx_start 脉冲）
  signal tx_start_reg  : std_logic := '0';
  signal tx_data_reg   : std_logic_vector(7 downto 0) := (others => '0');
  signal send_pending  : std_logic := '0';
  signal start_pending : std_logic := '0';

  -- 固定协议字节常量
  constant HEAD_BYTE   : std_logic_vector(7 downto 0) := x"7E";
  constant MATCH_BYTE  : std_logic_vector(7 downto 0) := x"AA";
  constant RESP_MATCH  : std_logic_vector(7 downto 0) := x"BB";
  constant RESP_OTHER  : std_logic_vector(7 downto 0) := x"CC";
begin
  tx_start <= tx_start_reg;
  tx_data  <= tx_data_reg;

  process (clk, rst_n)
  begin
    if rst_n = '0' then
      -- 异步复位：清空状态与缓冲区
      state        <= IDLE;
      payload      <= (others => (others => '0'));
      reply_data   <= (others => (others => '0'));
      payload_idx  <= 0;
      reply_idx    <= 0;
      tx_start_reg <= '0';
      tx_data_reg  <= (others => '0');
      send_pending <= '0';
      start_pending <= '0';
    elsif rising_edge(clk) then
      -- tx_start 默认拉低，确保单周期脉冲
      tx_start_reg <= '0';
      if start_pending = '1' then
        if tx_busy = '0' then
          tx_start_reg  <= '1';
          start_pending <= '0';
        end if;
      end if;

      case state is
        when IDLE =>
          -- 等待第一个字节
          payload_idx <= 0;
          if rx_done = '1' then
            if rx_data = HEAD_BYTE then
              state <= CHECK_HEAD2;
            else
              state <= IDLE;
            end if;
          end if;

        when CHECK_HEAD1 =>
          -- 预留状态（当前流程未使用）
          if rx_done = '1' then
            if rx_data = HEAD_BYTE then
              state <= CHECK_HEAD2;
            else
              state <= IDLE;
            end if;
          end if;

        when CHECK_HEAD2 =>
          -- 确认第二个头字节
          if rx_done = '1' then
            if rx_data = HEAD_BYTE then
              payload_idx <= 0;
              state       <= GET_DATA;
            else
              state <= IDLE;
            end if;
          end if;

        when GET_DATA =>
          -- 接收 2 字节 payload
          if rx_done = '1' then
            payload(payload_idx) <= rx_data;
            if payload_idx = 1 then
              state <= EVAL;
            else
              payload_idx <= payload_idx + 1;
            end if;
          end if;

        when EVAL =>
          -- 生成回复帧内容
          reply_data(0) <= HEAD_BYTE;
          reply_data(1) <= HEAD_BYTE;
          if payload(0) = MATCH_BYTE and payload(1) = MATCH_BYTE then
            reply_data(2) <= RESP_MATCH;
            reply_data(3) <= RESP_MATCH;
          else
            reply_data(2) <= RESP_OTHER;
            reply_data(3) <= RESP_OTHER;
          end if;
          reply_idx    <= 0;
          send_pending <= '1';
          state        <= SEND_REPLY;

        when SEND_REPLY =>
          -- 串行输出 4 字节，并等待 UART_TX 空闲
          if send_pending = '1' then
            if tx_busy = '0' then
              tx_data_reg   <= reply_data(reply_idx);
              start_pending <= '1';
              send_pending  <= '0';
            end if;
          else
            if tx_busy = '0' then
              if reply_idx = 3 then
                state <= IDLE;
              else
                reply_idx    <= reply_idx + 1;
                send_pending <= '1';
              end if;
            end if;
          end if;
      end case;
    end if;
  end process;
end architecture;
