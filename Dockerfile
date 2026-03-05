FROM linuxserver/chrome:latest

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

# ── 7. 替换 Selkies 网页界面的 favicon 为 Antigravity 图标 ────────────
# assets/favicon.ico 已在本地预先生成（64/32/16px 多尺寸 ICO），
# 直接 COPY 到四个 Selkies 静态资源目录，mkdir -p 确保路径存在。
COPY assets/favicon.ico /tmp/antigravity-favicon.ico
RUN mkdir -p /usr/share/selkies/www \
    && mkdir -p /usr/share/selkies/web \
    && mkdir -p /usr/share/selkies/selkies-dashboard-wish \
    && mkdir -p /usr/share/selkies/selkies-dashboard-zinc \
    && cp /tmp/antigravity-favicon.ico /usr/share/selkies/www/favicon.ico \
    && cp /tmp/antigravity-favicon.ico /usr/share/selkies/web/favicon.ico \
    && cp /tmp/antigravity-favicon.ico /usr/share/selkies/selkies-dashboard-wish/favicon.ico \
    && cp /tmp/antigravity-favicon.ico /usr/share/selkies/selkies-dashboard-zinc/favicon.ico \
    && rm /tmp/antigravity-favicon.ico

# ── 8. 首次启动初始化脚本 ─────────────────────────────────────────────
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
