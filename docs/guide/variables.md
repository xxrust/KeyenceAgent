# 变量与数据类型

变量声明与程序体分别维护。全局变量属于工程集成；局部变量属于指定程序或 FB；
FB 自变量还包含 IN、OUT、IN-OUT 等方向。不要混用两张表的 TSV 列格式。

数据类型必须先于引用它的声明存在。嵌套结构体按依赖顺序建立，系统自带
(System) 类型无需重建。成员表末尾空白新增行不计为实际成员。

接口、输入字段、读回范围统一见
[variable-editor.md](../../kv-studio-operator/references/variable-editor.md) 和
[脚本能力查询](../../kv-studio-operator/scripts/get_kv_capabilities.ps1)。
名称/类型通过不能代替初值、设备、保持属性、注释等完整语义还原；
报告明确列出已核对字段。

设备地址范围、保持行为和特殊软元件由具体 CPU/模块决定，请依据 Wiki 和
当前工程确认，不使用一张跨机型的通用地址表作为编程依据。
