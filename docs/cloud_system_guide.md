# 云端系统实现计划与讲解（V1）

## 1. 云端现在是什么

当前仓库中的 `cloud_server` 已经不是单纯的演示接口，而是一个可以继续扩展的云端基础骨架，包含：

- FastAPI 对外 API
- SQLite 元数据存储
- LocalBlobStore 原始分块存储
- 规则报告引擎 `rules_v1`
- 可替换的模型 Provider 抽象
- MQTT 直传 ingest 接口
- Admin 查询接口

它的定位是：

- 本地联调时，直接用 `uvicorn` 启动即可验证上传、分析、报告回传
- 后续上服务器时，可以直接演进为正式云端系统，而不是推倒重写

## 2. 云端 V1 的完整职责

V1 云端建议固定为 5 个子系统：

### 2.1 API 服务

负责：

- 上位机上传会话、摘要、片段
- 创建分析任务
- 返回医疗报告
- 给管理后台提供会话、设备、告警等查询接口

当前对应实现：

- `cloud_server/app/main.py`

### 2.2 MQTT 接入服务

负责：

- 接收 ESP32 的 `status / catalog / waveform / alerts`
- 将设备直传数据落到云端存储
- 与 API 层共用同一套存储模型

当前对应实现：

- `cloud_server/app/mqtt_ingest.py`
- `cloud_server/app/mqtt_ingest_runner.py`

### 2.3 分析 Worker

负责：

- 消费待分析任务
- 先跑规则分析
- 再调用模型 Provider
- 落库报告并更新任务状态

当前对应实现：

- `cloud_server/app/analysis_service.py`
- `cloud_server/app/worker_loop.py`

### 2.4 存储层

负责：

- `SQLite` 保存设备、会话、上传、任务、报告等元数据
- `LocalBlobStore` 保存原始波形分块 JSON
- 后续替换为 `PostgreSQL + MinIO/S3` 时，只改存储实现，不改上层 API

当前对应实现：

- `cloud_server/app/storage.py`
- `cloud_server/app/blob_store.py`

### 2.5 管理后台 Web

负责：

- 展示总览指标
- 查看设备列表、会话列表、任务状态、报告内容、告警记录
- 面向管理员做服务器数据可视化

当前对应实现：

- `admin_web/`

## 3. 三条数据链路怎么理解

### 3.1 BLE 调试链路

```text
ESP32 -> BLE -> 上位机 -> HTTPS REST -> 云端
```

特点：

- BLE 只负责近距离调试与实时显示
- 上位机负责上传摘要、片段和必要的原始数据
- 这是当前前期联调最方便的链路

### 3.2 WiFi 设备直传链路

```text
ESP32 -> WiFi/MQTT -> Broker -> 云端 ingest -> API/后台/上位机
```

特点：

- ESP32 不依赖上位机，可直接把数据送到云端
- 云端负责落库、任务触发、报告生成
- 后台和上位机都可以再从云端查询结果

### 3.3 文件回放链路

```text
CSV/JSON -> 上位机 -> HTTPS REST -> 云端
```

特点：

- 用于无硬件联调
- 和 BLE 路径共用上传逻辑

## 4. 医疗大模型怎么准备

## 4.1 闭源现成模型

你需要准备：

- API Key
- 模型名
- 兼容 OpenAI 风格的 Base URL
- 固定提示词模板
- 结构化输出约束

推荐流程：

1. 先由规则引擎给出基础报告
2. 再把摘要、特征、波形片段、规则报告一起发给外部模型
3. 模型返回补充结论
4. 云端把模型结果与规则结果合并后生成最终报告

本仓库已经预留对应环境变量：

```env
CARDIO_ANALYSIS_PROVIDER=closed_source
CARDIO_LLM_API_BASE_URL=
CARDIO_LLM_API_KEY=
CARDIO_LLM_MODEL=
CARDIO_LLM_PROMPT_VERSION=v1
```

### 4.2 开源自部署模型

推荐方式：

- 单独部署“模型推理服务”
- FastAPI 主服务不要直接承载大模型推理
- Worker 通过 HTTP 调本地模型服务

本仓库已经预留对应环境变量：

```env
CARDIO_ANALYSIS_PROVIDER=open_source
CARDIO_LOCAL_LLM_BASE_URL=
CARDIO_LOCAL_LLM_MODEL=
```

### 4.3 V1 的建议决策

- 第一阶段先用规则报告跑通闭环
- 第二阶段先接闭源 API
- 第三阶段再接开源自部署模型

原因是：

- 闭源 API 最容易先完成功能演示
- 开源模型通常还需要算力、显存、推理服务和运维

## 5. 当前后端已经实现的接口

### 5.1 上位机接口

- `POST /api/v1/sessions`
- `GET /api/v1/sessions/{id}`
- `GET /api/v1/sessions/{id}/raw`
- `POST /api/v1/sessions/{id}/uploads`
- `POST /api/v1/analysis/jobs`
- `GET /api/v1/analysis/jobs/{id}`
- `GET /api/v1/reports/{sessionId}`

### 5.2 设备直传接口

- `POST /api/v1/ingest/mqtt/session/open`
- `POST /api/v1/ingest/mqtt/catalog`
- `POST /api/v1/ingest/mqtt/frame-batch`
- `POST /api/v1/ingest/mqtt/alerts`
- `POST /api/v1/ingest/mqtt/device`

### 5.3 管理后台接口

- `GET /api/v1/admin/overview`
- `GET /api/v1/admin/sessions`
- `GET /api/v1/admin/sessions/{id}`
- `GET /api/v1/admin/devices`
- `GET /api/v1/admin/alerts`

后台接口通过 `X-Admin-Token` 保护。

## 6. 现在的存储模型

当前元数据表已经拆分为：

- `devices`
- `sessions`
- `uploads`
- `analysis_jobs`
- `reports`
- `channel_catalogs`
- `raw_chunks`
- `alerts`

设计原则：

- 数据库只保存索引、状态、摘要、报告
- 原始波形大块数据不直接塞数据库
- 原始波形分块写入对象存储抽象层

当前对象存储使用本地目录模拟：

- `cloud_server/data/object_store/`

这正是后续切换 `MinIO / S3` 的预留点。

## 7. 管理后台怎么用

当前 `admin_web` 已经提供一个独立管理后台骨架，页面固定为：

- 总览
- 设备
- 会话
- 报告
- 任务
- 告警

环境变量：

```env
VITE_API_BASE_URL=http://127.0.0.1:8000
VITE_ADMIN_TOKEN=change-me
```

本地启动：

```powershell
cd admin_web
cmd /c npm.cmd install
cmd /c npm.cmd run dev
```


如果你需要一份按这台服务器逐条执行的实操文档，请直接看 [opencloudos_deployment_manual.md](./opencloudos_deployment_manual.md)。
## 8. 你的服务器怎么部署

你当前服务器是：

- 腾讯云轻量服务器
- OpenCloudOS 9.4
- RHEL / CentOS 系兼容环境

这意味着部署方式优先推荐：

- Docker Engine
- Docker Compose Plugin
- Nginx
- Systemd

### 8.1 推荐部署方式

```bash
sudo dnf install -y docker docker-compose-plugin git
sudo systemctl enable --now docker
```

然后在项目根目录进入 `deploy/`：

```bash
cd deploy
cp .env.example .env
sudo docker compose up -d --build
```

默认访问：

- API 文档：`http://服务器IP:8000/docs`
- 管理后台：`http://服务器IP:8080`

### 8.2 如果后续换服务器，迁移难不难

只要坚持这几个原则，迁移并不困难：

- 不把配置写死在代码里
- 用 `.env` 管理地址、密钥、模型配置
- 元数据单独存数据库
- 原始文件单独存对象存储目录或桶
- 用容器化部署

后续迁移时主要搬这几样：

- 数据库文件或 PostgreSQL 备份
- `object_store` 目录或 MinIO/S3 桶
- `.env`
- Docker Compose 配置

这样换机器时基本不需要改业务代码。

## 9. 当前 V1 还没做的事

以下内容仍然是“预留但未完整实现”：

- 真正的 PostgreSQL 存储实现
- 真正的 MinIO/S3 对象存储实现
- 真正的 Redis 队列
- 完整的 MQTT Broker 部署脚本
- 完整的用户权限系统
- 生产级 HTTPS / 域名 / 反向代理配置
- 真正的闭源或开源医疗模型上线配置

所以现在这版更准确的定位是：

- 代码结构已经按正式云端系统来搭
- 本地联调已可用
- 部署骨架已准备好
- 生产环境细节仍需要结合你的服务器资源继续完善

## 10. 建议的下一步

建议你下一步按这个顺序推进：

1. 用当前 FastAPI + 管理后台骨架先跑通服务器本地部署
2. 用上位机把文件回放链路上传到云端，验证报告生成
3. 用 ESP32 先跑 BLE -> 上位机 -> 云端链路
4. 再接 MQTT Broker，跑 ESP32 直传链路
5. 最后再接闭源模型 API

这样推进成本最低，问题也最好定位。

