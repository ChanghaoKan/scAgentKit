"""Installed public R entry, separate R processes, reuse/restart and authority."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from store import scrub_secrets

ROOT = Path(__file__).resolve().parents[2]


class RStartTests(unittest.TestCase):
    def test_installed_entry_without_terminal_or_notes_and_bound_reopen(self):
        rscript = shutil.which("Rscript")
        if not rscript: self.skipTest("Rscript unavailable")
        env = scrub_secrets(dict(os.environ))
        available = subprocess.run([rscript,"--vanilla","-e",
            'quit(status=if(requireNamespace("scAgentKit",quietly=TRUE)&&"sc_start" %in% getNamespaceExports("scAgentKit"))0L else 42L)'],env=env,capture_output=True,timeout=30)
        if available.returncode == 42: self.skipTest("Current R start entry not installed")
        self.assertEqual(available.returncode,0,available.stderr)
        pids=set()
        with tempfile.TemporaryDirectory() as temporary:
            base=Path(temporary); input_path=base/"a.rds"; project=base/"project"
            def run(code,*args):
                return subprocess.run([rscript,"--vanilla","-e",code,*map(str,args)],
                    cwd=base,env=env,capture_output=True,timeout=120)
            made=run('data("pbmc_small",package="SeuratObject");saveRDS(pbmc_small,commandArgs(TRUE)[1])',input_path)
            self.assertEqual(made.returncode,0,made.stderr)
            invoke='library(scAgentKit);a<-commandArgs(TRUE);x<-sc_start(a[1],a[2],browse=FALSE%s);cat(jsonlite::toJSON(x,auto_unbox=TRUE),"\\n")'
            def start(extra):
                result=run(invoke%extra,input_path,project,ROOT)
                self.assertEqual(result.returncode,0,result.stderr.decode())
                value=json.loads(result.stdout.decode().splitlines()[-1]);pids.add(value["pid"]);return value
            try:
                first=start(',context=list(species="human",tissue="Blood",research_goal="Offline entry validation",columns=list(sample="orig.ident"))')
                self.assertFalse(first["reused"])
                policy=run('library(scAgentKit);s<-getFromNamespace(".sc_run_load","scAgentKit")(commandArgs(TRUE)[1]);stopifnot(is.null(s$config$scientific_review),identical(s$config$basic_expression_review$panel_set,"blood"))',project)
                self.assertEqual(policy.returncode,0,policy.stderr.decode())
                protected=[project/"state.rds",*sorted((project/"checkpoints").glob("*.rds"))]
                hashes=lambda:{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
                before=hashes()
                again=start('')
                self.assertTrue(again["reused"]);self.assertEqual(again["pid"],first["pid"])
                for extra in (',context=list(species="mouse")',',reuse_processed=TRUE',',cluster_column="foreign"'):
                    rejected=run(invoke%extra,input_path,project,ROOT)
                    self.assertNotEqual(rejected.returncode,0)
                    self.assertEqual(hashes(),before)
                other=base/"other.rds";shutil.copyfile(input_path,other)
                rejected=run(invoke%'',other,project,ROOT)
                self.assertNotEqual(rejected.returncode,0);self.assertEqual(hashes(),before)
                os.kill(first["pid"],signal.SIGTERM)
                restarted=start('')
                self.assertFalse(restarted["reused"]);self.assertNotEqual(restarted["pid"],first["pid"])
                self.assertEqual(hashes(),before)
            finally:
                for pid in pids:
                    try: os.kill(pid,signal.SIGTERM)
                    except ProcessLookupError: pass


if __name__=="__main__":unittest.main()
