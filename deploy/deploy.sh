#!/bin/bash

# Happy Server 一键部署脚本
# 用途：自动完成 Happy Server 的部署流程
# 作者：Happy Team

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}==>${NC} ${YELLOW}$1${NC}\n"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查 Docker 是否运行
check_docker_running() {
    if ! docker info >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# 启动 Docker
start_docker() {
    log_info "尝试启动 Docker..."
    
    # 检测操作系统
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        log_info "检测到 macOS，启动 Docker Desktop..."
        if [ -d "/Applications/Docker.app" ]; then
            open -a Docker
            log_success "Docker Desktop 启动命令已执行"
        else
            log_error "未找到 Docker Desktop，请手动安装"
            log_info "访问 https://www.docker.com/products/docker-desktop 下载"
            return 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        log_info "检测到 Linux，尝试启动 Docker 服务..."
        
        # 尝试 systemctl
        if command_exists systemctl; then
            if sudo systemctl start docker 2>/dev/null; then
                log_success "Docker 服务已启动 (systemctl)"
            else
                # 尝试 service
                if sudo service docker start 2>/dev/null; then
                    log_success "Docker 服务已启动 (service)"
                else
                    log_error "无法启动 Docker 服务，请检查权限或手动启动"
                    return 1
                fi
            fi
        elif command_exists service; then
            if sudo service docker start 2>/dev/null; then
                log_success "Docker 服务已启动 (service)"
            else
                log_error "无法启动 Docker 服务，请检查权限或手动启动"
                return 1
            fi
        else
            log_error "无法自动启动 Docker，请手动启动"
            return 1
        fi
    else
        # Windows (Git Bash/WSL)
        log_info "检测到 Windows/WSL，尝试启动 Docker Desktop..."
        
        # 尝试启动 Docker Desktop
        if [ -f "/mnt/c/Program Files/Docker/Docker/Docker Desktop.exe" ]; then
            cmd.exe /c "start \"\" \"C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe\"" 2>/dev/null
            log_success "Docker Desktop 启动命令已执行"
        elif [ -f "/c/Program Files/Docker/Docker/Docker Desktop.exe" ]; then
            "/c/Program Files/Docker/Docker/Docker Desktop.exe" &
            log_success "Docker Desktop 启动命令已执行"
        else
            log_warning "未找到 Docker Desktop，请手动启动"
            log_info "在 Windows 开始菜单中搜索 'Docker Desktop' 并启动"
            return 1
        fi
    fi
    
    # 等待 Docker 启动
    log_info "等待 Docker 启动（最多等待 60 秒）..."
    local wait_time=0
    local max_wait=60
    
    while [ $wait_time -lt $max_wait ]; do
        if check_docker_running; then
            echo ""
            log_success "Docker 已成功启动"
            return 0
        fi
        echo -n "."
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    echo ""
    log_error "Docker 启动超时，请手动检查 Docker 状态"
    return 1
}

# 生成随机密钥
generate_secret() {
    if command_exists openssl; then
        openssl rand -hex 32
    else
        # 备用方案：使用 /dev/urandom
        cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1
    fi
}

# 主函数
main() {
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════╗"
    echo "║   Happy Server 一键部署脚本          ║"
    echo "╚═══════════════════════════════════════╝"
    echo -e "${NC}"

    # 1. 检查依赖
    log_step "1/7 检查系统依赖"
    
    if ! command_exists docker; then
        log_error "Docker 未安装，请先安装 Docker"
        log_info "访问 https://docs.docker.com/get-docker/ 获取安装指南"
        exit 1
    fi
    log_success "Docker 已安装"

    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        log_info "访问 https://docs.docker.com/compose/install/ 获取安装指南"
        exit 1
    fi
    log_success "Docker Compose 已安装"

    if ! check_docker_running; then
        log_warning "Docker 服务未运行"
        
        # 询问是否自动启动
        read -p "是否自动启动 Docker？(Y/n): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            log_error "Docker 服务未运行，部署已取消"
            log_info "请手动启动 Docker 后重新运行脚本"
            exit 1
        fi
        
        # 尝试启动 Docker
        if ! start_docker; then
            log_error "无法自动启动 Docker，请手动启动后重新运行脚本"
            exit 1
        fi
    else
        log_success "Docker 服务正在运行"
    fi

    # 2. 切换到 deploy 目录
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    cd "$SCRIPT_DIR"
    log_info "工作目录: $SCRIPT_DIR"

    # 3. 配置环境变量
    log_step "2/7 配置环境变量"
    
    if [ -f .env ]; then
        log_warning ".env 文件已存在"
        read -p "是否要重新生成？这将覆盖现有配置 (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "保留现有 .env 配置"
        else
            create_env_file
        fi
    else
        create_env_file
    fi

    # 4. 准备数据存储
    log_step "3/7 准备数据存储"
    
    log_info "数据将使用 Docker volumes 存储"
    log_info "这样可以解决 Windows/WSL 权限问题"
    log_success "数据存储配置完成"

    # 5. 构建和拉取镜像
    log_step "4/7 构建和拉取 Docker 镜像"
    
    log_info "正在拉取基础镜像..."
    # 拉取基础镜像（postgres, redis, minio）
    if command_exists docker-compose; then
        docker-compose pull postgres redis minio minio-init 2>&1 || true
    else
        docker compose pull postgres redis minio minio-init 2>&1 || true
    fi
    log_success "基础镜像拉取完成"
    
    log_info "正在构建应用镜像，这可能需要几分钟..."
    log_warning "首次构建会下载依赖，请耐心等待"
    
    # 构建应用镜像
    if command_exists docker-compose; then
        if docker-compose build app; then
            log_success "应用镜像构建完成"
        else
            log_error "应用镜像构建失败"
            log_info "请检查 Dockerfile 和构建日志"
            exit 1
        fi
    else
        if docker compose build app; then
            log_success "应用镜像构建完成"
        else
            log_error "应用镜像构建失败"
            log_info "请检查 Dockerfile 和构建日志"
            exit 1
        fi
    fi

    # 6. 启动服务
    log_step "5/7 启动服务"
    
    log_info "正在启动所有服务..."
    if command_exists docker-compose; then
        docker-compose up -d
    else
        docker compose up -d
    fi
    log_success "服务已启动"

    # 7. 等待服务健康检查
    log_step "6/7 等待服务就绪"
    
    log_info "等待数据库和其他服务启动（最多等待 60 秒）..."
    WAIT_TIME=0
    MAX_WAIT=60
    
    while [ $WAIT_TIME -lt $MAX_WAIT ]; do
        if command_exists docker-compose; then
            HEALTHY=$(docker-compose ps | grep -c "healthy" || true)
        else
            HEALTHY=$(docker compose ps | grep -c "healthy" || true)
        fi
        
        if [ "$HEALTHY" -ge 3 ]; then  # postgres, redis, minio 至少 3 个服务健康
            log_success "服务已就绪"
            break
        fi
        
        echo -n "."
        sleep 2
        WAIT_TIME=$((WAIT_TIME + 2))
    done
    echo

    if [ $WAIT_TIME -ge $MAX_WAIT ]; then
        log_warning "服务启动超时，但这可能是正常的"
        log_info "请稍后手动检查服务状态：docker-compose ps"
    fi

    # 8. 运行数据库迁移
    log_step "7/7 运行数据库迁移"
    
    log_info "等待应用容器启动..."
    sleep 5
    
    if command_exists docker-compose; then
        CONTAINER_NAME=$(docker-compose ps -q app)
    else
        CONTAINER_NAME=$(docker compose ps -q app)
    fi

    if [ -n "$CONTAINER_NAME" ]; then
        log_info "正在运行数据库迁移..."
        if docker exec "$CONTAINER_NAME" sh -c "cd /app && yarn migrate" 2>/dev/null; then
            log_success "数据库迁移完成"
        else
            log_warning "数据库迁移失败，可能需要手动运行：docker-compose exec app yarn migrate"
        fi
    else
        log_warning "无法找到应用容器，请稍后手动运行：docker-compose exec app yarn migrate"
    fi

    # 9. 显示部署信息
    echo
    echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        部署成功！                     ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
    echo
    
    # 读取端口配置
    source .env
    
    log_info "服务访问地址："
    echo -e "  ${BLUE}•${NC} API 服务:      ${GREEN}http://localhost:${APP_PORT}${NC}"
    echo -e "  ${BLUE}•${NC} 健康检查:      ${GREEN}http://localhost:${APP_PORT}/health${NC}"
    echo -e "  ${BLUE}•${NC} Metrics:      ${GREEN}http://localhost:${METRICS_PORT}/metrics${NC}"
    echo -e "  ${BLUE}•${NC} MinIO 控制台:  ${GREEN}http://localhost:${MINIO_CONSOLE_PORT}${NC}"
    echo -e "  ${BLUE}•${NC} PostgreSQL:    ${GREEN}localhost:${POSTGRES_PORT}${NC}"
    echo -e "  ${BLUE}•${NC} Redis:         ${GREEN}localhost:${REDIS_PORT}${NC}"
    echo
    
    log_info "常用命令："
    echo -e "  ${BLUE}•${NC} 查看日志:      ${YELLOW}docker-compose logs -f${NC}"
    echo -e "  ${BLUE}•${NC} 查看状态:      ${YELLOW}docker-compose ps${NC}"
    echo -e "  ${BLUE}•${NC} 停止服务:      ${YELLOW}docker-compose down${NC}"
    echo -e "  ${BLUE}•${NC} 重启服务:      ${YELLOW}docker-compose restart${NC}"
    echo -e "  ${BLUE}•${NC} 更新服务:      ${YELLOW}./deploy.sh --update${NC}"
    echo
    
    log_info "数据存储位置："
    echo -e "  ${BLUE}•${NC} ${SCRIPT_DIR}/data/"
    echo
    
    log_warning "⚠️  安全提醒："
    echo "  1. 请确保 .env 文件的权限安全（建议执行: chmod 600 .env）"
    echo "  2. 生产环境请修改 .env 中的所有默认密码"
    echo "  3. 建议定期备份 data/ 目录"
    echo
}

# 创建 .env 文件
create_env_file() {
    log_info "创建 .env 配置文件..."
    
    if [ ! -f .env.example ]; then
        log_error ".env.example 模板文件不存在"
        exit 1
    fi
    
    cp .env.example .env
    
    # 生成安全的密钥
    log_info "生成安全密钥..."
    MASTER_SECRET=$(generate_secret)
    POSTGRES_PASSWORD=$(generate_secret | cut -c1-32)
    MINIO_PASSWORD=$(generate_secret | cut -c1-32)
    
    # 根据操作系统选择 sed 参数
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/HANDY_MASTER_SECRET=.*/HANDY_MASTER_SECRET=$MASTER_SECRET/" .env
        sed -i '' "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
        sed -i '' "s/MINIO_ROOT_PASSWORD=.*/MINIO_ROOT_PASSWORD=$MINIO_PASSWORD/" .env
    else
        # Linux
        sed -i "s/HANDY_MASTER_SECRET=.*/HANDY_MASTER_SECRET=$MASTER_SECRET/" .env
        sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
        sed -i "s/MINIO_ROOT_PASSWORD=.*/MINIO_ROOT_PASSWORD=$MINIO_PASSWORD/" .env
    fi
    
    log_success ".env 文件已创建并生成安全密钥"
    log_warning "如需修改配置，请编辑 .env 文件"
}

# 更新服务
update_services() {
    log_step "更新 Happy Server"
    
    log_info "重新构建应用镜像..."
    if command_exists docker-compose; then
        docker-compose build app
    else
        docker compose build app
    fi
    
    log_info "重启应用服务..."
    if command_exists docker-compose; then
        docker-compose up -d app
    else
        docker compose up -d app
    fi
    
    log_success "服务更新完成"
}

# 解析命令行参数
if [ "$1" = "--update" ]; then
    update_services
    exit 0
elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Happy Server 部署脚本"
    echo
    echo "用法："
    echo "  ./deploy.sh           - 完整部署"
    echo "  ./deploy.sh --update  - 更新服务到最新版本"
    echo "  ./deploy.sh --help    - 显示帮助信息"
    exit 0
fi

# 执行主函数
main

