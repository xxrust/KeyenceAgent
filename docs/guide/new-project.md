# 创建新项目

先明确 CPU、项目名称、程序任务、接口和验收范围。
通过 [能力查询](../../kv-studio-operator/scripts/get_kv_capabilities.ps1) 选择已发布操作；
只使用当前清单返回的接口和参数。

完整项目按依赖顺序准备类型、模块程序体、声明、实例/设备绑定和配置，
再在 KV STUDIO 中执行并转换。创建空项目只是其中一步。
其他已打开的不同项目（含未保存项目）不构成新建的阻碍；相同目标冲突应停止。

scaffold 是可选的完整程序示例。选择该模型时遵循
[mvp-runner-contract.md](../../kv-studio-operator/references/mvp-runner-contract.md)；
实际工程无需改造成 MVP 的模块布局。

开始桌面操作前准备输入，使用新的 OutDir 保存执行计划、run.log 和结果。
新建结束必须解除初始化弹窗并保存目标项目，不能只以 .kpr 已出现判成功。
后续导入、变量写入和编译分别检查自己的本次证据。
