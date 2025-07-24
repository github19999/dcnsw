# dcnsw
# 🐳 Sub-Panel-Stack：一键部署 Sub-Store + Wallos + Nginx Proxy Manager

> 用 Docker 快速部署三款主流面板工具：**Sub-Store**、**Wallos**、**Nginx Proxy Manager**。  
> 全自动安装，一键启动，适合科学上网订阅管理和反向代理可视化配置。

---

## ✨ 部署功能一览

| 服务名称               | 说明                                                                 |
|------------------------|----------------------------------------------------------------------|
| 🌐 Nginx Proxy Manager | 可视化反向代理 + HTTPS + 自动申请证书（端口：81）                     |
| 📦 Wallos              | 多订阅聚合管理工具（端口：8282）                                     |
| 📡 Sub-Store           | 多协议订阅面板，支持 Clash / Surge / V2Ray 等（端口：3001，API 隐藏） |

---

## 🚀 一键安装步骤

> 适用于全新 Ubuntu VPS，建议使用 `root` 用户运行。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/你的用户名/你的仓库名/main/install-all.sh)
系统会自动完成：

Docker 安装

三大面板部署

API 密钥自动生成（用于 Sub-Store 安全访问）

所有容器后台运行
