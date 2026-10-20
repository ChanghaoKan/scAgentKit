# scAgentKit

[English](README.md) · **简体中文**

面向长期研究使用的、受控的 LLM 单细胞基础分析助手。从计数矩阵到注释好的
Seurat 对象，QC、批次处理、分群和注释的关键决策都有明确记录：
**模型结合研究目的起草并提供可核对证据，研究者审阅、修改和批准。**

**当前仍在研发。** 请使用下面的 main 源码安装。软件流程验收不等于生物学准确率验证，正式评估尚未完成。

## 快速开始

支持 **macOS/Linux**；需要 R ≥ 4.2、Seurat ≥ 5、Python ≥ 3.9。不支持 Windows。

```r
install.packages("remotes")
remotes::install_github("ChanghaoKan/agentomicsCore@v0.3.0", upgrade = "never")
remotes::install_github("ChanghaoKan/scAgentKit", upgrade = "never")
library(scAgentKit)
# 先在 R 环境中配置所选 provider 的 API key。
sc_start("input.rds", "new-project",
  context = list(species = "human", tissue = "blood", research_goal = "你的研究目的"),
  provider = "deepseek")
```

一次确认汇总数据外发范围，然后依次审阅 **分析方案 → 实测分群 → 注释**。
采纳或保存草稿不等于批准。支持 RDS、10x MEX 和样本表；
用 `provider = "mock"` 可离线试用软件流程。
[安装与试用](docs/user/INSTALL.zh-CN.md) · [输入格式](docs/TENX_INPUT.md)。

## 可以核对什么

- QC 与批次诊断证据；每项实际处理由研究者批准。
- 本地 ACT 参考比对，以及对不确定注释的只读 ReAct 查证（默认 `react = "auto"`，`"off"` 关闭）。
- 保存的决策、工具证据、实际 token/费用记录，以及不需要 API 的注释重放。
- 注释好的 Seurat 对象、marker 表、图和项目审计记录。

费用事后记录，不设金额封顶；仍有步数和超时限制。投递不确定时不自动重发。
缺 key 或模型调用失败时，仍可使用规则默认值或人工审阅。

## 使用指南

| 任务 | 入口 |
| --- | --- |
| 三道审批、取结果、重开项目 | [完整流程](docs/user/WORKFLOW.zh-CN.md) |
| 理解注释查证 | [ReAct](docs/REACT_ZH.md) · [ACT](docs/ACT_LOCAL_REFERENCE.md) |
| 取消、续跑和磁盘额度 | [运行控制](docs/user/TRIAL_CONTROLS.zh.md) |
| 评估与离线重放 | [评估指南](docs/REACT_EVALUATION_ZH.md) |
| 运行完整示例 | [示例索引](inst/examples/README.md) |
| 查方法和环境要求 | [文档索引](docs/README.md) |
| 开发、验证与阶段报告 | [开发者索引](docs/dev/README.md) |

1.0 前影响科学结果的实现变更可能使旧项目无法继续，请保留原软件环境。
轨迹、通讯、调控网络和条件间比较等高级下游分析不在范围内。
[方法与局限](docs/SCIENTIFIC_METHODS_APPENDIX.md)。

[版本记录](NEWS.md) · [许可证](LICENSE.md) · [引用](CITATION.cff)
