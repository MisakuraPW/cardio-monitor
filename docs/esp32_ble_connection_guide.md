# 上位机与 ESP32 蓝牙连接说明

本文档说明当前 Flutter Web 上位机如何通过 BLE 连接 ESP32，以及这轮修订后的通信口径。

本次修订的核心变化：
- 默认设备名前缀从 `CardioESP32` 改为 `esp32-bio`
- BLE Notify 从 `UTF-8 JSON Lines` 改为 `BIO1` 二进制帧
- 上位机会根据二进制帧自动生成通道，不再依赖 `catalog` 文本消息

## 1. 推荐连接方式

当前推荐链路：

```text
ESP32 -> BLE / Web Bluetooth -> Flutter Web 上位机
```

前端运行要求：
- 浏览器：`Chrome` 或 `Edge`
- 页面环境：`localhost` 或 HTTPS

## 2. 默认蓝牙参数

### 2.1 设备名前缀

```text
esp32-bio
```

推荐设备名示例：
- `esp32-bio`
- `esp32-bio-01`
- `esp32-bio-demo`

### 2.2 UUID

Service UUID：

```text
c0ad0001-8d2b-4d6f-9a1c-1c8a52f0a001
```

Notify Characteristic UUID：

```text
c0ad1001-8d2b-4d6f-9a1c-1c8a52f0a001
```

Control Characteristic UUID：

```text
c0ad1002-8d2b-4d6f-9a1c-1c8a52f0a001
```

## 3. 为什么仍然有 3 个 UUID

BLE 的组织方式本来就是：
- 1 个服务 UUID
- 多个特征 UUID

在当前项目里分别是：
- `serviceUuid`：定义这一整组生理数据服务
- `notifyCharacteristicUuid`：ESP32 往上位机推数据
- `controlCharacteristicUuid`：上位机给 ESP32 写控制命令

## 4. 这轮改动后，ESP32 应该发什么

### 4.1 Notify 发送 BIO1 二进制帧

BLE Notify 载荷不再要求 JSON 行，而是直接发送二进制帧：

1. `magic`：4 bytes，固定 `BIO1`
2. `type`：1 byte，`E` / `P` / `I`
3. `seq`：`uint32_le`
4. `n`：`uint16_le`
5. `samples`：样本数组

### 4.2 样本结构

ECG：
- `ts_us: uint64_le`
- `raw_adc: uint16_le`
- `lod_p: uint8`
- `lod_n: uint8`

PPG：
- `ts_us: uint64_le`
- `ir: uint32_le`
- `red: uint32_le`

IMU：
- `ts_us: uint64_le`
- `ax: int16_le`
- `ay: int16_le`
- `az: int16_le`
- `gx: int16_le`
- `gy: int16_le`
- `gz: int16_le`

## 5. 上位机现在会如何解析

上位机会在 BLE Notify 侧：
- 做字节级缓存
- 搜索 `BIO1`
- 自动拼接多包 Notify
- 根据 `type + n` 算出完整帧长度
- 解析成波形通道并直接显示

当前自动生成的通道是：
- ECG -> `ecg`
- PPG -> `ppg_ir`、`ppg_red`
- IMU -> `imu_ax`、`imu_ay`、`imu_az`、`imu_gx`、`imu_gy`、`imu_gz`

## 6. 目录消息还需不需要

这轮蓝牙联调里，`catalog` 已经不是必须项。

只要 ESP32 连上后开始稳定推送 `BIO1` 帧，上位机就会自动生成目录并显示波形。

这对当前阶段很有帮助，因为你们可以先把最关键的“稳定传输波形”跑通，再慢慢补控制接口。

## 7. 控制接口现在是什么状态

当前上位机仍然保留控制特征写入能力，写入格式还是 JSON 行，主要给后续扩展使用，例如：
- `set_channels`
- 未来可扩展 `start_stream`
- 未来可扩展 `stop_stream`

但这轮调试里，ESP32 即使暂时不处理这些控制命令，也不影响 BLE 波形显示。

## 8. 连接流程

1. ESP32 开始 BLE 广播，设备名以 `esp32-bio` 开头。
2. 上位机切到“蓝牙”模式。
3. 确认设备名前缀和 3 个 UUID 与 ESP32 一致。
4. 点击“连接 / 开始”。
5. 浏览器弹出设备选择框。
6. 选择你的 `esp32-bio-*` 设备。
7. 上位机建立 GATT 连接并订阅 Notify。
8. ESP32 开始推送 `BIO1` 帧。
9. 上位机自动识别通道并显示波形。

## 9. 当前最推荐的联调顺序

1. ESP32 先只发 ECG 二进制帧。
2. 看上位机能否出现 `ecg` 通道并滚动。
3. 再加入 PPG。
4. 再加入 IMU。
5. 最后再补控制命令和更复杂的状态上报。

## 10. 常见问题

### 10.1 已连接但没波形

检查：
- Notify 是否真的在发 `BIO1`
- `magic` 是否正确
- `type` 是否是 `E/P/I`
- `n` 是否和样本数一致
- 小端序是否写对

### 10.2 能收一部分但不稳定

检查：
- 是否分包时丢字节
- 单样本大小是否严格匹配 12 / 16 / 20 bytes
- `seq` 是否连续递增
- MTU 是否合理设置

### 10.3 设备搜不到

检查：
- 设备名是否以 `esp32-bio` 开头
- UUID 是否一致
- 浏览器是否为 Chrome / Edge
- 页面是否运行在 `localhost` 或 HTTPS
