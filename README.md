# 多源心肺功能监测系统 V1

本仓库实现了一个可扩展的课程设计基础版本，包含：

- `flutter_app/`：Flutter Web 上位机，支持 `WiFi(MQTT over WebSocket)`、`数据文件回放`、蓝牙入口、实时波形显示、上传与报告查看
- `cloud_server/`：FastAPI 云端服务，提供会话、上传、分析任务、报告查询、MQTT ingest、管理查询接口
- `admin_web/`：独立管理后台骨架，用于可视化服务器数据、会话、报告、任务和告警
- `docs/`：通信协议、云端说明等文档
- `sample_data/`：本地调试用样例数据
- `deploy/`：容器化部署骨架与环境变量模板

## 快速开始

### 1. 云端服务

```powershell
cd cloud_server
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
$env:PYTHONPATH = (Get-Location)
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
```

### 2. Flutter Web 上位机

```powershell
cd flutter_app
G:\课设\FlutterSDK\flutter\bin\flutter.bat pub get
G:\课设\FlutterSDK\flutter\bin\flutter.bat run -d chrome
```

### 3. 管理后台骨架

```powershell
cd admin_web
cmd /c npm.cmd install
cmd /c npm.cmd run dev
```

## 说明文档

- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)：整体实现计划
- [docs/protocol.md](./docs/protocol.md)：主题、消息格式、文件回放格式
- [docs/esp32_communication_protocol.md](./docs/esp32_communication_protocol.md)：ESP32 协议说明
- [docs/esp32_ble_connection_guide.md](./docs/esp32_ble_connection_guide.md)：上位机与 ESP32 蓝牙连接说明
- [docs/cloud_system_guide.md](./docs/cloud_system_guide.md)：云端系统实现讲解与部署建议
- [docs/opencloudos_deployment_manual.md](./docs/opencloudos_deployment_manual.md)：OpenCloudOS 9.4 服务器逐条命令部署手册
- [docs/git_setup_and_server_update_guide.md](./docs/git_setup_and_server_update_guide.md)：Git 接入、`.gitignore` 模板与服务器增量更新手册
- [deploy/README.md](./deploy/README.md)：容器化部署骨架说明
