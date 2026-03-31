# FastAPI 云端服务

## 当前能力

- `POST /api/v1/sessions`：创建上位机上传会话
- `GET /api/v1/sessions/{id}`：查询会话详情
- `GET /api/v1/sessions/{id}/raw`：查询原始分块索引
- `POST /api/v1/sessions/{id}/uploads`：上传摘要与片段
- `POST /api/v1/analysis/jobs`：创建分析任务
- `GET /api/v1/analysis/jobs/{id}`：查询任务状态
- `GET /api/v1/reports/{sessionId}`：获取报告
- `POST /api/v1/ingest/mqtt/session/open`：设备直传时创建会话
- `POST /api/v1/ingest/mqtt/catalog`：写入通道目录
- `POST /api/v1/ingest/mqtt/frame-batch`：写入原始波形分块
- `POST /api/v1/ingest/mqtt/alerts`：写入告警
- `GET /api/v1/admin/overview`：后台总览
- `GET /api/v1/admin/sessions`：后台会话列表
- `GET /api/v1/admin/sessions/{id}`：后台会话详情
- `GET /api/v1/admin/devices`：后台设备列表
- `GET /api/v1/admin/alerts`：后台告警列表
- `GET /api/v1/health`：健康检查

## 运行

### 开发模式

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
$env:PYTHONPATH = (Get-Location)
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
```

### 规则+模型分析运行方式

- `CARDIO_ANALYSIS_EXECUTION_MODE=inline`
  - 创建任务后立刻同步执行，适合本地联调
- `CARDIO_ANALYSIS_EXECUTION_MODE=queue`
  - API 只入队，需额外运行 Worker

Worker 启动方式：

```powershell
$env:PYTHONPATH = (Get-Location)
.\.venv\Scripts\python.exe -m app.worker_loop
```

MQTT ingest 服务启动方式：

```powershell
$env:PYTHONPATH = (Get-Location)
.\.venv\Scripts\python.exe -m app.mqtt_ingest_runner
```

## 管理访问控制

后台接口通过 `X-Admin-Token` 进行最小访问控制，对应环境变量：

```env
CARDIO_ADMIN_TOKEN=change-me
```

## 存储实现

当前默认使用：

- `SQLite`：元数据
- `LocalBlobStore`：原始波形分块 JSON 文件

数据默认落在：

- `cloud_server/data/cardio_cloud.db`
- `cloud_server/data/object_store/`

后续可替换为：

- `PostgreSQL`：元数据
- `MinIO / S3`：原始分块
- `Redis`：任务队列或缓存

## 分析实现

当前分析流程为：

1. 规则报告 `rules_v1`
2. Provider 抽象层
3. 默认闭源模型接口预留
4. 开源自部署模型接口预留

如果没有配置外部模型，系统会自动回退到规则报告，不会阻塞联调。
