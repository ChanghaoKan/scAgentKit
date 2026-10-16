"""Measure verified portable loads and first saved-result opens; no HTTP/model call."""
import csv
import resource
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "workbench"))
from project import ProjectLoader
from run_workbench_runtime import RunWorkbenchRuntime

root = Path(sys.argv[1]).resolve()
library = sys.argv[2]
rows = []
for n in (1000, 5000, 10000):
    scope = root / f"cells-{n}"
    for label, action in (
        ("portable_load", lambda: ProjectLoader(scope / "export").load()),
        ("open_complete_result", lambda: RunWorkbenchRuntime(scope / "run", library=library).describe()),
    ):
        for repeat in range(3):
            before = time.perf_counter()
            value = action()
            if label == "portable_load" and value is None:
                raise RuntimeError("Portable result did not load")
            rows.append(dict(cells=n, operation=label, repeat=repeat + 1,
                             seconds=time.perf_counter() - before,
                             process_peak_rss=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
                             child_peak_rss=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss))
            with (root / "web-timings.csv").open("w", newline="") as output:
                writer = csv.DictWriter(output, fieldnames=rows[0].keys())
                writer.writeheader()
                writer.writerows(rows)
print("All portable loads and saved-result opens returned successfully.")
print("RSS units: bytes on macOS, KiB on Linux; process lifetime high-water marks, not per-operation allocations.")
