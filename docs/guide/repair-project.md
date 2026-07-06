# 修复现有项目

本指南说明如何使用 KeyenceAgent 修改、调试和修复已有的 KV STUDIO 项目。

## 概述

修复现有项目的基本流程：

```
导出项目 → 分析问题 → 修改代码/变量 → 生成修复脚手架 → 导入验证
```

**适用场景：**
- ✅ 编译错误修复
- ✅ 逻辑错误调试
- ✅ 功能增强
- ✅ 变量重构
- ✅ 性能优化

## 准备工作

### 1. 备份原项目

**手动备份：**
```powershell
# 复制项目文件
Copy-Item "C:\Projects\MyProject.kpr" "C:\Backup\MyProject_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').kpr"
```

**使用 KV STUDIO 备份：**
1. 打开项目
2. 文件 → 另存为
3. 保存到备份目录

### 2. 导出项目内容

```
使用 /kv-studio-operator 导出项目 MyProject：

项目路径：C:\Projects\MyProject.kpr

导出内容：
1. 所有模块的 MNM 文件
2. 全局变量表
3. 局部变量表
4. 功能块定义和参数
5. 项目配置

生成项目清单 project_inventory.json。
```

**AI 会生成：**
```
MyProject_export/
├── modules/
│   ├── MAIN/
│   │   ├── MAIN.mnm
│   │   └── variables.tsv
│   ├── STANDBY/
│   │   └── STANDBY.mnm
│   └── FB_MyFunction/
│       ├── FB_MyFunction.mnm
│       └── fb_arguments.tsv
├── project_inventory.json
└── config.json
```

## 修复编译错误

### 示例 1：变量未定义错误

**症状：**
```
编译错误：
MAIN.mnm 行 25: 变量 'TempSensor5' 未定义
MAIN.mnm 行 30: 变量 'PressureValue' 未定义
```

**修复步骤：**

**在 Claude Code 中：**
```
修复项目编译错误：

项目路径：C:\Projects\MyProject.kpr

错误信息：
- 行 25: TempSensor5 未定义
- 行 30: PressureValue 未定义

请：
1. 导出当前项目
2. 分析缺失的变量
3. 在变量表中补充定义
4. 重新导入并编译验证
```

**AI 执行过程：**

1. **导出项目**
   ```
   ✓ 导出 MAIN.mnm
   ✓ 导出变量表
   ```

2. **分析代码**
   ```
   发现 TempSensor5 在 MAIN.mnm 行 25 使用：
     LD TempSensor5
     > 800
     OUT HighTempAlarm
   
   推断：TempSensor5 应为 INT 型，表示温度传感器
   建议地址：DM304（DM300~DM303 已被使用）
   ```

3. **修复变量表**
   ```
   添加：
   DM304, INT, "温度传感器5"
   DM305, INT, "压力值"
   ```

4. **重新导入**
   ```
   ✓ 导入更新后的变量表
   ✓ 编译通过
   ```

**结果：**
```
✅ 修复成功

编译结果：
  转换结果 OK
  错误数量: 0
  警告数量: 0

修改内容：
  - 添加变量 DM304: TempSensor5
  - 添加变量 DM305: PressureValue
```

### 示例 2：指令语法错误

**症状：**
```
编译错误：
MAIN.mnm 行 15: 指令 'MOVV' 不存在
```

**修复：**
```
修复指令语法错误：

项目：C:\Projects\MyProject.kpr
错误：行 15 'MOVV' 指令不存在

请：
1. 查询正确的 KEYENCE 指令
2. 修正 MNM 文件
3. 重新导入编译
```

**AI 会：**
1. 查询知识库确认正确指令是 `MOV`
2. 修改 MAIN.mnm 行 15：`MOVV` → `MOV`
3. 重新导入并验证

### 示例 3：功能块调用错误

**症状：**
```
编译错误：
MAIN.mnm 行 40: 功能块 'AverageFilter' 参数数量不匹配
期望 3 个参数，实际 2 个
```

**修复：**
```
修复功能块调用错误：

项目：C:\Projects\MyProject.kpr
错误：AverageFilter 参数数量不匹配

请：
1. 检查功能块定义（fb_arguments.tsv）
2. 修正调用语句
3. 确保参数顺序正确
```

**AI 会：**
1. 检查 `FB_AverageFilter/fb_arguments.tsv`
2. 发现需要 3 个参数：InputValue, WindowSize, OutputValue
3. 修正调用：`CALL AverageFilter_1(DM100, 5, DM200)`

## 修复逻辑错误

### 示例 4：输出逻辑错误

**问题描述：**
```
项目功能异常：

预期：按下启动按钮（DM100.00），电机启动（R0 = 1）；
      按下停止按钮（DM100.01），电机停止（R0 = 0）

实际：按下启动按钮后，电机无法启动

项目路径：C:\Projects\MotorControl.kpr
```

**修复：**
```
调试项目逻辑错误：

项目：C:\Projects\MotorControl.kpr

问题：启动按钮无效

请：
1. 导出 MAIN.mnm
2. 分析启动逻辑
3. 找出问题原因
4. 修复并重新导入
```

**AI 分析：**
```
导出的 MAIN.mnm 行 10-15：

10: LD DM100.00
11: AND/ DM100.01    ; 停止按钮取反
12: OUT R0
13:
14: ; 问题：缺少自锁逻辑
15: ; 按钮释放后，R0 会立即变为 0
```

**AI 修复：**
```
修改后的逻辑：

10: LD DM100.00      ; 启动按钮
11: OR R0            ; 自锁
12: AND/ DM100.01    ; 停止按钮取反
13: OUT R0
```

**验证：**
```
✅ 修复成功

逻辑验证：
  - 按下启动：R0 = 1
  - 释放启动：R0 保持 1（自锁）
  - 按下停止：R0 = 0
```

### 示例 5：定时逻辑错误

**问题：**
```
定时器功能异常：

预期：按下启动后延时 5 秒启动电机
实际：按下启动后立即启动电机

项目：C:\Projects\DelayStart.kpr
```

**修复：**
```
调试定时逻辑：

项目：C:\Projects\DelayStart.kpr

问题：延时未生效

请分析并修复定时器逻辑。
```

**AI 分析和修复：**
```
问题原因：
  使用了 TMR T0, 50（50个扫描周期，约 50ms）
  应该使用：TMR T0, 5000（5000ms = 5秒）

修改：
  行 20: TMR T0, 50 → TMR T0, 5000
```

## 功能增强

### 示例 6：添加新功能

**需求：**
```
为现有项目添加计数功能：

项目：C:\Projects\ProductionLine.kpr

新功能：
1. 添加产品计数器（每次启动计数 +1）
2. 当计数达到 100 时报警
3. 提供手动复位功能

不影响现有的启停控制逻辑。
```

**在 Claude Code 中：**
```
为项目添加计数功能：

项目：C:\Projects\ProductionLine.kpr

新增需求：
1. 计数器：DM200（INT）
2. 报警输出：R10（BOOL）
3. 复位按钮：DM100.02（BOOL）

逻辑：
- 启动按钮（DM100.00）上升沿时，DM200 + 1
- DM200 >= 100 时，R10 = 1
- 按下复位按钮时，DM200 = 0，R10 = 0

请导出项目，添加新功能，重新导入。
```

**AI 执行：**

1. **导出现有项目**
2. **分析现有代码**，确定插入位置
3. **添加新变量**：
   ```
   DM200, INT, "产品计数器"
   R10, BIT, "计数报警"
   DM100.02, BIT, "复位按钮"
   ```
4. **添加新逻辑**：
   ```
   ; 上升沿检测
   LD DM100.00
   UP
   JMPN NO_COUNT
   INC DM200        ; 计数 +1
   NO_COUNT:
   
   ; 报警判断
   LD DM200
   >= 100
   OUT R10
   
   ; 复位
   LD DM100.02
   JMPN NO_RESET
   MOV 0, DM200
   LD 0
   OUT R10
   NO_RESET:
   ```
5. **导入验证**

### 示例 7：添加功能块

**需求：**
```
为现有项目添加滤波功能：

项目：C:\Projects\SensorMonitor.kpr

需求：
1. 导入 MovingAverage 功能块
2. 对 4 路温度传感器（DM300~DM303）应用滤波
3. 滤波后的值存储到 DM400~DM403
4. 不影响原有的报警逻辑
```

**修复：**
```
为项目添加滤波功能块：

项目：C:\Projects\SensorMonitor.kpr

步骤：
1. 导出项目
2. 添加 MovingAverage 功能块模块
3. 在主程序中调用 4 个实例
4. 修改报警逻辑使用滤波后的值
5. 重新导入验证
```

**AI 会：**
1. 生成 `FB_MovingAverage` 模块
2. 在主程序适当位置插入调用：
   ```
   ; 读取原始传感器值
   MOV EM1:CH0, DM300
   MOV EM1:CH1, DM301
   MOV EM1:CH2, DM302
   MOV EM1:CH3, DM303
   
   ; 应用滤波
   CALL MovingAverage_1(DM300, 5, DM400)
   CALL MovingAverage_2(DM301, 5, DM401)
   CALL MovingAverage_3(DM302, 5, DM402)
   CALL MovingAverage_4(DM303, 5, DM403)
   
   ; 报警逻辑使用滤波后的值
   LD DM400
   > 800
   OR/ DM401
   > 800
   ...
   OUT R0
   ```

## 变量重构

### 示例 8：重新分配变量地址

**问题：**
```
项目变量地址混乱：

当前状态：
- DM50: 温度传感器1
- DM200: 温度传感器2
- DM5: 温度传感器3
- DM1000: 温度传感器4

需求：
将所有温度传感器集中到 DM300~DM303，保持功能不变。
```

**修复：**
```
重构项目变量地址：

项目：C:\Projects\MessyProject.kpr

重新分配方案：
- DM50 → DM300
- DM200 → DM301
- DM5 → DM302
- DM1000 → DM303

请：
1. 导出项目
2. 全局替换地址引用
3. 更新变量表
4. 重新导入验证
```

**AI 会：**
1. 在所有 MNM 中查找并替换：
   ```
   DM50 → DM300
   DM200 → DM301
   DM5 → DM302
   DM1000 → DM303
   ```
2. 更新变量表注释
3. 验证无地址冲突
4. 重新导入

### 示例 9：变量类型更改

**需求：**
```
变量类型升级：

当前：DM100（INT，范围 -32768~32767）
需求：改为 DINT（范围更大）

涉及的操作都需要更新。
```

**注意：** KEYENCE 的变量类型变更可能影响地址分配（DINT 占用 2 个字）。AI 会提示：

```
⚠️ 类型变更影响分析：

DM100 (INT) → DM100-DM101 (DINT)

影响：
1. DM101 将被占用
2. 如果 DM101 已被使用，需要先移动
3. 所有使用 DM100 的指令需要更新为 DINT 指令

建议：
- 确认 DM101 未被使用
- 或选择其他地址（如 DM500-DM501）

是否继续？
```

## 性能优化

### 示例 10：优化扫描周期

**问题：**
```
项目扫描周期过长：

当前扫描周期：15ms
目标：< 10ms

请分析并优化程序。
```

**优化：**
```
优化项目扫描周期：

项目：C:\Projects\SlowProject.kpr

分析：
1. 识别耗时操作
2. 优化计算逻辑
3. 减少不必要的操作
4. 建议使用更高效的指令

生成优化报告。
```

**AI 可能的优化：**
1. **合并重复计算**
2. **使用批量指令**（如 BMOV 替代多个 MOV）
3. **减少跳转次数**
4. **优化循环逻辑**

## 项目快照和对比

### 创建快照

```
创建项目快照：

项目：C:\Projects\MyProject.kpr

快照内容：
1. 所有 MNM 文件的哈希值
2. 变量表版本
3. 编译结果
4. 项目配置

保存为：snapshots/snapshot_20240706_123456.json
```

### 对比快照

```
对比项目变更：

基线快照：snapshots/snapshot_20240701.json
当前项目：C:\Projects\MyProject.kpr

报告：
1. 新增/删除的模块
2. 修改的 MNM（行级对比）
3. 变量变更
4. 配置变更

生成差异报告 diff_report.md。
```

**示例报告：**
```
项目变更报告
═══════════════

模块变更：
  + FB_NewFilter（新增）
  
MNM 变更：
  MAIN.mnm:
    行 25: + LD DM304
    行 26: + > 800
    行 27: + OUT R15
  
变量变更：
  + DM304, INT, "新增传感器"
  + R15, BIT, "新增报警"
  
编译结果：
  变更前：0 错误，2 警告
  变更后：0 错误，0 警告
```

## 批量修复

### 多项目批量修复

```
批量修复多个项目：

项目列表：
1. C:\Projects\Project1.kpr
2. C:\Projects\Project2.kpr
3. C:\Projects\Project3.kpr

统一修改：
- 将所有项目中的 DM50（旧地址）改为 DM300
- 添加统一的错误处理逻辑
- 更新版本号到 v2.0

生成批量操作报告。
```

## 测试和验证

### 创建测试用例

```
为修复后的项目创建测试用例：

项目：C:\Projects\MyProject.kpr

测试场景：
1. 正常启动停止
2. 紧急停止
3. 边界条件测试
4. 异常处理测试

生成测试脚本和预期结果。
```

### 回归测试

```
运行回归测试：

项目：C:\Projects\MyProject.kpr

测试：
1. 重复创建项目 3 次
2. 每次验证编译通过
3. 对比生成的 artifacts
4. 确认一致性

使用 repeat runner 执行。
```

## 最佳实践

### 1. 修改前先备份
```powershell
# 自动备份脚本
$projectPath = "C:\Projects\MyProject.kpr"
$backupPath = "C:\Backup\MyProject_$(Get-Date -Format 'yyyyMMdd_HHmmss').kpr"
Copy-Item $projectPath $backupPath
```

### 2. 小步迭代
- ✅ 一次修改一个问题
- ✅ 修改后立即验证
- ✅ 记录每次修改内容

### 3. 保留修改历史
```
创建修改日志 CHANGELOG.md：

## v1.1 - 2024-07-06
- 修复：TempSensor5 未定义错误
- 新增：产品计数功能
- 优化：扫描周期从 15ms 降到 8ms

## v1.0 - 2024-07-01
- 初始版本
```

### 4. 测试覆盖
- ✅ 修改后的功能必须测试
- ✅ 相关的功能也要回归测试
- ✅ 边界条件不能忽略

### 5. 文档同步
```
修改代码的同时更新文档：
- TASK.md：任务描述
- VARIABLE_MAP.md：变量映射
- README.md：使用说明
```

## 常见问题

### 问题 1：导入快照过期

**症状：**
```
KV_SOURCE_SNAPSHOT_STALE
项目快照与当前状态不匹配
```

**解决：**
```
重新导出项目快照：

项目：C:\Projects\MyProject.kpr

更新快照后再进行修复。
```

### 问题 2：模块名称冲突

**症状：**
```
KV_MNM_SAME_NAME_IMPORT_REQUIRES_PREDELETE
模块 MAIN 已存在
```

**解决：**
AI 会自动：
1. 先删除旧模块
2. 再导入新模块

或者使用增量导入策略。

### 问题 3：变量粘贴未保存

**症状：**
```
KV_VARIABLE_PASTE_NOT_PERSISTED
变量表更新未生效
```

**解决：**
AI 会：
1. 检查粘贴格式
2. 重新生成 TSV
3. 使用备用粘贴方法

## 下一步

- 📘 学习 [创建新项目](new-project.md)
- 🧩 了解 [功能块开发](function-blocks.md)
- 📋 掌握 [变量管理](variables.md)

---

**需要帮助？** 查看 [故障排除](troubleshooting.md) 或 [提交 Issue](https://github.com/xxrust/KeyenceAgent/issues)。
