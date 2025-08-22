#!/bin/bash
set -e

echo "🔄 更新 Sub-Store..."
cd /root/docker/substore

echo "⏹️ 停止 Sub-Store 容器..."
docker compose down

echo "⬇️ 下载最新版本..."
curl -fsSL https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
curl -fsSL https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
unzip -o dist.zip && mv dist frontend && rm dist.zip

echo "🚀 重新启动容器..."
docker compose up -d

echo "✅ Sub-Store 更新完成！"
