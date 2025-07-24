# 🐳 Sub-Panel-Stack：一键部署 Sub-Store + Wallos + Nginx Proxy Manager

> 用 Docker 快速部署三款主流面板工具：**Sub-Store**、**Wallos**、**Nginx Proxy Manager**。
> 全自动安装，一键启动，适合科学上网订阅管理和反向代理可视化配置。

---

## ✨ 功能一览

| 服务名称                   | 说明                                                 |
| ---------------------- | -------------------------------------------------- |
| 🌐 Nginx Proxy Manager | 可视化反向代理 + HTTPS + 自动申请证书（端口：81）                    |
| 📦 Wallos              | 多订阅聚合管理工具（端口：8282）                                 |
| 🛁 Sub-Store           | 多协议订阅面板，支持 Clash / Surge / V2Ray 等（端口：3001，API 隐藏） |

---

## 🚀 一键安装

适用于全新 Ubuntu VPS，建议使用 `root` 用户运行。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/你的用户名/你的仓库名/main/install-all.sh)
```

🚧 安装过程会自动完成：

* 安装 Docker 和 Docker Compose
* 创建目录结构
* 启动所有服务
* 自动生成 Sub-Store 的 API 证钥并输出

---

## 🌐 服务访问

| 服务        | 访问地址格式                                                                                                     |
| --------- | ---------------------------------------------------------------------------------------------------------- |
| NPM 面板    | [http://你的服务器IP:81](http://你的服务器IP:81)                                                                     |
| 默认账号      | `admin@example.com`                                                                                        |
| 默认密码      | `changeme`                                                                                                 |
| Wallos 面板 | [http://你的服务器IP:8282/](http://你的服务器IP:8282/)                                                               |
| Sub-Store | [http://你的服务器IP:3001/?api=http://你的服务器IP:3001/你的随机密钥](http://你的服务器IP:3001/?api=http://你的服务器IP:3001/你的随机密钥) |

> ✅ 安装完成后会输出一条完整的 Sub-Store 访问链接，**请务必保存！**

---

## 📁 安装目录结构

默认部署在 `/root/docker/` 目录下：

```
/root/docker/
├── npm/         → Nginx Proxy Manager
├── wallos/      → Wallos 面板
└── substore/    → Sub-Store 后端 + 前端 + 数据
```

---

## 🔐 安全建议

* 部署完成后请立即修改 NPM 默认密码
* 推荐配置域名反代并启用 HTTPS 访问
* Sub-Store 的 API 证钥为随机字符串，避免暴露，建议通过反代隐藏真实路径

---

## 📦 适用场景

* 科学上网订阅整合管理
* Clash / Surge / V2Ray 节点统一分发
* HTTPS 反代与自动证书签发
* 多线路聚合 / 自动更新配置

---

## 🛠️ 后续开发建议

* 增加 `.env` 支持，实现端口/API 密钥自定义
* 增加 Web 安装向导页面
* 增加 Telegram Bot 推送订阅链接等功能

---

## 📄 License

本项目仅供学习研究用途，请在符合当地法律法规前提下使用。
各服务的版权归原始开发者所有。
