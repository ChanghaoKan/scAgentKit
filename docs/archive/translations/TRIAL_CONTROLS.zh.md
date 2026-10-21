# 暂停、续跑与可选磁盘额度

各入口只在调用后记录实际 usage 和费用，不预计数、不预留、不按金额阻断。
缺少 key 时保留所选 provider；在 R 中设置对应环境变量后，显式重新请求草稿。
续跑使用原项目、原模型和原科学配置，不是换模型重跑。

界面的 **Cancel after current call** 请求在安全边界停止当前模型任务。
当前 API 请求可能完成并产生费用；不会杀掉其他 R 进程或删除结果。R 中也可操作：

```r
sc_run_control(project_dir, cancel = TRUE, reason = "暂停检查")
sc_run_control(project_dir, cancel = FALSE, reason = "继续原分析")
sc_run_resume(project_dir, retry = TRUE)
```

最后一行用于已批准的本地计算阶段。模型草稿需重新打开同一项目，检查当前预览，
再显式请求。已完成的簇与工具轮次从检查点恢复；不会恢复到算法中断的某一条指令。
若 key 在网页服务启动后才设置，请从设置好 key 的 R 会话显式请求草稿。

若投递状态不确定，不会自动重发。费用回执不能证明投递成功或失败。
仅在独立核实后，使用 `sc_run_provider_reconcile(..., delivery="not_sent")`
或 `delivery="received"` 记录确认理由。陈旧锁也必须先确认原进程已停止，
再显式使用 `sc_run_unlock`；不要删除仍在运行的进程持有的锁。

磁盘额度默认不限，可在创建项目后设置：

```r
sc_run_control(project_dir, disk_limit_bytes = 20 * 1024^3,
               reason = "项目文件允许占用 20 GiB")
sc_run_control(project_dir, disk_limit_bytes = NULL,
               reason = "解除额度")
```

检查按文件逻辑大小统计，跳过符号链接，在阶段和检查点边界执行。
这不是操作系统硬配额：正在计算的文件、临时文件和必要审计记录可能暂时超额。
遇到额度停止后，增大或解除额度，再显式继续；不会自动删除已有结果。
界面的存储按钮可查看当前占用。

连续重复取得相同工具证据且没有进展时，返回一次性草稿并记录原因。
有效的最终草稿立即结束查证；既有步数和超时上限继续生效，科学决策仍须用户批准。
