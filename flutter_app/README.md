# Flutter Web 上位机

## 当前能力

- 三种模式入口：`蓝牙`、`WiFi(MQTT)`、`数据文件`
- 已实现：`WiFi(MQTT over WebSocket)`、`CSV/JSON 文件回放`
- 蓝牙：Web 首版保留页面入口与占位适配器
- 多通道动态目录与显隐控制
- 实时波形显示：流动、刻度网格、暂停/继续、历史回滚、增益缩放
- 云端上传、分析任务创建、报告回传

## 运行

```powershell
flutter pub get
flutter run -d chrome
```

## 页面组成

- 左侧：数据源配置、连接控制、文件导入、云端地址、上传分析、通道列表、状态日志
- 右侧：多通道实时波形、时间基准控制、报告查看

## 说明

- MQTT 连接需要 Broker 开启 WebSocket
- Web 首版蓝牙入口仅做占位提示，不影响其他功能
- 文件回放建议先使用仓库内 `sample_data/` 中的样例文件

