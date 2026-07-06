# 功能块开发

本指南详细说明如何使用 KeyenceAgent 创建和使用功能块（Function Block）。

## 什么是功能块？

功能块是可复用的程序模块，类似于编程语言中的函数。一次定义，多处调用。

**优势：**
- ✅ 代码复用，减少重复
- ✅ 模块化设计，便于维护
- ✅ 参数化配置，灵活调用
- ✅ 独立测试，提高质量

**KEYENCE 功能块特点：**
- 支持输入/输出参数
- 可定义内部变量
- 支持嵌套调用
- 可创建多个实例

## 基础功能块

### 示例 1：边沿检测功能块

**需求：**
检测输入信号的上升沿和下降沿。

**在 Claude Code 中输入：**
```
创建一个边沿检测功能块项目 EdgeDetectDemo：

功能块名称：EdgeDetect

输入参数：
- Input：当前输入信号（BOOL）

输出参数：
- RisingEdge：上升沿脉冲（BOOL）
- FallingEdge：下降沿脉冲（BOOL）

内部变量：
- LastInput：上一次的输入状态（BOOL）

功能：
- 当 Input 从 0→1 时，RisingEdge 输出 1 个扫描周期
- 当 Input 从 1→0 时，FallingEdge 输出 1 个扫描周期
- 其他情况，两个输出都为 0

在主程序中创建 2 个实例，分别检测 DM100.00 和 DM100.01 的边沿。
```

**生成的项目结构：**
```
EdgeDetectDemo/
├── modules/
│   ├── MAIN/
│   │   ├── MAIN.mnm
│   │   └── variables.tsv
│   └── FB_EdgeDetect/
│       ├── FB_EdgeDetect.mnm          (功能块定义)
│       └── fb_arguments.tsv            (参数表)
└── scaffold.model.json
```

**功能块 MNM 示例：**
```
; EdgeDetect 功能块
; 检测输入信号的上升沿和下降沿

; 上升沿检测
LD Input
AND/ LastInput
OUT RisingEdge

; 下降沿检测
LD/ Input
AND LastInput
OUT FallingEdge

; 更新状态
LD Input
OUT LastInput
```

**主程序调用示例：**
```
; 调用实例 1：检测 DM100.00
CALL EdgeDetect_1(DM100.00, R0, R1)

; 调用实例 2：检测 DM100.01
CALL EdgeDetect_2(DM100.01, R2, R3)

; R0：DM100.00 的上升沿
; R1：DM100.00 的下降沿
; R2：DM100.01 的上升沿
; R3：DM100.01 的下降沿
```

### 示例 2：消抖功能块

**需求：**
消除输入信号的抖动，稳定后才输出。

**在 Claude Code 中输入：**
```
创建消抖功能块项目 DebounceDemo：

功能块名称：Debounce

输入参数：
- Input：原始输入信号（BOOL）
- DelayTime：消抖时间（INT，单位：ms）

输出参数：
- Output：消抖后的输出（BOOL）

内部变量：
- Timer：定时器编号（使用 T0~T99）
- Stable：稳定状态（BOOL）

功能：
- Input 变化后，等待 DelayTime ms
- 如果期间 Input 保持稳定，则更新 Output
- 如果期间 Input 再次变化，则重新计时

在主程序中用于 4 个按钮输入的消抖，DelayTime = 50ms。
```

**功能块逻辑示例：**
```
; 输入变化检测
LD Input
XOR Stable
OUT M0    ; M0 = 输入变化标志

; 输入变化时启动定时器
LD M0
TMR Timer, DelayTime

; 定时到达且输入稳定，更新输出
LD Timer
AND Input
OUT Output

; 更新稳定状态
LD Input
OUT Stable
```

## 中等复杂度功能块

### 示例 3：移动平均滤波

**需求：**
对模拟量输入进行滑动窗口平均滤波。

**在 Claude Code 中输入：**
```
创建移动平均滤波功能块项目 MovingAverageDemo：

功能块名称：MovingAverage

输入参数：
- InputValue：原始输入值（INT）
- WindowSize：滑动窗口大小（INT，范围 2~10）

输出参数：
- OutputValue：滤波后的值（INT）
- DataReady：数据准备好标志（BOOL）

内部变量：
- Buffer[10]：存储历史数据（INT 数组）
- Index：当前写入位置（INT）
- Sum：当前窗口总和（INT）
- Count：已采集样本数（INT）

功能：
1. 将 InputValue 存入 Buffer[Index]
2. 更新 Index（循环：0→WindowSize-1）
3. 计算最近 WindowSize 个样本的平均值
4. Count < WindowSize 时，DataReady = 0
5. Count >= WindowSize 时，DataReady = 1，OutputValue = Sum / WindowSize

在主程序中对 4 路温度传感器应用，WindowSize = 5。
```

**功能块关键逻辑：**
```
; 存储新样本
MOV InputValue, Buffer[Index]

; 计算总和
LD Index
< WindowSize
JMPN CALC_SUM

; 循环遍历计算总和
; ... (使用循环或展开)

CALC_SUM:
; 更新计数
LD Count
< WindowSize
INC Count

; 计算平均值
LD Count
>= WindowSize
JMPN NOT_READY

DIV Sum, WindowSize, OutputValue
LD 1
OUT DataReady
JMPN END

NOT_READY:
LD 0
OUT DataReady

END:
; 更新索引
INC Index
LD Index
>= WindowSize
JMPN NO_RESET
LD 0
OUT Index
NO_RESET:
```

**主程序调用：**
```
; 读取传感器
MOV EM1:CH0, DM100
MOV EM1:CH1, DM101
MOV EM1:CH2, DM102
MOV EM1:CH3, DM103

; 应用滤波
CALL MovingAverage_1(DM100, 5, DM200, R0)
CALL MovingAverage_2(DM101, 5, DM201, R1)
CALL MovingAverage_3(DM102, 5, DM202, R2)
CALL MovingAverage_4(DM103, 5, DM203, R3)

; DM200~DM203：滤波后的值
; R0~R3：数据准备好标志
```

### 示例 4：PID 控制器

**需求：**
实现标准的 PID 控制算法。

**在 Claude Code 中输入：**
```
创建 PID 控制器功能块项目 PIDControllerDemo：

功能块名称：PIDController

输入参数：
- SetPoint：设定值（INT）
- ProcessValue：过程值（INT）
- Kp：比例系数（INT，放大 100 倍，如 150 表示 1.5）
- Ki：积分系数（INT，放大 100 倍）
- Kd：微分系数（INT，放大 100 倍）
- Enable：使能信号（BOOL）

输出参数：
- ControlValue：控制输出（INT，范围 0~1000）
- AtSetPoint：是否到达设定值（BOOL）

内部变量：
- Error：当前误差
- LastError：上次误差
- Integral：积分累积
- Derivative：微分项
- Output：输出值（未限幅）

功能：
实现标准 PID 算法：
Output = Kp * Error + Ki * Integral + Kd * Derivative

包含：
- 积分限幅（防止积分饱和）
- 输出限幅（0~1000）
- Enable = 0 时复位积分

在主程序中用于温度控制，SetPoint = 800。
```

### 示例 5：状态机功能块

**需求：**
可配置的状态机功能块。

**在 Claude Code 中输入：**
```
创建状态机功能块项目 StateMachineDemo：

功能块名称：StateMachine

输入参数：
- Start：启动信号（BOOL）
- Pause：暂停信号（BOOL）
- Resume：继续信号（BOOL）
- Stop：停止信号（BOOL）
- Reset：复位信号（BOOL）

输出参数：
- State：当前状态（INT，0=待机,1=运行,2=暂停,3=完成）
- IsRunning：是否运行中（BOOL）
- IsPaused：是否暂停（BOOL）
- IsCompleted：是否完成（BOOL）

内部变量：
- LastState：上一状态（INT）

功能：
- 待机 + Start → 运行
- 运行 + Pause → 暂停
- 暂停 + Resume → 运行
- 运行/暂停 + Stop → 完成
- 任意状态 + Reset → 待机

主程序中控制 3 个独立的工位，每个工位一个状态机实例。
```

## 功能块最佳实践

### 1. 参数设计

**输入参数：**
- ✅ 只读，不在功能块内修改
- ✅ 传递控制信号和配置参数
- ✅ 使用有意义的名称

**输出参数：**
- ✅ 只写，在功能块内更新
- ✅ 返回状态和计算结果
- ✅ 包含数据有效标志

**内部变量：**
- ✅ 保存功能块的状态
- ✅ 实例间独立
- ✅ 不对外暴露

### 2. 命名规范

```
功能块名称：大驼峰，如 EdgeDetect、MovingAverage
参数名称：大驼峰，如 InputValue、WindowSize
内部变量：小驼峰或下划线，如 lastInput、buffer_index
```

### 3. 错误处理

```
在功能块中添加错误检测：

功能块名称：SafeDivide

输入：
- Dividend：被除数（INT）
- Divisor：除数（INT）

输出：
- Result：结果（INT）
- Error：错误标志（BOOL，除零错误时为 1）

功能：
- 如果 Divisor = 0，Error = 1，Result = 0
- 否则，Error = 0，Result = Dividend / Divisor
```

### 4. 功能块测试

创建测试项目：

```
创建功能块测试项目 TestMovingAverage：

功能：
1. 生成测试输入序列：
   - 0, 100, 200, 300, 400, 500（递增）
   - 500, 500, 500, 500, 500（稳态）
   - 500, 400, 300, 200, 100（递减）

2. 调用 MovingAverage 功能块，WindowSize = 5

3. 记录每个周期的：
   - 输入值
   - 输出值
   - DataReady 标志

4. 输出到 DM1000~ 供监控
```

### 5. 文档化

让 AI 生成功能块文档：

```
为 MovingAverage 功能块生成文档：

包含：
- 功能说明
- 参数列表（输入/输出/内部）
- 算法描述
- 使用示例
- 注意事项

保存为 modules/FB_MovingAverage/README.md
```

## 功能块组合

### 级联功能块

```
创建级联滤波项目 CascadeFilterDemo：

功能：
输入 → 消抖 → 移动平均 → 限幅 → 输出

具体：
1. Debounce 功能块：消除输入抖动
2. MovingAverage 功能块：平滑信号
3. Limiter 功能块：限制输出范围

创建 3 个功能块，在主程序中依次调用。
```

**主程序逻辑：**
```
; 原始输入
MOV EM1:CH0, DM100

; 第 1 级：消抖
CALL Debounce_1(DM100, 50, DM101)

; 第 2 级：移动平均
CALL MovingAverage_1(DM101, 5, DM102, R0)

; 第 3 级：限幅
CALL Limiter_1(DM102, 0, 1000, DM103)

; DM103 为最终输出
```

### 嵌套功能块

```
创建一个复合功能块 SmartSensor：

SmartSensor 功能块内部调用：
- EdgeDetect：检测传感器连接状态变化
- Debounce：消抖
- MovingAverage：滤波
- RangeCheck：范围检查

输入：
- RawInput：原始传感器值（INT）
- MinValue：有效范围下限（INT）
- MaxValue：有效范围上限（INT）

输出：
- FilteredValue：滤波后的值（INT）
- IsValid：数据有效标志（BOOL）
- IsConnected：传感器连接标志（BOOL）
- OutOfRange：超出范围标志（BOOL）
```

**注意：** KEYENCE 功能块的嵌套调用需要注意：
- 每个功能块需要独立定义
- 内部调用的功能块也需要导入
- 管理好实例名称，避免冲突

## 功能块库

### 创建自己的功能块库

```
创建一个通用功能块库项目 CommonFBLibrary，包含：

1. 信号处理类：
   - EdgeDetect：边沿检测
   - Debounce：消抖
   - MovingAverage：移动平均
   - MedianFilter：中值滤波
   - RateLimit：速率限制

2. 控制类：
   - PIDController：PID 控制器
   - OnOffController：开关控制器
   - Hysteresis：滞环控制

3. 逻辑类：
   - StateMachine：状态机
   - Sequencer：顺序控制器
   - Timer：定时器封装

4. 数学类：
   - SafeDivide：安全除法
   - Saturate：饱和限幅
   - Scale：线性缩放

每个功能块包含：
- MNM 源文件
- 参数表
- README 文档
- 测试用例

将功能块保存到独立的模板目录，方便在新项目中导入。
```

### 导入功能块库

在新项目中使用：

```
创建新项目 MyProject，从 CommonFBLibrary 导入：
- EdgeDetect
- MovingAverage
- PIDController

在主程序中应用到温度控制回路。
```

## 功能块调试

### 调试策略

**1. 隔离测试**

为每个功能块创建独立的测试项目：

```
创建 MovingAverage 的测试项目：
- 使用固定的测试输入序列
- 验证输出是否符合预期
- 测试边界条件（WindowSize = 2, 10）
- 测试异常输入（负数、超大值）
```

**2. 添加调试输出**

```
在 MovingAverage 功能块中添加调试输出：
- Debug_Index：当前索引（DM9000）
- Debug_Sum：当前总和（DM9001）
- Debug_Count：样本计数（DM9002）

在测试时监控这些变量，验证内部逻辑。
```

**3. 逐步验证**

```
分步测试 PIDController：

第 1 步：只测试比例项（Ki = 0, Kd = 0）
第 2 步：添加积分项（Kd = 0）
第 3 步：添加微分项
第 4 步：测试完整 PID
```

### 常见问题

**问题 1：功能块未找到**

**症状：**
```
编译错误：功能块 'MyFB' 未定义
```

**原因：**
- 功能块 MNM 未正确导入
- MODULE_TYPE 不是 2

**解决：**
```
检查功能块定义：
- 确认 scaffold.model.json 中有该功能块模块
- 确认 MODULE_TYPE: 2
- 重新生成并导入
```

**问题 2：参数传递错误**

**症状：**
```
编译错误：参数数量不匹配
```

**原因：**
- 调用时的参数个数与定义不符
- 参数顺序错误

**解决：**
```
检查功能块调用：
- 核对参数表（fb_arguments.tsv）
- 确认参数顺序：输入参数在前，输出参数在后
- 修正调用语句
```

**问题 3：实例变量冲突**

**症状：**
```
运行异常：多个实例相互干扰
```

**原因：**
- 内部变量使用了全局地址
- 实例间共享了状态

**解决：**
AI 会自动为每个实例分配独立的内部变量地址。如果遇到问题：
```
重新生成功能块，确保内部变量对每个实例独立分配。
```

## 高级主题

### 递归功能块

KEYENCE 不直接支持递归，但可以用循环实现：

```
创建阶乘计算功能块（使用循环）：

功能块名称：Factorial

输入：
- N：输入值（INT，范围 0~10）

输出：
- Result：N! 的结果（INT）
- Overflow：溢出标志（BOOL）

使用循环实现，不使用递归。
```

### 可变参数功能块

KEYENCE 功能块参数固定，但可以用数组模拟：

```
创建多输入求和功能块：

功能块名称：SumN

输入：
- InputArray[10]：输入数组（INT）
- Count：有效输入个数（INT，范围 1~10）

输出：
- Sum：总和（INT）

功能：
对 InputArray 的前 Count 个元素求和。
```

### 泛型功能块（模拟）

通过命名规范模拟泛型：

```
创建一组类型特化的滤波功能块：
- MovingAverage_INT：处理 INT 型
- MovingAverage_DINT：处理 DINT 型
- MovingAverage_REAL：处理 REAL 型

每个功能块算法相同，只是参数类型不同。
```

## 下一步

- 📋 学习 [变量管理](variables.md)
- 🏗️ 理解 [脚手架模型](../architecture/scaffold-model.md)
- 🔧 查看 [修复现有项目](repair-project.md)

---

**需要帮助？** 查看 [故障排除](troubleshooting.md) 或 [提交 Issue](https://github.com/xxrust/KeyenceAgent/issues)。
