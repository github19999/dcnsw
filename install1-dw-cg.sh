#!/bin/bash
set -e

echo "🔄 更新系统..."
apt update -y

echo "📦 安装必要组件..."
apt install -y curl wget unzip git openssl

echo "🐳 安装 Docker..."
if ! command -v docker >/dev/null 2>&1; then
  echo "📋 检测系统版本并安装 Docker..."
  
  # 手动安装 Docker（适配更多系统版本）
  apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
  
  # 添加 Docker GPG 密钥
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  
  # 添加 Docker 仓库
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  # 更新并安装 Docker
  apt update -y
  apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  
  echo "✅ Docker 安装完成"
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
