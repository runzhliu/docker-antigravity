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

在浏览器打开 **http://localhost:3000** 即可。

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
      - 3001:3001   # Selkies 网页界面（HTTPS，推荐）
    shm_size: "1gb"
    restart: unless-stopped
```

---

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PUID` | `1000` | 文件权限用户 ID |
| `PGID` | `1000` | 文件权限组 ID |
| `TZ` | `UTC` | 时区（如 `Asia/Shanghai`） |
| `CUSTOM_USER` | — | 网页界面 HTTP Basic Auth 用户名 |
| `PASSWORD` | — | 网页界面 HTTP Basic Auth 密码 |

完整继承变量列表：[linuxserver/chrome 文档](https://docs.linuxserver.io/images/docker-chrome)

---

## 数据卷

| 路径 | 说明 |
|------|------|
| `/config` | Antigravity 配置、偏好设置及用户数据 |

---

## 工作原理

1. 基于 [`linuxserver/chrome`](https://docs.linuxserver.io/images/docker-chrome)，该镜像通过 [Selkies-GStreamer](https://github.com/selkies-project/selkies-gstreamer)（WebRTC）提供轻量 Openbox 桌面流。
2. 从 Google Artifact Registry 官方 Debian 仓库安装 Antigravity。
3. 用 wrapper 脚本替换 `google-chrome-stable`，确保始终携带 `--no-sandbox`（容器内必需）。
4. 创建 `wrapped-antigravity` 启动器，负责清理残留锁文件并传入必要启动参数。
5. 将默认 autostart 替换为 `wrapped-antigravity`，容器启动时自动拉起应用。
6. `custom-cont-init.d` 脚本处理首次运行配置：写入 `argv.json`、添加 Openbox 菜单项、迁移旧的 autostart。

---

## 贡献

欢迎提交 PR 和 Issue。大型改动请先开 Issue 讨论。

---

## 免责声明

本镜像/脚本仅供个人学术研究使用。用户需自行遵守 Google 的相关服务条款。

---

## 许可证

MIT
