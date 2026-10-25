# yuyin-bili · 余音 B站插件

给「余音 · 悬浮音乐播放器」v1.3.13 及以上用的 SillyTavern 服务端插件。它用你自己的网络直连 B站，搜索和播放不会再被公共中转限流。

需要自己部署的 SillyTavern，并装好酒馆助手（用来导入余音脚本）。

## 安装（Termux / Linux / macOS）

复制这一行到终端运行：

```sh
curl -fsSL https://raw.githubusercontent.com/cristiano7977/yuyin-bili/main/install.sh | bash
```

它会自动找到酒馆，装好插件，并把 `config.yaml` 里的 `enableServerPlugins` 改成 `true`。改之前会先备份原文件。

酒馆不在 `~/SillyTavern` 的话，在末尾加上路径：

```sh
curl -fsSL https://raw.githubusercontent.com/cristiano7977/yuyin-bili/main/install.sh | bash -s -- /你的/SillyTavern
```

装好后重启酒馆，再到酒馆助手里导入余音脚本就能用了。以后每次启动酒馆，插件都会自动更新。

检查是否装好：浏览器打开 `http://127.0.0.1:8000/api/plugins/yuyin-bili/health`（端口按自己的改），看到 `{"ok":true,...}` 就行。

## 手动安装（Windows 等）

1. 在 `SillyTavern/plugins/` 里运行 `git clone https://github.com/cristiano7977/yuyin-bili`，或者下载本仓库，把文件放进 `SillyTavern/plugins/yuyin-bili/`。
2. 打开 `SillyTavern/config.yaml`，把 `enableServerPlugins` 改成 `true`。
3. 重启酒馆。

## 说明

- 插件只接受 BV 号，只会访问 B站自己的域名，不需要登录 B站，也不会上传任何数据。
- 需要登录或大会员的视频放不了。
- 接口：`/api/plugins/yuyin-bili/health`、`/search?keyword=`、`/stream/<BV号>?p=`。
