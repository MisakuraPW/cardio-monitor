# 部署目录

本目录提供容器化部署骨架，目标环境为 Linux 服务器，例如你当前的 Tencent Cloud OpenCloudOS 9.4。

## 目录内容

- `docker-compose.yml`：启动云端 API、分析 Worker、管理后台
- `.env.example`：环境变量模板

## 建议部署步骤

```bash
cp .env.example .env
# 填写 CARDIO_ADMIN_TOKEN 与模型配置
sudo dnf install -y docker docker-compose-plugin
sudo systemctl enable --now docker
sudo docker compose up -d --build
```

## 访问

- 云端 API：`http://服务器IP:8000/docs`
- 管理后台：`http://服务器IP:8080`

## 迁移原则

- `cloud_server/data` 目录需要持久化
- 未来切 PostgreSQL / MinIO 时，只替换存储实现和 Compose 配置，不改上位机接口
