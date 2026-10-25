#!/usr/bin/env bash
# 余音 B站插件（yuyin-bili）一键安装：装插件 + 打开 enableServerPlugins。
# 用法：curl -fsSL https://raw.githubusercontent.com/cristiano7977/yuyin-bili/main/install.sh | bash
# 酒馆不在 ~/SillyTavern 时，在末尾加上路径：... | bash -s -- /你的/SillyTavern
set -euo pipefail

REPO="https://github.com/cristiano7977/yuyin-bili.git"
NAME="yuyin-bili"
stamp() { date +%Y%m%d%H%M%S; }
fail() { echo; echo "安装失败：$1" >&2; exit 1; }

is_tavern() { [ -f "$1/server.js" ] && grep -q '"name": *"sillytavern"' "$1/package.json" 2>/dev/null; }

ST="${1:-}"
if [ -z "$ST" ]; then
    for dir in "$PWD" "$HOME/SillyTavern" "$HOME/sillytavern" "$HOME/ST" /data/data/com.termux/files/home/SillyTavern; do
        if is_tavern "$dir"; then ST="$dir"; break; fi
    done
fi
[ -n "$ST" ] || fail "没找到 SillyTavern 文件夹。请在命令末尾加上酒馆路径：| bash -s -- /你的/SillyTavern"
is_tavern "$ST" || fail "$ST 不是 SillyTavern 文件夹（里面没有 server.js）"
ST="$(cd "$ST" && pwd)"
echo "· 酒馆目录：$ST"

command -v git >/dev/null 2>&1 || {
    if command -v pkg >/dev/null 2>&1; then echo "· 没有 git，正在安装"; pkg install -y git >/dev/null; else fail "需要先安装 git"; fi
}

TARGET="$ST/plugins/$NAME"
mkdir -p "$ST/plugins"
if [ -d "$TARGET/.git" ]; then
    git -C "$TARGET" pull --ff-only -q || fail "插件更新失败，请检查网络后重试"
    echo "· 插件已更新到最新版"
else
    if [ -e "$TARGET" ]; then
        OLD="$ST/plugins/.$NAME-old-$(stamp)"
        mv "$TARGET" "$OLD"
        echo "· 旧版插件已移到 plugins/$(basename "$OLD")"
    fi
    git clone -q --depth 1 "$REPO" "$TARGET" || fail "下载插件失败，请检查能否访问 GitHub 后重试"
    echo "· 插件已安装到 plugins/$NAME"
fi

CONFIG="$ST/config.yaml"
if [ ! -f "$CONFIG" ]; then
    if [ -f "$ST/default/config.yaml" ]; then cp "$ST/default/config.yaml" "$CONFIG"; else : > "$CONFIG"; fi
    echo "· 没找到 config.yaml，已按酒馆默认配置新建"
fi
if grep -Eq '^enableServerPlugins:[[:space:]]*true([[:space:]]|#|$)' "$CONFIG"; then
    echo "· enableServerPlugins 已经是 true，不用改"
else
    BACKUP="$CONFIG.bak-$(stamp)"
    cp "$CONFIG" "$BACKUP"
    if grep -Eq '^enableServerPlugins:' "$CONFIG"; then
        sed -i -E 's/^enableServerPlugins:.*/enableServerPlugins: true/' "$CONFIG"
    else
        printf '\nenableServerPlugins: true\n' >> "$CONFIG"
    fi
    echo "· 已把 enableServerPlugins 改成 true（原配置备份为 $(basename "$BACKUP")）"
fi

PORT="$(grep -E '^port:' "$CONFIG" | head -1 | grep -Eo '[0-9]+' || true)"
echo
echo "完成。重启酒馆后生效（之后每次启动酒馆，插件会自动更新）。"
echo "检查：浏览器打开 http://127.0.0.1:${PORT:-8000}/api/plugins/$NAME/health ，看到 {\"ok\":true,...} 就是装好了。"
