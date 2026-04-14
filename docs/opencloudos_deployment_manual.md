# OpenCloudOS 9.4 云端部署手册

本文档面向你当前这台腾讯云轻量服务器：

- 公网 IP：`182.254.220.56`
- 系统：`OpenCloudOS 9.4`
- 系统系谱：`RHEL / CentOS` 兼容

目标是把当前项目中的这三部分部署起来：

- `cloud_server`：FastAPI 云端 API
- `cloud_worker`：分析任务 Worker
- `admin_web`：管理后台 Web

本文档默认你在本地已经有完整项目目录，并且打算通过 `Docker Compose` 部署。

## 0. 先说明两件事

### 0.1 不建议继续长期使用 root 密码直登

你现在可以先用 `root` 登录完成首次部署，但建议后续尽快补：

- 新建普通管理员账号
- 配置 SSH 公钥登录
- 禁用密码登录或至少限制 root 远程登录

### 0.2 本文不再重复你的密码

这是出于安全考虑。后续命令里只写登录方式，不会再把密码写进文档。

## 1. 登录服务器

```bash
ssh root@182.254.220.56
```

这条命令的作用：

- 用 SSH 远程登录到你的云服务器。
- `root` 是登录用户名。
- `182.254.220.56` 是服务器公网 IP。

如果你是在 Windows PowerShell 下执行，上面这句也一样可以直接用。

## 2. 确认系统信息

```bash
cat /etc/os-release
```

这条命令的作用：

- 查看当前 Linux 发行版信息。
- 用来确认我们确实部署在 `OpenCloudOS 9.4` 上。
- 如果未来换机器，这一步也能快速确认命令是否仍适用。

## 3. 更新系统软件源缓存并升级基础包

```bash
sudo dnf makecache
```

这条命令的作用：

- 刷新 `dnf` 的软件仓库缓存。
- 避免后面安装 Docker、Git 时拿到过期索引。

```bash
sudo dnf update -y
```

这条命令的作用：

- 升级系统中已安装的软件包。
- `-y` 表示自动确认安装，不再逐个询问。

如果这是新服务器，建议做这一步；如果你担心线上环境变动太大，也可以先跳过升级，只执行安装命令。

## 4. 安装部署所需基础工具

```bash
sudo dnf install -y git docker docker-compose-plugin
```

这条命令的作用：

- 安装 `git`：用于拉取项目代码。
- 安装 `docker`：用于运行 API、Worker、后台容器。
- 安装 `docker-compose-plugin`：用于执行 `docker compose` 编排多服务。

## 5. 启动 Docker，并设置开机自启

```bash
sudo systemctl enable --now docker
```

这条命令的作用：

- `enable`：让 Docker 在系统开机时自动启动。
- `--now`：不等重启，现在立刻启动 Docker。

部署后这是必须步骤，否则 `docker compose` 无法运行。

## 6. 检查 Docker 是否正常

```bash
sudo systemctl status docker
```

这条命令的作用：

- 查看 Docker 服务当前状态。
- 如果状态里出现 `active (running)`，说明 Docker 已正常运行。

```bash
sudo docker version
```

这条命令的作用：

- 检查 Docker 客户端和服务端版本。
- 顺便确认 Docker CLI 能正常连接到守护进程。

## 7. 把项目传到服务器

你有两种常用方式。

### 方式 A：如果项目已经在 Git 仓库里

```bash
git clone <你的仓库地址> cardio-monitor
```

这条命令的作用：

- 把远端 Git 仓库克隆到服务器本地。
- 本地目录名会叫 `cardio-monitor`。

然后进入项目目录：

```bash
cd cardio-monitor
```

这条命令的作用：

- 进入项目根目录。
- 后续的 `deploy/`、`cloud_server/`、`admin_web/` 都在这里面。

### 方式 B：如果项目只在你本地电脑上

你可以在本地电脑执行：

```powershell
scp -r G:\课设\Flutter root@182.254.220.56:/root/cardio-monitor
```

这条命令的作用：

- 把你本地 `G:\课设\Flutter` 整个目录递归上传到服务器。
- 服务器端目标目录是 `/root/cardio-monitor`。

上传完成后，在服务器上进入目录：

```bash
cd /root/cardio-monitor
```

这条命令的作用：

- 进入刚才上传好的项目目录。

## 8. 进入部署目录

```bash
cd deploy
```

这条命令的作用：

- 进入仓库里的 `deploy/` 目录。
- 这里已经有 `docker-compose.yml` 和 `.env.example`。

## 9. 复制环境变量模板

```bash
cp .env.example .env
```

这条命令的作用：

- 复制一份环境变量模板。
- 后续真正部署时，Docker Compose 会读取 `.env`。
- 这样你改配置时不用动模板文件。

## 10. 编辑部署配置

推荐用 `vi`，如果你更习惯 `nano`，先安装它即可。

```bash
vi .env
```

这条命令的作用：

- 打开刚才复制出的 `.env` 文件。
- 你需要把管理员令牌、模型配置、MQTT 配置等改成自己的值。

至少建议先改这些：

```env
CARDIO_APP_ENV=production
CARDIO_ANALYSIS_EXECUTION_MODE=queue
CARDIO_ANALYSIS_PROVIDER=closed_source
CARDIO_ADMIN_TOKEN=你自己重新设置的强口令）（4IxrptkmpzymDZXtARYpX6EfNUm8SLU8U37wdtO9y2I）
CARDIO_LLM_API_BASE_URL=
CARDIO_LLM_API_KEY=
CARDIO_LLM_MODEL=
CARDIO_MQTT_HOST=127.0.0.1
CARDIO_MQTT_PORT=1883
CARDIO_MQTT_TOPIC_PREFIX=cardio
```

这些变量的作用：

- `CARDIO_APP_ENV`：标记当前环境为生产环境。
- `CARDIO_ANALYSIS_EXECUTION_MODE=queue`：让 API 只创建任务，由 Worker 异步执行分析，更适合服务器部署。
- `CARDIO_ANALYSIS_PROVIDER=closed_source`：当前默认走闭源模型路线。
- `CARDIO_ADMIN_TOKEN`：管理后台访问 admin API 时要带的令牌，一定要改。
- `CARDIO_LLM_*`：填写你的模型 API 信息；如果暂时没有模型，也可以先留空，系统会退回规则报告。
- `CARDIO_MQTT_*`：后续接 ESP32 直传时会用到。

## 11. 检查部署编排文件

```bash
cat docker-compose.yml
```

这条命令的作用：

- 查看当前会启动哪些容器。
- 现在默认会启动：
  - `cloud_api`
  - `cloud_worker`
  - `admin_web`

如果你还没部署 MQTT Broker，这一版也没关系，因为当前 `docker-compose.yml` 里并没有强依赖 Broker 容器。

## 12. 开始构建并启动容器

```bash
sudo docker compose up -d --build
```

这条命令的作用：

- `up`：启动容器。
- `-d`：后台运行，不占住当前终端。
- `--build`：先根据 Dockerfile 重新构建镜像，再启动。

第一次部署时这条命令耗时会久一些，因为需要构建 Python 和前端镜像。

## 13. 查看容器是否启动成功

```bash
sudo docker compose ps
```

这条命令的作用：

- 查看当前 Compose 管理的容器列表。
- 你应该能看到 `cloud_api`、`cloud_worker`、`admin_web` 都处于运行状态。

## 14. 查看 API 服务日志

```bash
sudo docker compose logs -f cloud_api
```

这条命令的作用：

- 实时查看 API 容器日志。
- `-f` 表示持续跟踪输出，类似“实时刷新”。
- 如果 FastAPI 正常启动，你会看到 `uvicorn` 的启动日志。

如果想退出日志查看，按：

```bash
Ctrl + C
```

这条操作的作用：

- 只退出日志跟踪界面，不会停止容器。

## 15. 查看 Worker 日志

```bash
sudo docker compose logs -f cloud_worker
```

这条命令的作用：

- 查看分析任务 Worker 的运行情况。
- 如果后续创建了分析任务，Worker 会在这里打印处理情况。

## 16. 查看管理后台日志

```bash
sudo docker compose logs -f admin_web
```

这条命令的作用：

- 查看管理后台容器日志。
- 正常情况下 Nginx 只会输出很少日志。

## 17. 验证 API 是否可访问

```bash
curl http://127.0.0.1:8000/api/v1/health
```

这条命令的作用：

- 在服务器本机上请求健康检查接口。
- 如果返回 `status: ok`，说明 API 服务本身已经起来了。

再验证 Swagger：

```bash
curl http://127.0.0.1:8000/docs
```

这条命令的作用：

- 检查文档页 HTML 是否能正常返回。
- 真正查看时建议直接浏览器打开。

## 18. 验证管理后台是否可访问

```bash
curl http://127.0.0.1:8080
```

这条命令的作用：

- 检查后台首页是否能从本机访问。
- 如果返回 HTML，说明前端容器正常。

## 19. 在本地浏览器中打开服务

部署完成后，你可以在自己电脑浏览器访问：

```text
http://182.254.220.56:8000/docs
http://182.254.220.56:8080
```

这两条地址的作用：

- `:8000/docs`：打开 FastAPI Swagger 文档。
- `:8080`：打开管理后台页面。

如果打不开，先检查腾讯云轻量服务器控制台的防火墙/安全组是否放行了：

- `8000`
- `8080`

## 20. 如果要开放系统防火墙

先检查系统里有没有启用 `firewalld`：

```bash
sudo systemctl status firewalld
```

这条命令的作用：

- 查看系统防火墙服务是否启用。
- 如果没启用，可以只管腾讯云控制台安全组。

如果启用了，并且你需要放行端口：

```bash
sudo firewall-cmd --permanent --add-port=8000/tcp
```

这条命令的作用：

- 永久放行 `8000` 端口给 API 服务。

```bash
sudo firewall-cmd --permanent --add-port=8080/tcp
```

这条命令的作用：

- 永久放行 `8080` 端口给管理后台。

```bash
sudo firewall-cmd --reload
```

这条命令的作用：

- 让前面新增的防火墙规则立即生效。

## 21. 如何更新代码并重新部署

如果后续你更新了仓库代码，在服务器上执行：

```bash
cd /root/cardio-monitor
```

这条命令的作用：

- 回到项目根目录。

如果你是 Git 部署：

```bash
git pull
```

这条命令的作用：

- 拉取远端仓库的最新代码。

然后重新进入部署目录：

```bash
cd deploy
```

这条命令的作用：

- 回到 Compose 配置所在目录。

重新构建并启动：

```bash
sudo docker compose up -d --build
```

这条命令的作用：

- 基于最新代码重新构建镜像并替换运行中的容器。

## 22. 如何停止服务

```bash
sudo docker compose down
```

这条命令的作用：

- 停止并删除当前 Compose 管理的容器。
- 不会删除你挂载到宿主机的数据目录。

如果你只是想临时停掉，不想删除容器：

```bash
sudo docker compose stop
```

这条命令的作用：

- 只停止容器，不删除它们。

## 23. 如何查看已保存的数据

```bash
ls ../cloud_server/data
```

这条命令的作用：

- 查看云端元数据和对象存储目录。
- 当前重要数据主要在这里持久化。

```bash
ls ../cloud_server/data/object_store
```

这条命令的作用：

- 查看原始波形分块文件是否已经落盘。

## 24. 如何备份数据

```bash
tar -czf cardio-cloud-data-backup.tar.gz ../cloud_server/data
```

这条命令的作用：

- 把当前云端数据目录整体打包。
- 适合先做最简单的整目录备份。

如果以后切换到 PostgreSQL / MinIO，这一步会改成分别备份数据库和对象存储桶。

## 25. 生产环境的下一步建议

当前这版部署完成后，你已经能做到：

- 跑通 FastAPI 云端 API
- 跑通分析 Worker
- 打开管理后台
- 用上位机上传数据并拿到报告

下一阶段建议按这个顺序继续：

1. 部署 Nginx，把 `8000` 和 `8080` 收到标准域名后面。
2. 配置 HTTPS。
3. 部署 MQTT Broker，例如 EMQX 或 Mosquitto。
4. 让 ESP32 走 `WiFi/MQTT -> 云端 ingest` 链路。
5. 配置闭源模型 API，完成真实模型分析闭环。

## 26. 最简命令清单

如果你只想先快速跑起来，可以按下面这组最简命令执行：

```bash
ssh root@182.254.220.56
sudo dnf install -y git docker docker-compose-plugin
sudo systemctl enable --now docker
cd /root
# 这里换成 git clone 或 scp 上传后的目录
cd cardio-monitor/deploy
cp .env.example .env
vi .env
sudo docker compose up -d --build
sudo docker compose ps
curl http://127.0.0.1:8000/api/v1/health
```

这组命令的作用：

- 登录服务器
- 安装 Docker 环境
- 进入项目部署目录
- 生成配置文件
- 启动全部服务
- 验证 API 是否存活
