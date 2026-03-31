# 基于 Flutter 的多源心肺监测上位机与云端 V1 实现计划

## Summary

- 目标是先做一个可运行的 Flutter Web 上位机，优先解决 `WiFi/MQTT 实时接入 + 数据文件回放 + 实时波形显示 + 数据上传 + 云端报告回传`。
- 项目采用同一仓库的分层结构：`Flutter Web 上位机 + Python FastAPI 云端服务 + 协议/数据模型文档与样例数据`。
- 云端以后端服务实现，后续如需统计后台，可在现有接口上再增加 Flutter Web 管理台。
- 首版保留三种数据源切换入口：`蓝牙 / WiFi / 数据文件`。其中 Web 首版真正落地 `WiFi + 数据文件`，蓝牙保留接口与入口。

## Milestones

1. 环境准备与仓库初始化
   在 `g:\课设\Flutter` 下建立单仓结构，完成基础目录、说明文档和调试样例。
2. 统一协议与数据模型
   定义通用 `SignalFrame`、通道目录、控制指令和上传报告模型。
3. 上位机壳体与数据源抽象
   Flutter Web 实现统一 `DataSourceAdapter` 抽象，先落地 MQTT 和文件回放。
4. 波形实时显示
   使用统一时间轴和每通道环形缓冲区展示多通道流式波形。
5. 数据上传与云端服务
   FastAPI 提供会话、上传、分析任务和报告接口。
6. 报告回传与联调收口
   使用规则引擎/模拟报告打通上传、分析、回传闭环。

## Key Changes

- 上位机核心接口固定为：`connect() / disconnect() / streamFrames / streamStatus / updateChannels() / sendControl()`
- 动态通道由 `ChannelCatalog` 驱动，不写死为 ECG/PPG/PCG。
- MQTT 主题固定为：
  - `cardio/{deviceId}/status`
  - `cardio/{deviceId}/catalog`
  - `cardio/{deviceId}/control`
  - `cardio/{deviceId}/waveform/{channelKey}`
  - `cardio/{deviceId}/metrics`
  - `cardio/{deviceId}/alerts`
- 波形帧字段至少包含：
  - `deviceId`
  - `sessionId`
  - `seq`
  - `timestampMs`
  - `channelKey`
  - `sampleRate`
  - `unit`
  - `quality`
  - `samples[]`
- 文件回放首版支持 `CSV` 和 `JSON`
- 云端 REST 接口固定为：
  - `POST /api/v1/sessions`
  - `POST /api/v1/sessions/{id}/uploads`
  - `POST /api/v1/analysis/jobs`
  - `GET /api/v1/analysis/jobs/{id}`
  - `GET /api/v1/reports/{sessionId}`

## Test Plan

- 验证 MQTT 与文件回放走同一缓存、波形、上传、报告流程
- 验证通道运行中新增、删除、禁用、恢复能正确反映到界面与上传摘要
- 验证多采样率通道同时显示时对齐正确
- 验证暂停、继续、回滚、时间缩放、增益调整行为稳定
- 验证上传失败、任务轮询、报告回传闭环
- 验证蓝牙入口不影响 Web 首版交付

## Assumptions

- 当前目录原本为空目录，需要从零初始化项目
- 本机在实现时未检测到 `flutter/dart` 命令，因此 Flutter 代码已落盘但未在本机完成运行验证
- Flutter Web 首版只正式支持 `WiFi(MQTT over WebSocket)` 与 `数据文件回放`
- 云端首版使用规则引擎/模拟分析，不直接接真实医疗大模型
- 联邦学习、差分隐私、边缘训练不在本轮实现范围

