# EtherNet/IP Snapshot Fixture

`KVX样例程序_v100` contains the EtherNet/IP connection and assignment data used
by the live snapshot regression. The test copies this directory under its run
output and reads the copy, leaving the fixture unchanged.

The baseline was captured from the verified snapshot sample project. A live
run requires KV STUDIO; it reads the configured connection and assignment
table and does not connect to a PLC.
