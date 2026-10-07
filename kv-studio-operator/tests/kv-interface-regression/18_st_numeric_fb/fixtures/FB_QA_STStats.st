// Fixed-size array aggregation with explicit FB inputs and outputs.
accumulator := LREAL#0.0;
IF Enable THEN
    FOR sampleIndex := 0 TO 3 DO
        accumulator := accumulator + Samples[sampleIndex];
    END_FOR;
    Sum := accumulator * Gain;
    Mean := Sum / LREAL#4.0;
    Valid := TRUE;
ELSE
    Sum := LREAL#0.0;
    Mean := 0.0;
    Valid := FALSE;
END_IF;
