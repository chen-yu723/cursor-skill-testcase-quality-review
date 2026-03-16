# testcase-quality-review

> 一个 Cursor Agent Skill，结合需求文档与测试用例，自动完成五维度质量校验并生成 MD + PDF 双格式分析报告。

---

## 功能概览

| 能力 | 说明 |
|---|---|
| 五维度质量校验 | 需求覆盖度 / 用例完整性 / 用例准确性 / 冗余控制 / 业务适配性 |
| 量化评分 | 100 分制加权评分，输出质量等级（优秀 / 良好 / 一般 / 较差） |
| 双格式报告 | 同时生成 `.md` 和 `.pdf` 报告，输出到指定目录 |
| XMind 支持 | 测试用例支持 `.xmind` 格式，自动转换为 Markdown 后再分析 |
| 缺参自动询问 | 路径未提供时，通过对话交互主动向用户确认 |

---

## 环境要求

| 依赖 | 版本要求 | 说明 |
|---|---|---|
| 操作系统 | Windows 10 / 11 | 脚本为 PowerShell，仅支持 Windows |
| PowerShell | 5.1 及以上 | 系统自带，无需额外安装 |
| Microsoft Edge | 任意现代版本 | PDF 生成使用 Edge 无头模式（CDP），需安装在默认路径 |
| Cursor IDE | 最新版 | 需支持 Agent Skills |

> **Edge 默认安装路径**：`C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`  
> 若 Edge 安装在其他路径，需修改 `scripts/gen_report_pdf_v3.ps1` 第 9 行的 `$edge` 变量。

---

## 安装方法

将本仓库克隆到 Cursor 的**用户全局 skills 目录**下：

```powershell
# 克隆到用户全局 skills 目录（对所有工作区生效）
git clone https://github.com/<your-username>/testcase-quality-review `
  "$env:USERPROFILE\.cursor\skills\testcase-quality-review"
```

或手动下载后，将整个文件夹放到以下路径：

```
C:\Users\<你的用户名>\.cursor\skills\testcase-quality-review\
```

安装完成后目录结构如下：

```
testcase-quality-review/
├── README.md
├── SKILL.md
└── scripts/
    ├── xmind_to_md.ps1        ← XMind → Markdown 转换脚本
    └── gen_report_pdf_v3.ps1  ← Markdown → PDF 生成脚本
```

---

## 使用方式

在 Cursor 对话框中使用以下任意方式触发：

**方式一：直接提供路径（推荐）**

```
@testcase-quality-review 结合需求文档 D:\project\prd.md，分析测试用例 D:\project\cases.xmind，报告放到 D:\project\output\
```

**方式二：触发后交互确认**

```
@testcase-quality-review 分析并给出报告
```
Skill 会逐步询问需求文档路径、测试用例路径、输出目录。

**支持的触发关键词**：用例审查、用例质量、用例校验、分析报告、质量分析

---

## 报告结构

生成的报告包含七个章节：

| 章节 | 内容 |
|---|---|
| 一、多维度量化指标汇总 | 需求覆盖度、完整用例占比、准确率、冗余数、业务覆盖度等核心指标 |
| 二、需求覆盖度分析 | 已覆盖需求清单 + 未覆盖需求清单（含优先级） |
| 三、用例完整性分析 | A类（测试点缺失）/ B类（结构不完整）/ C类（描述不明确）缺陷清单 |
| 四、用例准确性分析 | 与需求不符的用例清单，含错误类型和修改建议 |
| 五、用例冗余性校验 | 重复用例清单（建议删除）+ 相似用例清单（建议合并） |
| 六、业务适配性分析 | 已覆盖业务场景亮点 + 缺失业务场景风险项 |
| 七、综合评估与优化建议 | 100 分制评分表 + P0/P1/P2/P3 优先级优化清单 + 一句话总结 |

---

## 评分权重

| 维度 | 权重 | 说明 |
|---|---|---|
| 需求覆盖度 | 30 分 | 需求点是否全部映射到测试用例 |
| 用例完整性 | 25 分 | 前置条件、操作步骤、预期结果、异常场景是否齐全 |
| 用例准确性 | 20 分 | 用例描述与需求文档的一致性 |
| 冗余控制 | 15 分 | 重复/相似用例占比 |
| 业务适配性 | 10 分 | 风控、资金计算、接口联调等核心业务场景覆盖度 |

**质量等级**：≥85 优秀 / 70~84 良好 / 55~69 一般 / <55 较差

---

## 冗余判定规则

| 判定结论 | 判定条件 |
|---|---|
| **重复用例** | 章节标题（H4）**且**子节点标题（H5）均完全相同 → 建议删除 |
| **相似用例** | 章节标题不同，但子节点标题相同 → 建议合并差异点 |
| **正常用例** | 章节标题或子节点标题均不同 → 不视为冗余 |

---

## 文件说明

| 文件 | 作用 |
|---|---|
| `SKILL.md` | Skill 主定义文件，包含完整执行逻辑，Cursor 读取此文件驱动 Agent 行为 |
| `scripts/xmind_to_md.ps1` | 将 `.xmind` 文件（XML 或 JSON 格式）转换为结构化 Markdown |
| `scripts/gen_report_pdf_v3.ps1` | 将 Markdown 报告通过 Edge CDP 渲染为 PDF，支持中文字体、表格防截断 |

---

## 常见问题

**Q：PDF 生成失败，提示找不到 Edge？**  
A：确认 Edge 已安装，或修改 `scripts/gen_report_pdf_v3.ps1` 第 9 行 `$edge` 变量为实际路径。

**Q：XMind 文件转换后内容乱码？**  
A：脚本使用 `.NET` UTF-8 编码读取，确保 XMind 文件保存为 UTF-8 格式（XMind 8 及以上默认支持）。

**Q：中文路径报错找不到文件？**  
A：PowerShell 5.1 存在中文路径编码问题，Skill 已通过 JSON 配置文件方式规避，直接提供绝对路径即可正常使用。

**Q：能在 macOS / Linux 上用吗？**  
A：暂不支持，脚本依赖 PowerShell 和 Windows Edge。欢迎 PR 贡献跨平台版本。

---

## License

MIT
