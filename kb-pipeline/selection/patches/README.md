# Verification patches
Each verifier agent writes ONE json file here (list of objects). The coordinator merges them into the CSVs.
Object: {"file":"io_units.csv","model":"KV-C32XTD","field":"out_current_per_point",
         "old":"<current CSV value or ''>","new":"<value read from the PDF image>",
         "status":"confirmed|corrected|new|unreadable","source":"KVSHARDX3H.pdf PDF页56(印刷2-34)","note":"optional"}
