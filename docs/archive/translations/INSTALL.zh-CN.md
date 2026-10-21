# 安装与试用

使用当前 main；如需复现某次运行，请把安装引用换成已记录的完整 commit SHA。
适用于 macOS/Linux；需要 R ≥ 4.2、Python ≥ 3.9、Seurat ≥ 5。
macOS/Linux 安装运行时及空库安装由 CI 检查。
当前仍是研发版，正式实验尚未完成。请创建新项目；旧项目的科学实现
hash 不同会被阻断，不要手工篡改它以继续。

## Ubuntu/Debian 空环境的系统依赖

若已有可用的 R/Seurat 环境可跳过。以下为干净安装 CI 使用的构建依赖；R ≥ 4.2 需先安装：

```sh
sudo apt-get update
sudo apt-get install -y git curl python3 ca-certificates build-essential gfortran cmake pkg-config libcurl4-openssl-dev libssl-dev libxml2-dev libpng-dev libjpeg-dev libtiff-dev libfontconfig1-dev libfreetype6-dev libharfbuzz-dev libfribidi-dev libhdf5-dev libglpk-dev libgmp-dev
```

## 安装当前源码

在 R 中执行（源码依赖可能需要系统编译工具；macOS 使用 Xcode Command Line Tools）：

```r
install.packages("remotes")
remotes::install_github("ChanghaoKan/agentomicsCore@v0.3.0",
                        dependencies = NA, upgrade = "never")
remotes::install_github(
  "ChanghaoKan/scAgentKit",
  dependencies = NA, upgrade = "never")
library(scAgentKit)
```

若安装提示具体依赖缺失，先按该依赖的 CRAN/Bioconductor 安装说明补齐。
可选科学组件缺失时，按界面的未评估/规则兜底提示审阅，不把它当作已执行。

## 先做不收费的操作试用

```r
data("pbmc_small", package = "SeuratObject")
saveRDS(pbmc_small, "pbmc-small-trial.rds")
sc_start(
  "pbmc-small-trial.rds", "pbmc-small-trial-project",
  context = list(species = "human", tissue = "blood",
                 research_goal = "检查三道审批和查证过程"),
  provider = "mock", react = "all", doublet = "off")
```

mock 只验证软件操作，不提供可信生物学标签。依次审阅、采纳或修改并批准三道审批。
保存草稿不等于批准。关闭后用同样的 input 和 project_dir 重新调用 `sc_start()`。

## 自己的数据与 API

在本机 R 会话设置 `DEEPSEEK_API_KEY`，不要把 key 写进代码仓库或发到聊天中。
把上例 input 改为你的 RDS，project_dir 换成新的目录，研究目的填写真实内容，
provider 改为 `"deepseek"`；其余采用默认即可。首次外发前审阅授权范围。
实际 token/费用在调用后记录；没有金额封顶。ReAct 的步数与超时限制仍然有效。

## 暂停、续跑和磁盘额度

```r
sc_run_control("pbmc-small-trial-project", cancel = TRUE, reason = "暂停检查")
sc_run_control("pbmc-small-trial-project", cancel = FALSE, reason = "继续原项目")
sc_run_resume("pbmc-small-trial-project", retry = TRUE)

sc_run_control("pbmc-small-trial-project", disk_limit_bytes = 20 * 1024^3,
               reason = "允许 20 GiB")
sc_run_control("pbmc-small-trial-project", disk_limit_bytes = NULL,
               reason = "解除额度")
```

`sc_run_resume` 用于已批准的本地阶段；模型草稿请重新打开项目后显式请求。
续跑不切换模型。投递不确定时不自动重发，需核实账本；仅费用未知不会阻断。
磁盘额度是检查点边界检查，不是系统硬配额。取消也是安全边界停止，当前调用可能完成并计费。

下载构建归档后，使用[随包归档安装说明](../../../inst/INSTALL.md)。CI 从未经修改的归档提取并执行同一套命令。
