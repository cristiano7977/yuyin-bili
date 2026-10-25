# 余音 B站插件（yuyin-bili）Windows 一键安装：装插件 + 打开 enableServerPlugins。
# 用法（在 PowerShell 里运行）：irm https://raw.githubusercontent.com/cristiano7977/yuyin-bili/main/install.ps1 | iex
# 找不到酒馆时会提示输入路径；也可以先运行 $env:YUYIN_ST='D:\SillyTavern' 再运行上面那行。
# 兼容 Windows 自带的 PowerShell 5.1。
& {
    $ErrorActionPreference = 'Stop'
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    $Repo = 'https://github.com/cristiano7977/yuyin-bili.git'
    $ZipUrl = 'https://github.com/cristiano7977/yuyin-bili/archive/refs/heads/main.zip'
    $Name = 'yuyin-bili'
    $Utf8 = New-Object System.Text.UTF8Encoding($false)

    function Get-Stamp { Get-Date -Format 'yyyyMMddHHmmss' }
    function Say($text) { Write-Host $text }
    function Test-Tavern($dir) {
        if (-not $dir) { return $false }
        $pkg = Join-Path $dir 'package.json'
        if (-not (Test-Path -LiteralPath (Join-Path $dir 'server.js')) -or -not (Test-Path -LiteralPath $pkg)) { return $false }
        return [bool]([IO.File]::ReadAllText($pkg) -match '"name"\s*:\s*"sillytavern"')
    }
    function Find-Tavern {
        $list = New-Object System.Collections.Generic.List[string]
        foreach ($dir in @($env:YUYIN_ST, (Get-Location).Path)) { if ($dir) { $list.Add($dir) } }
        foreach ($base in @($HOME, [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'), (Join-Path $HOME 'Downloads'), (Join-Path $HOME 'SillyTavern-Launcher'))) {
            if ($base) { $list.Add((Join-Path $base 'SillyTavern')) }
        }
        foreach ($drive in 'C', 'D', 'E', 'F', 'G') {
            $root = $drive + ':\'
            if (-not (Test-Path -LiteralPath $root)) { continue }
            $list.Add($root + 'SillyTavern')
            Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { $list.Add((Join-Path $_.FullName 'SillyTavern')) }
        }
        foreach ($dir in $list) { if (Test-Tavern $dir) { return (Resolve-Path -LiteralPath $dir).Path } }
        while ($true) {
            $typed = ''
            try { $typed = Read-Host '没自动找到 SillyTavern 文件夹。请输入它的完整路径（直接回车退出）' } catch { return $null }
            $typed = $typed.Trim().Trim('"').Trim("'")
            if (-not $typed) { return $null }
            if (Test-Tavern $typed) { return (Resolve-Path -LiteralPath $typed).Path }
            Say '这个文件夹不是 SillyTavern（里面没有 server.js），再试一次。'
        }
    }
    function Move-Old($target) {
        $old = Join-Path (Split-Path $target -Parent) (".$Name-old-" + (Get-Stamp))
        Move-Item -LiteralPath $target -Destination $old
        Say ('· 旧版插件已移到 plugins\' + (Split-Path $old -Leaf))
    }

    try {
        $st = Find-Tavern
        if (-not $st) { throw '没有找到 SillyTavern。可以先运行 $env:YUYIN_ST=''酒馆路径''，再运行安装命令。' }
        Say ('· 酒馆目录：' + $st)

        $plugins = Join-Path $st 'plugins'
        $target = Join-Path $plugins $Name
        if (-not (Test-Path -LiteralPath $plugins)) { New-Item -ItemType Directory -Path $plugins | Out-Null }
        $git = Get-Command git -ErrorAction SilentlyContinue

        if ($git -and (Test-Path -LiteralPath (Join-Path $target '.git'))) {
            & git -C $target pull --ff-only -q
            if ($LASTEXITCODE -ne 0) { throw '插件更新失败，请检查网络后重试' }
            Say '· 插件已更新到最新版'
        } elseif ($git) {
            if (Test-Path -LiteralPath $target) { Move-Old $target }
            & git clone -q --depth 1 $Repo $target
            if ($LASTEXITCODE -ne 0) { throw '下载插件失败，请检查能否访问 GitHub 后重试' }
            Say ('· 插件已安装到 plugins\' + $Name)
        } else {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('yuyin-bili-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tmp | Out-Null
            try {
                $zip = Join-Path $tmp 'plugin.zip'
                try { Invoke-WebRequest -Uri $ZipUrl -OutFile $zip -UseBasicParsing } catch { throw '下载插件失败，请检查能否访问 GitHub 后重试' }
                Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
                $source = Join-Path $tmp 'yuyin-bili-main'
                if (-not (Test-Path -LiteralPath (Join-Path $source 'index.js'))) { throw '下载的插件不完整，请重试' }
                if (Test-Path -LiteralPath $target) { Move-Old $target }
                New-Item -ItemType Directory -Path $target | Out-Null
                Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse
            } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
            Say ('· 插件已安装到 plugins\' + $Name + '（电脑上没有 git，所以不会自动更新；以后再运行一次这条命令就能更新）')
        }

        $config = Join-Path $st 'config.yaml'
        if (-not (Test-Path -LiteralPath $config)) {
            $default = Join-Path (Join-Path $st 'default') 'config.yaml'
            if (Test-Path -LiteralPath $default) { Copy-Item -LiteralPath $default -Destination $config } else { [IO.File]::WriteAllText($config, '', $Utf8) }
            Say '· 没找到 config.yaml，已按酒馆默认配置新建'
        }
        $text = [IO.File]::ReadAllText($config)
        if ($text -match '(?m)^enableServerPlugins:[ \t]*true([ \t#\r]|$)') {
            Say '· enableServerPlugins 已经是 true，不用改'
        } else {
            $backup = $config + '.bak-' + (Get-Stamp)
            Copy-Item -LiteralPath $config -Destination $backup
            if ($text -match '(?m)^enableServerPlugins:') {
                $text = [regex]::Replace($text, '(?m)^enableServerPlugins:[^\r\n]*', 'enableServerPlugins: true')
            } else {
                $nl = "`n"; if ($text.Contains("`r`n")) { $nl = "`r`n" }
                $text = $text.TrimEnd() + $nl + 'enableServerPlugins: true' + $nl
            }
            [IO.File]::WriteAllText($config, $text, $Utf8)
            Say ('· 已把 enableServerPlugins 改成 true（原配置备份为 ' + (Split-Path $backup -Leaf) + '）')
        }

        $port = '8000'
        $m = [regex]::Match([IO.File]::ReadAllText($config), '(?m)^port:\s*(\d+)')
        if ($m.Success) { $port = $m.Groups[1].Value }
        Say ''
        Say '完成。重启酒馆后生效。'
        Say ('检查：浏览器打开 http://127.0.0.1:' + $port + '/api/plugins/' + $Name + '/health ，看到 {"ok":true,...} 就是装好了。')
    } catch {
        Write-Host ''
        Write-Host ('安装失败：' + $_.Exception.Message) -ForegroundColor Red
    }
}
