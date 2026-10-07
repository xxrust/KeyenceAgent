# KV ST 控制流与数值

用于 CASE/循环、类型转换、统计和基础几何问题。这里只保留可复用的 KV ST 调用形状；程序变量及 FB 实例由 KV STUDIO 变量表定义，程序体不写 IEC 声明块。

## 控制流

```st
CASE uiMeasureData OF
    90..65535: strMessage := 'Upper limit error';
    81..89:    strMessage := 'Upper limit alarm';
    20..80:    strMessage := 'Normal';
    10..19:    strMessage := 'Lower limit alarm';
    0..9:      strMessage := 'Lower limit error';
END_CASE;

R_TRIG1(CLK := xExecute);
IF R_TRIG1.Q THEN
    FOR i := 0 TO (nData - 1) BY 1 DO
        rTmp := (UINT_TO_REAL(auiData[i]) - rAverage) ** 2 + rTmp;
    END_FOR;
END_IF;
```

`WHILE ... END_WHILE` 与 `REPEAT ... UNTIL ... END_REPEAT` 可用于有界循环。循环变量、累加器和退出边界必须在每次请求时初始化，并与实际数组容量一致；避免扫描周期中无退出条件的循环。

## 转换与数值

```st
diRoundValue := TRUNC_DINT(rValue + 0.5);
udiAbsValue := ABS(diValue);
rAverage := UINT_TO_REAL(ArySum(auiData[0], nData)) / nData;
iInData := (10000 - 0) * (iAnalogData - 1000) / (5000 - 1000);
iScalingVal := LIMIT(0, iInData, 10000);
```

整数与 REAL 运算间显式转换。`TRUNC_DINT` 是向零截断；`rValue + 0.5` 仅表达常见非负数舍入，不是任意正负数的通用 ROUND。除数和 `ArySum` 的数量须做范围/零值保护。官方 ST 样例使用 `**` 表示幂。

## 统计与几何

```st
rSUM := UINT_TO_REAL(ArySum(auiData[0], nData));
rAverage := rSUM / nData;
rTmp := 0.0;
FOR i := 0 TO (nData - 1) BY 1 DO
    rTmp := rTmp + (UINT_TO_REAL(auiData[i]) - rAverage) ** 2;
END_FOR;
rVariance := rTmp / nData;
rSD := SQRT(rVariance);

rDistance := SQRT((astPoint[1].diX - astPoint[0].diX) ** 2
                + (astPoint[1].diY - astPoint[0].diY) ** 2);
```

只有确认一维数组下界为 0 时才将首元素写成 `[0]`。批量聚合通常以首元素和数量为参数；否则先取 `LOWER_BOUND`/`UPPER_BOUND` 并按真实下界访问。边沿触发的统计须在每次新请求时清零累加器；不要让扫描循环重复累加。

几何计算的角度单位、坐标系、`ATAN2` 参数顺序和整数结果精度都应按目标 CPU/项目证据确认。遇到未确认函数、负数舍入或溢出语义时，转 `kv-studio-kb-programming` 查证，不按其他 PLC 的习惯替换。
