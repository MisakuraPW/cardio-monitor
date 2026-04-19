# Git 接入与服务器更新手册

本文档面向你当前这个项目仓库：

- 根目录：`G:\课设\Flutter`
- 项目结构：
  - `flutter_app`
  - `cloud_server`
  - `admin_web`
  - `deploy`
  - `docs`

目标是解决 3 件事：

1. 解释你现在的 Git 实际状态
2. 告诉你后续应该怎样管理整个项目
3. 告诉你服务器以后如何通过 `git pull` 增量更新，而不是每次手工复制粘贴

---

## 1. 先说结论

你这个项目现在最推荐的做法是：

- 用 **一个 Git 仓库** 管理整个项目
- 服务器只部署其中需要运行的部分：
  - `cloud_server`
  - `admin_web`
  - `deploy`
- `flutter_app` 虽然不一定部署在服务器上，但仍然应该放进同一个 Git 仓库

这样做好处最大：

- 协议改动、上位机改动、云端改动可以同步提交
- 版本一致，不容易出现“ESP32 / 上位机 / 云端口径不一致”
- 以后服务器更新只需要 `git pull`，再 `docker compose up -d --build`

---

## 2. 你当前仓库的实际状态

截至本次检查，我已经确认：

- 你的本地项目目录 **已经有 Git 仓库**
  - 根目录下存在 `.git`
- 根目录 **已经有 `.gitignore`**
- 当前仓库 **已经绑定了一个远程仓库**
  - 远程名：`cardio-monitor`

这意味着：

- 你不是“完全没配置 Git”
- 你真正还需要确认的是：
  - 这个远程仓库是不是你想继续用的那个
  - 代码是否已经提交并推送完整
  - 服务器是否要切换到 Git 管理的工作流

---

## 3. 整个项目都要进 Git 吗

答案是：**建议整个项目都进 Git**。

也就是把下面这些都作为同一个仓库的一部分：

- `flutter_app`
- `cloud_server`
- `admin_web`
- `deploy`
- `docs`
- `sample_data`

不要只把“服务器那部分”放进 Git，而把上位机扔在 Git 之外。

原因很简单：

- 这个项目本质上是一整套系统
- BLE / MQTT 协议修改会同时影响：
  - ESP32 说明文档
  - 上位机解析逻辑
  - 云端 ingest 逻辑
- 如果只管服务器代码，后面联调会很乱

你可以理解为：

- **Git 管理的是整套源码**
- **服务器运行的是其中一部分**

这两件事不冲突。

---

## 4. `git pull` 会不会每次重新拉整个项目

正常不会。

### 第一次

第一次 `git clone` 时，确实相当于把整套项目拉下来一次。

### 后续

之后每次：

```bash
git pull
```

Git 只会拉：

- 新增的提交
- 发生变化的文件对象

也就是说，后续一般是 **增量更新**，不是每次完整重传。

所以只要进入 Git 工作流，服务器后面的更新会比“复制粘贴整个目录”轻松很多。

---

## 5. 根目录 `.gitignore` 应该放什么

这份项目建议只保留一个 **根目录 `.gitignore`** 作为主规则文件。

`flutter_app` 自己已经有 Flutter 生成的 `.gitignore`，通常保留即可，不需要你再额外折腾。

当前推荐的根目录 `.gitignore` 内容如下：

```gitignore
.dart_tool/
.idea/
.vscode/
.packages
.flutter-plugins
.flutter-plugins-dependencies
.pub/
.pub-cache/
build/
coverage/
__pycache__/
.pytest_cache/
.mypy_cache/
.ruff_cache/
.venv/
venv/

# Local environment files
deploy/.env
cloud_server/.env
cloud_server/.venv/
cloud_server/data/

# Frontend build artifacts
admin_web/node_modules/
admin_web/dist/
admin_web/.env.local
admin_web/.env.*.local

# Flutter project outputs
flutter_app/build/
flutter_app/.dart_tool/
flutter_app/.flutter-plugins
flutter_app/.flutter-plugins-dependencies

# OS / editor noise
.DS_Store
Thumbs.db
```

### 为什么这些内容不能提交

- `deploy/.env`
  - 里面有服务器部署参数、token、密钥，不应该进 Git
- `cloud_server/data/`
  - 这是运行时数据，不是源码
- `cloud_server/.venv/`
  - 这是虚拟环境，可以重新创建
- `admin_web/node_modules/`
  - 依赖目录，应该通过 `npm install` 生成
- `admin_web/dist/`
  - 构建产物，不是源码
- `flutter_app/build/`
  - Flutter 构建产物，不是源码

---

## 6. 你现在应该先做什么

建议先在本地确认这 3 件事。

### 6.1 看本地 Git 状态

在 PowerShell 里运行：

```powershell
cd G:\课设\Flutter
git status
git remote -v
```

这两条命令的作用：

- `git status`
  - 查看当前是否有未提交改动
- `git remote -v`
  - 查看当前绑定了哪个远程仓库

### 6.2 如果当前远程仓库就是你想继续用的

那你不需要新建 Git 仓库，只需要继续用现有的远程即可。

### 6.3 如果当前远程仓库不是你想用的

那就把它替换掉。

先删除旧远程：

```powershell
git remote remove cardio-monitor
```

再绑定新远程：

```powershell
git remote add origin 你的新仓库地址
```

然后检查：

```powershell
git remote -v
```

---

## 7. 如果你想从现在开始规范提交代码

建议按下面顺序做。

### 7.1 在本地提交一次当前版本

```powershell
cd G:\课设\Flutter
git add .
git commit -m "Prepare repository for server-based workflow"
```

这两条命令的作用：

- `git add .`
  - 把当前工作区里需要跟踪的改动加入暂存区
- `git commit`
  - 把这批改动保存成一个本地提交

### 7.2 把本地提交推到远程

如果你的主分支是 `main`：

```powershell
git push -u cardio-monitor main
```

如果你改成了 `origin` 这个远程名：

```powershell
git push -u origin main
```

这条命令的作用：

- 把本地提交推到 GitHub
- `-u` 会记录上游分支，后面直接 `git push` 即可

---

## 8. 服务器现在是复制粘贴部署的，接下来怎么切 Git

### 推荐方案

不要直接在当前服务器目录里硬接 Git。

更稳妥的方式是：

1. 先备份当前运行目录
2. 再从远程仓库重新 `clone` 一份干净工作区
3. 把服务器本地专属文件拷回去
4. 重新部署

这样最不容易混乱。

---

## 9. 服务器迁移到 Git 工作流的详细步骤

下面默认服务器当前目录是：

```text
/root/cardio-monitor
```

### 9.1 先备份当前目录

```bash
cd /root
mv cardio-monitor cardio-monitor_backup_20260419
```

这条命令的作用：

- 把当前复制粘贴部署的目录整体备份
- 避免误操作后没法回退

### 9.2 从远程仓库重新拉一个干净目录

如果你继续使用当前远程仓库：

```bash
cd /root
git clone 你的仓库地址 cardio-monitor
```

这条命令的作用：

- 从 GitHub 拉取一份新的、干净的工作区
- 新目录名仍然叫 `cardio-monitor`

### 9.3 把服务器本地专属文件迁回来

至少建议迁这两个：

```bash
cp /root/cardio-monitor_backup_20260419/deploy/.env /root/cardio-monitor/deploy/.env
cp -r /root/cardio-monitor_backup_20260419/cloud_server/data /root/cardio-monitor/cloud_server/
```

这两条命令的作用：

- 恢复部署配置
- 恢复云端运行数据

如果你后面还有别的服务器本地文件，也可以按同样方式迁回来。

### 9.4 重新启动部署

```bash
cd /root/cardio-monitor/deploy
sudo docker compose up -d --build
```

这条命令的作用：

- 基于新的 Git 工作区重新构建并启动服务

---

## 10. 以后服务器更新代码的标准流程

以后每次你本地改完代码并推送到 GitHub 后，服务器只要这样做：

```bash
cd /root/cardio-monitor
git pull --ff-only
cd deploy
sudo docker compose up -d --build
```

### 每条命令的作用

- `git pull --ff-only`
  - 只接受“快进式”更新
  - 能避免服务器工作区被自动合并得一团乱
- `docker compose up -d --build`
  - 用最新代码重新构建并启动服务

这是后面最推荐的固定流程。

---

## 11. 如果服务器上有本地修改怎么办

服务器最好不要直接改源码。

最佳实践是：

- 代码只在本地开发机修改
- 本地提交并推送
- 服务器只负责：
  - `git pull`
  - 构建
  - 运行

如果你确实在服务器改过代码，再直接 `git pull`，很可能会冲突。

这时候要先看：

```bash
git status
```

如果看到服务器上有未提交改动，建议先把改动拿回本地整理，而不是继续在服务器上临时修。

---

## 12. 以后日常开发的推荐流程

### 本地

```powershell
cd G:\课设\Flutter
git status
git add .
git commit -m "描述这次修改"
git push
```

### 服务器

```bash
cd /root/cardio-monitor
git pull --ff-only
cd deploy
sudo docker compose up -d --build
```

---

## 13. 你现在最推荐的下一步

如果你准备正式切到 Git 工作流，建议按这个顺序：

1. 本地先运行 `git status` 和 `git remote -v`
2. 确认当前远程仓库是不是你要继续使用的
3. 本地提交当前版本
4. 推送到远程
5. 服务器备份旧目录
6. 服务器重新 `clone`
7. 恢复 `.env` 和 `cloud_server/data`
8. 重启部署

这样切过去之后，后面就不用再靠复制粘贴整项目了。

---

## 14. 最简命令清单

### 本地

```powershell
cd G:\课设\Flutter
git status
git remote -v
git add .
git commit -m "Prepare repository for Git-based deployment"
git push
```

### 服务器首次切换

```bash
cd /root
mv cardio-monitor cardio-monitor_backup_20260419
git clone 你的仓库地址 cardio-monitor
cp /root/cardio-monitor_backup_20260419/deploy/.env /root/cardio-monitor/deploy/.env
cp -r /root/cardio-monitor_backup_20260419/cloud_server/data /root/cardio-monitor/cloud_server/
cd /root/cardio-monitor/deploy
sudo docker compose up -d --build
```

### 服务器后续更新

```bash
cd /root/cardio-monitor
git pull --ff-only
cd deploy
sudo docker compose up -d --build
```
