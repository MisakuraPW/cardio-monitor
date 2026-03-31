# 基于 Flutter 的多源心肺监测上位机与云端 V1 实现计划

## Summary
- 目标是先做一个可运行的 Flutter Web 上位机，优先解决 `WiFi/MQTT 实时接入 + 数据文件回放 + 实时波形显示 + 数据上传 + 云端报告回传`。
- 项目采用同一仓库的分层结构：`Flutter Web 上位机 + Python FastAPI 云端服务 + 协议/数据模型文档与样例数据`。
- 云端建议实现为后端服务，而不是用 Flutter 写后端；如果后续需要统计后台，再单独补一个 Flutter Web 管理台。
- 首版保留三种数据源切换入口：`蓝牙 / WiFi / 数据文件`。其中 Web 首版真正落地 `WiFi + 数据文件`，蓝牙只保留接口与页面入口，后续补 Web BLE 或 Flutter Windows 端。

## Milestones
1. 环境准备与仓库初始化  
   在 `g:\课设\Flutter` 下建立单仓结构，优先完成 Flutter SDK、Web 构建环境、Python 后端环境和基础目录。默认计划文档落盘为 `IMPLEMENTATION_PLAN.md`。
2. 统一协议与数据模型  
   先定义通用数据域模型，确保 MQTT、文件回放、未来 BLE 都输出同一种 `SignalFrame`。同步确定 MQTT 主题、消息帧字段、控制指令、CSV/JSON 文件格式。
3. 上位机壳体与数据源抽象  
   Flutter Web 实现 `DataSourceAdapter` 抽象层，先落地 `MqttDataSourceAdapter` 与 `FileReplayAdapter`，蓝牙适配器先做占位实现。页面先完成三模式切换、连接状态、会话状态、动态通道列表。
4. 波形实时显示  
   实现多通道实时波形页，采用统一时间轴 + 每通道环形缓冲区。必须支持流动显示、刻度网格、暂停/继续、历史回滚、通道显隐、时间基准缩放、增益调整、信号质量状态。
5. 数据上传与云端服务  
   FastAPI 提供会话创建、数据上传、分析任务创建、报告查询接口。首版优先上传摘要特征和选定原始片段，不做默认全量原始波形上传。
6. 报告回传与联调收口  
   云端分析先做规则引擎/模拟报告适配层，完整打通“上传 -> 分析 -> 报告生成 -> 应用端查看”闭环。最后补齐联调脚本、样例数据、部署说明与演示流程。

## Key Changes
- 上位机核心接口固定为：`connect() / disconnect() / streamFrames / streamStatus / updateChannels() / sendControl()`。
- 动态通道不再写死为 ECG/PPG/PCG；由 `ChannelCatalog` 驱动，支持运行时增删通道，页面和缓存跟随目录自动变化。
- MQTT 主题建议固定为：`cardio/{deviceId}/status`、`cardio/{deviceId}/catalog`、`cardio/{deviceId}/control`、`cardio/{deviceId}/waveform/{channelKey}`、`cardio/{deviceId}/metrics`、`cardio/{deviceId}/alerts`。
- 波形帧建议至少包含：`deviceId`、`sessionId`、`seq`、`timestampMs`、`channelKey`、`sampleRate`、`unit`、`quality`、`samples[]`。高频信号按帧发送，不按单点发送。
- 文件回放首版支持 `CSV`，扩展支持 `JSON`；导入时完成列映射、单位映射、采样率和时间戳映射，随后进入与 MQTT 完全相同的下游流程。
- 云端 REST 接口建议固定为：`POST /api/v1/sessions`、`POST /api/v1/sessions/{id}/uploads`、`POST /api/v1/analysis/jobs`、`GET /api/v1/analysis/jobs/{id}`、`GET /api/v1/reports/{sessionId}`。
- Dart 公共类型至少包含：`ChannelDescriptor`、`SignalFrame`、`SessionRecord`、`UploadTask`、`AnalysisJob`、`MedicalReport`。

## Test Plan
- 验证 MQTT 与文件回放都能进入同一缓存、波形、上传、报告流程，不出现双套逻辑。
- 验证通道可在运行中新增、删除、禁用、恢复，界面和上传内容同步变化。
- 验证多采样率通道同时显示时，时间轴对齐正确，回滚和暂停后不丢帧、不跳轴。
- 验证网络抖动、重连、乱序帧、缺帧时，系统能重排、补空窗或明确标记异常。
- 验证上传失败重试、任务轮询、报告回传、报告再次打开等完整闭环。
- 验证 Web 构建可正常运行，即使蓝牙适配器尚未启用也不影响首版交付。

## Assumptions
- 当前 `g:\课设\Flutter` 为空目录，且本机在 2026-03-30 这次检查时未检测到 `flutter/dart` 命令，因此初始化与工具链安装属于第一阶段必做项。
- Flutter Web 首版只正式支持 `WiFi(MQTT over WebSocket)` 和 `数据文件回放`；蓝牙因 Web Bluetooth 受浏览器兼容性、HTTPS、安全上下文限制，先保留接口与入口，不在 V1 强交付。
- 云端技术栈默认选 `FastAPI + PostgreSQL + 本地磁盘/对象存储抽象`，因为后续接医疗模型与规则分析更顺手。
- 首版分析默认使用“适配层 + 模拟/规则报告”，不直接接真实医疗大模型；后续可替换为 OpenAI 兼容接口或其他医疗模型服务。
- 联邦学习、差分隐私、边缘训练本轮不实现，只在架构上预留后续扩展点，不进入 V1 开发范围。
