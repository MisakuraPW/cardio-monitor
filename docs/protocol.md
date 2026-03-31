# 通信协议与数据模型

## 1. 设计目标

- 统一 `WiFi/MQTT`、`蓝牙`、`文件回放` 三种数据接入方式的下游处理逻辑
- 允许通道在运行期动态新增、删除、禁用、恢复
- 允许在没有硬件的情况下用 `CSV/JSON` 文件替代实时采集
- 将实时流与云端管理职责分离：`MQTT` 负责实时流，`REST` 负责会话、上传、分析与报告

## 2. MQTT 主题规范

统一命名空间：

```text
cardio/{deviceId}/status
cardio/{deviceId}/catalog
cardio/{deviceId}/control
cardio/{deviceId}/waveform/{channelKey}
cardio/{deviceId}/metrics
cardio/{deviceId}/alerts
```

建议 QoS：

- `status`：`QoS 1`
- `catalog`：`QoS 1`
- `control`：`QoS 1`
- `waveform/*`：`QoS 0`
- `metrics`：`QoS 1`
- `alerts`：`QoS 1`

## 3. 通道目录消息

主题：`cardio/{deviceId}/catalog`

```json
{
  "deviceId": "esp32-demo-01",
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

## 4. 波形帧消息

主题：`cardio/{deviceId}/waveform/{channelKey}`

```json
{
  "deviceId": "esp32-demo-01",
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

字段说明：

- `timestampMs`：这一帧第一个采样点的时间戳
- `samples`：建议 20ms 到 200ms 的采样片段
- `quality`：`0.0 ~ 1.0`，可用于界面显示与云端评估

## 5. 控制指令消息

主题：`cardio/{deviceId}/control`

```json
{
  "type": "set_channels",
  "payload": {
    "enabledKeys": ["ecg", "ppg", "pcg"]
  }
}
```

常用控制指令：

- `set_channels`
- `set_sample_rate`
- `start_stream`
- `stop_stream`
- `sync_clock`

## 6. 文件回放格式

### CSV

首列建议为时间戳列，其他列为动态通道：

```csv
timestamp_ms,ecg_mV,ppg_au,pcg_au,spo2_pct,temp_c
1711780800000,0.01,0.42,0.06,98.0,36.7
1711780800004,0.03,0.43,0.05,98.0,36.7
```

解析规则：

- `timestamp_ms`、`time_ms`、`time` 都视为时间列
- 其他列自动转换为通道
- 列名中以下划线后的片段视为单位，如 `ecg_mV`
- 无法识别单位时使用 `a.u.`

### JSON

```json
{
  "deviceId": "file-demo-01",
  "sessionId": "file-session-01",
  "channels": [
    { "key": "ecg", "label": "ECG", "unit": "mV", "sampleRate": 250, "colorHex": "#F25F5C", "enabled": true }
  ],
  "frames": [
    {
      "deviceId": "file-demo-01",
      "sessionId": "file-session-01",
      "seq": 1,
      "timestampMs": 1711780800000,
      "channelKey": "ecg",
      "sampleRate": 250,
      "unit": "mV",
      "quality": 0.95,
      "samples": [0.01, 0.03, 0.07]
    }
  ]
}
```

## 7. 云端 REST 载荷

### 创建会话

`POST /api/v1/sessions`

```json
{
  "deviceId": "esp32-demo-01",
  "sourceMode": "wifi",
  "channelKeys": ["ecg", "ppg", "pcg"],
  "startedAt": "2026-03-30T22:55:00Z"
}
```

### 上传摘要

`POST /api/v1/sessions/{id}/uploads`

```json
{
  "summary": {
    "durationSeconds": 18.4,
    "qualityScore": 0.88,
    "channels": {
      "ecg": { "samples": 4600, "mean": 0.08, "min": -0.22, "max": 1.08 },
      "ppg": { "samples": 1840, "mean": 0.52, "min": 0.31, "max": 0.84 }
    }
  },
  "excerpts": {
    "ecg": [0.01, 0.03, 0.07, 0.48, 0.95]
  }
}
```

### 创建分析任务

`POST /api/v1/analysis/jobs`

```json
{
  "sessionId": "session-001"
}
```

## 8. 首版规则分析范围

首版报告只做演示级分析，不输出医疗诊断结论。默认规则包括：

- 数据时长是否足够
- 通道数量是否满足多源监测
- 平均质量评分是否过低
- 是否存在明显幅值异常或数据缺失

