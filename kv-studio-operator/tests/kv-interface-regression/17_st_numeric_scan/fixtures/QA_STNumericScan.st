// Numeric arrays and bounded ST loops; deterministic declaration smoke.
sampleValues[0] := 1.0;
sampleValues[1] := 2.0;
sampleValues[2] := 3.0;
sampleValues[3] := 4.0;
sampleMean := 0.0;
weightedSum := LREAL#0.0;
FOR sampleIndex := 0 TO 3 DO
    preciseValues[sampleIndex] := sampleValues[sampleIndex];
    sampleMean := sampleMean + sampleValues[sampleIndex];
    weightedSum := weightedSum + preciseValues[sampleIndex] * (sampleIndex + 1);
END_FOR;
sampleMean := sampleMean / 4.0;
