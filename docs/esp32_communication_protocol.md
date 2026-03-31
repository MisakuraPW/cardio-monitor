# ESP32 通信协议说明

本文档确定本项目中 ESP32 与上位机之间的两种实时通信方式：

- `WiFi + MQTT`
- `BLE / Web Bluetooth`

目标是让 ESP32、Flutter Web 上位机和文件回放三种输入方式尽量共用同一套数据模型与后续处理链路。

## 1. 统一数据模型

无论来自 MQTT、BLE 还是文件回放，进入上位机之后都统一转换为以下两类对象：

### 1.1 通道目录 `catalog`

```json
{
  "deviceId": "esp32-cardio-01",
  "sessionId": "session-001",
  "channels": [
    {
      "key": "ecg",
      "label": "ECG",
      "unit": "mV",
      "sampleRate": 250,
      "colorHex": "#F25F5C",
      "enabled": true
    },
    {
      "key": "ppg",
      "label": "PPG",
      "unit": "a.u.",
      "sampleRate": 100,
      "colorHex": "#247BA0",
      "enabled": true
    }
  ]
}
```

### 1.2 波形帧 `frame`

```json
{
  "deviceId": "esp32-cardio-01",
  "sessionId": "session-001",
  "seq": 128,
  "timestampMs": 1711780800000,
  "channelKey": "ecg",
  "sampleRate": 250,
  "unit": "mV",
  "quality": 0.92,
  "samples": [0.03, 0.04, 0.08, 0.45, 0.92, 0.51]
}
```

字段要求：

- `timestampMs` 使用毫秒时间戳
- `samples` 是一小段连续样本，而不是单点上传
- `seq` 为每个会话内递增序号
- `quality` 范围建议 `0.0 ~ 1.0`

## 2. WiFi / MQTT 协议

### 2.1 主题结构

```text
cardio/{deviceId}/status
cardio/{deviceId}/catalog
cardio/{deviceId}/control
cardio/{deviceId}/waveform/{channelKey}
cardio/{deviceId}/metrics
cardio/{deviceId}/alerts
```

### 2.2 主题用途

- `status`：设备在线状态、连接状态、电量、固件版本
- `catalog`：设备当前可用通道目录，可动态增删通道
- `control`：上位机发送控制命令
- `waveform/{channelKey}`：原始波形帧
- `metrics`：设备端计算后的即时指标
- `alerts`：异常事件、信号质量过低、设备离线等

### 2.3 QoS 建议

- `status`：`QoS 1`
- `catalog`：`QoS 1`
- `control`：`QoS 1`
- `waveform/*`：`QoS 0`
- `metrics`：`QoS 1`
- `alerts`：`QoS 1`

### 2.4 控制命令格式

ESP32 订阅 `cardio/{deviceId}/control`，消息体统一为 JSON：

```json
{
  "type": "set_channels",
  "payload": {
    "enabledKeys": ["ecg", "ppg", "pcg"]
  }
}
```

常用命令：

- `hello`
- `get_catalog`
- `set_channels`
- `set_sample_rate`
- `start_stream`
- `stop_stream`
- `sync_clock`

### 2.5 ESP32 端推荐行为

- 上电后先连接 WiFi 和 MQTT Broker
- 连上后立即发布一次 `status`
- 连上后立即发布一次 `catalog`
- 采样过程中按通道发布 `waveform` 帧
- 收到 `set_channels` 后动态启停对应通道
- 收到 `get_catalog` 时重新发布目录

## 3. BLE / Web Bluetooth 协议

Web 端蓝牙基于浏览器的 Web Bluetooth，只支持 BLE，不支持经典蓝牙串口。

### 3.1 GATT 服务与特征 UUID

本项目固定如下 UUID：

- 服务 UUID：`c0ad0001-8d2b-4d6f-9a1c-1c8a52f0a001`
- 数据通知特征 UUID：`c0ad1001-8d2b-4d6f-9a1c-1c8a52f0a001`
- 控制写入特征 UUID：`c0ad1002-8d2b-4d6f-9a1c-1c8a52f0a001`

推荐设备名：`CardioESP32-*`

### 3.2 BLE 消息承载方式

BLE 采用 `UTF-8 JSON Lines`：

- ESP32 发出的每一条业务消息都编码为一行 JSON 文本
- 每条 JSON 末尾必须附带换行符 `\n`
- 如果单条 JSON 长度超过单个通知包可承载的大小，ESP32 可以把该文本按字节切片后分多个通知发出
- 上位机按字节拼接，直到遇到换行符，再解析为一条完整消息

这意味着 BLE 链路不要求“一个通知包等于一条完整消息”，只要求“按顺序把 UTF-8 字节流送达”。

### 3.3 BLE 业务消息类型

BLE 数据通知特征发出的业务消息统一为：

```json
{
  "type": "catalog",
  "payload": {
    "deviceId": "esp32-cardio-01",
    "sessionId": "session-001",
    "channels": []
  }
}
```

或：

```json
{
  "type": "frame",
  "payload": {
    "deviceId": "esp32-cardio-01",
    "sessionId": "session-001",
    "seq": 128,
    "timestampMs": 1711780800000,
    "channelKey": "ecg",
    "sampleRate": 250,
    "unit": "mV",
    "quality": 0.92,
    "samples": [0.03, 0.04, 0.08, 0.45]
  }
}
```

支持的 `type`：

- `catalog`
- `frame`
- `status`
- `alerts`
- `metrics`
- `ack`

### 3.4 BLE 控制消息格式

上位机写入控制特征时，同样发送 `UTF-8 JSON Lines`：

```json
{
  "type": "get_catalog",
  "payload": {}
}
```

或：

```json
{
  "type": "set_channels",
  "payload": {
    "enabledKeys": ["ecg", "ppg"]
  }
}
```

### 3.5 BLE 使用建议

- BLE 主要用于近距离调试、设备配对、低吞吐演示
- 如果需要长期稳定上传高频多通道原始波形，优先使用 `WiFi + MQTT`
- BLE 帧建议更短，例如每帧只携带 `20 ~ 80 ms` 左右的数据
- 设备端应尽量先提高 MTU，再开始通知

## 4. ESP32 端时间与同步要求

- 所有通道必须使用同一时间基准
- `timestampMs` 表示当前帧第一个采样点的时间戳
- 同一帧内的后续采样点时间由 `sampleRate` 推导
- 如果设备已联网，建议同步 NTP 时间
- 如果尚未联网，也至少保证单机递增时间戳连续可用

## 5. 目录与动态通道要求

ESP32 不能把通道写死为固定三种。设备必须支持：

- 启动时上报当前可用通道目录
- 根据配置动态启停通道
- 新增一个新传感器后，只需把新通道加入目录即可
- 上位机按目录自动生成界面与缓存，不需要重新改前端代码

推荐通道命名：

- `ecg`
- `ppg`
- `pcg`
- `spo2`
- `temp`
- `resp`
- `imu_x`
- `imu_y`
- `imu_z`

## 6. 首版 ESP32 实现优先级

建议先按以下顺序开发设备端：

1. BLE 连接与 `catalog` 返回
2. BLE `frame` 推送与上位机显示
3. MQTT 连接与 `catalog` 发布
4. MQTT `frame` 发布
5. 控制命令 `set_channels / get_catalog / start_stream / stop_stream`
6. `metrics / alerts`

## 7. 与 Flutter 上位机当前实现对应关系

当前上位机已经按以下约定实现：

- MQTT：订阅 `catalog` 和 `waveform/*`
- BLE：扫描设备名 `CardioESP32-*`，连接上述 UUID 的服务与特征
- BLE：接收 `JSON Lines`，支持目录消息和波形帧消息
- 文件回放：最终进入同一套 `SignalFrame` 缓存、显示、上传和报告流程
