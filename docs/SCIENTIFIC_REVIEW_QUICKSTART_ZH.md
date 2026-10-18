# 科学诊断：一页操作指南

本开发分支的诊断均为可选项。结果可能不变或变差；审批成功不代表生物学结论正确。
旧项目需保留原包和依赖环境，不要修改其 hashes、审批或 checkpoints 来强行恢复。

1. **明确输入和样本角色，再打开新项目。** 使用原始 counts；sample、donor、capture、condition
   分别按实际元数据声明，不从名字猜测，不把处理条件当作技术批次或样本重复。
   标准浏览器入口现在可显式开启以下诊断（会增加本地计算时间，不调用模型）：

   ```r
   service <- sc_start("input.rds", "new-review-project",
     context = list(species="human", tissue="Blood", research_goal="Review local evidence",
       columns=list(sample="sample_id", condition="condition")),
     scientific_review=list(pc_sensitivity=TRUE, resampling=TRUE,
       resolution_extension=TRUE, panels="blood", cross_sample=TRUE,
       mixed_lineage=TRUE))
   ```

   仅在输入确有这两列及相应实验事实时使用该示例；没有 sample 信息就省略该声明。
   `panels="pancreas"` 提供另一组明确的人类描述性面板；其他物种需传入命名 gene list。

2. **审查 QC 草稿和样本比较。** 分布、每样本中位数、跨样本异常提示与组内细胞 MAD 分开显示。
   跨样本稳健异常需要至少五个可比较样本和非零 MAD。满足完整证据及风险上限时，页面可预填
   `any_quality3` 比较草稿，并显著标记未保存/未批准；可修改或弃用。预填不会改变 saved proposal
   或删细胞。先点保存重建影响，再单独审批，最后继续计算；缺失条件会显示不适用原因。

3. **比较分析参数，保留必要的不确定性。** 默认 HVG 仍是全局 vst；若有至少两个明确样本且每样本
   至少 30 个保留细胞，可在完整 strategy JSON 的 analysis 中显式添加
   `"hvg_method":"sample_consensus", "hvg_column":"sample_id"`，保存并审查后审批。
   PC 面板并列显示 top50 内部 80/85% 与弦距肘部，均不是最优参数；可选 k±5 和五次 80% 重采样
   在副本上重建图/聚类并显示 ARI、簇 Jaccard、覆盖及 marker 一致性。固定图分辨率扫描与重采样
   是不同证据；有限扩展也不改变已经批准的 resolution。暂不能复现的 Harmony/周期回归组合会明确
   标为不可用，不用 PCA-only 对照冒充同方法稳定性。

4. **看表达再判断注释；污染校正另存。** 经典面板提供 mean log-normalized expression、原 counts
   检出比例、组内外差值及逐样本方向；通用表达、混合面板共表达都不是类型或污染诊断真值。
   已知标签的支持引用必须有正 FC 和正检出率差；仍不验证基因与标签的语义。参考页保留 hits/
   denominator/coverage，Fisher 仅在记录精确可检验背景时显示，且对全部标签校正；不能把 p 值当概率。
   unresolved 保留 Unknown。保存完整注释后，还需要独立审批才能写入结果。

可选 `sc_run_ambient_correction()` 要求明确的完整单 capture 声明及命名初步 clusters；SoupX
需要严格匹配的 raw+filtered 矩阵和额外背景 droplets。decontX 可无 raw，但其背景来自其他簇的
模型假设，可能删掉真实 RNA。返回单独 corrected counts 和前后 counts/检出/污染估计记录，
不替换原对象或项目 checkpoints；`round_counts=TRUE` 必须明确选择。先对照经典面板、稀有群和
原始结果，再决定是否用校正矩阵另建项目。依赖缺失时不会自动安装或换算法。

查看[方法及限制](SCIENTIFIC_METHODS_APPENDIX.md)和[冻结评估协议](EVALUATION_PROTOCOL_V1.md)。
上述操作示例是软件路径，尚不能据此声称准确率或人工时间改善；统一效果基准和平台验收另报。
