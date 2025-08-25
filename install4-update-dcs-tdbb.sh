#!/bin/bash
set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}ℹ️  $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_step() {
    echo -e "${BLUE}🔄 $1${NC}"
}

log_version() {
    echo -e "${PURPLE}📦 $1${NC}"
}

# 显示帮助信息
show_help() {
    echo "Sub-Store 版本更新脚本"
    echo
    echo "用法："
    echo "  $0 [选项] [版本号]"
    echo
    echo "选项："
    echo "  -h, --help              显示此帮助信息"
    echo "  -l, --list              列出可用版本"
    echo "  -i, --interactive       交互式选择版本"
    echo "  -c, --current           显示当前版本信息"
    echo "  -f, --force             强制更新（跳过版本检查）"
    echo "  --backend-only          仅更新后端"
    echo "  --frontend-only         仅更新前端"
    echo
    echo "版本号格式："
    echo "  latest                  更新到最新版本（默认）"
    echo "  v2.14.180              更新到指定版本"
    echo "  2.14.180               更新到指定版本（自动添加v前缀）"
    echo
    echo "示例："
    echo "  $0                      # 更新到最新版本"
    echo "  $0 -i                   # 交互式选择版本"
    echo "  $0 latest               # 更新到最新版本"
    echo "  $0 v2.14.180           # 更新到 v2.14.180"
    echo "  $0 2.14.180            # 更新到 v2.14.180"
    echo "  $0 -l                   # 列出可用版本"
    echo "  $0 --backend-only v2.14.180  # 仅更新后端到指定版本"
    echo "  $0 -i --frontend-only   # 交互式选择前端版本"
}

# 获取GitHub API的版本列表
get_available_versions() {
    log_info "获取可用版本列表..."
    
    # 后端版本
    log_version "Sub-Store 后端可用版本："
    curl -s "https://api.github.com/repos/sub-store-org/Sub-Store/releases" | \
        grep '"tag_name":' | head -10 | \
        sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | \
        while read version; do
            echo "  📦 $version"
        done
    
    echo
    
    # 前端版本
    log_version "Sub-Store 前端可用版本："
    curl -s "https://api.github.com/repos/sub-store-org/Sub-Store-Front-End/releases" | \
        grep '"tag_name":' | head -10 | \
        sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | \
        while read version; do
            echo "  🎨 $version"
        done
}

# 交互式版本选择
interactive_version_select() {
    log_info "获取可用版本..."
    
    # 获取后端版本列表
    BACKEND_VERSIONS=($(curl -s "https://api.github.com/repos/sub-store-org/Sub-Store/releases" | \
        grep '"tag_name":' | head -15 | \
        sed 's/.*"tag_name": *"\([^"]*\)".*/\1/'))
    
    # 获取前端版本列表
    FRONTEND_VERSIONS=($(curl -s "https://api.github.com/repos/sub-store-org/Sub-Store-Front-End/releases" | \
        grep '"tag_name":' | head -15 | \
        sed 's/.*"tag_name": *"\([^"]*\)".*/\1/'))
    
    if [ ${#BACKEND_VERSIONS[@]} -eq 0 ] || [ ${#FRONTEND_VERSIONS[@]} -eq 0 ]; then
        log_error "无法获取版本信息，请检查网络连接"
        exit 1
    fi
    
    echo
    echo "🎯 ============================================="
    echo "🎯        Sub-Store 版本选择"
    echo "🎯 ============================================="
    echo
    
    # 显示更新范围
    if [ "$UPDATE_BACKEND" = true ] && [ "$UPDATE_FRONTEND" = true ]; then
        log_version "更新范围: 后端 + 前端（将自动匹配兼容版本）"
        VERSIONS=("${BACKEND_VERSIONS[@]}")
        REPO_TYPE="backend"
    elif [ "$UPDATE_BACKEND" = true ]; then
        log_version "更新范围: 仅后端"
        VERSIONS=("${BACKEND_VERSIONS[@]}")
        REPO_TYPE="backend"
    elif [ "$UPDATE_FRONTEND" = true ]; then
        log_version "更新范围: 仅前端"
        VERSIONS=("${FRONTEND_VERSIONS[@]}")
        REPO_TYPE="frontend"
    fi
    
    echo
    echo "📦 可用版本列表："
    echo "   0) latest (最新版本)"
    
    for i in "${!VERSIONS[@]}"; do
        local index=$((i + 1))
        local version="${VERSIONS[i]}"
        if [ $i -eq 0 ]; then
            echo "   $index) $version (当前最新)"
        else
            echo "   $index) $version"
        fi
    done
    
    echo
    echo -n "请选择要更新的版本 [0-${#VERSIONS[@]}]: "
    read -r choice
    
    # 验证输入
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt ${#VERSIONS[@]} ]; then
        log_error "无效的选择，请输入 0-${#VERSIONS[@]} 之间的数字"
        exit 1
    fi
    
    if [ "$choice" -eq 0 ]; then
        SELECTED_VERSION="latest"
        log_version "已选择: latest (最新版本)"
    else
        local index=$((choice - 1))
        SELECTED_VERSION="${VERSIONS[index]}"
        log_version "已选择: $SELECTED_VERSION"
    fi
    
    # 确认选择
    echo
    echo -n "确认更新到版本 $SELECTED_VERSION? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "更新已取消"
        exit 0
    fi
    
    return 0
}

# 获取当前版本信息
get_current_version() {
    cd "$SUBSTORE_DIR"
    
    log_version "当前版本信息："
    
    # 检查后端文件
    if [ -f "./sub-store.bundle.js" ]; then
        # 尝试从文件中提取版本信息（如果有的话）
        BACKEND_SIZE=$(ls -lh sub-store.bundle.js | awk '{print $5}')
        BACKEND_DATE=$(ls -l sub-store.bundle.js | awk '{print $6, $7, $8}')
        echo "  📦 后端文件: sub-store.bundle.js ($BACKEND_SIZE, $BACKEND_DATE)"
    else
        echo "  📦 后端文件: 不存在"
    fi
    
    # 检查前端目录
    if [ -d "./frontend" ]; then
        FRONTEND_COUNT=$(find ./frontend -type f | wc -l)
        FRONTEND_DATE=$(ls -ld frontend | awk '{print $6, $7, $8}')
        echo "  🎨 前端文件: frontend/ ($FRONTEND_COUNT 个文件, $FRONTEND_DATE)"
    else
        echo "  🎨 前端文件: 不存在"
    fi
    
    # 检查容器状态
    if docker compose ps | grep -q "substore"; then
        CONTAINER_STATUS=$(docker compose ps | grep substore | awk '{print $4}')
        echo "  🐳 容器状态: $CONTAINER_STATUS"
    else
        echo "  🐳 容器状态: 未运行"
    fi
}

# 验证版本号是否存在
verify_version() {
    local repo=$1
    local version=$2
    
    if [ "$version" = "latest" ]; then
        return 0
    fi
    
    # 确保版本号有v前缀
    if [[ ! $version =~ ^v ]]; then
        version="v$version"
    fi
    
    log_info "验证版本 $version 是否存在于 $repo..."
    
    # 检查版本是否存在
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/repos/$repo/releases/tags/$version")
    
    if [ "$HTTP_CODE" = "200" ]; then
        log_info "✅ 版本 $version 验证成功"
        return 0
    else
        log_error "版本 $version 在 $repo 中不存在"
        log_warn "请使用 '$0 -l' 查看可用版本"
        return 1
    fi
}

# 构建下载URL
build_download_url() {
    local repo=$1
    local version=$2
    local filename=$3
    
    if [ "$version" = "latest" ]; then
        echo "https://github.com/$repo/releases/latest/download/$filename"
    else
        # 确保版本号有v前缀
        if [[ ! $version =~ ^v ]]; then
            version="v$version"
        fi
        echo "https://github.com/$repo/releases/download/$version/$filename"
    fi
}

# 解析命令行参数
parse_arguments() {
    UPDATE_BACKEND=true
    UPDATE_FRONTEND=true
    TARGET_VERSION="latest"
    FORCE_UPDATE=false
    INTERACTIVE_MODE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                get_available_versions
                exit 0
                ;;
            -i|--interactive)
                INTERACTIVE_MODE=true
                shift
                ;;
            -c|--current)
                get_current_version
                exit 0
                ;;
            -f|--force)
                FORCE_UPDATE=true
                shift
                ;;
            --backend-only)
                UPDATE_BACKEND=true
                UPDATE_FRONTEND=false
                shift
                ;;
            --frontend-only)
                UPDATE_BACKEND=false
                UPDATE_FRONTEND=true
                shift
                ;;
            -*)
                log_error "未知选项: $1"
                echo "使用 '$0 --help' 查看帮助信息"
                exit 1
                ;;
            *)
                if [ "$INTERACTIVE_MODE" = false ]; then
                    TARGET_VERSION="$1"
                fi
                shift
                ;;
        esac
    done
}

# 主更新函数
perform_update() {
    local backend_url frontend_url
    
    # 构建下载URL
    if [ "$UPDATE_BACKEND" = true ]; then
        backend_url=$(build_download_url "sub-store-org/Sub-Store" "$TARGET_VERSION" "sub-store.bundle.js")
        log_info "后端下载URL: $backend_url"
    fi
    
    if [ "$UPDATE_FRONTEND" = true ]; then
        frontend_url=$(build_download_url "sub-store-org/Sub-Store-Front-End" "$TARGET_VERSION" "dist.zip")
        log_info "前端下载URL: $frontend_url"
    fi
    
    # ==========================================
    # 第四步：下载指定版本文件
    # ==========================================
    log_step "步骤 4/6: 下载指定版本文件"
    
    # 下载后端文件
    if [ "$UPDATE_BACKEND" = true ]; then
        log_info "下载后端文件 ($TARGET_VERSION)..."
        if curl -fsSL "$backend_url" -o sub-store.bundle.js.tmp; then
            mv sub-store.bundle.js.tmp sub-store.bundle.js
            log_info "✅ 后端文件下载完成"
        else
            log_error "后端文件下载失败"
            if [ -f "$TEMP_BACKUP_DIR/sub-store.bundle.js" ]; then
                cp "$TEMP_BACKUP_DIR/sub-store.bundle.js" ./
            fi
            rm -rf "$TEMP_BACKUP_DIR"
            exit 1
        fi
    else
        log_warn "跳过后端文件更新"
    fi
    
    # 下载前端文件
    if [ "$UPDATE_FRONTEND" = true ]; then
        log_info "下载前端文件 ($TARGET_VERSION)..."
        if curl -fsSL "$frontend_url" -o dist.zip; then
            if [ -d "./frontend" ]; then
                rm -rf ./frontend
            fi
            unzip -o dist.zip && mv dist frontend && rm dist.zip
            log_info "✅ 前端文件下载完成"
        else
            log_error "前端文件下载失败"
            # 恢复备份
            if [ -f "$TEMP_BACKUP_DIR/sub-store.bundle.js" ]; then
                cp "$TEMP_BACKUP_DIR/sub-store.bundle.js" ./
            fi
            if [ -d "$TEMP_BACKUP_DIR/frontend" ]; then
                rm -rf ./frontend
                cp -r "$TEMP_BACKUP_DIR/frontend" ./
            fi
            rm -rf "$TEMP_BACKUP_DIR"
            exit 1
        fi
    else
        log_warn "跳过前端文件更新"
    fi
}

# 主程序开始
main() {
    # 解析命令行参数
    parse_arguments "$@"
    
    # 检查是否在正确的目录
    SUBSTORE_DIR="/root/docker/substore"
    if [ ! -d "$SUBSTORE_DIR" ]; then
        log_error "Sub-Store 目录不存在: $SUBSTORE_DIR"
        exit 1
    fi
    
    cd "$SUBSTORE_DIR"
    
    # 创建临时备份目录
    TEMP_BACKUP_DIR="/tmp/substore_backup_$(date +%s)"
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    
    # 显示更新信息
    echo "🎯 ============================================="
    echo "🎯        Sub-Store 版本更新"
    echo "🎯 ============================================="
    echo
    log_version "目标版本: $TARGET_VERSION"
    if [ "$UPDATE_BACKEND" = true ] && [ "$UPDATE_FRONTEND" = true ]; then
        log_version "更新范围: 后端 + 前端"
    elif [ "$UPDATE_BACKEND" = true ]; then
        log_version "更新范围: 仅后端"
    elif [ "$UPDATE_FRONTEND" = true ]; then
        log_version "更新范围: 仅前端"
    fi
    echo
    
    # 版本验证（除非使用force选项）
    if [ "$FORCE_UPDATE" = false ] && [ "$TARGET_VERSION" != "latest" ]; then
        if [ "$UPDATE_BACKEND" = true ]; then
            verify_version "sub-store-org/Sub-Store" "$TARGET_VERSION" || exit 1
        fi
        if [ "$UPDATE_FRONTEND" = true ]; then
            verify_version "sub-store-org/Sub-Store-Front-End" "$TARGET_VERSION" || exit 1
        fi
    fi
    
    log_step "开始更新流程..."
    
    # ==========================================
    # 第一步：备份用户配置数据
    # ==========================================
    log_step "步骤 1/6: 备份用户配置数据"
    
    if [ -d "./data" ]; then
        log_info "创建临时备份目录: $TEMP_BACKUP_DIR"
        mkdir -p "$TEMP_BACKUP_DIR"
        
        log_info "备份配置数据..."
        cp -r ./data "$TEMP_BACKUP_DIR/"
        
        # 同时创建永久备份（用于故障恢复）
        PERMANENT_BACKUP_DIR="./backups/backup_${TIMESTAMP}_${TARGET_VERSION}"
        mkdir -p "$PERMANENT_BACKUP_DIR"
        cp -r ./data "$PERMANENT_BACKUP_DIR/"
        
        log_info "✅ 配置数据备份完成"
        log_info "   - 临时备份: $TEMP_BACKUP_DIR/data"
        log_info "   - 永久备份: $PERMANENT_BACKUP_DIR/data"
    else
        log_warn "数据目录 ./data 不存在，将在更新后创建新的数据目录"
        mkdir -p "$TEMP_BACKUP_DIR"
    fi
    
    # ==========================================
    # 第二步：停止容器
    # ==========================================
    log_step "步骤 2/6: 停止 Sub-Store 容器"
    
    if docker compose ps | grep -q "substore"; then
        docker compose down
        log_info "✅ 容器已停止"
    else
        log_warn "容器未运行，跳过停止步骤"
    fi
    
    # ==========================================
    # 第三步：备份当前程序文件
    # ==========================================
    log_step "步骤 3/6: 备份当前程序文件"
    
    if [ -f "./sub-store.bundle.js" ]; then
        cp ./sub-store.bundle.js "$TEMP_BACKUP_DIR/"
        log_info "✅ 后端文件已备份"
    fi
    
    if [ -d "./frontend" ]; then
        cp -r ./frontend "$TEMP_BACKUP_DIR/"
        log_info "✅ 前端文件已备份"
    fi
    
    # 执行更新
    perform_update
    
    # ==========================================
    # 第五步：恢复用户配置数据
    # ==========================================
    log_step "步骤 5/6: 恢复用户配置数据"
    
    if [ -d "$TEMP_BACKUP_DIR/data" ]; then
        # 确保数据目录存在
        mkdir -p ./data
        
        # 恢复用户配置数据
        log_info "恢复用户配置数据..."
        cp -r "$TEMP_BACKUP_DIR/data/"* ./data/ 2>/dev/null || true
        
        log_info "✅ 用户配置数据已恢复"
    else
        log_warn "没有找到用户配置数据，将使用默认配置启动"
        mkdir -p ./data
    fi
    
    # ==========================================
    # 第六步：启动容器并验证
    # ==========================================
    log_step "步骤 6/6: 启动容器并验证"
    
    log_info "启动 Sub-Store 容器..."
    if docker compose up -d; then
        log_info "✅ 容器启动成功"
    else
        log_error "容器启动失败，正在完整回滚..."
        
        # 完整回滚：恢复程序文件和数据
        if [ -f "$TEMP_BACKUP_DIR/sub-store.bundle.js" ]; then
            cp "$TEMP_BACKUP_DIR/sub-store.bundle.js" ./
        fi
        if [ -d "$TEMP_BACKUP_DIR/frontend" ]; then
            rm -rf ./frontend
            cp -r "$TEMP_BACKUP_DIR/frontend" ./
        fi
        if [ -d "$TEMP_BACKUP_DIR/data" ]; then
            rm -rf ./data
            cp -r "$TEMP_BACKUP_DIR/data" ./
        fi
        
        log_info "尝试使用备份文件启动容器..."
        docker compose up -d
        rm -rf "$TEMP_BACKUP_DIR"
        exit 1
    fi
    
    # 检查容器状态
    log_info "等待容器完全启动..."
    sleep 10
    
    if docker compose ps | grep -q "Up"; then
        log_info "✅ 容器运行状态正常"
        
        # 检查服务是否可访问
        log_info "检查服务可访问性..."
        sleep 5
        
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:3001" | grep -q "200\|404"; then
            log_info "✅ 服务访问正常"
        else
            log_warn "⚠️  服务可能还在启动中，请稍后检查"
        fi
        
        # 清理临时备份
        log_info "清理临时备份文件..."
        rm -rf "$TEMP_BACKUP_DIR"
        
        # 清理旧的永久备份（保留最近5个）
        if [ -d "./backups" ]; then
            log_info "清理旧备份文件..."
            ls -t ./backups | tail -n +6 | xargs -I {} rm -rf "./backups/{}" 2>/dev/null || true
            BACKUP_COUNT=$(ls ./backups 2>/dev/null | wc -l)
            log_info "当前保留 $BACKUP_COUNT 个历史备份"
        fi
        
    else
        log_error "容器状态异常"
        docker compose logs --tail=20
        rm -rf "$TEMP_BACKUP_DIR"
        exit 1
    fi
    
    # ==========================================
    # 更新完成总结
    # ==========================================
    echo
    echo "🎉 ============================================="
    echo "🎉        Sub-Store 更新成功完成！"
    echo "🎉 ============================================="
    echo
    
    # 获取访问信息
    IP=$(curl -s https://ipinfo.io/ip 2>/dev/null || echo "<你的IP>")
    API_PATH=$(grep "SUB_STORE_FRONTEND_BACKEND_PATH" docker-compose.yml | cut -d'"' -f2 | sed 's/\///')
    
    echo "📋 更新摘要："
    echo "   🎯 目标版本: $TARGET_VERSION"
    if [ "$UPDATE_BACKEND" = true ] && [ "$UPDATE_FRONTEND" = true ]; then
        echo "   ✅ 后端和前端均已更新"
    elif [ "$UPDATE_BACKEND" = true ]; then
        echo "   ✅ 后端已更新"
    elif [ "$UPDATE_FRONTEND" = true ]; then
        echo "   ✅ 前端已更新"
    fi
    echo "   ✅ 用户配置数据已自动恢复"
    echo "   ✅ 容器运行状态正常"
    echo
    echo "🔗 访问地址: http://$IP:3001/?api=http://$IP:3001/$API_PATH"
    echo "📁 历史备份: $PERMANENT_BACKUP_DIR"
    echo
    
    log_info "更新流程完成！您的所有配置和数据都已保持不变。"
    
    # 显示容器状态
    echo "📊 当前容器状态："
    docker compose ps
}

# 运行主程序
main "$@"
