# EtherCAT Live Fixture

`KVXEcTest` is the baseline project for the EtherCAT node live regression. The
test copies this directory under its run output before adding a node, so the
fixture remains unchanged.

The baseline was captured from the verified `KVXEcTest` scratch project. A live
run requires KV STUDIO and the EtherCAT catalog model `SV630_1Axis_03713`; it
does not connect to a PLC.
