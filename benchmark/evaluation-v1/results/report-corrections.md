# 保存结果的 post-hoc 共同类别与计时补充

此次仅重算保存的聚合混淆表、读取已封存审计事件及已有review-operation计时；没有模型调用或科学重跑。
这是查看过原结果后的探索性修正，不是预注册确认性验证；既有冻结输入、映射、原结果和失败记录保持原样。
[原报告](report-original-v1.md)、[原始聚合指标](metrics.json)和[补充机器记录](posthoc-common-class.json)均保留。

## ifnb：明确区分原始与共同类别分母

固定共同类为B、Dendritic、Monocyte、NK、T，来自冻结作者/参考词表交集，排除Other，不按分数挑类。
只排除非共同类别的作者truth；共同类细胞上的Unknown、非共同类预测、失败和缺失仍算错。
原始5000细胞，子集4894，排除106；子集macro-F1与原始全部类macro-F1不是相同估计目标。

| 变体 | 方法 | 原始N | 子集N | 排除N | 正确数 | 子集macro-F1 | 子集正确产出 | 正确数/原始N |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| baseline-1 | candidate_author | 5000 | 4894 | 106 | 4188 | 0.740983 | 0.855742 | 0.837600 |
| baseline-1 | singler_author | 5000 | 4894 | 106 | 4449 | 0.831083 | 0.909072 | 0.889800 |
| after-1 | candidate_author | 5000 | 4894 | 106 | 4188 | 0.740983 | 0.855742 | 0.837600 |
| after-1 | singler_author | 5000 | 4894 | 106 | 4449 | 0.831083 | 0.909072 | 0.889800 |
| after-no-diagnostics-1 | candidate_author | 5000 | 4894 | 106 | 4188 | 0.740983 | 0.855742 | 0.837600 |
| after-no-diagnostics-1 | singler_author | 5000 | 4894 | 106 | 4449 | 0.831083 | 0.909072 | 0.889800 |

两方法在原始三种变体中的结果没有变化，不构成新增诊断改善标签的证据。所有已审批最终标签
仍是显式Unknown软件控制；上表候选和SingleR均不是已确认生物学标签。

## Baron：胰腺准确率不适用

本轮冻结HPCA没有目标胰腺类型覆盖，不能评价alpha/beta/delta/PP/acinar/ductal准确率。
胰腺accuracy及macro-F1为null/not applicable；旧标签字面匹配仅保留为历史记账，不进入
胰腺准确率比较。非血液注释质量验证缺口仍未通过，没有补选更有利参考或重跑分类。

## 已保存阶段wall区间

以下数值按封存state审计事件分段；每段包含实际API校验、持久化和可能的review渲染。
它们不等于纯算法内核成本、孤立日志成本或人工作业时间；各段边界见JSON。
纯compute、峰值内存、人工作业均未测量，保持null。总wall与CPU user/system及逐次review操作
在JSON单列；CPU时间也不是阶段纯compute。并行负载及PBMC内存/文件collector变化限制直接比较。

| 数据 | 变体 | 基础审批→测量审阅秒 | 测量审阅→选择审批秒 | 选择审批→注释证据秒 | 注释证据→审批秒 | 审批→完成秒 |
| --- | --- | --- | --- | --- | --- | --- |
| pbmc3k | baseline-1 | 110.654 | 17.766 | 19.459 | 256.233 | 13.027 |
| pbmc3k | after-snapshot-1 | 379.779 | 373.513 | 30.570 | 1480.499 | 25.042 |
| pbmc3k | after-no-diagnostics-1 | 249.647 | 20.104 | 46.728 | 29.282 | 22.908 |
| pbmc3k | after-qc-or-1 | 440.040 | 29.015 | 63.222 | 106.626 | 42.807 |
| ifnb | baseline-1 | 428.283 | 16.765 | 69.687 | 34.325 | 35.621 |
| ifnb | after-1 | 929.242 | 25.281 | 79.288 | 146.529 | 46.981 |
| ifnb | after-no-diagnostics-1 | 422.328 | 16.299 | 74.250 | 26.302 | 23.276 |
| baron | baseline-1 | 2089.879 | 28.129 | 309.729 | 42.943 | 46.662 |
| baron | after-1 | 2689.706 | 38.108 | 235.354 | 269.929 | 75.064 |
| baron | after-no-diagnostics-1 | 1377.014 | 19.339 | 224.443 | 30.084 | 32.736 |
| baron | after-sample-hvg-1 | 2747.301 | 40.260 | 239.073 | 279.273 | 90.016 |

PBMC after-snapshot为恢复态复制，审批事件可能来自原始项目，不能把其历史区间视为该复制的独立耗时。
已有show/revise/approve操作的elapsed包含完整公共API和渲染，approve还可能继续科学计算；
不得把sum(show)称作全部日志成本，或把wall−show称作纯compute。现有大R文本输出回归证明
展示量减少，尚无本轮科学基准运行速度改善测量。

模型A/B仅方案（已撤下的未执行方案）：无调用、无传输、无费用；尚无模型效果结果。

## 预测状态审计补充

评分现仅允许实际生产者状态 `candidate_only_not_reviewed` 和 `reference_prediction` 计分。
`unknown` / `explicit_unknown_control` 为弃权；失败、未运行、schema失败、缺失或未知状态
即使携带正确标签也按Unknown/错误计入原分母，原始输出不改写。
post-hoc不再信任无状态核验的旧聚合；使用与原始metrics哈希绑定、从保存CSV重算的状态审计。

本轮只读检查36个保存CSV、144978行：未发现不具计分资格却携带非Unknown标签的行，
22组已有候选/SingleR作者标签指标比较没有数值变化；ifnb共同类F1仍为0.740983/0.831083。
这是实际审计结论，不表示该评分漏洞无害；失败却标签正确的回归证明旧代码会错误给分。
原metrics、原失败及CSV字节保持不变，完整状态/来源hash见[prediction-status-audit.json](prediction-status-audit.json)。
