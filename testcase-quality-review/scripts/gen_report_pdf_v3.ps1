# gen_report_pdf_v3.ps1
# 表格方案：每行独立 <table>（block-level），break-inside:avoid 在 table 上完全有效
# flex/grid/table-row 容器均在 Chrome/Edge 打印中存在 break-inside:avoid 失效问题
# 脚本中无中文字面量（PowerShell 5.1 以 ANSI 读取 UTF-8 文件，字面量会乱码）

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$edge        = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
$tmpHtml     = [System.IO.Path]::Combine($env:TEMP, "rpt_v3.html")
$debugPort   = 19444
$userDataDir = [System.IO.Path]::Combine($env:TEMP, "EdgeCdpV3")

# ── 从配置文件读取路径（避免中文字面量乱码）──────────────────────────────────
$cfgPath = [System.IO.Path]::Combine($env:TEMP, "rpt_pdf_cfg.json")
if ([System.IO.File]::Exists($cfgPath)) {
    $cfg    = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $mdFile = $cfg.mdFile
    $dstDir = $cfg.dstDir
} else {
    Write-Error "Config not found: $cfgPath"; exit 1
}
if (![System.IO.File]::Exists($mdFile)) { Write-Error "MD not found: $mdFile"; exit 1 }
Write-Host "MD: $mdFile"
$md = [System.IO.File]::ReadAllText($mdFile, [System.Text.Encoding]::UTF8)

# 从 MD 第一个 # 标题提取报告标题（来自文件读取，编码正确）
$reportTitle = ($md -split "`n" |
    Where-Object { $_ -match '^#\s+' } |
    Select-Object -First 1) -replace '^#+\s+', ''
$today = (Get-Date).ToString("yyyy-MM-dd")

# ── MD → HTML 转换 ───────────────────────────────────────────────────────────
function fmtInline([string]$t) {
    $t = $t -replace '&', '&amp;'
    $t = $t -replace '<(?!/?b>|/?code>)', '&lt;'
    $t = $t -replace '\*\*(.+?)\*\*', '<b>$1</b>'
    $t = $t -replace '`(.+?)`', '<code>$1</code>'
    return $t
}

function Convert-MdToHtml([string]$text) {
    $lines      = $text -split "`n"
    $sb         = [System.Text.StringBuilder]::new()
    $inCode     = $false
    $inTable    = $false
    $tableFirst = $true
    $tableCols  = 1

    foreach ($raw in $lines) {
        $line = $raw.TrimEnd()

        # 代码块
        if ($line -match '^```') {
            if ($inTable) { $inTable=$false; $tableFirst=$true }
            if ($inCode)  { $null = $sb.AppendLine("</code></pre>"); $inCode=$false }
            else          { $null = $sb.AppendLine("<pre><code>"); $inCode=$true }
            continue
        }
        if ($inCode) { $null = $sb.AppendLine([System.Net.WebUtility]::HtmlEncode($line)); continue }

        # ── 表格：每行生成独立 <table>，break-inside:avoid 在 block-level table 完全有效 ──
        if ($line -match '^\|') {
            if ($line -match '^\|\s*[-:| ]+$') { continue }   # 分隔行跳过
            $cells = $line -split '\|' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() }
            $cols  = [Math]::Max($cells.Count, 1)

            if ($tableFirst) {
                $tableCols  = $cols
                $inTable    = $true
                $w  = [Math]::Round(100.0 / $tableCols, 4)
                $cg = ("<colgroup>" + (1..$tableCols | ForEach-Object { "<col style='width:$($w)%'>" }) + "</colgroup>")
                # 表头行：div 包裹，break-inside:avoid 在 display:block 的 div 上完全有效
                $null = $sb.Append("<div class='trow-wrap thead-wrap'><table class='trow-tbl'>$cg<thead><tr class='thead'>")
                foreach ($c in $cells) { $null = $sb.Append("<th class='tcell'>$(fmtInline $c)</th>") }
                $null = $sb.AppendLine("</tr></thead></table></div>")
                $tableFirst = $false
            } else {
                # 数据行：同样用 div 包裹（border-top:none 消除双边框）
                $w  = [Math]::Round(100.0 / $tableCols, 4)
                $cg = ("<colgroup>" + (1..$tableCols | ForEach-Object { "<col style='width:$($w)%'>" }) + "</colgroup>")
                $null = $sb.Append("<div class='trow-wrap'><table class='trow-tbl data-tbl'>$cg<tbody><tr>")
                foreach ($c in $cells) { $null = $sb.Append("<td class='tcell'>$(fmtInline $c)</td>") }
                $null = $sb.AppendLine("</tr></tbody></table></div>")
            }
            continue
        }
        if ($inTable) { $inTable=$false; $tableFirst=$true }

        # 标题
        if ($line -match '^(#{1,6})\s+(.+)') {
            $lvl = $Matches[1].Length
            $null = $sb.AppendLine("<h$lvl>$(fmtInline $Matches[2])</h$lvl>")
            continue
        }
        if ($line -match '^>\s*(.*)') { $null = $sb.AppendLine("<blockquote>$($Matches[1])</blockquote>"); continue }
        if ($line -match '^-{3,}$')   { $null = $sb.AppendLine("<hr>"); continue }
        if ($line -match '^(\s*)[-*]\s+(.+)') {
            $indent = [Math]::Floor($Matches[1].Length / 2)
            $null = $sb.AppendLine("<div class='li' style='padding-left:$($indent*1.5+1)em'>&#x25AA; $(fmtInline $Matches[2])</div>")
            continue
        }
        if ($line.Trim() -eq '') { $null = $sb.AppendLine("<div class='blank'></div>"); continue }
        $null = $sb.AppendLine("<p>$(fmtInline $line)</p>")
    }
    return $sb.ToString()
}

$body = Convert-MdToHtml $md

# ── 组装 HTML（无中文字面量，通过变量引入中文）──────────────────────────────
$css = [string]::Concat(@(
"@page{size:A4;margin:22mm 16mm 12mm 16mm;}",
"*{box-sizing:border-box;}",
".pdf-header{position:fixed;top:-17mm;left:0;right:0;height:15mm;background:#fff;",
"  font-family:`"Microsoft YaHei`",`"PingFang SC`",SimHei,Arial,sans-serif;",
"  font-size:9pt;color:#888;display:flex;justify-content:space-between;",
"  align-items:flex-end;padding:0 4mm 2mm;border-bottom:0.5pt solid #ccc;}",
"body{font-family:`"Microsoft YaHei`",`"PingFang SC`",SimHei,Arial,sans-serif;",
"  font-size:10.5pt;line-height:1.7;color:#222;margin:0;padding:0;}",
"h1{font-size:18pt;color:#1a237e;border-bottom:2pt solid #1a237e;padding-bottom:4pt;margin-top:12pt;break-after:avoid;}",
"h2{font-size:14pt;color:#283593;border-left:4pt solid #3949ab;padding-left:8pt;margin-top:18pt;break-after:avoid;}",
"h3{font-size:12pt;color:#3949ab;margin-top:12pt;break-after:avoid;}",
"h4{font-size:11pt;color:#5c6bc0;break-after:avoid;}",
"/* div 包裹每行 table：break-inside:avoid 在 display:block div 上完全有效 */",
".trow-wrap{break-inside:avoid;page-break-inside:avoid;}",
".thead-wrap{margin-top:10pt;}",
".trow-tbl{width:100%;table-layout:fixed;border-collapse:collapse;margin:0;font-size:9.5pt;}",
".tcell{border:0.5pt solid #bbb;padding:4pt 6pt;overflow-wrap:break-word;word-break:break-word;vertical-align:top;}",
".data-tbl .tcell{border-top:none;}",
".thead th.tcell{background:#e8eaf6;font-weight:bold;}",
"p{margin:3pt 0;break-inside:avoid;}",
".li{margin:2pt 0;line-height:1.6;}",
".blank{height:4pt;}",
"blockquote{border-left:3pt solid #7986cb;margin:8pt 0;padding:6pt 10pt;background:#f3f4ff;color:#555;font-size:9pt;break-inside:avoid;}",
"code{background:#f0f0f0;padding:1pt 4pt;border-radius:3pt;font-family:Consolas,monospace;font-size:9pt;}",
"pre{background:#f5f5f5;padding:10pt;border-radius:4pt;font-size:9pt;break-inside:avoid;}",
"hr{border:none;border-top:1pt solid #ddd;margin:12pt 0;}",
"b{color:#c62828;}"
))

$htmlContent = [string]::Concat(@(
"<!DOCTYPE html><html lang=`"zh-CN`"><head><meta charset=`"UTF-8`"><style>",
$css,
"</style></head><body>",
"<div class=`"pdf-header`"><span>", $reportTitle, "</span><span>V6.16.0 - $today</span></div>",
$body,
"</body></html>"
))

[System.IO.File]::WriteAllText($tmpHtml, $htmlContent, [System.Text.Encoding]::UTF8)
Write-Host "HTML written: $tmpHtml"

# ── CDP WebSocket 工具 ────────────────────────────────────────────────────────
function Read-WsMsg($ws) {
    $mem = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 1048576
    do {
        $task = $ws.ReceiveAsync([ArraySegment[byte]]$buf, [System.Threading.CancellationToken]::None)
        $task.Wait()
        if ($task.IsFaulted -or $task.IsCanceled) { return $null }
        $r = $task.Result
        if ($r.Count -gt 0) { $mem.Write($buf, 0, $r.Count) }
    } while (!$r.EndOfMessage)
    return [System.Text.Encoding]::UTF8.GetString($mem.ToArray())
}
function Send-Cdp($ws, $id, $method, $params) {
    $cmd = @{id=$id; method=$method; params=$params} | ConvertTo-Json -Depth 10 -Compress
    $b   = [System.Text.Encoding]::UTF8.GetBytes($cmd)
    $ws.SendAsync([ArraySegment[byte]]$b,
        [System.Net.WebSockets.WebSocketMessageType]::Text, $true,
        [System.Threading.CancellationToken]::None).Wait()
}
function Recv-Until($ws, $id, $field=$null) {
    for ($i = 0; $i -lt 50; $i++) {
        $raw = Read-WsMsg $ws
        if (!$raw) { return $null }
        if (($raw.Contains("`"id`":$id") -or $raw.Contains("`"id`": $id")) -and
            (!$field -or $raw.Contains("`"$field`""))) { return $raw }
    }
    return $null
}

# ── 启动 Edge + CDP 打印 ─────────────────────────────────────────────────────
$edgeProc = $null
try {
    if ([System.IO.Directory]::Exists($userDataDir)) {
        Remove-Item $userDataDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $edgeArgs = "--headless --disable-gpu --no-sandbox " +
                "--remote-debugging-port=$debugPort " +
                "--user-data-dir=`"$userDataDir`""
    $edgeProc = Start-Process $edge -ArgumentList $edgeArgs -PassThru
    Write-Host "Edge PID: $($edgeProc.Id)"
    Start-Sleep -Milliseconds 3000

    $target = $null
    for ($i = 0; $i -lt 10; $i++) {
        try {
            $list   = Invoke-RestMethod "http://localhost:$debugPort/json/list" -ErrorAction Stop
            $target = @($list) | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
            if ($target) { break }
        } catch { }
        Start-Sleep -Milliseconds 1000
    }
    if (!$target) { throw "Cannot get CDP page target" }

    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl, [System.Threading.CancellationToken]::None).Wait()
    Write-Host "WebSocket connected"

    $fileUrl = "file:///" + $tmpHtml.Replace('\', '/')
    Send-Cdp $ws 1 "Page.navigate" @{ url=$fileUrl }
    Recv-Until $ws 1 | Out-Null
    Start-Sleep -Milliseconds 2500
    Write-Host "Page loaded"

    $mmIn = 1.0 / 25.4
    Send-Cdp $ws 2 "Page.printToPDF" @{
        displayHeaderFooter = $false
        printBackground     = $true
        paperWidth   = [double]([math]::Round(210 * $mmIn, 4))
        paperHeight  = [double]([math]::Round(297 * $mmIn, 4))
        marginTop    = [double]([math]::Round(22  * $mmIn, 4))
        marginBottom = [double]([math]::Round(12  * $mmIn, 4))
        marginLeft   = [double]([math]::Round(16  * $mmIn, 4))
        marginRight  = [double]([math]::Round(16  * $mmIn, 4))
    }
    Write-Host "Waiting for PDF..."
    $pdfRaw = Recv-Until $ws 2 "data"

    if ($pdfRaw) {
        $dataIdx  = $pdfRaw.IndexOf('"data":"') + 8
        $dataEnd  = $pdfRaw.IndexOf('"', $dataIdx)
        $pdfBytes = [System.Convert]::FromBase64String($pdfRaw.Substring($dataIdx, $dataEnd - $dataIdx))
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($mdFile)
        $finalPdf = [System.IO.Path]::Combine($dstDir, $baseName + ".pdf")
        [System.IO.File]::WriteAllBytes($finalPdf, $pdfBytes)
        Write-Host "PDF saved: $finalPdf  ($([Math]::Round($pdfBytes.Length/1024)) KB)"
    } else {
        Write-Error "No printToPDF response"
    }

    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "",
        [System.Threading.CancellationToken]::None).Wait()
} finally {
    if ($edgeProc -and !$edgeProc.HasExited) {
        Stop-Process -Id $edgeProc.Id -Force -ErrorAction SilentlyContinue
        Write-Host "Edge terminated"
    }
    Remove-Item $tmpHtml -ErrorAction SilentlyContinue
    if ([System.IO.Directory]::Exists($userDataDir)) {
        Remove-Item $userDataDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Done."
}
