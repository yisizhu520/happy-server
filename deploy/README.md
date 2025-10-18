# Happy Server Deployment

这个目录包含 Happy Server 的完整部署配置，支持 Docker Compose 一键部署。

## 🚀 一键部署（推荐）

### Linux / macOS

```bash
cd deploy
./deploy.sh
```

### Windows (PowerShell)

```powershell
cd deploy
.\deploy.ps1
```

部署脚本会自动完成：
- ✅ 检查 Docker 环境
- ⚡ **自动启动 Docker**（如果未运行）
- ✅ 生成安全的 `.env` 配置文件（自动生成随机密钥）
- ✅ 拉取基础镜像（PostgreSQL, Redis, MinIO）
- 🔨 **本地构建应用镜像**（首次构建约需 5-10 分钟）
- ✅ 启动所有服务（PostgreSQL, Redis, MinIO, App）
- ✅ 等待服务健康检查
- ✅ 自动运行数据库迁移
- ✅ 显示访问地址和常用命令

**就这么简单！** 🎉

### 🚀 自动启动 Docker

如果检测到 Docker 未运行，脚本会询问是否自动启动：
- **macOS**: 自动打开 Docker Desktop 应用
- **Linux**: 使用 systemctl/service 启动 Docker 服务（可能需要 sudo 权限）
- **Windows**: 自动启动 Docker Desktop 程序

然后等待 Docker 服务就绪（最多 60 秒）后继续部署。

---

## 📦 服务组件

- **app**: Happy Server 应用（**本地构建**）
- **postgres**: PostgreSQL 16 数据库
- **redis**: Redis 7（用于 pub/sub 和缓存）
- **minio**: MinIO S3 兼容对象存储
- **minio-init**: MinIO 存储桶初始化（一次性任务）

## 📁 目录结构

```
deploy/
├── docker-compose.yml    # 主配置文件
├── deploy.sh            # Linux/macOS 一键部署脚本
├── deploy.ps1           # Windows 一键部署脚本
├── .env                 # 环境变量（自动生成，包含密钥）
└── .env.example         # 环境变量模板

数据存储（Docker Volumes）：
├── happy-postgres-data  # PostgreSQL 数据卷
├── happy-redis-data     # Redis 数据卷
└── happy-minio-data     # MinIO/S3 数据卷
```

**注意：** 为解决 Windows/WSL 权限问题，数据使用 Docker named volumes 存储，而不是本地目录。

## 🎯 快速开始

### 方式一：使用部署脚本（推荐）

#### Linux / macOS
```bash
cd deploy
chmod +x deploy.sh  # 添加执行权限（首次需要）
./deploy.sh         # 一键部署
```

#### Windows
```powershell
cd deploy
.\deploy.ps1        # 一键部署
```

### 方式二：手动部署

#### 1. 配置环境变量

**重要**：必须从模板创建 `.env` 文件：

```bash
cd deploy
cp .env.example .env
```

**必须修改的配置**：
- 设置 `HANDY_MASTER_SECRET` 为安全的随机值（使用 `openssl rand -hex 32`）
- 生产环境：修改 `POSTGRES_PASSWORD` 和 `MINIO_ROOT_PASSWORD`

#### 2. 启动服务

```bash
docker-compose up -d
```

数据会自动存储在 `./data/` 目录。

#### 3. 验证服务

```bash
# 检查所有服务是否运行
docker-compose ps

# 查看应用日志
docker-compose logs -f app
```

#### 4. 运行数据库迁移

```bash
docker-compose exec app yarn migrate
```

### 访问服务

所有端口可通过 `.env` 文件配置。默认值：

- **Happy Server API**: http://localhost:3000
- **健康检查**: http://localhost:3000/health
- **Metrics**: http://localhost:9090/metrics
- **MinIO 控制台**: http://localhost:9001（凭据在 `.env` 中）
- **PostgreSQL**: localhost:5432（凭据在 `.env` 中）
- **Redis**: localhost:6379

## 📊 常用操作

### 更新服务

使用脚本（推荐）：
```bash
# Linux/macOS
./deploy.sh --update

# Windows
.\deploy.ps1 -Update
```

或手动更新：
```bash
docker-compose pull app
docker-compose up -d app
```

### 查看日志

```bash
# 所有服务
docker-compose logs -f

# 特定服务
docker-compose logs -f app
docker-compose logs -f postgres
```

### 服务控制

```bash
# 停止所有服务
docker-compose down

# 重启所有服务
docker-compose restart

# 重启特定服务
docker-compose restart app

# 查看服务状态
docker-compose ps
```

### 数据库迁移

```bash
# 运行迁移
docker-compose exec app yarn migrate

# 创建新迁移
docker-compose exec app yarn migrate:create
```

## 💾 数据管理

### 数据存储方式

数据使用 **Docker named volumes** 存储，而不是本地目录：
- ✅ **解决 Windows/WSL 权限问题**
- ✅ **更好的性能**
- ✅ **数据独立于源代码**

### 查看数据卷

```bash
# 查看所有 Happy Server 相关的数据卷
docker volume ls | grep happy

# 查看数据卷详细信息
docker volume inspect happy-postgres-data
docker volume inspect happy-redis-data
docker volume inspect happy-minio-data

# 查看数据卷磁盘使用
docker system df -v
```

### 备份数据

```bash
# 备份 PostgreSQL 数据
docker run --rm -v happy-postgres-data:/data -v $(pwd):/backup alpine \
  tar czf /backup/postgres-backup-$(date +%Y%m%d).tar.gz -C /data .

# 备份 Redis 数据
docker run --rm -v happy-redis-data:/data -v $(pwd):/backup alpine \
  tar czf /backup/redis-backup-$(date +%Y%m%d).tar.gz -C /data .

# 备份 MinIO 数据
docker run --rm -v happy-minio-data:/data -v $(pwd):/backup alpine \
  tar czf /backup/minio-backup-$(date +%Y%m%d).tar.gz -C /data .
```

### 恢复数据

```bash
# 恢复 PostgreSQL 数据
docker run --rm -v happy-postgres-data:/data -v $(pwd):/backup alpine \
  tar xzf /backup/postgres-backup-YYYYMMDD.tar.gz -C /data

# 恢复 Redis 数据  
docker run --rm -v happy-redis-data:/data -v $(pwd):/backup alpine \
  tar xzf /backup/redis-backup-YYYYMMDD.tar.gz -C /data

# 恢复 MinIO 数据
docker run --rm -v happy-minio-data:/data -v $(pwd):/backup alpine \
  tar xzf /backup/minio-backup-YYYYMMDD.tar.gz -C /data
```

### 清理数据

⚠️ **警告：** 以下操作将永久删除所有数据！

```bash
# 停止所有服务
docker compose down

# 删除数据卷
docker volume rm happy-postgres-data happy-redis-data happy-minio-data

# 或删除所有未使用的数据卷
docker volume prune
```

## 🔒 生产环境考虑

### 1. 安全性
- ✅ 生成安全的密钥（部署脚本会自动生成）
- ✅ 修改 `.env` 中的所有默认密码
- ✅ 限制文件权限：`chmod 600 .env`
- ⚠️ 为所有服务启用 SSL/TLS
- ⚠️ 使用密钥管理服务（如 Docker secrets、Vault）

### 2. 数据持久化
- 📦 定期备份 `./data/` 目录
- 🗄️ 生产环境建议使用托管数据库服务
- 💾 考虑使用 Docker volumes 提高隔离性

### 3. 扩展性
- 🚀 使用独立的 Redis 集群应对生产负载
- 💡 考虑 PostgreSQL 连接池
- ☁️ 使用外部 S3 服务代替 MinIO

### 4. 监控
- 📊 配置 Prometheus 抓取端口 9090 的 metrics
- 🏥 配置健康检查端点
- 📝 设置日志聚合服务
- 💿 监控 `./data/` 目录的磁盘使用情况

## 🔧 故障排查

### 应用启动失败

查看日志：
```bash
docker-compose logs app
```

常见问题：
- 数据库未就绪：等待 postgres 健康检查通过
- 缺少迁移：运行 `docker-compose exec app yarn migrate`
- 端口冲突：检查 `.env` 中的端口是否被占用

### PostgreSQL 权限错误（Windows/WSL）

**错误：**
```
chmod: changing permissions of '/var/lib/postgresql/data': Operation not permitted
initdb: error: could not change permissions of directory
```

**已解决：** ✅ 项目已配置为使用 Docker volumes，自动解决此问题。  
**详细说明：** 查看 [WSL-SETUP.md](./WSL-SETUP.md)

### 数据库连接错误

验证 PostgreSQL 健康状态：
```bash
docker-compose ps postgres
docker-compose exec postgres pg_isready -U postgres
```

### MinIO 访问错误

检查 MinIO 是否运行且存储桶已创建：
```bash
docker-compose ps minio minio-init
docker-compose logs minio-init
```

### 服务无响应

检查服务状态和资源使用：
```bash
docker-compose ps
docker stats
```

### 镜像拉取失败/超时

如果遇到网络问题导致镜像拉取失败：

```
✗ 镜像拉取失败，已重试 3 次
⚠ 这可能是由于网络问题导致的
```

**解决方案：**
1. 脚本会自动重试 3 次
2. 配置 Docker 镜像加速器
3. 使用 VPN/代理访问 GitHub Container Registry
4. 查看详细排查指南：[网络问题排查](./NETWORK-TROUBLESHOOTING.md)

## 📝 环境变量说明

查看 `.env.example` 了解所有可用配置选项。

**必需配置**：
- `HANDY_MASTER_SECRET`: 认证密钥（部署脚本会自动生成）

**可选配置**：
- `METRICS_ENABLED`: 启用 Prometheus metrics（默认：true）
- `NODE_ENV`: 运行环境（默认：production）
- 所有端口配置都可以自定义

## 🆘 获取帮助

```bash
# Linux/macOS
./deploy.sh --help

# Windows
.\deploy.ps1 -Help
```
