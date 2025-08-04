#端口和reality(2)冲突，修改了NPM端口映射

#!/bin/bash

set -e

echo "🔄 更新系统..."
apt update -y

echo "📦 安装必要组件..."
apt install -y curl wget unzip git openssl

echo "🐳 安装 Docker（官方脚本）..."
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
else
  echo "🐳 Docker 已安装，跳过安装步骤"
fi

echo "🔧 启动 Docker 并设置开机自启..."
systemctl enable docker
systemctl start docker

echo "⏰ 设置系统时区为上海"
timedatectl set-timezone Asia/Shanghai

# ------------------------------
# 部署 Sub-Store
# ------------------------------
echo "📁 创建 Sub-Store 目录并准备环境..."
mkdir -p /root/docker/substore
cd /root/docker/substore

API_PATH=$(openssl rand -hex 12)
echo "🔐 Sub-Store API 路径：/$API_PATH"

echo "⬇️ 下载 Sub-Store 后端..."
curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js

echo "⬇️ 下载 Sub-Store 前端..."
curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
unzip -o dist.zip && mv dist frontend && rm dist.zip

echo "📋 写入 Sub-Store docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  substore:
    image: node:20.18.0
    container_name: substore
    restart: unless-stopped
    working_dir: /app
    command: ["node", "sub-store.bundle.js"]
    ports:
      - "3001:3001"
    environment:
      SUB_STORE_FRONTEND_BACKEND_PATH: "/$API_PATH"
      SUB_STORE_BACKEND_CRON: "0 0 * * *"
      SUB_STORE_FRONTEND_PATH: "/app/frontend"
      SUB_STORE_FRONTEND_HOST: "0.0.0.0"
      SUB_STORE_FRONTEND_PORT: "3001"
      SUB_STORE_DATA_BASE_PATH: "/app"
      SUB_STORE_BACKEND_API_HOST: "127.0.0.1"
      SUB_STORE_BACKEND_API_PORT: "3000"
    volumes:
      - ./sub-store.bundle.js:/app/sub-store.bundle.js
      - ./frontend:/app/frontend
      - ./data:/app/data
EOF

echo "🚀 启动 Sub-Store 容器..."
docker compose up -d

# ------------------------------
# 部署 Nginx Proxy Manager (npm)
# ------------------------------
echo "📁 创建 Nginx Proxy Manager 目录..."
mkdir -p /root/docker/npm
cd /root/docker/npm

echo "📋 写入 Nginx Proxy Manager docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '8080:80'
      - '81:81'
      - '8444:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

echo "🚀 启动 Nginx Proxy Manager 容器..."
docker compose up -d

# ------------------------------
# 部署 Wallos
# ------------------------------
echo "📁 创建 Wallos 目录..."
mkdir -p /root/docker/wallos
cd /root/docker/wallos

echo "📋 写入 Wallos docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: '3.0'

services:
  wallos:
    container_name: wallos
    image: bellamy/wallos:2.39.0
    ports:
      - "8282:80/tcp"
    environment:
      TZ: 'Asia/Shanghai'
    volumes:
      - './db:/var/www/html/db'
      - './logos:/var/www/html/images/uploads/logos'
    restart: unless-stopped
EOF

echo "🚀 启动 Wallos 容器..."
docker compose up -d

# ------------------------------
# 完成提示
# ------------------------------
IP=$(curl -s https://ipinfo.io/ip || echo "<你的IP>")

echo
echo "✅ 所有项目安装完成！"
echo "🔗 Sub-Store访问地址: http://$IP:3001/?api=http://$IP:3001/$API_PATH"
echo "🔗 Nginx Proxy Manager管理面板: http://$IP:81"
echo "    默认登录：admin@example.com / changeme"
echo "🔗 Wallos访问地址: http://$IP:8282/"
echo
echo "🌐 建议绑定域名并使用 CDN 保护你的服务器 IP。"
