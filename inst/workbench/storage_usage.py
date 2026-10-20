"""Read-only, bounded project accounting. Never follows links or deletes data."""
import os
import stat
import time
from pathlib import Path


def project_storage(root, max_entries=100000, seconds=2):
    root = Path(root)
    totals = {}
    files = entries = links = 0
    partial = False
    started = time.monotonic()
    pending = [(root, 'root')]
    while pending:
        directory, category = pending.pop()
        try:
            fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                listing = os.scandir(fd)
            except BaseException:
                os.close(fd)
                del fd
                raise
            with listing:
                for item in listing:
                    entries += 1
                    if entries > max_entries or time.monotonic() - started > seconds:
                        partial = True
                        pending.clear()
                        break
                    info = item.stat(follow_symlinks=False)
                    if stat.S_ISLNK(info.st_mode):
                        links += 1
                    elif stat.S_ISDIR(info.st_mode):
                        pending.append((directory / item.name, item.name if directory == root else category))
                    elif stat.S_ISREG(info.st_mode):
                        totals[category] = totals.get(category, 0) + info.st_size
                        files += 1
        except OSError:
            partial = True
        finally:
            if "fd" in locals():
                os.close(fd)
                del fd
    return {'schema': 'scagentkit.storage-usage.v1', 'logical_bytes': sum(totals.values()),
            'files': files, 'categories': totals, 'skipped_links': links, 'partial': partial,
            'notice': 'Local logical file sizes; a live snapshot, not allocated disk space. Partial totals are lower bounds. Nothing is deleted. Stop active work before copying the complete project for archival; preserve original inputs and the software environment separately.'}
