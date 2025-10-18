# Happy Server 一键部署脚本 (Windows PowerShell)
# 用途：自动完成 Happy Server 的部署流程

# 错误时退出
$ErrorActionPreference = "Stop"

# 颜色函数
function Write-ColorOutput($ForegroundColor, $Message) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    Write-Output $Message
    $host.UI.RawUI.ForegroundColor = $fc
}

function Log-Info($Message) {
    Write-ColorOutput Blue "ℹ $Message"
}

function Log-Success($Message) {
    Write-ColorOutput Green "✓ $Message"
}

function Log-Warning($Message) {
    Write-ColorOutput Yellow "⚠ $Message"
}

function Log-Error($Message) {
    Write-ColorOutput Red "✗ $Message"
}

function Log-Step($Message) {
    Write-Host ""
    Write-ColorOutput Yellow "==> $Message"
    Write-Host ""
}

# 检查命令是否存在
function Test-CommandExists($Command) {
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# 检查 Docker 是否运行
function Test-DockerRunning {
    try {
        docker info | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# 启动 Docker Desktop
function Start-DockerDesktop {
    Log-Info "尝试启动 Docker Desktop..."
    
    # 查找 Docker Desktop 可执行文件
    $dockerPaths = @(
        "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Docker\Docker Desktop.exe"
    )
    
    $dockerExe = $null
    foreach ($path in $dockerPaths) {
        if (Test-Path $path) {
            $dockerExe = $path
            break
        }
    }
    
    if (-not $dockerExe) {
        Log-Error "未找到 Docker Desktop，请确保已安装"
        Log-Info "访问 https://www.docker.com/products/docker-desktop 下载"
        return $false
    }
    
    # 检查是否已经在运行
    $dockerProcess = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    if ($dockerProcess) {
        Log-Info "Docker Desktop 进程已存在，等待服务就绪..."
    }
    else {
        Log-Info "启动 Docker Desktop..."
        Start-Process -FilePath $dockerExe -WindowStyle Hidden
        Log-Success "Docker Desktop 已启动"
    }
    
    # 等待 Docker 服务就绪
    Log-Info "等待 Docker 服务启动（最多等待 60 秒）..."
    $waitTime = 0
    $maxWait = 60
    
    while ($waitTime -lt $maxWait) {
        if (Test-DockerRunning) {
            Write-Host ""
            Log-Success "Docker 服务已就绪"
            return $true
        }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 2
        $waitTime += 2
    }
    
    Write-Host ""
    Log-Error "Docker 启动超时，请手动检查 Docker Desktop 状态"
    return $false
}

# 生成随机密钥
function New-RandomSecret {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    return [BitConverter]::ToString($bytes).Replace("-", "").ToLower()
}

# 创建 .env 文件
function New-EnvFile {
    Log-Info "创建 .env 配置文件..."
    
    if (-not (Test-Path .env.example)) {
        Log-Error ".env.example 模板文件不存在"
        exit 1
    }
    
    Copy-Item .env.example .env -Force
    
    # 生成安全的密钥
    Log-Info "生成安全密钥..."
    $masterSecret = New-RandomSecret
    $postgresPassword = (New-RandomSecret).Substring(0, 32)
    $minioPassword = (New-RandomSecret).Substring(0, 32)
    
    # 替换配置
    $content = Get-Content .env -Raw
    $content = $content -replace "HANDY_MASTER_SECRET=.*", "HANDY_MASTER_SECRET=$masterSecret"
    $content = $content -replace "POSTGRES_PASSWORD=.*", "POSTGRES_PASSWORD=$postgresPassword"
    $content = $content -replace "MINIO_ROOT_PASSWORD=.*", "MINIO_ROOT_PASSWORD=$minioPassword"
    $content | Set-Content .env -NoNewline
    
    Log-Success ".env 文件已创建并生成安全密钥"
    Log-Warning "如需修改配置，请编辑 .env 文件"
}

# 更新服务
function Update-Services {
    Log-Step "更新 Happy Server"
    
    Log-Info "重新构建应用镜像..."
    docker-compose build app
    
    Log-Info "重启应用服务..."
    docker-compose up -d app
    
    Log-Success "服务更新完成"
}

# 主函数
function Main {
    Write-Host ""
    Write-ColorOutput Green "╔═══════════════════════════════════════╗"
    Write-ColorOutput Green "║   Happy Server 一键部署脚本          ║"
    Write-ColorOutput Green "╚═══════════════════════════════════════╝"
    Write-Host ""

    # 1. 检查依赖
    Log-Step "1/7 检查系统依赖"
    
    if (-not (Test-CommandExists docker)) {
        Log-Error "Docker 未安装，请先安装 Docker Desktop"
        Log-Info "访问 https://www.docker.com/products/docker-desktop 下载"
        exit 1
    }
    Log-Success "Docker 已安装"

    if (-not (Test-CommandExists docker-compose)) {
        Log-Error "Docker Compose 未安装，请确保 Docker Desktop 已正确安装"
        exit 1
    }
    Log-Success "Docker Compose 已安装"

    if (-not (Test-DockerRunning)) {
        Log-Warning "Docker 服务未运行"
        
        # 询问是否自动启动
        $response = Read-Host "是否自动启动 Docker Desktop？(Y/n)"
        
        if ($response -eq "n" -or $response -eq "N") {
            Log-Error "Docker 服务未运行，部署已取消"
            Log-Info "请手动启动 Docker Desktop 后重新运行脚本"
            exit 1
        }
        
        # 尝试启动 Docker
        if (-not (Start-DockerDesktop)) {
            Log-Error "无法自动启动 Docker，请手动启动 Docker Desktop 后重新运行脚本"
            exit 1
        }
    }
    else {
        Log-Success "Docker 服务正在运行"
    }

    # 2. 切换到 deploy 目录
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    Set-Location $scriptDir
    Log-Info "工作目录: $scriptDir"

    # 3. 配置环境变量
    Log-Step "2/7 配置环境变量"
    
    if (Test-Path .env) {
        Log-Warning ".env 文件已存在"
        $response = Read-Host "是否要重新生成？这将覆盖现有配置 (y/N)"
        if ($response -ne "y" -and $response -ne "Y") {
            Log-Info "保留现有 .env 配置"
        }
        else {
            New-EnvFile
        }
    }
    else {
        New-EnvFile
    }

    # 4. 准备数据存储
    Log-Step "3/7 准备数据存储"
    
    Log-Info "数据将使用 Docker volumes 存储"
    Log-Info "这样可以解决 Windows/WSL 权限问题"
    Log-Success "数据存储配置完成"

    # 5. 构建和拉取镜像
    Log-Step "4/7 构建和拉取 Docker 镜像"
    
    Log-Info "正在拉取基础镜像..."
    # 拉取基础镜像（postgres, redis, minio）
    try {
        docker-compose pull postgres redis minio minio-init 2>&1 | Out-Null
    }
    catch {
        # 忽略错误，继续执行
    }
    Log-Success "基础镜像拉取完成"
    
    Log-Info "正在构建应用镜像，这可能需要几分钟..."
    Log-Warning "首次构建会下载依赖，请耐心等待"
    
    # 构建应用镜像
    try {
        docker-compose build app
        Log-Success "应用镜像构建完成"
    }
    catch {
        Log-Error "应用镜像构建失败"
        Log-Info "请检查 Dockerfile 和构建日志"
        exit 1
    }

    # 6. 启动服务
    Log-Step "5/7 启动服务"
    
    Log-Info "正在启动所有服务..."
    docker-compose up -d
    Log-Success "服务已启动"

    # 7. 等待服务健康检查
    Log-Step "6/7 等待服务就绪"
    
    Log-Info "等待数据库和其他服务启动（最多等待 60 秒）..."
    $waitTime = 0
    $maxWait = 60
    
    while ($waitTime -lt $maxWait) {
        $ps = docker-compose ps
        $healthy = ($ps | Select-String "healthy").Count
        
        if ($healthy -ge 3) {  # postgres, redis, minio 至少 3 个服务健康
            Write-Host ""
            Log-Success "服务已就绪"
            break
        }
        
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 2
        $waitTime += 2
    }
    Write-Host ""

    if ($waitTime -ge $maxWait) {
        Log-Warning "服务启动超时，但这可能是正常的"
        Log-Info "请稍后手动检查服务状态：docker-compose ps"
    }

    # 8. 运行数据库迁移
    Log-Step "7/7 运行数据库迁移"
    
    Log-Info "等待应用容器启动..."
    Start-Sleep -Seconds 5
    
    $containerName = (docker-compose ps -q app)
    if ($containerName) {
        Log-Info "正在运行数据库迁移..."
        try {
            docker exec $containerName sh -c "cd /app && yarn migrate"
            Log-Success "数据库迁移完成"
        }
        catch {
            Log-Warning "数据库迁移失败，可能需要手动运行：docker-compose exec app yarn migrate"
        }
    }
    else {
        Log-Warning "无法找到应用容器，请稍后手动运行：docker-compose exec app yarn migrate"
    }

    # 9. 显示部署信息
    Write-Host ""
    Write-ColorOutput Green "╔═══════════════════════════════════════╗"
    Write-ColorOutput Green "║        部署成功！                     ║"
    Write-ColorOutput Green "╚═══════════════════════════════════════╝"
    Write-Host ""
    
    # 读取端口配置
    $env = Get-Content .env | ConvertFrom-StringData
    $appPort = $env.APP_PORT
    $metricsPort = $env.METRICS_PORT
    $minioConsolePort = $env.MINIO_CONSOLE_PORT
    $postgresPort = $env.POSTGRES_PORT
    $redisPort = $env.REDIS_PORT
    
    Log-Info "服务访问地址："
    Write-Host "  • API 服务:      http://localhost:$appPort" -ForegroundColor Green
    Write-Host "  • 健康检查:      http://localhost:$appPort/health" -ForegroundColor Green
    Write-Host "  • Metrics:      http://localhost:$metricsPort/metrics" -ForegroundColor Green
    Write-Host "  • MinIO 控制台:  http://localhost:$minioConsolePort" -ForegroundColor Green
    Write-Host "  • PostgreSQL:    localhost:$postgresPort" -ForegroundColor Green
    Write-Host "  • Redis:         localhost:$redisPort" -ForegroundColor Green
    Write-Host ""
    
    Log-Info "常用命令："
    Write-Host "  • 查看日志:      docker-compose logs -f" -ForegroundColor Yellow
    Write-Host "  • 查看状态:      docker-compose ps" -ForegroundColor Yellow
    Write-Host "  • 停止服务:      docker-compose down" -ForegroundColor Yellow
    Write-Host "  • 重启服务:      docker-compose restart" -ForegroundColor Yellow
    Write-Host "  • 更新服务:      .\deploy.ps1 -Update" -ForegroundColor Yellow
    Write-Host ""
    
    Log-Info "数据存储位置："
    Write-Host "  • $scriptDir\data\"
    Write-Host ""
    
    Log-Warning "⚠️  安全提醒："
    Write-Host "  1. 请确保 .env 文件的权限安全"
    Write-Host "  2. 生产环境请修改 .env 中的所有默认密码"
    Write-Host "  3. 建议定期备份 data\ 目录"
    Write-Host ""
}

# 解析命令行参数
param(
    [switch]$Update,
    [switch]$Help
)

if ($Help) {
    Write-Host "Happy Server 部署脚本"
    Write-Host ""
    Write-Host "用法："
    Write-Host "  .\deploy.ps1           - 完整部署"
    Write-Host "  .\deploy.ps1 -Update   - 更新服务到最新版本"
    Write-Host "  .\deploy.ps1 -Help     - 显示帮助信息"
    exit 0
}

if ($Update) {
    Update-Services
    exit 0
}

# 执行主函数
try {
    Main
}
catch {
    Log-Error "部署过程中出现错误: $_"
    exit 1
}

