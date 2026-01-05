#!/bin/bash
set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
      - "8282:80/tcp"
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
  echo "1. 查看所有服务状态"
  echo "2. 重启 Sub-Store"
  echo "3. 重启 Wallos"
  echo "4. 重启所有服务"
  echo "5. 查看 Sub-Store 日志"
  echo "6. 查看 Wallos 日志"
  echo "7. 停止所有服务"
  echo "8. 启动所有服务"
  echo "9. 查看 Sub-Store API 路径"
  echo "0. 退出"
  echo -e "${BLUE}========================================${NC}"
}

while true; do
  show_menu
  read -p "请选择操作 [0-9]: " choice
  
  case $choice in
    1)
      echo -e "${BLUE}📊 服务状态：${NC}"
      docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
      ;;
    2)
      echo -e "${BLUE}🔄 重启 Sub-Store...${NC}"
      cd /root/docker/substore && docker compose restart
      echo -e "${GREEN}✅ Sub-Store 已重启${NC}"
      ;;
    3)
      echo -e "${BLUE}🔄 重启 Wallos...${NC}"
      cd /root/docker/wallos && docker compose restart
      echo -e "${GREEN}✅ Wallos 已重启${NC}"
      ;;
    4)
      echo -e "${BLUE}🔄 重启所有服务...${NC}"
      cd /root/docker/substore && docker compose restart
      cd /root/docker/wallos && docker compose restart
      echo -e "${GREEN}✅ 所有服务已重启${NC}"
      ;;
    5)
      echo -e "${BLUE}📋 Sub-Store 日志（Ctrl+C 退出）：${NC}"
      docker logs -f substore
      ;;
    6)
      echo -e "${BLUE}📋 Wallos 日志（Ctrl+C 退出）：${NC}"
      docker logs -f wallos
      ;;
    7)
      echo -e "${YELLOW}⚠️  停止所有服务...${NC}"
      cd /root/docker/substore && docker compose stop
      cd /root/docker/wallos && docker compose stop
      echo -e "${GREEN}✅ 所有服务已停止${NC}"
      ;;
    8)
      echo -e "${BLUE}▶️  启动所有服务...${NC}"
      cd /root/docker/substore && docker compose start
      cd /root/docker/wallos && docker compose start
      echo -e "${GREEN}✅ 所有服务已启动${NC}"
      ;;
    9)
      if [ -f /root/docker/substore/api_path.txt ]; then
        API=$(cat /root/docker/substore/api_path.txt)
        echo -e "${YELLOW}🔐 Sub-Store API 路径：/$API${NC}"
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
IP=$(curl -s https://ipinfo.io/ip || echo "<你的IP>")

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✅ 所有项目安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${BLUE}🔗 访问地址：${NC}"
echo -e "   Sub-Store: ${YELLOW}http://$IP:3001/?api=http://$IP:3001/$API_PATH${NC}"
echo -e "   Wallos:    ${YELLOW}http://$IP:8282/${NC}"
echo
echo -e "${BLUE}🔐 Sub-Store API 路径已保存到：${NC}"
echo -e "   ${YELLOW}/root/docker/substore/api_path.txt${NC}"
echo
echo -e "${BLUE}📋 常用命令：${NC}"
echo -e "   ${YELLOW}vps-manage${NC}              # 打开图形化管理菜单"
echo
echo -e "${BLUE}📂 项目目录：${NC}"
echo -e "   Sub-Store: ${YELLOW}/root/docker/substore${NC}"
echo -e "   Wallos:    ${YELLOW}/root/docker/wallos${NC}"
echo
echo -e "${BLUE}🔧 手动管理命令：${NC}"
echo -e "   ${YELLOW}# 查看所有容器状态${NC}"
echo -e "   docker ps -a"
echo
echo -e "   ${YELLOW}# 重启服务${NC}"
echo -e "   cd /root/docker/substore && docker compose restart"
echo -e "   cd /root/docker/wallos && docker compose restart"
echo
echo -e "   ${YELLOW}# 查看日志${NC}"
echo -e "   docker logs -f substore"
echo -e "   docker logs -f wallos"
echo
echo -e "   ${YELLOW}# 停止服务${NC}"
echo -e "   cd /root/docker/substore && docker compose stop"
echo -e "   cd /root/docker/wallos && docker compose stop"
echo
echo -e "   ${YELLOW}# 启动服务${NC}"
echo -e "   cd /root/docker/substore && docker compose start"
echo -e "   cd /root/docker/wallos && docker compose start"
echo
echo -e "   ${YELLOW}# 更新服务（拉取最新镜像）${NC}"
echo -e "   cd /root/docker/substore && docker compose pull && docker compose up -d"
echo -e "   cd /root/docker/wallos && docker compose pull && docker compose up -d"
echo
echo -e "   ${YELLOW}# 完全删除服务（包括数据）${NC}"
echo -e "   cd /root/docker/substore && docker compose down -v"
echo -e "   cd /root/docker/wallos && docker compose down -v"
echo
echo -e "${BLUE}🌐 安全建议：${NC}"
echo -e "   • 建议绑定域名并使用 CDN 保护服务器 IP"
echo -e "   • 考虑配置防火墙限制端口访问"
echo -e "   • 定期备份 ${YELLOW}/root/docker${NC} 目录"
echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  🎉 安装完成！输入 ${YELLOW}vps-manage${GREEN} 开始管理${NC}"
echo -e "${GREEN}========================================${NC}"
