#!/bin/bash
set -euo pipefail  # Added -u and -o pipefail for better error handling

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "此脚本需要root权限运行"
   exit 1
fi

print_status "🔄 更新系统..."
apt update -y && apt upgrade -y

print_status "📦 安装必要组件..."
apt install -y curl wget unzip git openssl ufw fail2ban

print_status "🔒 配置基础安全设置..."
# Configure UFW firewall
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 81/tcp
ufw allow 443/tcp
ufw allow 3001/tcp
ufw allow 8282/tcp

print_status "🐳 安装 Docker（官方脚本）..."
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    # Verify the script (basic check)
    if [[ ! -f get-docker.sh ]]; then
        print_error "Docker安装脚本下载失败"
        exit 1
    fi
    sh get-docker.sh
    rm get-docker.sh
else
    print_status "🐳 Docker 已安装，跳过安装步骤"
fi

# Install Docker Compose if not present
if ! command -v docker-compose >/dev/null 2>&1; then
    print_status "📦 安装 Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

print_status "🔧 启动 Docker 并设置开机自启..."
systemctl enable docker
systemctl start docker

print_status "⏰ 设置系统时区为上海"
timedatectl set-timezone Asia/Shanghai

# Create main docker directory with proper permissions
mkdir -p /root/docker
chmod 700 /root/docker

# ------------------------------
# 部署 Sub-Store
# ------------------------------
print_status "📁 创建 Sub-Store 目录并准备环境..."
mkdir -p /root/docker/substore/data
cd /root/docker/substore

# Generate a more secure API path
API_PATH=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-16)
print_status "🔐 Sub-Store API 路径：/$API_PATH"

print_status "⬇️ 下载 Sub-Store 后端..."
if ! curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js; then
    print_error "Sub-Store 后端下载失败"
    exit 1
fi

print_status "⬇️ 下载 Sub-Store 前端..."
if ! curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip; then
    print_error "Sub-Store 前端下载失败"
    exit 1
fi

unzip -o dist.zip && mv dist frontend && rm dist.zip

print_status "📋 写入 Sub-Store docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  substore:
    image: node:20.18.0-alpine  # Using alpine for smaller size
    container_name: substore
    restart: unless-stopped
    working_dir: /app
    command: ["node", "sub-store.bundle.js"]
    ports:
      - "127.0.0.1:3001:3001"  # Bind to localhost only
    environment:
      SUB_STORE_FRONTEND_BACKEND_PATH: "/$API_PATH"
      SUB_STORE_BACKEND_CRON: "0 0 * * *"
      SUB_STORE_FRONTEND_PATH: "/app/frontend"
      SUB_STORE_FRONTEND_HOST: "0.0.0.0"
      SUB_STORE_FRONTEND_PORT: "3001"
      SUB_STORE_DATA_BASE_PATH: "/app"
      SUB_STORE_BACKEND_API_HOST: "127.0.0.1"
      SUB_STORE_BACKEND_API_PORT: "3000"
      NODE_ENV: "production"
    volumes:
      - ./sub-store.bundle.js:/app/sub-store.bundle.js:ro
      - ./frontend:/app/frontend:ro
      - ./data:/app/data
    user: "1000:1000"  # Run as non-root user
    read_only: true
    tmpfs:
      - /tmp
    security_opt:
      - no-new-privileges:true
EOF

print_status "🚀 启动 Sub-Store 容器..."
docker-compose up -d

# ------------------------------
# 部署 Nginx Proxy Manager (npm)
# ------------------------------
print_status "📁 创建 Nginx Proxy Manager 目录..."
mkdir -p /root/docker/npm/{data,letsencrypt}
cd /root/docker/npm

print_status "📋 写入 Nginx Proxy Manager docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    environment:
      DB_SQLITE_FILE: "/data/database.sqlite"
      DISABLE_IPV6: 'true'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    healthcheck:
      test: ["CMD", "/bin/check-health"]
      interval: 10s
      timeout: 3s
EOF

print_status "🚀 启动 Nginx Proxy Manager 容器..."
docker-compose up -d

# ------------------------------
# 部署 Wallos
# ------------------------------
print_status "📁 创建 Wallos 目录..."
mkdir -p /root/docker/wallos/{db,logos}
cd /root/docker/wallos

print_status "📋 写入 Wallos docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  wallos:
    container_name: wallos
    image: bellamy/wallos:2.39.0
    ports:
      - "127.0.0.1:8282:80"  # Bind to localhost only
    environment:
      TZ: 'Asia/Shanghai'
    volumes:
      - './db:/var/www/html/db'
      - './logos:/var/www/html/images/uploads/logos'
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

print_status "🚀 启动 Wallos 容器..."
docker-compose up -d

# ------------------------------
# 创建备份脚本
# ------------------------------
print_status "📝 创建备份脚本..."
cat > /root/backup_docker_services.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="/root/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup Sub-Store data
tar -czf $BACKUP_DIR/substore_$DATE.tar.gz -C /root/docker/substore data

# Backup Nginx Proxy Manager data
tar -czf $BACKUP_DIR/npm_$DATE.tar.gz -C /root/docker/npm data letsencrypt

# Backup Wallos data
tar -czf $BACKUP_DIR/wallos_$DATE.tar.gz -C /root/docker/wallos db logos

# Keep only last 7 backups
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
EOF

chmod +x /root/backup_docker_services.sh

# Add to crontab for daily backups
(crontab -l 2>/dev/null; echo "0 2 * * * /root/backup_docker_services.sh >> /var/log/backup.log 2>&1") | crontab -

# ------------------------------
# 完成提示
# ------------------------------
print_status "⏳ 等待服务启动..."
sleep 10

# Get public IP
IP=$(curl -s --max-time 10 https://ipinfo.io/ip || curl -s --max-time 10 https://api.ipify.org || echo "<获取IP失败>")

echo
print_status "✅ 所有项目安装完成！"
echo
print_warning "📋 重要信息："
echo "🔐 API密钥: $API_PATH"
echo "🔗 Sub-Store访问地址: http://$IP:3001/?api=http://$IP:3001/$API_PATH"
echo "🔗 Nginx Proxy Manager管理面板: http://$IP:81"
echo "    默认登录：admin@example.com / changeme"
echo "🔗 Wallos访问地址: http://$IP:8282/"
echo
print_warning "🔒 安全建议："
echo "1. 立即登录 Nginx Proxy Manager 更改默认密码"
echo "2. 配置SSL证书和反向代理"
echo "3. 考虑使用CDN保护真实IP"
echo "4. 定期检查 /var/log/backup.log 确认备份正常"
echo
print_status "📊 服务状态检查："
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Save important info to file
cat > /root/docker/service_info.txt <<EOF
部署完成时间: $(date)
服务器IP: $IP
Nginx Proxy Manager: http://$IP:81
备份脚本位置: /root/backup_docker_services.sh
EOF

print_status "📝 服务信息已保存到 /root/docker/service_info.txt"
