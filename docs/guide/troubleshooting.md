# 故障处理

先读本次 workflow 结果中的 error_code、current_step、failure 和 run_log_path。
步骤 receipt 记录入口、输入、代码指纹、结果文件及耗时。
不要从旧运行目录找一个成功结果来替代当前失败，也不要直接执行历史脚本。

- 脚本加载失败：用 `powershell -NoProfile -ExecutionPolicy Bypass -File ...`
  启动公开接口；安装和配置问题参考 [installation.md](../installation.md)。
- 未找到能力：通过 get_kv_capabilities 查询当前清单。未发布的能力返回
  ROUTE_RESEARCH_REQUIRED，不能因某个旧文件存在就当作已支持。
- 焦点/弹窗失败：停止后续输入，查看日志和截图。采用已有的目标弹窗处理；
  不恢复主窗口焦点来绕过模态框，不缩放窗口，不穷举控件。
- 结果缺失、过期或格式错误：检查 child stderr 和精确结果契约。进程返回零
  不能替代语义结果。
- 编译 NG：读取 compile_result_copied.txt，修改相关源程序/声明，再转换。
  未取得完整错误文本时明确报告提取失败。
- 同名项目或多实例：绑定明确的目标项目；不要批量结束所有 Kvs 进程。
- 安装漂移：开发模式运行 assert_keyence_dev_links，维护代码只改仓库源。

遇到陌生且未验证的 UI 操作，请提供停留界面、已执行步骤和具体疑问，
寻求人类操作说明后再完善共享脚本。已知脚本缺陷可在授权范围内修复，
修复后必须验证 agent 实际调用的 workflow。
