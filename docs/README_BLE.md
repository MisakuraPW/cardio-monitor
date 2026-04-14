# ESP32 BLE 调试协议说明

本文档用于约定 `ESP32 -> BLE -> Flutter Web 上位机` 的调试协议。

当前仓库里的上位机已经按本文档完成了 BLE 接收侧修订，重点变化有两点：
- 默认设备名前缀改为 `esp32-bio`
- Notify 载荷从 `JSON Lines` 改为 `BIO1` 二进制帧

## 1. 默认配置

- 设备名前缀：`esp32-bio`
- Service UUID：`c0ad0001-8d2b-4d6f-9a1c-1c8a52f0a001`
- Notify Characteristic UUID：`c0ad1001-8d2b-4d6f-9a1c-1c8a52f0a001`
- Control Characteristic UUID：`c0ad1002-8d2b-4d6f-9a1c-1c8a52f0a001`
- 建议 MTU：`512`

上位机当前会按 `namePrefix + serviceUuid` 过滤设备，所以最稳妥的广播名是：
- `esp32-bio`
- `esp32-bio-01`
- `esp32-bio-demo`

## 2. GATT 结构

建议 ESP32 侧创建 1 个服务、2 个特征：

- 服务 UUID：`c0ad0001-8d2b-4d6f-9a1c-1c8a52f0a001`
- 通知特征 UUID：`c0ad1001-8d2b-4d6f-9a1c-1c8a52f0a001`
  - 属性建议：`READ | NOTIFY`
- 控制特征 UUID：`c0ad1002-8d2b-4d6f-9a1c-1c8a52f0a001`
  - 属性建议：`WRITE | WRITE WITHOUT RESPONSE`

## 3. Notify 载荷协议

BLE Notify 载荷复用 MQTT 二进制 telemetry 帧，采用小端序。

帧头格式：
1. `magic`：4 bytes，固定为 ASCII `BIO1`
2. `type`：1 byte，`E` / `P` / `I`
3. `seq`：`uint32_le`
4. `n`：`uint16_le`
5. `samples`：按 `type` 决定的样本数组

### 3.1 ECG 帧

- `type = 'E'`
- 单个样本大小：12 bytes
- 每个样本结构：
  - `ts_us: uint64_le`
  - `raw_adc: uint16_le`
  - `lod_p: uint8`
  - `lod_n: uint8`

### 3.2 PPG 帧

- `type = 'P'`
- 单个样本大小：16 bytes
- 每个样本结构：
  - `ts_us: uint64_le`
  - `ir: uint32_le`
  - `red: uint32_le`

### 3.3 IMU 帧

- `type = 'I'`
- 单个样本大小：20 bytes
- 每个样本结构：
  - `ts_us: uint64_le`
  - `ax: int16_le`
  - `ay: int16_le`
  - `az: int16_le`
  - `gx: int16_le`
  - `gy: int16_le`
  - `gz: int16_le`

## 4. 分包与重组

单个 `BIO1` 帧可以被拆成多个 BLE Notify 包发送。

上位机当前实现会：
- 按字节缓存 Notify 数据
- 搜索 `BIO1` 魔数
- 根据 `type + n` 计算完整帧长度
- 自动拼包后再解析

所以 ESP32 侧不需要额外加换行符，也不需要额外的文本分隔符。

## 5. 上位机如何映射为通道

当前 Flutter Web 上位机会自动从二进制帧生成通道目录，不再依赖 `catalog` 文本消息。

映射规则如下：
- ECG 帧 -> `ecg`
- PPG 帧 -> `ppg_ir`、`ppg_red`
- IMU 帧 -> `imu_ax`、`imu_ay`、`imu_az`、`imu_gx`、`imu_gy`、`imu_gz`

也就是说，只要 ESP32 连上后开始推 `BIO1` 帧，上位机就会自动看到这些通道并开始画波形。

## 6. 采样率处理

上位机会优先根据同一帧内相邻样本的 `ts_us` 自动估算采样率。

如果估算失败，回退值为：
- ECG：`500 Hz`
- PPG：`100 Hz`
- IMU：`100 Hz`

## 7. 控制特征的现状

当前修订重点是把 Notify 接口改成二进制协议。

所以现在的联调建议是：
- ESP32 先优先保证 Notify 二进制流稳定输出
- Control 特征可以先保留
- 即使 Control 还没有真正实现，上位机也已经能在连接后直接接收并显示波形

当前上位机写控制特征时，仍然会发送 JSON 行命令，主要用于后续扩展：
- `set_channels`
- 未来可扩展 `start_stream` / `stop_stream`

如果 ESP32 这轮还没实现控制解析，可以先忽略这些写入，不影响 BIO1 波形调试。

## 8. 联调建议

推荐先按下面顺序联调：
1. ESP32 能被浏览器发现，设备名以 `esp32-bio` 开头。
2. 上位机能连接到 BLE 服务和两个特征。
3. ESP32 只发送一种最简单的 `ECG BIO1` 帧。
4. 上位机确认 `ecg` 通道出现且波形滚动。
5. 再逐步加入 `PPG` 和 `IMU`。

## 9. 常见问题

### 9.1 连上了但没有波形

优先检查：
- Notify 特征是否真的在发 `BIO1` 帧
- `magic` 是否为 `BIO1`
- `type` 是否为 `E/P/I`
- `n` 与真实样本数量是否一致
- 小端序是否写对

### 9.2 只有部分波形或通道错乱

优先检查：
- 单个样本字节数是否严格匹配 12 / 16 / 20
- 分包后是否丢字节
- `seq` 是否单调递增

### 9.3 设备搜不到

优先检查：
- 设备名是否以 `esp32-bio` 开头
- UUID 是否与上位机一致
- 页面是否运行在 `localhost` 或 HTTPS
- 浏览器是否为 Chrome / Edge
