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
echo "✅ Wallos 安装完成！"
echo "🔗 Wallos访问地址: http://$IP:8282/"
echo
echo "🌐 建议绑定域名并使用 CDN 保护你的服务器 IP。"
