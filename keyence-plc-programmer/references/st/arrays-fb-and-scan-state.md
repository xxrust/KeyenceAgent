# KV ST 数组、FB 与扫描状态

用于数组边界、边沿检测器、定时器、FIFO、复位及跨扫描状态。程序体不写 `VAR...END_VAR`；FB 实例和局部状态需在工程变量表中定义。

## 数组边界与聚合接口

```st
udiStart := LOWER_BOUND(ARR := auiData, DIM := 1);
udiEnd := UPPER_BOUND(ARR := auiData, DIM := 1);
udiSum := 0;
FOR idx := udiStart TO udiEnd BY 1 DO
    udiSum := udiSum + auiData[idx];
END_FOR;

udiCount := GetAryCount(In := auiData, Dim := 1);
rSum := UDINT_TO_REAL(ArySum(auiData[0], udiCount));
```

`ArySum`、FIFO 等常见接口使用首元素和数量，而不是数组对象。仅在工程确认下界为 0 时使用 `[0]`；否则传真实首元素或先查询 KEYENCE 文档。空数组须先保护，避免无效下标或除零。

## 有状态 FB

```st
R_TRIG1(CLK := xFlag, Q => xRisingEdge);
F_TRIG1(CLK := xFlag, Q => xFallingEdge);
IF xRisingEdge THEN
    uiData := 10;
END_IF;
IF xFallingEdge THEN
    uiData := 20;
END_IF;

TON1(In := xExecute, PT := tSettingTime);
F_TRIG_Execute(CLK := xExecute);
IF F_TRIG_Execute.Q THEN
    tMeasured := TON1.ET;
END_IF;
```

`R_TRIG`、`F_TRIG`、`TON` 和用户 FB 是有状态实例，应保留实例并按扫描周期调用；只在触发分支调用会破坏状态更新。定时器下降沿采样的调用顺序以及 `IN := FALSE` 时 `ET` 的清零时机可能影响结果，应以目标系列/版本资料或编译运行证据确认。

## FIFO 与数组操作

```st
IF _FirstScanOn THEN
    udiMaxCount := GetAryCount(In := auiTable, Dim := 1);
END_IF;
R_TRIG_Write(CLK := xWrite);
R_TRIG_Insert(CLK := xInsert);
R_TRIG_Delete(CLK := xDelete);

FIFORead(EN := R_TRIG_Write.Q AND (udiDataNum = udiMaxCount),
         Table := auiTable[0], MaxDataNum := udiMaxCount,
         DataNum := udiDataNum, Dst => uiOldData);
FIFOWrite(EN := R_TRIG_Write.Q, In := uiNewData,
          MaxDataNum := udiMaxCount, DataNum := udiDataNum,
          Table := auiTable[0]);
FIFOInsert(EN := R_TRIG_Insert.Q AND (udiDataNum < udiMaxCount),
           In := uiNewData, MaxDataNum := udiMaxCount,
           DataNum := udiDataNum, Table := auiTable[0], Pos := udiInsertPos);
FIFODelete(EN := R_TRIG_Delete.Q, Table := auiTable[0],
           MaxDataNum := udiMaxCount, DataNum := udiDataNum, Pos := udiDeletePos);
```

队列已满且要求覆盖最旧值时，先读出再写入。`AryShiftL`、`AryShiftR`、`BlockMove`、`DataSearch` 的长度单位、边界和重叠行为应依对应 KEYENCE 版本资料确认，不能按宿主语言接口推断。

## 初始化与复用边界

```st
IF _FirstScanOn THEN
    StructReset(stData);
    AryReset(auiData[0], 10);
END_IF;
```

确认数组边界和容量后再初始化。FB 内部状态放 FB 局部变量；与设备、轴或业务相关的映射放调用方变量/自变量，不把固定软元件泄漏进可复用 FB。用户 FB 的变量接口和导入检查按本 skill 的 FB 规则及校验脚本执行。
