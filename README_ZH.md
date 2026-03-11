# docker-antigravity

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)

在 Docker 容器里运行 [Antigravity](https://antigravity.app)，通过浏览器访问 Selkies 图形界面，无需本地安装。

**注意：** 本项目未在任何镜像仓库发布预构建镜像。使用前请先在本地进行构建。

[English README](README.md)

---

## 演示

<video src="https://github.com/user-attachments/assets/9c1bb5f6-06c5-40e1-815a-8d0cd5113077" controls width="100%"></video>

---

## 本地构建

> **注意：** `linuxserver/chrome:latest` 仅发布了 `linux/amd64` 镜像。Dockerfile 已通过 `--platform=linux/amd64` 固定平台，在 ARM 宿主机（如 Apple Silicon）上会通过 QEMU 仿真构建。建议开启 [BuildKit](https://docs.docker.com/build/buildkit/) 以获得更快、更稳定的构建体验。

```bash
git clone https://github.com/runzhliu/docker-antigravity.git
cd docker-antigravity
DOCKER_BUILDKIT=1 docker build -t docker-antigravity:latest .
```

---

## 快速开始

```bash
docker run -d \
  --name=antigravity \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Shanghai \
  -e CUSTOM_USER=your-username \
  -e PASSWORD=your-password \
  -p 3000:3000 \
  -p 3001:3001 \
  -v ./config:/config \
  --shm-size="1gb" \
  --restart unless-stopped \
  docker-antigravity:latest
```

在浏览器打开 **https://localhost:3001** 即可。

> **自签证书提示：** 3001 端口使用 HTTPS，但证书由 Linuxserver.io 自签，浏览器首次访问时会显示安全警告。点击**高级 → 继续前往**即可正常使用。本地或局域网场景下这是正常现象。如需受信任的证书（无警告），请参考下方 [Let's Encrypt 自动 HTTPS](#lets-encrypt-自动-https可选)。

### Docker Compose

```yaml
services:
  antigravity:
    image: docker-antigravity:latest
    container_name: antigravity
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - CUSTOM_USER=your-username   # 公网部署必填
      - PASSWORD=your-password      # 公网部署必填
    volumes:
      - ./config:/config
    ports:
      - 3000:3000   # Selkies 网页界面（HTTP）
      - 3001:3001   # Selkies 网页界面（HTTPS，自签证书）
    shm_size: "1gb"
    restart: unless-stopped
```

---

## Let's Encrypt 自动 HTTPS（可选）

公网部署且有真实域名时，镜像可自动申请并续期 Let's Encrypt 受信任证书。证书会写入容器内 nginx 的 SSL 配置路径，3001 端口即可提供受信任的 HTTPS，浏览器无安全警告。

**前提条件：**
- 公网域名已解析到宿主机 IP
- 宿主机 80 端口对公网可达（用于 ACME HTTP-01 验证）
- 宿主机 443 端口未被其他服务占用（如已有反代，需先停止）

**使用方式：**

```bash
docker run -d \
  --name=antigravity \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Shanghai \
  -e CUSTOM_USER=your-username \
  -e PASSWORD=your-password \
  -e DOMAIN=antigravity.example.com \
  -e LETSENCRYPT_EMAIL=you@example.com \
  -p 80:80 \
  -p 443:3001 \
  -v ./config:/config \
  --shm-size="1gb" \
  --sysctl net.ipv6.conf.all.disable_ipv6=1 \
  --restart unless-stopped \
  docker-antigravity:latest
```

在浏览器打开 **https://antigravity.example.com** 即可，无安全警告。

**工作流程：**
1. 首次启动时，certbot 通过 HTTP-01 验证（standalone 模式，80 端口）申请证书。
2. 证书写入 `/config/ssl/cert.pem` 和 `/config/ssl/cert.key`——这是容器内 nginx 读取 TLS 证书的实际路径。
3. nginx 在容器 3001 端口（映射到宿主机 443）提供 Let's Encrypt 证书的 HTTPS 服务。
4. 每周一凌晨 3 点，cron 任务自动续期证书并执行 `nginx -s reload`，**无需重启容器，服务不中断**。
5. 证书持久化存储于 `/config/ssl/`，容器重启后自动复用。

> **注意：** `--sysctl net.ipv6.conf.all.disable_ipv6=1` 是必要参数。若不加，certbot 只绑定 IPv6 的 80 端口，而 Let's Encrypt CA 通过 IPv4 验证，导致连接被拒绝，证书申请失败。

若未设置 `DOMAIN` 或 `LETSENCRYPT_EMAIL`，容器回退使用内置自签证书（3001 端口），参见快速开始中的提示。

---

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PUID` | `1000` | 文件权限用户 ID |
| `PGID` | `1000` | 文件权限组 ID |
| `TZ` | `UTC` | 时区（如 `Asia/Shanghai`） |
| `CUSTOM_USER` | — | 网页界面 HTTP Basic Auth 用户名 |
| `PASSWORD` | — | 网页界面 HTTP Basic Auth 密码 |
| `DOMAIN` | — | Let's Encrypt 证书对应的公网域名 |
| `LETSENCRYPT_EMAIL` | — | Let's Encrypt 注册邮箱 |

完整继承变量列表：[linuxserver/chrome 文档](https://docs.linuxserver.io/images/docker-chrome)

---

## 数据卷

| 路径 | 说明 |
|------|------|
| `/config` | Antigravity 配置、偏好设置及用户数据 |

---

## 工作原理

1. 基于 [`linuxserver/chrome`](https://docs.linuxserver.io/images/docker-chrome)，该镜像通过 [Selkies-GStreamer](https://github.com/selkies-project/selkies-gstreamer)（WebRTC）提供轻量 Openbox 桌面流。容器内 nginx 作为反代在 3001 端口处理 HTTPS。
2. 从 Google Artifact Registry 官方 Debian 仓库安装 Antigravity。
3. 用 wrapper 脚本替换 `google-chrome-stable`，确保始终携带 `--no-sandbox`（容器内必需）。
4. 创建 `wrapped-antigravity` 启动器，负责清理残留锁文件并传入必要启动参数。
5. 将默认 autostart 替换为 `wrapped-antigravity`，容器启动时自动拉起应用。
6. `custom-cont-init.d` 脚本处理首次运行配置：写入 `argv.json`、添加 Openbox 菜单项、迁移旧的 autostart。
7. 若设置了 `DOMAIN` 和 `LETSENCRYPT_EMAIL`，另一个启动脚本通过 certbot 申请 Let's Encrypt 证书，写入 `/config/ssl/cert.pem` 和 `cert.key`（nginx TLS 实际读取路径）。宿主机 `-p 443:3001` 即可对外提供标准 HTTPS。每周 cron 任务自动续期并 reload nginx，服务不中断。

---

## 贡献

欢迎提交 PR 和 Issue。大型改动请先开 Issue 讨论。

---

## 免责声明

本镜像/脚本仅供个人学术研究使用。用户需自行遵守 Google 的相关服务条款。

---

## 许可证

MIT
