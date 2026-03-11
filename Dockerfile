# syntax=docker/dockerfile:1
FROM --platform=linux/amd64 linuxserver/chrome:latest

# ── 1. 安装 Antigravity ────────────────────────────────────────────────
# Google Artifact Registry 的公共签名密钥（与 packages.cloud.google.com 共用）
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | gpg --dearmor -o /etc/apt/keyrings/antigravity-repo-key.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] \
        https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ \
        antigravity-debian main" \
        > /etc/apt/sources.list.d/antigravity.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends antigravity \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── 2. 强制 Chrome 始终带 --no-sandbox 启动 ──────────────────────────
# Docker 容器里 Chrome 必须加 --no-sandbox，否则 xdg-open 触发 OAuth 时
# Chrome 静默崩溃，导致登录无反应。
# 用 wrapper 替换原始二进制，确保任何调用路径（xdg-open、.desktop、直接调用）
# 都生效，无需依赖 update-desktop-database。
RUN mv /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable.real \
    && printf '#!/bin/bash\nexec /usr/bin/google-chrome-stable.real --no-sandbox "$@"\n' \
        > /usr/bin/google-chrome-stable \
    && chmod +x /usr/bin/google-chrome-stable

# ── 3. 创建 wrapped-antigravity（仿照 wrapped-chrome 的模式）────────────
# 清理残留锁文件 + 传入容器必要参数，桌面以 abc 用户启动，不会以 root 运行。
RUN cat > /usr/bin/wrapped-antigravity << 'EOF'
#!/bin/bash

BIN=/usr/bin/antigravity

# 清理残留 Singleton 锁，防止上次异常退出后无法启动
if pgrep -x antigravity > /dev/null; then
    rm -f "$HOME/antigravity-data/SingletonLock" \
          "$HOME/antigravity-data/SingletonCookie" \
          "$HOME/antigravity-data/SingletonSocket"
fi

${BIN} \
    --no-sandbox \
    --password-store=basic \
    --user-data-dir=/config/antigravity-data \
    "$@" > /dev/null 2>&1
EOF
RUN chmod +x /usr/bin/wrapped-antigravity

# ── 4. 修改默认 autostart：使用 wrapped-antigravity ──────────────────
RUN printf '#!/bin/bash\nwrapped-antigravity\n' > /defaults/autostart

# ── 5. 为 custom-cont-init.d 准备 argv.json 模板 ──────────────────────
# password-store=basic：跳过 GNOME Keyring/KWallet，用加密文件存储凭据。
RUN mkdir -p /defaults/antigravity \
    && printf '{\n\t"enable-crash-reporter": false,\n\t"password-store": "basic"\n}\n' \
        > /defaults/antigravity/argv.json

# ── 6. 在镜像内所有 openbox menu.xml 里加入 Antigravity 入口 ──────────
RUN find / -name "menu.xml" -path "*/openbox/*" 2>/dev/null \
    | while read -r f; do \
        grep -q 'label="Chrome"' "$f" && ! grep -q "Antigravity" "$f" \
        && sed -i '/label="Chrome"/i <item label="Antigravity" icon="\/usr\/share\/pixmaps\/antigravity.png"><action name="Execute"><command>wrapped-antigravity<\/command><\/action><\/item>' "$f"; \
    done; true

# ── 7. 替换 Selkies 网页界面图标与标题 ───────────────────────────────
# icon.png 是 Selkies web UI 实际使用的图标文件（非 favicon.ico）。
# TITLE 环境变量控制浏览器 tab 上显示的标题。
COPY assets/antigravity.png /usr/share/selkies/www/icon.png
ENV TITLE="Antigravity"

# ── 8. 安装 certbot（Let's Encrypt 证书支持）─────────────────────────────
# certbot 申请证书后写入 /config/keys/，Selkies 原生 HTTPS（3001）直接使用。
# 宿主机只需 -p 443:3001 即可对外提供标准 HTTPS，无需额外反代层。
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        certbot \
        cron \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── 9. Let's Encrypt 自动申请/续期启动脚本 ───────────────────────────────
# 脚本序号 05- 确保在 Selkies 启动之前运行，写好证书后 Selkies 直接读取。
# 若未设置 DOMAIN / LETSENCRYPT_EMAIL，则完全跳过，不影响默认自签证书（3001）。
RUN mkdir -p /custom-cont-init.d \
    && cat > /custom-cont-init.d/05-letsencrypt.sh << 'EOF'
#!/bin/bash
set -euo pipefail

DOMAIN="${DOMAIN:-}"
EMAIL="${LETSENCRYPT_EMAIL:-}"
SSL_DIR="/config/ssl"     # nginx ssl_certificate / ssl_certificate_key 所在目录
CRON_FILE="/etc/cron.d/letsencrypt-renew"

# ── 跳过条件 ────────────────────────────────────────────────────────────
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo "[letsencrypt] DOMAIN 或 LETSENCRYPT_EMAIL 未设置，跳过自动证书配置"
    echo "[letsencrypt] 继续使用自签证书（端口 3001）"
    exit 0
fi

echo "[letsencrypt] 为域名 $DOMAIN 配置 Let's Encrypt 证书..."
mkdir -p "$SSL_DIR"

# ── 判断是否需要申请/续期 ────────────────────────────────────────────────
LIVE_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
NEEDS_CERT=true

if [ -f "$LIVE_CERT" ]; then
    EXPIRY=$(openssl x509 -enddate -noout -in "$LIVE_CERT" | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))
    echo "[letsencrypt] 现有证书还有 ${DAYS_LEFT} 天到期"
    [ "$DAYS_LEFT" -gt 30 ] && NEEDS_CERT=false
fi

if $NEEDS_CERT; then
    echo "[letsencrypt] 通过 certbot standalone 申请证书（需要端口 80 对外可达）..."
    if ! certbot certonly \
            --standalone \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL" \
            -d "$DOMAIN" \
            --http-01-port 80; then
        echo "[letsencrypt] 证书申请失败，降级使用自签证书（端口 3001）"
        exit 0
    fi
fi

# ── 将证书写入 nginx SSL 路径（/config 是持久化卷，重启后仍有效）────────────
# nginx 配置：ssl_certificate /config/ssl/cert.pem
#             ssl_certificate_key /config/ssl/cert.key
cp -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$SSL_DIR/cert.pem"
cp -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem"   "$SSL_DIR/cert.key"
chown abc:abc "$SSL_DIR/cert.pem" "$SSL_DIR/cert.key"
chmod 644 "$SSL_DIR/cert.pem"
chmod 600 "$SSL_DIR/cert.key"
echo "[letsencrypt] 证书已写入 $SSL_DIR（cert.pem + cert.key），nginx 启动后即生效"

# ── 配置 cron 自动续期（每周一凌晨 3 点）────────────────────────────────
cat > "$CRON_FILE" << CRON_EOF
# Let's Encrypt 自动续期（docker-antigravity 生成）
0 3 * * 1 root certbot renew --standalone --quiet \
    && cp -f /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ${SSL_DIR}/cert.pem \
    && cp -f /etc/letsencrypt/live/${DOMAIN}/privkey.pem   ${SSL_DIR}/cert.key \
    && nginx -s reload
CRON_EOF
chmod 644 "$CRON_FILE"

cron
echo "[letsencrypt] 自动续期 cron 已配置（每周一 03:00）"
EOF
RUN chmod +x /custom-cont-init.d/05-letsencrypt.sh

# ── 10. 首次启动初始化脚本 ────────────────────────────────────────────────
RUN mkdir -p /custom-cont-init.d \
    && cat > /custom-cont-init.d/10-antigravity-setup.sh << 'EOF'
#!/bin/bash
ARGV_DIR="/config/.antigravity"
ARGV_JSON="$ARGV_DIR/argv.json"

# 如果 argv.json 不含 password-store 配置，则写入
mkdir -p "$ARGV_DIR"
if ! grep -q '"password-store"' "$ARGV_JSON" 2>/dev/null; then
    cp /defaults/antigravity/argv.json "$ARGV_JSON"
fi
chown -R abc:abc "$ARGV_DIR"

# 若 autostart 仍用旧的 Chrome / 原始 antigravity 启动，则更新为 wrapped-antigravity
AUTOSTART="/config/.config/openbox/autostart"
if [ -f "$AUTOSTART" ] && grep -qE "wrapped-chrome|google-chrome|antigravity" "$AUTOSTART" \
        && ! grep -q "wrapped-antigravity" "$AUTOSTART"; then
    printf '#!/bin/bash\nwrapped-antigravity\n' > "$AUTOSTART"
fi

# 在 Openbox 菜单里加入 Antigravity 入口
MENU="/config/.config/openbox/menu.xml"
mkdir -p "$(dirname "$MENU")"
if [ ! -f "$MENU" ]; then
    cat > "$MENU" << 'MENU_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="MENU">
    <item label="Antigravity" icon="/usr/share/pixmaps/antigravity.png">
      <action name="Execute"><command>wrapped-antigravity</command></action>
    </item>
    <item label="Chrome" icon="/usr/share/icons/hicolor/48x48/apps/google-chrome.png">
      <action name="Execute"><command>/usr/bin/wrapped-chrome</command></action>
    </item>
    <item label="xterm" icon="/usr/share/pixmaps/xterm-color_48x48.xpm">
      <action name="Execute"><command>/usr/bin/xterm</command></action>
    </item>
  </menu>
</openbox_menu>
MENU_EOF
elif ! grep -q "Antigravity" "$MENU"; then
    sed -i '/label="Chrome"/i <item label="Antigravity" icon="\/usr\/share\/pixmaps\/antigravity.png"><action name="Execute"><command>wrapped-antigravity<\/command><\/action><\/item>' "$MENU"
fi
EOF
RUN chmod +x /custom-cont-init.d/10-antigravity-setup.sh
