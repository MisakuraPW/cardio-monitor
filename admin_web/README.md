# Cardio Cloud Admin

一个独立的 React + Vite 管理后台骨架，用于连接 `cloud_server` 的 admin 接口，完成：

- 总览看板
- 设备列表
- 会话列表与详情
- 报告查看
- 任务查看
- 告警查看

## 环境变量

新建 `.env`：

```env
VITE_API_BASE_URL=http://127.0.0.1:8000
VITE_ADMIN_TOKEN=change-me
```

## 启动

```powershell
cmd /c npm.cmd install
cmd /c npm.cmd run dev
```

当前仓库只提供骨架，后续可继续扩展搜索、筛选、报告复核和用户权限。
