#!/bin/bash

# Nginx Proxy Manager Docker Deployment Script
# Deploys: Nginx Proxy Manager only
# Author: Auto-deployment script
# Date: $(date +%Y-%m-%d)

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

# System update and package installation
log "🔄 Updating system packages..."
apt update -y

log "📦 Installing essential packages..."
apt install -y curl wget unzip git openssl

# Docker installation
log "🐳 Installing Docker..."
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    log "✅ Docker installed successfully"
else
    log "🐳 Docker already installed, skipping..."
fi

# Start Docker service
log "🔧 Starting Docker service and enabling auto-start..."
systemctl enable docker
systemctl start docker

# Set timezone
log "⏰ Setting timezone to Asia/Shanghai..."
timedatectl set-timezone Asia/Shanghai

# Create base directory
mkdir -p /root/docker
cd /root/docker

# ------------------------------
# Deploy Nginx Proxy Manager
# ------------------------------
log "📁 Setting up Nginx Proxy Manager..."
mkdir -p /root/docker/npm
cd /root/docker/npm

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
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    environment:
      DB_SQLITE_FILE: "/data/database.sqlite"
    healthcheck:
      test: ["CMD", "/bin/check-health"]
      interval: 10s
      timeout: 3s
      retries: 3
EOF

log "🚀 Starting Nginx Proxy Manager container..."
docker compose up -d

# ------------------------------
# Final setup and information
# ------------------------------

# Get server IP
log "🔍 Detecting server IP address..."
SERVER_IP=$(curl -s --connect-timeout 10 https://ipinfo.io/ip 2>/dev/null || curl -s --connect-timeout 10 http://ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

# Wait for service to start
log "⏳ Waiting for Nginx Proxy Manager to initialize..."
sleep 15

# Check service status
log "🔍 Checking service status..."
if docker ps --format "table {{.Names}}" | grep -q "nginx-proxy-manager"; then
    log "✅ Nginx Proxy Manager is running"
else
    warning "⚠️  Nginx Proxy Manager may not be running properly"
fi

# Display completion message
echo
echo "=================================================================================="
log "🎉 Nginx Proxy Manager has been deployed successfully!"
echo "=================================================================================="
echo
echo -e "${BLUE}📋 Service Access Information:${NC}"
echo "└── 🔗 Nginx Proxy Manager: http://$SERVER_IP:81"
echo "    └── Default credentials: admin@example.com / changeme"
echo
echo -e "${YELLOW}📋 Management Commands:${NC}"
echo "├── View container status: docker ps"
echo "├── View NPM logs: docker logs nginx-proxy-manager"
echo "├── Restart NPM: docker restart nginx-proxy-manager"
echo "└── Stop NPM: docker stop nginx-proxy-manager"
echo
echo -e "${YELLOW}🔧 Configuration Tips:${NC}"
echo "├── First login will prompt you to change admin credentials"
echo "├── Configure your domain names and SSL certificates"
echo "├── Use 'Proxy Host' to forward domains to internal services"
echo "└── Enable 'Force SSL' for better security"
echo
echo -e "${YELLOW}🔒 Security Recommendations:${NC}"
echo "├── Change default admin password immediately"
if [ "$HTTP_PORT" != "80" ] || [ "$HTTPS_PORT" != "443" ]; then
    echo "├── Configure firewall rules (allow ports $ADMIN_PORT"
    [ -n "$HTTP_PORT" ] && echo -n ", $HTTP_PORT"
    [ -n "$HTTPS_PORT" ] && echo -n ", $HTTPS_PORT"
    echo ")"
else
    echo "├── Configure firewall rules (allow ports 80, 443, $ADMIN_PORT)"
fi
echo "├── Use strong SSL certificates (Let's Encrypt recommended)"
echo "├── Consider restricting access to port $ADMIN_PORT (admin panel)"
echo "└── Regular backups of /root/docker/npm/data directory"
echo
echo -e "${BLUE}📂 File Locations:${NC}"
echo "├── Docker Compose: /root/docker/npm/docker-compose.yml"
echo "├── NPM Data: /root/docker/npm/data/"
echo "└── SSL Certificates: /root/docker/npm/letsencrypt/"
echo
echo "=================================================================================="

# Create management script
log "📝 Creating management script..."
cat > /root/docker/manage-npm.sh <<'EOF'
#!/bin/bash

show_status() {
    echo "=== Nginx Proxy Manager Status ==="
    docker ps --filter "name=nginx-proxy-manager" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo
    echo "=== Container Health ==="
    docker inspect nginx-proxy-manager --format='{{.State.Health.Status}}' 2>/dev/null || echo "Health check not available"
}

show_logs() {
    echo "=== Nginx Proxy Manager Logs ==="
    docker logs -f nginx-proxy-manager
}

restart_npm() {
    echo "=== Restarting Nginx Proxy Manager ==="
    docker restart nginx-proxy-manager
    echo "✅ Nginx Proxy Manager restarted"
}

stop_npm() {
    echo "=== Stopping Nginx Proxy Manager ==="
    docker stop nginx-proxy-manager
    echo "✅ Nginx Proxy Manager stopped"
}

start_npm() {
    echo "=== Starting Nginx Proxy Manager ==="
    cd /root/docker/npm
    docker compose up -d
    echo "✅ Nginx Proxy Manager started"
}

backup_npm() {
    BACKUP_DIR="/root/backups/npm_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    echo "=== Creating backup at $BACKUP_DIR ==="
    cp -r /root/docker/npm/data "$BACKUP_DIR/"
    cp -r /root/docker/npm/letsencrypt "$BACKUP_DIR/" 2>/dev/null || true
    echo "✅ Backup completed: $BACKUP_DIR"
}

case "$1" in
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    restart)
        restart_npm
        ;;
    stop)
        stop_npm
        ;;
    start)
        start_npm
        ;;
    backup)
        backup_npm
        ;;
    *)
        echo "Usage: $0 {status|logs|restart|stop|start|backup}"
        echo
        echo "Commands:"
        echo "  status   - Show Nginx Proxy Manager status"
        echo "  logs     - Show and follow NPM logs"
        echo "  restart  - Restart NPM container"
        echo "  stop     - Stop NPM container"
        echo "  start    - Start NPM container"
        echo "  backup   - Create backup of NPM data"
        echo
        echo "Examples:"
        echo "  $0 status    - Check if NPM is running"
        echo "  $0 logs      - View real-time logs"
        echo "  $0 backup    - Create backup before updates"
        ;;
esac
EOF

chmod +x /root/docker/manage-npm.sh
log "✅ Management script created at /root/docker/manage-npm.sh"

# Save stopped services list for later restoration
if [ ${#STOPPED_SERVICES[@]} -gt 0 ]; then
    printf '%s\n' "${STOPPED_SERVICES[@]}" > /root/docker/stopped_services.txt
    log "📝 Stopped services list saved to /root/docker/stopped_services.txt"
fi

# Create update script
log "📝 Creating update script..."
cat > /root/docker/update-npm.sh <<'EOF'
#!/bin/bash

echo "=== Nginx Proxy Manager Update Script ==="
echo "This will update NPM to the latest version"
echo "A backup will be created automatically"
echo

read -p "Continue with update? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Update cancelled"
    exit 1
fi

cd /root/docker/npm

# Create backup
echo "Creating backup..."
/root/docker/manage-npm.sh backup

# Pull latest image
echo "Pulling latest NPM image..."
docker compose pull

# Recreate container
echo "Recreating container with latest image..."
docker compose up -d --force-recreate

echo "✅ Update completed!"
echo "Check status with: /root/docker/manage-npm.sh status"
EOF

chmod +x /root/docker/update-npm.sh
log "✅ Update script created at /root/docker/update-npm.sh"

log "🎯 Installation completed! Nginx Proxy Manager should be accessible in a few minutes."
