# Gost Proxy Manager

> 一键管理 HTTPS / HTTP / SOCKS5 代理，基于 Gost + Docker

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Required-blue.svg)](https://www.docker.com/)
[![Gost](https://img.shields.io/badge/Gost-latest-green.svg)](https://github.com/ginuerzh/gost)
[![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey.svg)](https://www.linux.org/)

---

## 📦 简介

Gost Proxy Manager 是一个基于 Gost 和 Docker 的多协议代理管理脚本，提供**交互式菜单**和**命令行**两种操作方式，支持：

- ✅ **HTTPS** 代理（TLS 加密 + 10 年自签证书）
- ✅ **HTTP** 代理（明文，适合内网）
- ✅ **SOCKS5** 代理（明文，适合全局代理）

三种代理**独立管理**，互不影响，支持单独安装、启动、停止、修改配置、卸载。

---

## 🚀 快速安装

```
bash
curl -sSL https://github.com/xingfu111/proxy-manager/blob/main/proxy-manager.sh | bash
```

安装完成后，执行以下命令进入管理面板：

```bash
proxy-manager
```

---

## 📖 使用指南

### 交互式菜单

运行 `proxy-manager` 进入主菜单：

```
===== Gost 三代理管理面板 =====
 HTTPS 代理: 运行中
 HTTP 代理: 已停止
 SOCKS5 代理: 未安装
=========================
 1) 管理 HTTPS 代理
 2) 管理 HTTP 代理
 3) 管理 SOCKS5 代理
 8) 卸载所有（彻底删除全部文件）
 0) 退出
=========================
请选择 [0-3,8]:
```

选择对应数字进入子菜单：

```
===== HTTPS 代理管理 =====
 1) 安装 / 重新安装
 2) 查看状态
 3) 启动代理
 4) 停止代理
 5) 重启代理
 6) 修改端口/密码
 7) 卸载 (删除所有)
 0) 返回主菜单
=========================
```

### 命令行操作

```bash
proxy-manager <协议> <操作> [参数]
```

#### 支持的操作

| 操作 | 说明 | 示例 |
|------|------|------|
| `install` | 安装/重装 | `proxy-manager https install 8443 admin mypass` |
| `status` | 查看状态 + 最近日志 | `proxy-manager https status` |
| `start` | 启动 | `proxy-manager http start` |
| `stop` | 停止 | `proxy-manager s5 stop` |
| `restart` | 重启 | `proxy-manager https restart` |
| `change` | 修改端口/密码（交互式） | `proxy-manager http change` |
| `uninstall` | 卸载 | `proxy-manager s5 uninstall` |

#### 支持的协议

| 协议 | 参数名 | 默认端口 | 加密 |
|------|--------|----------|------|
| HTTPS | `https` | 8443 | ✅ TLS |
| HTTP | `http` | 8080 | ❌ 明文 |
| SOCKS5 | `s5` | 1080 | ❌ 明文 |

---

## 🔧 配置说明

### 配置文件位置

每个协议独立存储：

| 协议 | 配置目录 |
|------|----------|
| HTTPS | `/etc/proxy-manager-https/` |
| HTTP | `/etc/proxy-manager-http/` |
| SOCKS5 | `/etc/proxy-manager-s5/` |

### 配置文件内容

```bash
# /etc/proxy-manager-https/config.env
PORT="8443"
USER="admin"
PASS="mypassword"
SERVER_IP="1.2.3.4"
```

### HTTPS 证书

HTTPS 代理自动生成 **10 年有效期**自签名证书：

```
/etc/proxy-manager-https/
├── cert.pem      # 证书
├── key.pem       # 私钥
└── config.env    # 配置
```

---

## 🗑️ 卸载

### 卸载单个代理

进入对应子菜单 → 选择 `7) 卸载` → 输入 `yes`

### 一键卸载所有

主菜单 → 选择 `8) 卸载所有` → 输入 `yes`

**卸载删除的内容：**
- 对应的 Docker 容器
- 对应的配置目录（含证书、私钥、密码文件）

**不会被删除：**
- Docker 镜像 `ginuerzh/gost`（如需删除：`docker rmi ginuerzh/gost`）

---

## ❓ 常见问题

### 1. HTTPS 代理浏览器提示不安全？

使用自签名证书，浏览器会拦截。点击 **「高级」→「继续前往」** 即可。

### 2. 输入密码报错 `invalid control character`？

脚本内置密码净化功能，自动过滤特殊字符。若仍有问题，执行 **卸载 → 重装**。

### 3. 服务器 IP 变了怎么办？

执行 `proxy-manager https install`，脚本自动检测 IP 变化并重新生成证书。

### 4. 如何查看代理日志？

```bash
proxy-manager <协议> status
```

会显示最近 5 行日志。

### 5. 多个代理端口冲突？

安装时修改端口为不同值，默认分别为 **8443 / 8080 / 1080**。

### 6. 密码忘了怎么办？

进入对应代理子菜单 → 选择 `6) 修改端口/密码` → 重新设置。

---

## 📋 依赖

| 依赖 | 说明 |
|------|------|
| Docker | 已安装并运行 |
| OpenSSL | 用于生成证书（安装时自动检查） |
| curl | 用于获取公网 IP |

---

## 📝 更新日志

### v4.0 (2026-06-19)
- 🎉 新增 SOCKS5 代理支持
- 🗑️ 新增一键卸载所有
- 📊 主菜单显示所有代理状态
- 🔧 优化密码净化逻辑

### v3.0 (2026-06-18)
- 🎉 新增 HTTP 代理独立管理
- 🔧 优化证书生成逻辑

### v2.0 (2026-06-17)
- 🔧 新增密码自动净化
- 🛡️ 修复控制字符导致的启动失败

### v1.0 (2026-06-16)
- 🎉 初始版本，支持 HTTPS 代理

---

## 📄 许可证

[MIT License](LICENSE)

---

## 🙏 致谢

- [Gost](https://github.com/ginuerzh/gost) - 强大的代理工具
- [Docker](https://www.docker.com/) - 容器化运行

---

**⭐ 如果对你有帮助，请给个 Star！**
