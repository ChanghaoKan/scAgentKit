import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from storage_usage import project_storage

class StorageTests(unittest.TestCase):
    def test_counts_no_links_no_deletion_and_explicit_partial(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'checks').mkdir()
            (root/'checks'/'x').write_bytes(b'1234')
            (root/'y').write_bytes(b'12')
            (root/'link').symlink_to(root/'checks', target_is_directory=True)
            out = project_storage(root)
            self.assertEqual(out['logical_bytes'],6)
            self.assertEqual(out['files'],2)
            self.assertEqual(out['skipped_links'],1)
            self.assertFalse(out['partial'])
            self.assertEqual((root/'checks'/'x').read_bytes(),b'1234')
            self.assertTrue(project_storage(root,max_entries=1)['partial'])
