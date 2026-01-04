#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

echo "======================================"
echo "  VPS 安全加固脚本"
echo "======================================"
echo ""

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本必须以 root 权限运行"
   exit 1
fi

# ==========================================
# 1. 安装和配置 UFW 防火墙
# ==========================================
log_info "安装 UFW 防火墙..."
apt update
apt install -y ufw

log_info "配置防火墙规则..."

# 默认策略：拒绝所有入站，允许所有出站
ufw --force default deny incoming
ufw --force default allow outgoing

# 允许 SSH（重要！否则会断开连接）
log_warn "请输入你的 SSH 端口（默认 22）:"
read -p "SSH 端口: " SSH_PORT
SSH_PORT=${SSH_PORT:-22}
ufw allow $SSH_PORT/tcp comment 'SSH'

# 可选：限制特定 IP 访问 SSH（推荐）
log_warn "是否限制 SSH 只允许特定 IP 访问？(y/n)"
read -p "选择: " LIMIT_SSH
if [[ "$LIMIT_SSH" == "y" ]]; then
    read -p "请输入允许访问的 IP 地址: " ALLOWED_IP
    ufw delete allow $SSH_PORT/tcp
    ufw allow from $ALLOWED_IP to any port $SSH_PORT proto tcp comment 'SSH from trusted IP'
    log_info "SSH 访问已限制为: $ALLOWED_IP"
fi

# 询问是否公开 Sub-Store 和 Wallos
log_warn "是否允许公网访问 Sub-Store (3001) 和 Wallos (8282)？"
echo "  建议: 使用 Cloudflare Tunnel 或 VPN，不直接暴露端口"
read -p "允许公网访问？(y/n): " ALLOW_PUBLIC

if [[ "$ALLOW_PUBLIC" == "y" ]]; then
    ufw allow 3001/tcp comment 'Sub-Store'
    ufw allow 8282/tcp comment 'Wallos'
    log_info "已开放端口 3001 和 8282"
else
    log_info "端口 3001 和 8282 仅允许本地访问"
    log_warn "请配置反向代理或 Cloudflare Tunnel 来访问服务"
fi

# 启用防火墙
log_info "启用防火墙..."
ufw --force enable

log_info "当前防火墙规则:"
ufw status numbered

# ==========================================
# 2. 安装 Fail2ban（防暴力破解）
# ==========================================
echo ""
log_info "安装 Fail2ban..."
apt install -y fail2ban

log_info "配置 Fail2ban..."
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
EOF

systemctl enable fail2ban
systemctl restart fail2ban

log_info "Fail2ban 已启动"

# ==========================================
# 3. 配置自动更新
# ==========================================
echo ""
log_info "配置自动安全更新..."
apt install -y unattended-upgrades

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

log_info "自动更新已配置"

# ==========================================
# 4. 修改 Docker 端口绑定（仅本地）
# ==========================================
if [[ "$ALLOW_PUBLIC" != "y" ]]; then
    echo ""
    log_warn "将 Docker 服务改为仅本地访问..."
    
    # Sub-Store
    if [ -f "/root/docker/substore/docker-compose.yml" ]; then
        cd /root/docker/substore
        sed -i 's/- "3001:3001"/- "127.0.0.1:3001:3001"/' docker-compose.yml
        docker compose up -d
        log_info "Sub-Store 已改为本地访问"
    fi
    
    # Wallos
    if [ -f "/root/docker/wallos/docker-compose.yml" ]; then
        cd /root/docker/wallos
        sed -i 's/- "8282:80\/tcp"/- "127.0.0.1:8282:80\/tcp"/' docker-compose.yml
        docker compose up -d
        log_info "Wallos 已改为本地访问"
    fi
fi

# ==========================================
# 5. 安装 Nginx（可选）
# ==========================================
echo ""
log_warn "是否安装 Nginx 反向代理？(y/n)"
read -p "选择: " INSTALL_NGINX

if [[ "$INSTALL_NGINX" == "y" ]]; then
    apt install -y nginx certbot python3-certbot-nginx
    
    log_warn "请输入你的域名（例如: sub.example.com）"
    read -p "Sub-Store 域名: " SUBSTORE_DOMAIN
    read -p "Wallos 域名: " WALLOS_DOMAIN
    
    # Sub-Store Nginx 配置
    if [ ! -z "$SUBSTORE_DOMAIN" ]; then
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
    }
}
EOF
        ln -sf /etc/nginx/sites-available/substore /etc/nginx/sites-enabled/
        ufw allow 80/tcp comment 'HTTP'
        ufw allow 443/tcp comment 'HTTPS'
    fi
    
    # Wallos Nginx 配置
    if [ ! -z "$WALLOS_DOMAIN" ]; then
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
    }
}
EOF
        ln -sf /etc/nginx/sites-available/wallos /etc/nginx/sites-enabled/
    fi
    
    nginx -t && systemctl reload nginx
    log_info "Nginx 配置完成"
    
    # 申请 SSL 证书
    log_warn "是否自动申请 SSL 证书？(需要域名已解析到此服务器)(y/n)"
    read -p "选择: " INSTALL_SSL
    
    if [[ "$INSTALL_SSL" == "y" ]]; then
        [ ! -z "$SUBSTORE_DOMAIN" ] && certbot --nginx -d $SUBSTORE_DOMAIN --non-interactive --agree-tos --email admin@$SUBSTORE_DOMAIN
        [ ! -z "$WALLOS_DOMAIN" ] && certbot --nginx -d $WALLOS_DOMAIN --non-interactive --agree-tos --email admin@$WALLOS_DOMAIN
        log_info "SSL 证书已配置"
    fi
fi

# ==========================================
# 完成
# ==========================================
echo ""
echo "======================================"
log_info "安全加固完成！"
echo "======================================"
echo ""
echo "已启用的防护措施:"
echo "  ✓ UFW 防火墙"
echo "  ✓ Fail2ban 防暴力破解"
echo "  ✓ 自动安全更新"
if [[ "$ALLOW_PUBLIC" != "y" ]]; then
    echo "  ✓ Docker 端口仅本地访问"
fi
if [[ "$INSTALL_NGINX" == "y" ]]; then
    echo "  ✓ Nginx 反向代理"
fi
echo ""
log_warn "重要提醒:"
echo "  1. 记住你的 SSH 端口: $SSH_PORT"
echo "  2. 定期检查日志: journalctl -f"
echo "  3. 查看被封禁 IP: fail2ban-client status sshd"
echo "  4. 建议使用密钥登录 SSH，禁用密码登录"
echo "  5. 考虑使用 Cloudflare Tunnel 完全隐藏服务器 IP"
echo ""
echo "常用命令:"
echo "  查看防火墙: ufw status"
echo "  查看 fail2ban: fail2ban-client status"
echo "  查看 nginx 日志: tail -f /var/log/nginx/access.log"
echo "======================================"
