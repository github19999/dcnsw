#!/bin/bash

set -e

echo "🔄 更新系统..."
apt update -y && apt upgrade -y

echo "📦 安装必要组件..."
apt install -y curl wget unzip git sudo nano vim

echo "🕒 设置时区为上海..."
timedatectl set-timezone Asia/Shanghai

# ========================================
# 🚀 安装 Sub-Store
# ========================================
echo "📁 设置 Sub-Store 环境..."
mkdir -p /root/docker/substore
cd /root/docker/substore

echo "🔐 生成 Sub-Store API 路径..."
API_PATH=$(openssl rand -hex 12)

echo "⬇️ 下载 Sub-Store 后端..."
curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js

echo "⬇️ 下载 Sub-Store 前端..."
curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
unzip dist.zip && mv dist frontend && rm dist.zip

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

echo "🚀 启动 Sub-Store..."
docker compose up -d

# ========================================
# 🚀 安装 Nginx Proxy Manager
# ========================================
echo "📁 设置 Nginx Proxy Manager 环境..."
mkdir -p /root/docker/npm
cd /root/docker/npm

echo "📋 写入 NPM docker-compose.yaml..."
cat > docker-compose.yaml <<EOF
version: '3.8'
services:
  app:
    image: jc21/nginx-proxy-manager:latest
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

echo "🚀 启动 NPM..."
docker compose up -d

# ========================================
# 🚀 安装 Wallos
# ========================================
echo "📁 设置 Wallos 环境..."
mkdir -p /root/docker/wallos
cd /root/docker/wallos

echo "📋 写入 Wallos docker-compose.yaml..."
cat > docker-compose.yaml <<EOF
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

echo "🚀 启动 Wallos..."
docker compose up -d

# ========================================
# ✅ 输出访问链接
# ========================================
IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me)

echo
echo "✅ 所有服务安装完成！以下是访问链接："
echo "🔗 Sub-Store： http://$IP:3001/?api=http://$IP:3001/$API_PATH"
echo "🔗 Nginx Proxy Manager： http://$IP:81"
echo "🔗 Wallos： http://$IP:8282/"
echo
echo "📌 Nginx Proxy Manager 默认登录账户：admin@example.com / changeme"
echo "📌 建议设置防火墙或配合 CDN 以增强安全性。"
