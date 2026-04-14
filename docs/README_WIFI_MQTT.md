# ESP32 WiFi / MQTT 协议说明

本文档描述的是 `ESP32 -> WiFi / MQTT -> 上位机或云端` 的设备侧协议约定。

它和 BLE 的关键统一点是：
- 二进制 telemetry 都使用同一套 `BIO1` 帧结构
- status 仍然使用 JSON

## 1. 建议开关

建议 ESP32 侧保留以下开关：
- `ENABLE_WIFI_OUTPUT`
- `ENABLE_UART_OUTPUT`
- `ENABLE_SERIAL_LOGGER`
- `MQTT_PAYLOAD_MODE`

推荐含义：
- `MQTT_PAYLOAD_MODE = 0`：只发 JSON telemetry
- `MQTT_PAYLOAD_MODE = 1`：只发二进制 telemetry
- `MQTT_PAYLOAD_MODE = 2`：JSON + 二进制双发，便于兼容联调

如果目标是稳定传输与低开销，推荐优先使用：
- `MQTT_PAYLOAD_MODE = 1`

## 2. MQTT 主题建议

设备侧建议至少保留 3 个主题：
- telemetry JSON：`esp32/trans1/telemetry`
- telemetry binary：`esp32/trans1/telemetry_bin`
- status JSON：`esp32/trans1/status`

你也可以把 `trans1` 替换成自己的设备分组或设备编号，但同一批设备最好统一命名规则。

## 3. BIO1 二进制 telemetry 协议

二进制帧使用小端序，结构如下：
1. `magic`：4 bytes，固定为 ASCII `BIO1`
2. `type`：1 byte，`E` / `P` / `I`
3. `seq`：`uint32_le`
4. `n`：`uint16_le`
5. `samples`：按 `type` 决定的样本数组

### 3.1 ECG 帧

- `type = 'E'`
- 单个样本大小：12 bytes
- 样本结构：
  - `ts_us: uint64_le`
  - `raw_adc: uint16_le`
  - `lod_p: uint8`
  - `lod_n: uint8`

### 3.2 PPG 帧

- `type = 'P'`
- 单个样本大小：16 bytes
- 样本结构：
  - `ts_us: uint64_le`
  - `ir: uint32_le`
  - `red: uint32_le`

### 3.3 IMU 帧

- `type = 'I'`
- 单个样本大小：20 bytes
- 样本结构：
  - `ts_us: uint64_le`
  - `ax: int16_le`
  - `ay: int16_le`
  - `az: int16_le`
  - `gx: int16_le`
  - `gy: int16_le`
  - `gz: int16_le`

## 4. JSON telemetry 协议

如果还需要保留 JSON 兼容路径，建议字段名固定，不要随意改动。

### 4.1 ECG JSON 示例

```json
{
  "device": "esp32-bio-ABCD",
  "type": "ECG",
  "seq": 1001,
  "n": 24,
  "samples": [
    [191011272, 4095, 1, 1],
    [191013297, 4090, 1, 1]
  ]
}
```

每个 ECG 样本字段顺序为：
- `[ts_us, raw_adc, lod_p, lod_n]`

### 4.2 PPG JSON 示例

```json
{
  "device": "esp32-bio-ABCD",
  "type": "PPG",
  "seq": 1002,
  "n": 12,
  "samples": [
    [159501316, 103840, 104257],
    [159506316, 103859, 104262]
  ]
}
```

每个 PPG 样本字段顺序为：
- `[ts_us, ir, red]`

### 4.3 IMU JSON 示例

```json
{
  "device": "esp32-bio-ABCD",
  "type": "IMU",
  "seq": 1003,
  "n": 12,
  "samples": [
    [210000000, -12, 104, 16390, 2, -1, 0],
    [210005000, -11, 103, 16388, 2, -1, 0]
  ]
}
```

每个 IMU 样本字段顺序为：
- `[ts_us, ax, ay, az, gx, gy, gz]`

## 5. Status JSON 协议

status 建议继续使用 JSON，便于调试和日志查看。

```json
{
  "device": "esp32-bio-ABCD",
  "seq": 1200,
  "uptime_ms": 123456,
  "rssi": -45,
  "q": {"ecg": 120, "ppg": 30, "imu": 28},
  "drop": {"ecg": 0, "ppg": 2, "imu": 1},
  "ow": {"ecg": 10, "ppg": 5, "imu": 3}
}
```

字段建议：
- `q`：当前队列长度
- `drop`：累计丢包或丢帧计数
- `ow`：累计覆盖写入计数或队列溢出计数

## 6. 发送策略建议

为了降低高频 ECG 的阻塞风险，建议采用“采样任务”和“打包任务”分离：
- 采样任务只负责把 ECG / PPG / IMU 放入主队列
- 打包任务负责按批次取样并发 MQTT

推荐思路：
- ECG 每帧多打一些样本，降低 publish 次数
- PPG / IMU 维持较小帧长，减少等待时间
- `seq` 按帧递增，不按单个样本递增

## 7. 与上位机当前实现的关系

当前这轮 Flutter Web 修订，已经完成了 BLE 侧的 `BIO1` 二进制解析。

这意味着：
- BLE 直连调试已经能直接吃 `BIO1`
- WiFi / MQTT 直连后续也建议沿用同一套二进制帧
- 这样 ESP32 只需要维护一套 telemetry 打包逻辑

## 8. 联调建议

推荐顺序：
1. 先在 BLE 链路上把 `BIO1` 帧跑通。
2. 确认 `seq`、`n`、样本字节数都稳定。
3. 再把同样的打包器接到 MQTT 发布路径。
4. 最后决定是否保留 JSON 双发兼容模式。
