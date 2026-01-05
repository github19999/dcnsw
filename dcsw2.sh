#!/bin/bash
set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 全局变量
SUBSTORE_PORT=3001
WALLOS_PORT=8282
NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443

echo -e "${BLUE}🔄 更新系统...${NC}"
apt update -y

echo -e "${BLUE}📦 安装必要组件...${NC}"
apt install -y curl wget unzip git openssl

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

# 安装 Docker Compose 插件（如果未安装）
if ! docker compose version >/dev/null 2>&1; then
  echo -e "${BLUE}📦 安装 Docker Compose 插件...${NC}"
  apt install -y docker-compose-plugin
fi

echo -e "${BLUE}⏰ 设置系统时区为上海${NC}"
timedatectl set-timezone Asia/Shanghai

# ------------------------------
# 部署 Nginx
# ------------------------------
echo -e "${BLUE}📁 创建 Nginx 目录并准备环境...${NC}"
mkdir -p /root/docker/nginx/{conf.d,certs,html}
cd /root/docker/nginx

# 获取服务器IP
SERVER_IP=$(curl -s https://ipinfo.io/ip || echo "YOUR_IP")

# 提示用户输入域名
echo -e "${YELLOW}请输入域名配置（可选）：${NC}"
read -p "Sub-Store 域名 (留空跳过): " SUBSTORE_DOMAIN
read -p "Wallos 域名 (留空跳过): " WALLOS_DOMAIN

# 保存域名配置
cat > domain_config.txt <<EOF
SUBSTORE_DOMAIN=${SUBSTORE_DOMAIN}
WALLOS_DOMAIN=${WALLOS_DOMAIN}
SERVER_IP=${SERVER_IP}
EOF

echo -e "${BLUE}📋 生成 Nginx 配置文件...${NC}"

# 默认配置
cat > conf.d/default.conf <<'EOF'
server {
    listen 80 default_server;
    server_name _;
    
    location / {
        return 404;
    }
}
EOF

# Sub-Store 配置
if [ -n "$SUBSTORE_DOMAIN" ]; then
cat > conf.d/substore.conf <<EOF
server {
    listen 80;
    server_name ${SUBSTORE_DOMAIN};
    
    location / {
        proxy_pass http://substore:3001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
else
cat > conf.d/substore.conf <<EOF
server {
    listen 80;
    server_name ${SERVER_IP};
    
    location /substore {
        rewrite ^/substore/(.*) /\$1 break;
        proxy_pass http://substore:3001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
fi

# Wallos 配置
if [ -n "$WALLOS_DOMAIN" ]; then
cat > conf.d/wallos.conf <<EOF
server {
    listen 80;
    server_name ${WALLOS_DOMAIN};
    
    location / {
        proxy_pass http://wallos:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
else
cat > conf.d/wallos.conf <<EOF
server {
    listen 80;
    server_name ${SERVER_IP};
    
    location /wallos {
        rewrite ^/wallos/(.*) /\$1 break;
        proxy_pass http://wallos:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
fi

echo -e "${BLUE}📋 写入 Nginx docker-compose.yml...${NC}"
cat > docker-compose.yml <<EOF
version: '3.8'

networks:
  app_network:
    driver: bridge

services:
  nginx:
    image: nginx:latest
    container_name: nginx
    restart: unless-stopped
    ports:
      - "${NGINX_HTTP_PORT}:80"
      - "${NGINX_HTTPS_PORT}:443"
    volumes:
      - ./conf.d:/etc/nginx/conf.d
      - ./certs:/etc/nginx/certs
      - ./html:/usr/share/nginx/html
      - /var/log/nginx:/var/log/nginx
    networks:
      - app_network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

echo -e "${BLUE}🚀 启动 Nginx 容器...${NC}"
docker compose up -d

# ------------------------------
# 部署 Sub-Store
# ------------------------------
echo -e "${BLUE}📁 创建 Sub-Store 目录并准备环境...${NC}"
mkdir -p /root/docker/substore/data
cd /root/docker/substore

API_PATH=$(openssl rand -hex 12)
echo -e "${YELLOW}🔐 Sub-Store API 路径：/$API_PATH${NC}"

# 保存 API 路径到文件以便后续查看
echo "$API_PATH" > api_path.txt

echo -e "${BLUE}⬇️ 下载 Sub-Store 后端...${NC}"
curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js

echo -e "${BLUE}⬇️ 下载 Sub-Store 前端...${NC}"
curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
unzip -o dist.zip && mv dist frontend && rm dist.zip

echo -e "${BLUE}📋 写入 Sub-Store docker-compose.yml...${NC}"
cat > docker-compose.yml <<EOF
version: '3.8'

networks:
  app_network:
    external: true
    name: nginx_app_network

services:
  substore:
    image: node:20.18.0
    container_name: substore
    restart: unless-stopped
    working_dir: /app
    command: ["node", "sub-store.bundle.js"]
    expose:
      - "3001"
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
    networks:
      - app_network
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

networks:
  app_network:
    external: true
    name: nginx_app_network

services:
  wallos:
    container_name: wallos
    image: bellamy/wallos:2.39.0
    expose:
      - "80"
    environment:
      TZ: 'Asia/Shanghai'
    volumes:
      - './db:/var/www/html/db'
      - './logos:/var/www/html/images/uploads/logos'
    restart: unless-stopped
    networks:
      - app_network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

echo -e "${BLUE}🚀 启动 Wallos 容器...${NC}"
docker compose up -d

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
  clear
  echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}              VPS 服务管理菜单${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}【查看状态】${NC}"
  echo "  1.  查看所有服务状态"
  echo
  echo -e "${YELLOW}【启动服务】${NC}"
  echo "  2.  启动 Nginx"
  echo "  3.  启动 Sub-Store"
  echo "  4.  启动 Wallos"
  echo "  5.  启动所有服务"
  echo
  echo -e "${YELLOW}【重启服务】${NC}"
  echo "  6.  重启 Nginx"
  echo "  7.  重启 Sub-Store"
  echo "  8.  重启 Wallos"
  echo "  9.  重启所有服务"
  echo
  echo -e "${YELLOW}【停止服务】${NC}"
  echo "  10. 停止 Nginx"
  echo "  11. 停止 Sub-Store"
  echo "  12. 停止 Wallos"
  echo "  13. 停止所有服务"
  echo
  echo -e "${YELLOW}【更新服务】${NC}"
  echo "  14. 更新 Nginx"
  echo "  15. 更新 Sub-Store"
  echo "  16. 更新 Wallos"
  echo
  echo -e "${YELLOW}【删除服务】${NC}"
  echo "  17. 完全删除 Nginx"
  echo "  18. 完全删除 Sub-Store（包括数据）"
  echo "  19. 完全删除 Wallos（包括数据）"
  echo "  20. 完全删除所有服务（包括数据）"
  echo
  echo -e "${YELLOW}【安装服务】${NC}"
  echo "  21. 再次安装 Nginx"
  echo "  22. 再次安装 Sub-Store"
  echo "  23. 再次安装 Wallos"
  echo
  echo -e "${YELLOW}【日志查看】${NC}"
  echo "  24. 查看 Nginx 日志"
  echo "  25. 查看 Sub-Store 日志"
  echo "  26. 查看 Wallos 日志"
  echo
  echo -e "${YELLOW}【其他功能】${NC}"
  echo "  27. 查看 Sub-Store API 路径"
  echo "  28. 查看访问地址"
  echo
  echo "  0.  退出"
  echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
}

install_nginx() {
  echo -e "${BLUE}📁 安装 Nginx...${NC}"
  mkdir -p /root/docker/nginx/{conf.d,certs,html}
  cd /root/docker/nginx
  
  if [ ! -f docker-compose.yml ]; then
    echo -e "${RED}❌ 请先运行初始安装脚本${NC}"
    return
  fi
  
  docker compose up -d
  echo -e "${GREEN}✅ Nginx 安装完成${NC}"
}

install_substore() {
  echo -e "${BLUE}📁 安装 Sub-Store...${NC}"
  mkdir -p /root/docker/substore/data
  cd /root/docker/substore
  
  if [ ! -f sub-store.bundle.js ]; then
    echo -e "${BLUE}⬇️ 下载 Sub-Store 后端...${NC}"
    curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
  fi
  
  if [ ! -d frontend ]; then
    echo -e "${BLUE}⬇️ 下载 Sub-Store 前端...${NC}"
    curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    unzip -o dist.zip && mv dist frontend && rm dist.zip
  fi
  
  if [ ! -f docker-compose.yml ]; then
    echo -e "${RED}❌ 请先运行初始安装脚本${NC}"
    return
  fi
  
  docker compose up -d
  echo -e "${GREEN}✅ Sub-Store 安装完成${NC}"
}

install_wallos() {
  echo -e "${BLUE}📁 安装 Wallos...${NC}"
  mkdir -p /root/docker/wallos/{db,logos}
  cd /root/docker/wallos
  
  if [ ! -f docker-compose.yml ]; then
    echo -e "${RED}❌ 请先运行初始安装脚本${NC}"
    return
  fi
  
  docker compose up -d
  echo -e "${GREEN}✅ Wallos 安装完成${NC}"
}

update_service() {
  local service=$1
  local dir=$2
  
  echo -e "${BLUE}🔄 更新 $service...${NC}"
  cd "$dir"
  
  read -p "是否指定镜像版本？(y/n，默认 n 使用最新版本): " use_version
  
  if [[ "$use_version" == "y" || "$use_version" == "Y" ]]; then
    read -p "请输入镜像版本 (例如: 2.39.0): " version
    if [ -n "$version" ]; then
      # 修改 docker-compose.yml 中的版本
      sed -i "s/image: \(.*\):.*/image: \1:$version/" docker-compose.yml
    fi
  fi
  
  docker compose pull
  docker compose up -d
  echo -e "${GREEN}✅ $service 更新完成${NC}"
}

while true; do
  show_menu
  read -p "请选择操作 [0-28]: " choice
  
  case $choice in
    1)
      echo -e "${BLUE}📊 服务状态：${NC}"
      docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
      ;;
    2)
      echo -e "${BLUE}▶️  启动 Nginx...${NC}"
      cd /root/docker/nginx && docker compose start
      echo -e "${GREEN}✅ Nginx 已启动${NC}"
      ;;
    3)
      echo -e "${BLUE}▶️  启动 Sub-Store...${NC}"
      cd /root/docker/substore && docker compose start
      echo -e "${GREEN}✅ Sub-Store 已启动${NC}"
      ;;
    4)
      echo -e "${BLUE}▶️  启动 Wallos...${NC}"
      cd /root/docker/wallos && docker compose start
      echo -e "${GREEN}✅ Wallos 已启动${NC}"
      ;;
    5)
      echo -e "${BLUE}▶️  启动所有服务...${NC}"
      cd /root/docker/nginx && docker compose start
      cd /root/docker/substore && docker compose start
      cd /root/docker/wallos && docker compose start
      echo -e "${GREEN}✅ 所有服务已启动${NC}"
      ;;
    6)
      echo -e "${BLUE}🔄 重启 Nginx...${NC}"
      cd /root/docker/nginx && docker compose restart
      echo -e "${GREEN}✅ Nginx 已重启${NC}"
      ;;
    7)
      echo -e "${BLUE}🔄 重启 Sub-Store...${NC}"
      cd /root/docker/substore && docker compose restart
      echo -e "${GREEN}✅ Sub-Store 已重启${NC}"
      ;;
    8)
      echo -e "${BLUE}🔄 重启 Wallos...${NC}"
      cd /root/docker/wallos && docker compose restart
      echo -e "${GREEN}✅ Wallos 已重启${NC}"
      ;;
    9)
      echo -e "${BLUE}🔄 重启所有服务...${NC}"
      cd /root/docker/nginx && docker compose restart
      cd /root/docker/substore && docker compose restart
      cd /root/docker/wallos && docker compose restart
      echo -e "${GREEN}✅ 所有服务已重启${NC}"
      ;;
    10)
      echo -e "${YELLOW}⏸️  停止 Nginx...${NC}"
      cd /root/docker/nginx && docker compose stop
      echo -e "${GREEN}✅ Nginx 已停止${NC}"
      ;;
    11)
      echo -e "${YELLOW}⏸️  停止 Sub-Store...${NC}"
      cd /root/docker/substore && docker compose stop
      echo -e "${GREEN}✅ Sub-Store 已停止${NC}"
      ;;
    12)
      echo -e "${YELLOW}⏸️  停止 Wallos...${NC}"
      cd /root/docker/wallos && docker compose stop
      echo -e "${GREEN}✅ Wallos 已停止${NC}"
      ;;
    13)
      echo -e "${YELLOW}⏸️  停止所有服务...${NC}"
      cd /root/docker/nginx && docker compose stop
      cd /root/docker/substore && docker compose stop
      cd /root/docker/wallos && docker compose stop
      echo -e "${GREEN}✅ 所有服务已停止${NC}"
      ;;
    14)
      update_service "Nginx" "/root/docker/nginx"
      ;;
    15)
      update_service "Sub-Store" "/root/docker/substore"
      ;;
    16)
      update_service "Wallos" "/root/docker/wallos"
      ;;
    17)
      read -p "确认删除 Nginx？(y/n): " confirm
      if [[ "$confirm" == "y" ]]; then
        cd /root/docker/nginx && docker compose down -v
        echo -e "${GREEN}✅ Nginx 已删除${NC}"
      fi
      ;;
    18)
      read -p "⚠️  确认删除 Sub-Store 及所有数据？(y/n): " confirm
      if [[ "$confirm" == "y" ]]; then
        cd /root/docker/substore && docker compose down -v
        rm -rf /root/docker/substore/data/*
        echo -e "${GREEN}✅ Sub-Store 已删除${NC}"
      fi
      ;;
    19)
      read -p "⚠️  确认删除 Wallos 及所有数据？(y/n): " confirm
      if [[ "$confirm" == "y" ]]; then
        cd /root/docker/wallos && docker compose down -v
        rm -rf /root/docker/wallos/{db,logos}/*
        echo -e "${GREEN}✅ Wallos 已删除${NC}"
      fi
      ;;
    20)
      read -p "⚠️  确认删除所有服务及数据？此操作不可恢复！(yes/n): " confirm
      if [[ "$confirm" == "yes" ]]; then
        cd /root/docker/nginx && docker compose down -v
        cd /root/docker/substore && docker compose down -v
        cd /root/docker/wallos && docker compose down -v
        rm -rf /root/docker/substore/data/*
        rm -rf /root/docker/wallos/{db,logos}/*
        echo -e "${GREEN}✅ 所有服务已删除${NC}"
      fi
      ;;
    21)
      install_nginx
      ;;
    22)
      install_substore
      ;;
    23)
      install_wallos
      ;;
    24)
      echo -e "${BLUE}📋 Nginx 日志（Ctrl+C 退出）：${NC}"
      docker logs -f nginx
      ;;
    25)
      echo -e "${BLUE}📋 Sub-Store 日志（Ctrl+C 退出）：${NC}"
      docker logs -f substore
      ;;
    26)
      echo -e "${BLUE}📋 Wallos 日志（Ctrl+C 退出）：${NC}"
      docker logs -f wallos
      ;;
    27)
      if [ -f /root/docker/substore/api_path.txt ]; then
        API=$(cat /root/docker/substore/api_path.txt)
        echo -e "${YELLOW}🔐 Sub-Store API 路径：/$API${NC}"
      else
        echo -e "${RED}❌ API 路径文件未找到${NC}"
      fi
      ;;
    28)
      if [ -f /root/docker/nginx/domain_config.txt ]; then
        source /root/docker/nginx/domain_config.txt
        echo -e "${BLUE}🔗 访问地址：${NC}"
        if [ -n "$SUBSTORE_DOMAIN" ]; then
          echo -e "   Sub-Store: ${YELLOW}http://$SUBSTORE_DOMAIN${NC}"
        else
          echo -e "   Sub-Store: ${YELLOW}http://$SERVER_IP/substore${NC}"
        fi
        if [ -n "$WALLOS_DOMAIN" ]; then
          echo -e "   Wallos:    ${YELLOW}http://$WALLOS_DOMAIN${NC}"
        else
          echo -e "   Wallos:    ${YELLOW}http://$SERVER_IP/wallos${NC}"
        fi
      else
        echo -e "${RED}❌ 配置文件未找到${NC}"
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
done
SCRIPT

chmod +x /usr/local/bin/vps-manage

# ------------------------------
# 完成提示
# ------------------------------
echo
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ 所有项目安装完成！${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo
echo -e "${BLUE}🔗 访问地址：${NC}"

if [ -n "$SUBSTORE_DOMAIN" ]; then
  if [ -f /root/docker/substore/api_path.txt ]; then
    API_PATH=$(cat /root/docker/substore/api_path.txt)
    echo -e "   Sub-Store: ${YELLOW}http://$SUBSTORE_DOMAIN/?api=http://$SUBSTORE_DOMAIN/$API_PATH${NC}"
  else
    echo -e "   Sub-Store: ${YELLOW}http://$SUBSTORE_DOMAIN${NC}"
  fi
else
  if [ -f /root/docker/substore/api_path.txt ]; then
    API_PATH=$(cat /root/docker/substore/api_path.txt)
    echo -e "   Sub-Store: ${YELLOW}http://$SERVER_IP/substore/?api=http://$SERVER_IP/substore/$API_PATH${NC}"
  else
    echo -e "   Sub-Store: ${YELLOW}http://$SERVER_IP/substore${NC}"
  fi
fi

if [ -n "$WALLOS_DOMAIN" ]; then
  echo -e "   Wallos:    ${YELLOW}http://$WALLOS_DOMAIN${NC}"
else
  echo -e "   Wallos:    ${YELLOW}http://$SERVER_IP/wallos${NC}"
fi

echo
echo -e "${BLUE}🔐 Sub-Store API 路径已保存到：${NC}"
echo -e "   ${YELLOW}/root/docker/substore/api_path.txt${NC}"
echo
echo -e "${BLUE}📂 项目目录：${NC}"
echo -e "   Nginx:     ${YELLOW}/root/docker/nginx${NC}"
echo -e "   Sub-Store: ${YELLOW}/root/docker/substore${NC}"
echo -e "   Wallos:    ${YELLOW}/root/docker/wallos${NC}"
echo
echo -e "${BLUE}🌐 SSL 证书配置（可选）：${NC}"
echo -e "   证书目录: ${YELLOW}/root/docker/nginx/certs${NC}"
echo -e "   配置文件: ${YELLOW}/root/docker/nginx/conf.d/*.conf${NC}"
echo
echo -e "${BLUE}🔧 快速管理：${NC}"
echo -e "   输入命令: ${YELLOW}vps-manage${NC}"
echo
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 输入 ${YELLOW}vps-manage${GREEN} 开始管理服务${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
