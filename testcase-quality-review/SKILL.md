---
name: testcase-quality-review
description: 结合需求文档（PRD/MD格式）与测试用例文档（支持 .md 和 .xmind 格式），从需求覆盖度、用例完整性、用例准确性、冗余性、业务适配性五个维度进行全面质量校验，生成结构化质量校验报告（MD + PDF 双格式）并输出到指定目录。当用户提及"用例审查"、"用例质量"、"用例校验"、"分析报告"、"质量分析"，或提供需求文档和测试用例（md/xmind）并要求给出报告时触发。支持用户直接在消息中附上文件路径，也支持 @本skill 后跟简短指令（如"结合[需求文档]和[测试用例]，分析并给出报告"）。
---

# 测试用例质量校验

## 第零步：解析入参（必须先执行）

### 从对话中提取三个必要参数

| 参数 | 从对话中识别的关键词 | 支持格式 |
|-----|------------------|---------|
| `prd_path` | 需求文档、PRD、需求文件、需求 | `.md` |
| `cases_path` | 测试用例、用例文件、用例文档 | `.md` 或 `.xmind` |
| `output_dir` | 输出到、放到、存到、报告目录 | 目录路径 |

提取完成后立即检测 `cases_path` 的扩展名：
- 扩展名为 `.xmind` → 进入**步骤 0.5：XMind 转换**，完成后再继续
- 扩展名为 `.md` → 跳过步骤 0.5，直接进入五维度分析

### 缺失参数时主动询问

若对话中**缺少任意参数**，在开始分析前使用 `AskQuestion` 工具逐项确认：

```
问题1（prd_path 缺失）：
  "请提供需求文档（PRD）的完整路径，例如：D:\project\output\prdmd\xxx.md"

问题2（cases_path 缺失）：
  "请提供测试用例文档的完整路径，例如：D:\project\output\test_cases\xxx.md"

问题3（output_dir 缺失）：
  "请提供报告输出目录（MD + PDF 都会放在这里），
   直接回车可使用测试用例文件所在目录作为默认值"
```

三个参数齐全后，根据 `cases_path` 扩展名决定是否执行步骤 0.5。

---

## 步骤 0.5：XMind → Markdown 转换（仅 .xmind 时执行）

### 执行步骤

**1. 定位转换脚本**

用 Glob 工具搜索：`**/testcase-quality-review/scripts/xmind_to_md.ps1`

**2. 处理中文路径**（参考同级三档规则）

| 脚本路径含中文 | XMind/输出路径含中文 | 处理方式 |
|-------------|-------------------|---------|
| 否 | 否 | 直接执行，参数命令行传入 |
| 否 | 是 | 写配置文件，脚本读配置 |
| 是 | 任意 | 先复制脚本到 `%TEMP%\xmind2md.ps1`，再写配置文件 |

配置文件路径：`%TEMP%\xmind2md_cfg.json`，内容：
```json
{"xmind": "<cases_path>", "output": "<转换后 md 路径>"}
```

**3. 确定转换输出路径**

```
converted_md = cases_path 所在目录 + 同文件名 + ".md"
示例：D:\项目\V6.16.0\晋建保理V6.16.0.xmind
  →  D:\项目\V6.16.0\晋建保理V6.16.0.md
```

**4. 调用脚本**

```powershell
# 直接方式（路径全英文）
powershell -ExecutionPolicy Bypass -File "<脚本路径>" `
  -XMindPath "<cases_path>" -OutputPath "<converted_md>"

# 配置文件方式（含中文路径）
powershell -ExecutionPolicy Bypass -File "<脚本路径>" `
  -Config "%TEMP%\xmind2md_cfg.json"
```

**5. 更新 cases_path**

脚本执行成功后，将 `cases_path` 更新为 `converted_md`，继续后续五维度分析。

**6. 清理**：删除 `%TEMP%\xmind2md_cfg.json` 和 `%TEMP%\xmind2md.ps1`（如有）。

---

## 五维度分析

### ① 需求覆盖度

1. 从需求文档逐章提取功能需求点，编号 `R{模块}.{序号}`，统计每个模块的需求点总数
2. 逐条在测试用例中寻找对应覆盖，输出：
   - 各模块覆盖率表（含需求点数 / 覆盖数 / 覆盖率 / 状态）
   - 未覆盖需求清单（含编号、模块、未覆盖需求点描述、影响等级 高/中/低）

### ② 用例完整性

检查每个用例是否包含：前置条件 / 操作步骤 / 预期结果，分三类问题标注：
- **A类（前置条件缺失）**：用例有明显环境/数据依赖，但未声明前置条件
- **B类（预期结果笼统）**：预期结果仅写"正确"/"逻辑正确"/"取值正确"等，无法作为验收依据
- **C类（步骤与预期混淆）**：操作步骤和预期结果层级不清，或将字段描述当成测试步骤

对每类问题输出：用例路径 / 当前内容 / 建议完善内容

### ③ 用例准确性

对比用例与需求原文，标注偏差：

| 偏差类型 | 严重程度 | 判定标准 |
|---------|---------|---------|
| 逻辑错误 | 高 | 场景描述与功能相悖（如端/角色/操作写错） |
| 范围遗漏 | 中 | 需求明确要求但用例未覆盖 |
| 文案偏差 | 低 | 标题/描述与需求原文不一致但不影响逻辑 |

输出：用例路径 / 问题描述 / 严重程度 / 修改建议

### ④ 用例冗余性

**判定规则（二级标题体系）**：

| 判定结论 | 判定条件 | 说明 |
|---------|---------|------|
| **重复用例** | 章节标题 **且** 子节点标题均完全相同 | 完全等价，可直接删除其中一条 |
| **相似用例** | 章节标题不同，但子节点标题相同 | 同一操作在不同入口/模块下重复覆盖，可合并或保留差异点 |
| **正常用例** | 章节标题或子节点标题均不同 | 不视为冗余 |

分两组输出：
- **重复用例清单**（建议删除）：重复范围 / 重复用例数 / 完全相同的标题路径 / 处理建议
- **相似用例清单**（建议合并）：相似范围 / 相似用例数 / 相同子节点标题 / 所在不同章节 / 处理建议

最后汇总：重复用例数 + 相似用例数 + 合计占总用例比例。

### ⑤ 业务适配性

**分两部分输出**：

**（1）已覆盖的核心业务场景（优点）** — 积极列举用例在哪些核心场景上表现突出：
- 支付/审批状态机完整覆盖情况
- 关键数据字段精确性验证
- 多端/多角色一致性覆盖

**（2）缺失的核心业务场景** — 按以下四类排查：

| 类别 | 关注点 |
|-----|-------|
| A 风控规则 | 权限越权、签署/操作顺序强制性、数据隔离 |
| B 资金计算 | 金额精度（DECIMAL）、零值/负值/大额边界 |
| C 接口联调 | 接口字段值精确性、超时/降级处理、第三方服务不可用 |
| D 业务流程 | 协议/版本升级后老数据兼容、并发操作、历史存量数据 |

---

## 报告结构（固定七章顺序）

```
一、多维度量化指标汇总
    — 表格：校验维度 | 指标名称 | 数值 | 基准说明（多行，每个维度可有多个指标）
    — 总体质量等级（文字说明）

二、需求覆盖度校验
    2.1 各模块覆盖情况（表格）
    2.2 未覆盖需求清单（表格，含影响等级）

三、用例完整性校验
    3.1 完整性问题清单
        A类：前置条件缺失（表格：编号/用例路径/缺失内容/修改建议）
        B类：预期结果笼统（表格：编号/用例路径/当前预期/建议完善为）
        C类：步骤与预期混淆（表格：编号/具体问题/修改建议）

四、用例准确性校验
    4.1 准确性问题清单（表格：编号/用例路径/问题描述/严重程度/修改建议）

五、用例冗余性校验
    5.1 重复用例清单（章节标题+子节点标题均相同，建议删除）
        表格：编号/重复范围/重复用例数/完全相同标题路径/处理建议
    5.2 相似用例清单（章节标题不同但子节点标题相同，建议合并）
        表格：编号/相似范围/相似用例数/相同子节点标题/所在章节/处理建议
    — 最后汇总：重复用例数 + 相似用例数 + 合计占总用例比例

六、业务适配性校验
    6.1 已覆盖的核心业务场景（优点，表格：场景类型/具体体现）
    6.2 缺失的核心业务场景（表格：编号/缺失场景/业务风险/建议补充）

七、总结与优化建议
    7.1 用例整体质量等级（文字 + 子评分表）
    7.2 优化优先级（表格：优先级/问题类型/具体项）
        — P0（阻塞级）：准确性逻辑错误，影响用例执行正确性，必须立即修复
        — P1（高优先级）：高风险需求未覆盖、关键业务场景缺失
        — P2（中优先级）：完整性补充、中等风险未覆盖
        — P3（低优先级）：冗余合并、低风险场景补充
    7.3 一句话总结（> 引用格式，突出优点 + 主要问题 + 首要修复建议）
```

报告命名：`{版本名}_用例质量校验报告.md`

### 质量等级评分

各维度权重（总分 100 分）：

| 维度 | 满分 | 说明 |
|------|------|------|
| ① 需求覆盖度 | 30 | 需求点覆盖比例及未覆盖风险 |
| ② 用例完整性 | 25 | 前置条件/步骤/预期结果完备性 |
| ③ 用例准确性 | 20 | 与需求原文的一致性 |
| ④ 冗余控制 | 15 | 重复/无效用例占比 |
| ⑤ 业务适配性 | 10 | 风控/资金/接口/流程核心场景覆盖 |

| 总分 | 等级 | | 总分 | 等级 |
|-----|------|--|-----|------|
| 90-100 | 优秀（Excellent）| | 60-74 | 一般（Fair）|
| 75-89 | 良好（Good）| | < 60 | 较差（Poor）|

---

## PDF 生成（Windows / Edge CDP）

### 核心方案：CDP Page.printToPDF（彻底去掉页眉/页脚）

> `--print-to-pdf-no-header` 参数在 Edge 新版中无法完全禁用系统页脚（日期/URL 会显示在 margin 区）。
> 必须用 **CDP（Chrome DevTools Protocol）** 的 `Page.printToPDF` + `displayHeaderFooter:false` 才能彻底去掉。

```powershell
$edge        = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
$tmpHtml     = "$env:TEMP\rpt_tmp.html"
$debugPort   = 19444
$userDataDir = "$env:TEMP\EdgeCdpTmp"

# 1. 写 HTML 文件（.NET 方法处理中文路径）
[System.IO.File]::WriteAllText($tmpHtml, $htmlContent, [System.Text.Encoding]::UTF8)

# 2. 启动 Edge headless + 开启远程调试
$edgeArgs = "--headless --disable-gpu --no-sandbox " +
            "--remote-debugging-port=$debugPort " +
            "--user-data-dir=`"$userDataDir`""
$edgeProc = Start-Process $edge -ArgumentList $edgeArgs -PassThru
Start-Sleep -Milliseconds 3000

# 3. 获取 CDP 调试目标（带重试）
$target = $null
for ($i = 0; $i -lt 10; $i++) {
    try {
        $list   = Invoke-RestMethod "http://localhost:$debugPort/json/list" -ErrorAction Stop
        $target = @($list) | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
        if ($target) { break }
    } catch { }
    Start-Sleep -Milliseconds 1000
}

# 4. 建立 WebSocket，读消息用 MemoryStream（避免 PowerShell 切片的类型问题）
function Read-WsMsg($ws) {
    $mem = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 1048576   # 1MB/帧，支持大型 PDF base64
    do {
        $task = $ws.ReceiveAsync([ArraySegment[byte]]$buf, [System.Threading.CancellationToken]::None)
        $task.Wait()
        if ($task.IsFaulted) { return $null }
        $r = $task.Result
        if ($r.Count -gt 0) { $mem.Write($buf, 0, $r.Count) }
    } while (!$r.EndOfMessage)
    return [System.Text.Encoding]::UTF8.GetString($mem.ToArray())
}
function Send-Cdp($ws, $id, $method, $params) {
    $cmd = @{id=$id; method=$method; params=$params} | ConvertTo-Json -Depth 10 -Compress
    $b = [System.Text.Encoding]::UTF8.GetBytes($cmd)
    $ws.SendAsync([ArraySegment[byte]]$b, [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true, [System.Threading.CancellationToken]::None).Wait()
}
function Recv-Until($ws, $id, $field=$null) {
    for ($i=0; $i -lt 30; $i++) {
        $raw = Read-WsMsg $ws
        if (!$raw) { return $null }
        if (($raw.Contains("`"id`":$id") -or $raw.Contains("`"id`": $id")) -and
            (!$field -or $raw.Contains("`"$field`""))) { return $raw }
    }
    return $null
}

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl, [System.Threading.CancellationToken]::None).Wait()

# 5. 导航到 HTML 文件
$fileUrl = "file:///" + $tmpHtml.Replace('\', '/')
Send-Cdp $ws 1 "Page.navigate" @{ url=$fileUrl }
Recv-Until $ws 1 | Out-Null
Start-Sleep -Milliseconds 2500

# 6. 打印为 PDF（displayHeaderFooter=false 彻底去掉系统页眉/页脚）
$mmIn = 1.0/25.4
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
$pdfRaw = Recv-Until $ws 2 "data"

# 7. 提取 base64 并保存（手动字符串提取，避免 ConvertFrom-Json 处理超大 JSON）
$dataIdx = $pdfRaw.IndexOf('"data":"') + 8
$dataEnd = $pdfRaw.IndexOf('"', $dataIdx)
$pdfBytes = [System.Convert]::FromBase64String($pdfRaw.Substring($dataIdx, $dataEnd - $dataIdx))
$finalPdf = [IO.Path]::Combine($dstDir, [IO.Path]::GetFileNameWithoutExtension($mdFile) + ".pdf")
[System.IO.File]::WriteAllBytes($finalPdf, $pdfBytes)

# 8. 清理
$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "",
    [System.Threading.CancellationToken]::None).Wait()
Stop-Process -Id $edgeProc.Id -Force -ErrorAction SilentlyContinue
Remove-Item $tmpHtml, $userDataDir -Recurse -Force -ErrorAction SilentlyContinue
```

### HTML 模板关键规则（两个已验证的坑）

#### 坑1：脚本中的中文字面量会乱码

PowerShell 5.1 在 Windows 上默认以 ANSI（GBK）读取 `.ps1` 文件，  
即使脚本文件保存为 UTF-8 without BOM，脚本中的中文字面量也会乱码。

**✅ 解法**：报告标题等中文内容从 MD 文件第一行提取（MD 文件用 `.NET ReadAllText+UTF8` 读取，编码正确）：
```powershell
# 从 MD 文件第一行 # 标题提取报告标题（绝对不要在脚本中硬编码中文字面量）
$reportTitle = ($md -split "`n" | Where-Object { $_ -match '^#\s+' } | Select-Object -First 1) `
               -replace '^#+\s+', ''
```

HTML 模板用 `[string]::Concat(@(...))` 拼接，字符串片段全为英文/变量，通过变量引入中文：
```powershell
$html = [string]::Concat(@(
    "...<div class=`"pdf-header`"><span>", $reportTitle, "</span>...",
    $body,
    "...</html>"
))
```

#### 坑2：表格行截断（break-inside:avoid 在 flex/table-row 上不可靠）

- `<tr>` 上的 `break-inside: avoid`：Chrome/Edge 打印**不可靠**  
- `display:flex` 容器上的 `break-inside: avoid`：Chrome/Edge 打印**仍不可靠**  
- **✅ 唯一可靠方案：`<div>` 包裹每行独立 `<table>`，`break-inside:avoid` 设在 `<div>` 上**

Chrome/Edge 打印对 `break-inside: avoid` 的支持情况（经过完整验证）：
- `<tr>` / `display:table-row`：**不可靠**（截断）
- `display:flex` 容器：**不可靠**（截断）
- `display:grid` 容器：**不可靠**（截断）
- `float` 块：**列会错位**（浮点误差导致换行）
- `<table>` (`display:table`)：**不可靠**（table 有特殊排版处理）
- **`<div>`（`display:block`）：完全有效** ✅

```css
/* div 包裹每行 table */
.trow-wrap  { break-inside:avoid; page-break-inside:avoid; }
.thead-wrap { margin-top:10pt; }
.trow-tbl   { width:100%; table-layout:fixed; border-collapse:collapse;
              margin:0; font-size:9.5pt; }
.tcell      { border:0.5pt solid #bbb; padding:4pt 6pt;
              overflow-wrap:break-word; vertical-align:top; }
.data-tbl .tcell { border-top:none; }   /* 消除与上行底边的双重边框 */
.thead th.tcell  { background:#e8eaf6; font-weight:bold; }
```

**生成逻辑**：每个 Markdown 表格行用 `<div class="trow-wrap">` 包裹，内含一个独立 `<table>`：
```powershell
$w  = [Math]::Round(100.0 / $tableCols, 4)
$cg = "<colgroup>" + (1..$tableCols | ForEach-Object { "<col style='width:$($w)%'>" }) + "</colgroup>"

# 表头行
"<div class='trow-wrap thead-wrap'><table class='trow-tbl'>$cg<thead><tr class='thead'><th class='tcell'>...</th></tr></thead></table></div>"
# 数据行
"<div class='trow-wrap'><table class='trow-tbl data-tbl'>$cg<tbody><tr><td class='tcell'>...</td></tr></tbody></table></div>"
```

#### 完整页眉/正文样式要点

```css
@page { size:A4; margin:22mm 16mm 12mm 16mm; }
.pdf-header { position:fixed; top:-17mm; left:0; right:0; height:15mm; background:#fff;
  font-family:"Microsoft YaHei","PingFang SC",SimHei,Arial,sans-serif;
  font-size:9pt; display:flex; justify-content:space-between; align-items:flex-end; }
h1,h2,h3,h4 { break-after: avoid; }
p { break-inside: avoid; }
blockquote, pre { break-inside: avoid; }
```

### 执行完毕后清理所有临时文件（.ps1 / .html / EdgeCdpTmp/）

---

## 快速调用示例

```
# MD 格式用例
@testcase-quality-review
需求文档：D:\project\output\prdmd\xxx.md
测试用例：D:\project\output\test_cases\xxx.md
输出到：D:\project\output\test_cases\

# XMind 格式用例（自动转换后分析）
@testcase-quality-review
需求文档：D:\project\output\prdmd\xxx.md
测试用例：D:\项目资料\VX.X.X\xxx.xmind
输出到：D:\project\output\test_cases\

# 简化方式（缺路径时 agent 自动询问）
@testcase-quality-review 结合 [需求文档] 和 [测试用例]，分析并给出报告

# 极简方式
@testcase-quality-review 帮我做用例质量分析
```

## 相关文件

- 转换脚本：`scripts/xmind_to_md.ps1`（XMind → Markdown，支持 JSON 新版 + XML 旧版）
