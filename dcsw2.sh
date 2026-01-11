#!/bin/bash
set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔄 更新系统...${NC}"
apt update -y

echo -e "${BLUE}📦 安装必要组件...${NC}"
apt install -y curl wget unzip git openssl nginx certbot python3-certbot-nginx

echo -e "${BLUE}🐳 安装 Docker（官方脚本）...${NC}"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
else
  echo -e "${GREEN}🐳 Docker 已安装，跳过安装步骤${NC}"
fi

echo -e "${BLUE}🔧 启动 Docker 并设置开机自启...${NC}"
systemctl enable docker
systemctl start docker

if ! docker compose version >/dev/null 2>&1; then
  echo -e "${BLUE}📦 安装 Docker Compose 插件...${NC}"
  apt install -y docker-compose-plugin
fi

echo -e "${BLUE}⏰ 设置系统时区为上海${NC}"
timedatectl set-timezone Asia/Shanghai

# ------------------------------
# 域名配置
# ------------------------------
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}🌐 HTTPS 配置（可选）${NC}"
echo -e "${BLUE}========================================${NC}"
read -p "是否配置域名和 HTTPS？(y/n): " use_domain

if [[ "$use_domain" =~ ^[Yy]$ ]]; then
  read -p "请输入 Sub-Store 域名 (例: sub.example.com): " SUBSTORE_DOMAIN
  read -p "请输入 Wallos 域名 (例: wallos.example.com): " WALLOS_DOMAIN
  USE_HTTPS=true
else
  USE_HTTPS=false
  IP=$(curl -s https://ipinfo.io/ip || echo "YOUR_IP")
fi

# ------------------------------
# 部署 Sub-Store
# ------------------------------
echo -e "${BLUE}📁 创建 Sub-Store 目录并准备环境...${NC}"
mkdir -p /root/docker/substore/data
cd /root/docker/substore

API_PATH=$(openssl rand -hex 12)
echo -e "${YELLOW}🔐 Sub-Store API 路径：/$API_PATH${NC}"
echo "$API_PATH" > api_path.txt

echo -e "${BLUE}⬇️ 下载 Sub-Store 后端...${NC}"
curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js

echo -e "${BLUE}⬇️ 下载 Sub-Store 前端...${NC}"
curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
unzip -o dist.zip && mv dist frontend && rm dist.zip

echo -e "${BLUE}📋 写入 Sub-Store docker-compose.yml...${NC}"
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
      - "127.0.0.1:3001:3001"
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
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

echo -e "${BLUE}🚀 启动 Sub-Store 容器...${NC}"
docker compose up -d

# ------------------------------
# 部署 Wallos
# ------------------------------
echo -e "${BLUE}📁 创建 Wallos 目录...${NC}"
mkdir -p /root/docker/wallos/{db,logos}
cd /root/docker/wallos

echo -e "${BLUE}📋 写入 Wallos docker-compose.yml...${NC}"
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  wallos:
    container_name: wallos
    image: bellamy/wallos:2.39.0
    ports:
      - "127.0.0.1:8282:80/tcp"
    environment:
      TZ: 'Asia/Shanghai'
    volumes:
      - './db:/var/www/html/db'
      - './logos:/var/www/html/images/uploads/logos'
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

echo -e "${BLUE}🚀 启动 Wallos 容器...${NC}"
docker compose up -d

# ------------------------------
# 配置 Nginx 反向代理
# ------------------------------
if [ "$USE_HTTPS" = true ]; then
  echo -e "${BLUE}🔧 配置 Nginx 反向代理...${NC}"
  
  # Sub-Store Nginx 配置
  cat > /etc/nginx/sites-available/substore <<EOF
server {
    listen 80;
    server_name $SUBSTORE_DOMAIN;
    
    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

  # Wallos Nginx 配置
  cat > /etc/nginx/sites-available/wallos <<EOF
server {
    listen 80;
    server_name $WALLOS_DOMAIN;
    
    location / {
        proxy_pass http://127.0.0.1:8282;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/substore /etc/nginx/sites-enabled/
  ln -sf /etc/nginx/sites-available/wallos /etc/nginx/sites-enabled/
  
  nginx -t && systemctl restart nginx
  
  echo -e "${BLUE}🔒 申请 SSL 证书...${NC}"
  certbot --nginx -d $SUBSTORE_DOMAIN -d $WALLOS_DOMAIN --non-interactive --agree-tos --register-unsafely-without-email
  
  # 保存域名配置
  echo "$SUBSTORE_DOMAIN" > /root/docker/substore/domain.txt
  echo "$WALLOS_DOMAIN" > /root/docker/wallos/domain.txt
fi

# ------------------------------
# 创建管理脚本
# ------------------------------
echo -e "${BLUE}📝 创建管理脚本...${NC}"
cat > /usr/local/bin/vps-manage <<'SCRIPT'
#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

show_menu() {
  echo -e "${BLUE}========================================${NC}"
  echo -e "${GREEN}     VPS 服务管理菜单${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo "1.  查看所有服务状态"
  echo "2.  启动 Sub-Store"
  echo "3.  启动 Wallos"
  echo "4.  启动所有服务"
  echo "5.  停止 Sub-Store"
  echo "6.  停止 Wallos"
  echo "7.  停止所有服务"
  echo "8.  重启 Sub-Store"
  echo "9.  重启 Wallos"
  echo "10. 重启所有服务"
  echo "11. 更新 Sub-Store"
  echo "12. 更新 Wallos"
  echo "13. 删除 Sub-Store"
  echo "14. 删除 Wallos"
  echo "15. 查看 Sub-Store 日志"
  echo "16. 查看 Wallos 日志"
  echo "17. 查看访问地址"
  echo "18. 查看 Sub-Store API 路径"
  echo "0.  退出"
  echo -e "${BLUE}========================================${NC}"
}

get_url() {
  local service=$1
  local port=$2
  local domain_file="/root/docker/$service/domain.txt"
  
  if [ -f "$domain_file" ]; then
    domain=$(cat "$domain_file")
    echo "https://$domain"
  else
    ip=$(curl -s https://ipinfo.io/ip 2>/dev/null || echo "YOUR_IP")
    echo "http://$ip:$port"
  fi
}

while true; do
  show_menu
  read -p "请选择操作 [0-18]: " choice
  
  case $choice in
    1)
      echo -e "${BLUE}📊 服务状态：${NC}"
      docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
      ;;
    2)
      echo -e "${BLUE}▶️  启动 Sub-Store...${NC}"
      cd /root/docker/substore && docker compose start
      echo -e "${GREEN}✅ Sub-Store 已启动${NC}"
      ;;
    3)
      echo -e "${BLUE}▶️  启动 Wallos...${NC}"
      cd /root/docker/wallos && docker compose start
      echo -e "${GREEN}✅ Wallos 已启动${NC}"
      ;;
    4)
      echo -e "${BLUE}▶️  启动所有服务...${NC}"
      cd /root/docker/substore && docker compose start
      cd /root/docker/wallos && docker compose start
      echo -e "${GREEN}✅ 所有服务已启动${NC}"
      ;;
    5)
      echo -e "${YELLOW}⏸️  停止 Sub-Store...${NC}"
      cd /root/docker/substore && docker compose stop
      echo -e "${GREEN}✅ Sub-Store 已停止${NC}"
      ;;
    6)
      echo -e "${YELLOW}⏸️  停止 Wallos...${NC}"
      cd /root/docker/wallos && docker compose stop
      echo -e "${GREEN}✅ Wallos 已停止${NC}"
      ;;
    7)
      echo -e "${YELLOW}⏸️  停止所有服务...${NC}"
      cd /root/docker/substore && docker compose stop
      cd /root/docker/wallos && docker compose stop
      echo -e "${GREEN}✅ 所有服务已停止${NC}"
      ;;
    8)
      echo -e "${BLUE}🔄 重启 Sub-Store...${NC}"
      cd /root/docker/substore && docker compose restart
      echo -e "${GREEN}✅ Sub-Store 已重启${NC}"
      ;;
    9)
      echo -e "${BLUE}🔄 重启 Wallos...${NC}"
      cd /root/docker/wallos && docker compose restart
      echo -e "${GREEN}✅ Wallos 已重启${NC}"
      ;;
    10)
      echo -e "${BLUE}🔄 重启所有服务...${NC}"
      cd /root/docker/substore && docker compose restart
      cd /root/docker/wallos && docker compose restart
      echo -e "${GREEN}✅ 所有服务已重启${NC}"
      ;;
    11)
      echo -e "${BLUE}⬆️  更新 Sub-Store...${NC}"
      cd /root/docker/substore
      curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
      rm -rf frontend dist.zip
      curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
      unzip -o dist.zip && mv dist frontend && rm dist.zip
      docker compose restart
      echo -e "${GREEN}✅ Sub-Store 已更新${NC}"
      ;;
    12)
      echo -e "${BLUE}⬆️  更新 Wallos...${NC}"
      cd /root/docker/wallos
      docker compose pull
      docker compose up -d
      echo -e "${GREEN}✅ Wallos 已更新${NC}"
      ;;
    13)
      read -p "确认删除 Sub-Store？此操作将删除所有数据 (y/n): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}🗑️  删除 Sub-Store...${NC}"
        cd /root/docker/substore && docker compose down -v
        rm -rf /root/docker/substore
        [ -f /etc/nginx/sites-enabled/substore ] && rm /etc/nginx/sites-enabled/substore
        [ -f /etc/nginx/sites-available/substore ] && rm /etc/nginx/sites-available/substore
        systemctl reload nginx 2>/dev/null
        echo -e "${GREEN}✅ Sub-Store 已删除${NC}"
      fi
      ;;
    14)
      read -p "确认删除 Wallos？此操作将删除所有数据 (y/n): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}🗑️  删除 Wallos...${NC}"
        cd /root/docker/wallos && docker compose down -v
        rm -rf /root/docker/wallos
        [ -f /etc/nginx/sites-enabled/wallos ] && rm /etc/nginx/sites-enabled/wallos
        [ -f /etc/nginx/sites-available/wallos ] && rm /etc/nginx/sites-available/wallos
        systemctl reload nginx 2>/dev/null
        echo -e "${GREEN}✅ Wallos 已删除${NC}"
      fi
      ;;
    15)
      echo -e "${BLUE}📋 Sub-Store 日志（Ctrl+C 退出）：${NC}"
      docker logs -f substore
      ;;
    16)
      echo -e "${BLUE}📋 Wallos 日志（Ctrl+C 退出）：${NC}"
      docker logs -f wallos
      ;;
    17)
      echo -e "${BLUE}🔗 访问地址：${NC}"
      substore_url=$(get_url "substore" "3001")
      wallos_url=$(get_url "wallos" "8282")
      
      if [ -f /root/docker/substore/api_path.txt ]; then
        api=$(cat /root/docker/substore/api_path.txt)
        echo -e "   Sub-Store: ${YELLOW}${substore_url}/?api=${substore_url}/${api}${NC}"
      else
        echo -e "   Sub-Store: ${YELLOW}${substore_url}${NC}"
      fi
      echo -e "   Wallos:    ${YELLOW}${wallos_url}${NC}"
      ;;
    18)
      if [ -f /root/docker/substore/api_path.txt ]; then
        api=$(cat /root/docker/substore/api_path.txt)
        substore_url=$(get_url "substore" "3001")
        echo -e "${YELLOW}🔐 Sub-Store API 路径：${NC}"
        echo -e "   /${api}"
        echo -e "${YELLOW}🔗 完整 API 地址：${NC}"
        echo -e "   ${substore_url}/${api}"
      else
        echo -e "${RED}❌ API 路径文件未找到${NC}"
      fi
      ;;
    0)
      echo -e "${GREEN}👋 再见！${NC}"
      exit 0
      ;;
    *)
      echo -e "${RED}❌ 无效选择，请重新输入${NC}"
      ;;
  esac
  echo
  read -p "按 Enter 键继续..."
  clear
done
SCRIPT

chmod +x /usr/local/bin/vps-manage

# ------------------------------
# 完成提示
# ------------------------------
echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✅ 所有项目安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${BLUE}🔗 访问地址：${NC}"

if [ "$USE_HTTPS" = true ]; then
  echo -e "   Sub-Store: ${YELLOW}https://$SUBSTORE_DOMAIN/?api=https://$SUBSTORE_DOMAIN/$API_PATH${NC}"
  echo -e "   Wallos:    ${YELLOW}https://$WALLOS_DOMAIN${NC}"
else
  echo -e "   Sub-Store: ${YELLOW}http://$IP:3001/?api=http://$IP:3001/$API_PATH${NC}"
  echo -e "   Wallos:    ${YELLOW}http://$IP:8282/${NC}"
fi

echo
echo -e "${BLUE}🔐 Sub-Store API 路径：${NC}"
echo -e "   ${YELLOW}/$API_PATH${NC}"
echo -e "   已保存到：${YELLOW}/root/docker/substore/api_path.txt${NC}"
echo
echo -e "${BLUE}📋 管理命令：${NC}"
echo -e "   ${YELLOW}vps-manage${NC}    # 打开图形化管理菜单"
echo
echo -e "${BLUE}📂 项目目录：${NC}"
echo -e "   Sub-Store: ${YELLOW}/root/docker/substore${NC}"
echo -e "   Wallos:    ${YELLOW}/root/docker/wallos${NC}"
echo
echo -e "${BLUE}🔧 Nginx 配置：${NC}"
if [ "$USE_HTTPS" = true ]; then
  echo -e "   ${YELLOW}/etc/nginx/sites-available/substore${NC}"
  echo -e "   ${YELLOW}/etc/nginx/sites-available/wallos${NC}"
  echo -e "   SSL 证书自动续期已启用"
else
  echo -e "   未配置 HTTPS，服务直接通过端口访问"
fi
echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  🎉 安装完成！输入 ${YELLOW}vps-manage${GREEN} 开始管理${NC}"
echo -e "${GREEN}========================================${NC}"
