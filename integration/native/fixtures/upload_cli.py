"""Uploads one archive through Platform Edge the way the export agent does, with the driver of flow F1 (f1_scenario.Upload). usage: upload_cli.py PROVIDER FILE DEVICE_CREDENTIAL [CHUNK_BYTES]

Prints the terminal operation as one JSON line {"operation_id", "status", "codes"} and exits 0 when the operation reached a terminal state, 1 otherwise. Environment: RATATOSKR_SMOKE_DIR, NATIVE_ROOT, EV (as for f1_scenario.py)."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f1_scenario as f1

provider, file, credential = sys.argv[1:4]
chunk = int(sys.argv[4]) if len(sys.argv) > 4 else 65536
upload = f1.Upload(provider, credential, file, chunk)
deadline = 150
import time

end = time.time() + deadline
while True:
    status, _ = upload.prepare()
    if status != 404 or time.time() > end:
        break
    time.sleep(3)
if status != 202:
    print(json.dumps({"operation_id": None, "status": f"prepare-{status}", "codes": []}))
    sys.exit(1)
upload.open()
for index in range(len(upload.chunks())):
    upload.put(index)
upload.finalize()
operation = upload.poll(240)
print(json.dumps({"operation_id": upload.op, "status": operation.get("status"), "codes": f1.warn_codes(operation)}))
sys.exit(0 if operation.get("status") in f1.TERMINAL else 1)
