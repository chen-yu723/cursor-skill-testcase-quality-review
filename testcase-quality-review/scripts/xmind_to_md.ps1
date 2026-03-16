# xmind_to_md.ps1
# 将 XMind 文件转换为 Markdown 格式（支持 JSON 新版 和 XML 旧版）
#
# 用法1 — 路径全英文时直接传参：
#   powershell -File xmind_to_md.ps1 -XMindPath "C:\a.xmind" -OutputPath "C:\a.md"
#
# 用法2 — 含中文路径时用配置文件：
#   配置文件 (UTF-8 JSON): {"xmind":"<路径>","output":"<路径>"}
#   powershell -File xmind_to_md.ps1 -Config "C:\tmp\cfg.json"

param(
    [string]$XMindPath = "",
    [string]$OutputPath = "",
    [string]$Config = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -Assembly "System.IO.Compression.FileSystem"

# 从配置文件读取参数（含中文路径时）
if ($Config -ne "") {
    $cfg = [System.IO.File]::ReadAllText($Config, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $XMindPath = $cfg.xmind
    $OutputPath = $cfg.output
}

if (-not $XMindPath -or -not $OutputPath) {
    Write-Error "缺少必要参数: XMindPath 或 OutputPath"
    exit 1
}
if (-not [System.IO.File]::Exists($XMindPath)) {
    Write-Error "XMind 文件不存在: $XMindPath"
    exit 1
}

# ----------------------------------------------------------------
# JSON 格式转换（XMind 8 / XMind 2020 / XMind 2023）
# ----------------------------------------------------------------
function Convert-JsonTopic {
    param($topic, [int]$depth)
    if ($null -eq $topic) { return "" }
    $title = ("$($topic.title)").Trim()
    if ($title -eq "") { return "" }

    $sb = New-Object System.Text.StringBuilder

    if ($depth -le 5) {
        $null = $sb.AppendLine(("#" * $depth) + " " + $title)
        $null = $sb.AppendLine("")
    } else {
        $null = $sb.AppendLine(("  " * ($depth - 6)) + "- " + $title)
    }

    # 内嵌备注 (notes.plain.content)
    try {
        if ($topic.notes -and $topic.notes.plain -and $topic.notes.plain.content) {
            $note = ("$($topic.notes.plain.content)").Trim()
            if ($note) {
                foreach ($line in ($note -split "`r?`n")) {
                    $null = $sb.AppendLine("> $line")
                }
                $null = $sb.AppendLine("")
            }
        }
    } catch {}

    # 递归子节点
    $kids = @()
    if ($topic.children -and $topic.children.attached) {
        $a = $topic.children.attached
        $kids = if ($a -is [array]) { $a } else { @($a) }
    }
    foreach ($k in $kids) {
        $null = $sb.Append((Convert-JsonTopic -topic $k -depth ($depth + 1)))
    }
    return $sb.ToString()
}

# ----------------------------------------------------------------
# XML 格式转换（XMind 旧版 / XMind ZEN 前）
# ----------------------------------------------------------------
function Get-XmlText {
    param($node)
    if ($null -eq $node) { return "" }
    if ($node -is [System.Xml.XmlElement]) { return $node.InnerText }
    return "$node"
}

function Convert-XmlTopic {
    param($node, [int]$depth)
    $title = Get-XmlText $node.title
    if ([string]::IsNullOrWhiteSpace($title)) { return "" }

    $sb = New-Object System.Text.StringBuilder

    if ($depth -le 5) {
        $null = $sb.AppendLine(("#" * $depth) + " " + $title.Trim())
        $null = $sb.AppendLine("")
    } else {
        $null = $sb.AppendLine(("  " * ($depth - 6)) + "- " + $title.Trim())
    }

    # 备注
    if ($node.notes -and $node.notes.plain) {
        $note = (Get-XmlText $node.notes.plain).Trim()
        if ($note) {
            $null = $sb.AppendLine("> $note")
            $null = $sb.AppendLine("")
        }
    }

    # 递归子节点
    if ($node.children) {
        foreach ($tg in @($node.children.topics)) {
            if (-not $tg) { continue }
            $items = $tg.topic
            if ($null -eq $items) { continue }
            if ($items -is [System.Xml.XmlElement]) { $items = @($items) }
            foreach ($child in $items) {
                $null = $sb.Append((Convert-XmlTopic -node $child -depth ($depth + 1)))
            }
        }
    }
    return $sb.ToString()
}

# ----------------------------------------------------------------
# Main
# ----------------------------------------------------------------
$tmpDir = [System.IO.Path]::Combine($env:TEMP, "xmind_$(Get-Random)")
[System.IO.Directory]::CreateDirectory($tmpDir) | Out-Null

try {
    [System.IO.Compression.ZipFile]::ExtractToDirectory($XMindPath, $tmpDir)

    $jsonFile = [System.IO.Path]::Combine($tmpDir, "content.json")
    $xmlFile  = [System.IO.Path]::Combine($tmpDir, "content.xml")
    $result   = New-Object System.Text.StringBuilder

    if ([System.IO.File]::Exists($jsonFile)) {
        Write-Host "[xmind_to_md] 格式: JSON (XMind 8/2020/2023)"
        $raw    = [System.IO.File]::ReadAllText($jsonFile, [System.Text.Encoding]::UTF8)
        $sheets = $raw | ConvertFrom-Json
        foreach ($sheet in $sheets) {
            if ($sheet.rootTopic) {
                $null = $result.Append((Convert-JsonTopic -topic $sheet.rootTopic -depth 1))
            }
        }

    } elseif ([System.IO.File]::Exists($xmlFile)) {
        Write-Host "[xmind_to_md] 格式: XML (XMind 旧版)"
        $raw = [System.IO.File]::ReadAllText($xmlFile, [System.Text.Encoding]::UTF8)
        $xml = [xml]$raw
        $root = $xml.DocumentElement  # xmap-content
        foreach ($sheet in @($root.sheet)) {
            if ($sheet -and $sheet.topic) {
                $null = $result.Append((Convert-XmlTopic -node $sheet.topic -depth 1))
            }
        }

    } else {
        Write-Error "[xmind_to_md] 未找到 content.json 或 content.xml，解压内容："
        Get-ChildItem $tmpDir | ForEach-Object { Write-Host "  $($_.Name)" }
        exit 1
    }

    # 确保输出目录存在
    $outDir = [System.IO.Path]::GetDirectoryName($OutputPath)
    if ($outDir -and -not [System.IO.Directory]::Exists($outDir)) {
        [System.IO.Directory]::CreateDirectory($outDir) | Out-Null
    }

    [System.IO.File]::WriteAllText($OutputPath, $result.ToString(), [System.Text.Encoding]::UTF8)
    Write-Host "[xmind_to_md] 完成 → $OutputPath ($($result.Length) chars)"

} finally {
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
