#!/bin/bash

echo "📦 开始更新系统并安装依赖..."

# 更新系统并安装常用工具
apt update -y && apt upgrade -y
apt install -y curl sudo wget git unzip nano vim

echo "🐳 安装 Docker..."

# 安装 Docker
curl -fsSL https://get.docker.com | sh

echo "✅ Docker 安装完成，安装 Docker Compose 插件..."

# 安装 Docker Compose 插件（v2）
mkdir -p ~/.docker/cli-plugins/
curl -SL https://github.com/docker/compose/releases/download/v2.24.7/docker-compose-linux-x86_64 \
  -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose

# 确保 docker compose 命令可用
export PATH=$PATH:~/.docker/cli-plugins/

echo "✅ Docker Compose 安装完成"

echo "📁 创建目录结构..."
mkdir -p /root/docker/{npm,substore,wallos}

echo "📦 写入 docker-compose 文件..."

# 写入 NPM 配置
cat > /root/docker/npm/docker-compose.yml <<EOF
version: '3.8'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

# 写入 Wallos 配置
cat > /root/docker/wallos/docker-compose.yml <<EOF
version: '3.8'
services:
  wallos:
    image: ghcr.io/wallosworld/wallos:latest
    container_name: wallos
    restart: unless-stopped
    ports:
      - "8282:80"
    volumes:
      - ./data:/app/data
EOF

# 生成随机 API 密钥
SUBSTORE_API_KEY=$(openssl rand -hex 16)

# 写入 Sub-Store 配置
cat > /root/docker/substore/docker-compose.yml <<EOF
version: '3.8'
services:
  substore:
    image: ghcr.io/sub-store-org/sub-store:latest
    container_name: substore
    restart: unless-stopped
    ports:
      - "3001:3000"
    volumes:
      - ./data:/app/data
    environment:
      - API_SECRET=$SUBSTORE_API_KEY
EOF

echo "🚀 正在启动所有服务..."

cd /root/docker/npm && docker compose up -d
cd /root/docker/wallos && docker compose up -d
cd /root/docker/substore && docker compose up -d

echo "✅ 所有服务已启动完成"

echo "🔑 Sub-Store API 访问密钥: $SUBSTORE_API_KEY"
echo "🌐 Sub-Store 访问地址: http://$(curl -s ifconfig.me):3001/?api=http://$(curl -s ifconfig.me):3001/$SUBSTORE_API_KEY"
