# RS422 UART 通信系统（Xilinx FPGA / VHDL）

## 1. 项目概述
本工程提供一个完整的 RS422 串口通信系统，包含 UART 接收、UART 发送、协议解析与顶层集成模块，并附带可仿真的 Testbench。系统参数如下：

- **系统时钟**：50 MHz
- **波特率**：115200 bps
- **复位**：低电平异步复位（Active Low, Async）
- **UART 格式**：8N1（8 数据位，无校验，1 停止位）

目录结构：

- `src/uart_rx.vhd`：UART 接收驱动
- `src/uart_tx.vhd`：UART 发送驱动
- `src/protocol_parser.vhd`：协议解析核心逻辑
- `src/top_module.vhd`：顶层集成模块
- `tb/top_module_tb.vhd`：仿真 Testbench

## 2. 模块功能说明

### 2.1 UART_RX（接收驱动）
- 负责从 `rx_line` 接收 UART 字节。
- 在收到完整 1 字节后，输出 `rx_data` 并在 `rx_done` 给出一个单周期脉冲。

### 2.2 UART_TX（发送驱动）
- 接收上层 `tx_start` 脉冲和 `tx_data` 字节。
- 在 `tx_busy` 期间持续发送 UART 帧，空闲时 `tx_line` 维持高电平。

### 2.3 Protocol_Parser（协议解析）
- 按照协议要求解析数据帧：
  - 等待帧头 `7E 7E`
  - 读取后续 2 字节作为 Payload
  - 若 Payload 为 `AA AA`，发送 `7E 7E BB BB`
  - 否则发送 `7E 7E CC CC`
- 内部状态机按字节驱动，并将发回数据送至 UART_TX。

### 2.4 Top_Module（顶层）
- 将 `UART_RX`、`Protocol_Parser` 与 `UART_TX` 连接起来，实现完整的收发链路。

## 3. 状态机流转（文字描述）

Protocol_Parser 状态机流程如下：

1. **IDLE**：等待接收第一个字节。
2. **CHECK_HEAD1**：本实现将 IDLE 与第一字节检查合并（若非 0x7E，保持 IDLE）。
3. **CHECK_HEAD2**：收到第二个字节，若仍为 `0x7E`，进入数据接收阶段。
4. **GET_DATA**：连续接收 2 字节 Payload。
5. **PROCESS**：
   - 若 Payload == `AA AA`，准备回复 `7E 7E BB BB`。
   - 否则准备回复 `7E 7E CC CC`。
6. **SEND_REPLY**：依次发送 4 个字节，全部发完后回到 **IDLE**。

## 4. 如何仿真

以 GHDL 为例：

```bash
# 进入工程目录
cd /workspace/KS-Stest

# 编译
ghdl -a src/uart_rx.vhd src/uart_tx.vhd src/protocol_parser.vhd src/top_module.vhd tb/top_module_tb.vhd

# 运行
ghdl -e top_module_tb
./top_module_tb
```

仿真会执行两个用例：

- **Case 1**：输入 `7E 7E AA AA`，验证输出末尾为 `BB BB`
- **Case 2**：输入 `7E 7E 12 34`，验证输出末尾为 `CC CC`

如果输出不匹配，Testbench 会触发 `assert` 报错。

## 5. 为什么这样改更好？

- **解耦（Decoupling）**：UART 驱动与协议逻辑分离，符合 FPGA 设计规范。未来修改波特率或底层串口实现时，无需触碰协议层。
- **消除歧义**：明确规定固定 4 字节窗口（`7E 7E [XX] [YY]`），确保能区分 `AA AA` 与其它数据，避免只处理 2 字节的设计错误。
- **便于验证**：Testbench 的 Case 1 / Case 2 覆盖了两条分支逻辑，确保“匹配”与“非匹配”的行为都被验证。
