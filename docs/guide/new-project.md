# 创建新项目

本指南详细说明如何使用 KeyenceAgent 从零创建一个新的 KV STUDIO 项目。

## 概述

创建新项目的基本流程：

```
描述需求 → AI 设计程序 → 生成脚手架 → 自动导入 KV STUDIO → 编译验证
```

**时间：** 通常 2-5 分钟

## 准备工作

### 1. 确保环境就绪

```powershell
# 检查配置状态
.\setup_keyence_agent.ps1 -Status

# 确认 KV STUDIO 未在运行
Get-Process -Name "Kvs" -ErrorAction SilentlyContinue
```

### 2. 明确项目需求

在开始前，准备好以下信息：

- **项目名称** - 有意义的英文名（如 `TemperatureControl`）
- **控制逻辑** - 输入、输出、处理逻辑
- **变量需求** - 需要哪些全局/局部变量
- **特殊功能** - 是否需要功能块、后备模块等

## 基础项目示例

### 示例 1：简单的启停控制

**需求描述：**
```
创建一个启停控制项目：
- 项目名：StartStopControl
- 启动按钮：DM100.00
- 停止按钮：DM100.01
- 运行指示灯：R0
- 逻辑：按启动点亮，按停止熄灭
```

**在 Claude Code 中输入：**
```
使用 /kv-studio-operator 创建新项目 StartStopControl：

输入：
- DM100.00：启动按钮
- DM100.01：停止按钮

输出：
- R0：运行指示灯

逻辑：
- 按下启动按钮时，R0 置为 ON
- 按下停止按钮时，R0 置为 OFF
- 具有自锁功能
```

**AI 执行过程：**

1. **查询知识库**
   ```
   调用 kv-studio-kb-programming 查询：
   - LD/OUT 指令语法
   - 位设备地址规则
   ```

2. **设计程序**
   ```
   调用 keyence-plc-programmer 生成：
   - scaffold.model.json（项目模型）
   - modules/MAIN/MAIN.mnm（主程序）
   - modules/MAIN/variables.tsv（变量表）
   ```

3. **运行门禁**
   ```
   静态检查：
   ✓ 变量地址合法性
   ✓ 模块完整性
   ✓ Checklist 存在
   ```

4. **启动 KV STUDIO**
   ```
   调用 kv-studio-operator：
   - 创建新项目
   - 导入 MAIN.mnm
   - 粘贴变量表
   - 编译
   ```

5. **报告结果**
   ```
   ✅ 项目创建成功
   
   编译结果：
     转换结果 OK
     错误数量: 0
     警告数量: 0
   
   项目位置：
     C:\Temp\KeyenceWork\StartStopControl\StartStopControl.kpr
   ```

**生成的程序逻辑（示例）：**
```
LD DM100.00    ; 启动按钮
OR R0          ; 自锁
AND/ DM100.01  ; 停止按钮取反
OUT R0         ; 输出到指示灯
```

### 示例 2：计数器项目

**需求描述：**
```
创建一个计数器项目：
- 项目名：CounterDemo
- 计数输入：DM100.00
- 复位按钮：DM100.01
- 计数值：DM200（INT 型）
- 达到 10 次时输出报警：R10
```

**在 Claude Code 中输入：**
```
使用 /kv-studio-operator 创建计数器项目 CounterDemo：

功能：
1. 每次 DM100.00 上升沿时，DM200 加 1
2. 按下 DM100.01 时，DM200 清零
3. 当 DM200 >= 10 时，R10 置为 ON
4. DM200 清零时，R10 复位
```

**AI 会自动：**
- 使用 UP 指令实现上升沿检测
- 使用 CNT 指令或直接计数
- 使用比较指令判断阈值

**生成的变量表（示例）：**
```
设备名称     数据类型    用途
DM100.00    BIT         计数触发
DM100.01    BIT         复位按钮
DM200       INT         计数值
R10         BIT         报警输出
```

## 中等复杂度项目

### 示例 3：多传感器监控

**需求：**
```
创建一个传感器监控项目：
- 项目名：SensorMonitor
- 4 路温度传感器（EM1:CH0~CH3）
- 读取值存储到 DM100~DM103
- 任意传感器 > 800 时报警（R0）
- 所有传感器 < 200 时指示正常（R1）
```

**在 Claude Code 中输入：**
```
使用 /kv-studio-operator 创建传感器监控项目 SensorMonitor：

硬件配置：
- 扩展单元 EM1 的 CH0~CH3 为温度传感器

数据采集：
- 读取 EM1:CH0~CH3 的值
- 分别存储到 DM100、DM101、DM102、DM103

报警逻辑：
- 任意温度 > 800 时，R0 = ON（高温报警）
- 所有温度 < 200 时，R1 = ON（正常指示）
- 其他情况，R0 和 R1 都为 OFF
```

**AI 会处理：**
- 查询扩展单元地址格式
- 生成多路数据读取代码
- 实现复杂的比较逻辑

### 示例 4：定时控制

**需求：**
```
创建一个定时控制项目：
- 项目名：TimerControl
- 启动按钮：DM100.00
- 延时 5 秒后启动电机：R0
- 电机运行 10 秒后自动停止
- 停止按钮：DM100.01（随时可停止）
```

**在 Claude Code 中输入：**
```
使用 /kv-studio-operator 创建定时控制项目 TimerControl：

时序要求：
1. 按下 DM100.00（启动按钮）
2. 延时 5 秒
3. R0 = ON（电机启动）
4. 再运行 10 秒
5. R0 = OFF（电机停止）
6. 整个过程中，按下 DM100.01 立即停止

请使用 KEYENCE 的定时器指令实现。
```

**AI 会使用：**
- TMR（定时器）指令
- 状态机逻辑
- 适当的复位条件

## 高级项目：使用功能块

### 示例 5：自定义功能块项目

**需求：**
```
创建一个带功能块的滤波项目：
- 项目名：FilterDemo
- 自定义功能块：MovingAverage（移动平均滤波）
- 应用到 4 路传感器
```

**步骤 1：定义功能块**

```
使用 /kv-studio-operator 创建项目 FilterDemo，包含自定义功能块：

功能块名称：MovingAverage

输入参数：
- InputValue：原始输入值（INT）
- WindowSize：窗口大小（INT，默认 5）

输出参数：
- OutputValue：滤波后的值（INT）

内部变量：
- Buffer：存储最近 WindowSize 个样本的数组
- Index：当前写入位置
- Sum：当前总和

功能：
对输入值进行移动平均滤波，返回最近 WindowSize 个样本的平均值。
```

**步骤 2：使用功能块**

AI 会自动：
1. 生成功能块的 MNM（`MODULE_TYPE:2`）
2. 生成功能块参数表
3. 在主程序中实例化 4 个功能块
4. 配置每个实例的输入输出

**生成的项目结构：**
```
FilterDemo/
├── modules/
│   ├── MAIN/
│   │   ├── MAIN.mnm                    (主程序，调用 FB)
│   │   └── variables.tsv
│   └── FB_MovingAverage/
│       ├── FB_MovingAverage.mnm        (功能块定义)
│       └── fb_arguments.tsv            (功能块参数)
└── scaffold.model.json
```

**主程序示例逻辑：**
```
; 读取传感器
MOV EM1:CH0, DM100
MOV EM1:CH1, DM101
MOV EM1:CH2, DM102
MOV EM1:CH3, DM103

; 调用功能块
CALL FB_MovingAverage_1(DM100, 5, DM200)
CALL FB_MovingAverage_2(DM101, 5, DM201)
CALL FB_MovingAverage_3(DM102, 5, DM202)
CALL FB_MovingAverage_4(DM103, 5, DM203)
```

## 项目模板

### 通用项目模板

如果你有固定的项目结构，可以创建模板：

**在 Claude Code 中：**
```
为我创建一个通用的项目模板，包含：
1. 标准的全局变量区域划分：
   - DM0~DM99：系统控制
   - DM100~DM199：输入信号
   - DM200~DM299：输出信号
   - DM300~DM999：中间变量

2. 标准的程序结构：
   - 初始化段（首次扫描执行）
   - 输入读取段
   - 主逻辑段
   - 输出写入段
   - 错误处理段

3. 通用功能块：
   - Debounce：消抖
   - EdgeDetect：边沿检测
   - RateLimit：速率限制

将模板保存到 kv-studio-operator/templates/ 目录。
```

### 使用模板创建项目

```
基于 StandardProject 模板创建新项目 MyProject：
- 保留模板的结构和通用功能块
- 在主逻辑段添加：...（你的具体需求）
```

## 常见模式

### 模式 1：状态机

```
创建一个状态机控制项目：

状态定义：
- 0：待机
- 1：准备
- 2：运行
- 3：暂停
- 4：完成

状态转换：
- 待机 → 准备：按下启动按钮
- 准备 → 运行：准备完成（延时 3 秒）
- 运行 → 暂停：按下暂停按钮
- 暂停 → 运行：按下继续按钮
- 运行 → 完成：工艺完成
- 完成 → 待机：按下复位按钮

使用 DM0 存储当前状态。
```

### 模式 2：顺序控制

```
创建一个顺序控制项目（洗衣机示例）：

步骤：
1. 注水（5 秒）
2. 加洗涤剂（1 秒）
3. 洗涤（30 秒）
4. 排水（10 秒）
5. 漂洗（20 秒）
6. 排水（10 秒）
7. 脱水（15 秒）
8. 完成

每个步骤完成后自动进入下一步。
提供暂停和急停功能。
```

### 模式 3：多任务并行

```
创建一个多任务控制项目：

任务 1：温度监控（每 100ms 执行）
任务 2：压力监控（每 50ms 执行）
任务 3：数据记录（每 1s 执行）
任务 4：通信处理（事件触发）

使用 KEYENCE 的多任务机制或定时中断实现。
```

## 项目配置

### 添加后备模块

```
在项目中添加后备模块：

后备模块名称：STANDBY_MAIN
触发条件：主程序出错时切换
功能：
- 停止所有输出
- 显示故障代码
- 保持安全状态
```

AI 会：
- 生成 `MODULE_TYPE:1`，`category=standby` 的 MNM
- 配置后备模块的导入选项

### 添加中断程序

```
添加高速中断程序：

中断号：0
触发：外部中断输入 INT0
功能：
- 紧急停机
- 保存当前状态到 DM1000~
- 置位紧急停机标志 R100
```

**注意：** 中断程序的 KV STUDIO 配置目前需要手动设置，AI 会提示你：
```
ROUTE_RESEARCH_REQUIRED: 
中断程序的 CPU 系统中断设置和中断允许配置尚未脚本化。
请按照以下步骤手动配置：
1. 在 KV STUDIO 中打开项目
2. 菜单：PLC → CPU 系统设置
3. 选择"中断"选项卡
...
```

## 验证和调试

### 编译验证

项目创建后，AI 会自动编译并报告：

```
✅ 编译成功
转换结果 OK
错误数量: 0
警告数量: 0
```

或：

```
❌ 编译失败
错误数量: 2

错误详情：
MAIN.mnm 行 15: 变量 'TempSensor5' 未定义
MAIN.mnm 行 23: 指令 'MOVV' 不存在（应为 'MOV'）
```

**AI 会自动修复编译错误**，无需手动干预。

### 手动检查项目

```powershell
# 打开生成的项目
$config = Get-Content "$env:KV_STUDIO_OPERATOR_CONFIG" | ConvertFrom-Json
$projectPath = "$($config.work_root)\YourProject\YourProject.kpr"

# 启动 KV STUDIO
& $config.kvs_exe $projectPath
```

在 KV STUDIO 中检查：
- 程序逻辑是否正确
- 变量是否完整
- 功能块是否正确导入

### 重复性验证

确保项目稳定：

```
使用 repeat runner 验证项目稳定性：
- 要求连续成功 3 次
- 每次都是全新创建
- 验证变量持久化
```

## 最佳实践

### 1. 项目命名

- ✅ 使用有意义的英文名：`TemperatureControl`
- ✅ 使用驼峰命名或下划线：`temperature_control`
- ❌ 避免中文：`温度控制`
- ❌ 避免空格：`Temperature Control`
- ❌ 避免特殊字符：`Temp@Control`

### 2. 变量规划

**建议的地址分配：**
```
DM0~DM99        系统控制和状态
DM100~DM199     数字输入
DM200~DM299     数字输出
DM300~DM399     模拟输入
DM400~DM499     模拟输出
DM500~DM999     中间变量
DM1000~         数据记录
```

### 3. 模块化设计

对于复杂项目：
- 将独立功能封装为功能块
- 主程序只做调度和协调
- 功能块负责具体逻辑

### 4. 注释和文档

让 AI 生成注释：
```
为项目添加详细注释：
- 每个程序段的功能说明
- 关键变量的用途
- 特殊逻辑的解释

同时生成 TASK.md 文档，说明：
- 项目目的
- 硬件配置
- 操作说明
```

### 5. 版本管理

```
生成项目后，创建 VERSION.md：
- 版本号：v1.0
- 创建日期
- 功能列表
- 已知问题
```

## 故障排除

### 问题 1：脚手架验证失败

**症状：**
```
❌ 静态门禁失败
KV_CHECKLIST_MISSING
```

**解决：**
AI 会自动重新生成 checklist，你无需手动干预。

### 问题 2：变量地址冲突

**症状：**
```
警告：DM100 被多次定义
```

**解决：**
告诉 AI：
```
项目中 DM100 地址冲突，请重新规划变量地址，避免冲突。
```

### 问题 3：功能块导入失败

**症状：**
```
❌ 功能块 'MyFB' 未找到
```

**解决：**
```
功能块导入失败，请检查：
1. 功能块 MNM 是否正确生成
2. MODULE_TYPE 是否为 2
3. 功能块名称是否匹配
```

AI 会重新生成并修复。

## 下一步

- 📖 学习如何 [修复现有项目](repair-project.md)
- 🧩 深入了解 [功能块开发](function-blocks.md)
- 📋 掌握 [变量管理](variables.md)

---

**需要帮助？** 查看 [故障排除](troubleshooting.md) 或 [提交 Issue](https://github.com/xxrust/KeyenceAgent/issues)。
