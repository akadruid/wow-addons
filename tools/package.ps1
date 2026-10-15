<#
.SYNOPSIS
    把插件目录打成发布用 zip，输出到仓库根目录下的 dist\。
.DESCRIPTION
    包内根目录就是插件目录本身（Cheeser\...），文件名 插件名-版本.zip，
    版本号取自各插件 .toc 里的 ## Version。发布约定见 docs/git-workflow.md。
.EXAMPLE
    .\tools\package.ps1
    .\tools\package.ps1 -Plugin RollWorthy
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'Cheeser', 'RollWorthy')]
    [string[]]$Plugin = @('all'),
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'dist' }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$allPlugins = @('Cheeser', 'RollWorthy')
$targets = if ($Plugin -contains 'all') { $allPlugins } else { $Plugin }

# 打包时跳过的杂项（插件管理器标记文件、编辑器备份、系统文件）
$skipNames = @('dd_author.toc', '*.bak', '*.tmp', 'Thumbs.db', 'desktop.ini', '.DS_Store')

foreach ($name in $targets) {
    $pluginDir = Join-Path $repoRoot $name
    $tocPath = Join-Path $pluginDir "$name.toc"
    if (-not (Test-Path $tocPath)) { throw "缺少 $name.toc：$tocPath" }

    $match = Select-String -Path $tocPath -Pattern '^##\s*Version:\s*(\S+)' | Select-Object -First 1
    if (-not $match) { throw "读不到 $name.toc 里的 ## Version" }
    $version = $match.Matches[0].Groups[1].Value.Trim()

    $zipPath = Join-Path $OutDir "$name-$version.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    $files = Get-ChildItem $pluginDir -File -Recurse | Where-Object {
        $rel = $_.FullName.Substring($pluginDir.Length + 1)
        if ($rel -match '^(\.git|\.vscode|\.idea)[\\/]') { return $false }
        foreach ($pattern in $skipNames) { if ($_.Name -like $pattern) { return $false } }
        return $true
    }

    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            $rel = $file.FullName.Substring($pluginDir.Length + 1).Replace('\', '/')
            $entry = $zip.CreateEntry("$name/$rel", [System.IO.Compression.CompressionLevel]::Optimal)
            $outStream = $entry.Open()
            try {
                $inStream = [System.IO.File]::OpenRead($file.FullName)
                try { $inStream.CopyTo($outStream) } finally { $inStream.Dispose() }
            } finally { $outStream.Dispose() }
        }
    } finally { $zip.Dispose() }

    $size = (Get-Item $zipPath).Length
    "{0,-11} {1,7:N1} KB  {2}" -f $name, ($size / 1KB), (Join-Path 'dist' (Split-Path $zipPath -Leaf))
}
