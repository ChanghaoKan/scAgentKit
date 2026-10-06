"""Durable async suggestion mechanism; real Python children, simulated R, zero API."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_suggestion_runtime as module
from run_suggestion_runtime import RunSuggestionRuntime
from store import StoreError

FAKE_R = r'''#!/usr/bin/env python3
import json, os, pathlib, sys, tempfile, time
operation=sys.argv[3]; project=pathlib.Path(sys.argv[4]); request=pathlib.Path(sys.argv[5]); output=pathlib.Path(sys.argv[6])
payload=json.loads(request.read_text()); descriptor=json.loads((project/'fixture.json').read_text()); mode=json.loads((project/'mode.json').read_text())
def atomic(path,value):
 fd,tmp=tempfile.mkstemp(dir=path.parent)
 with os.fdopen(fd,'w') as f: json.dump(value,f)
 os.replace(tmp,path)
call={'operation':operation,'pid':os.getpid(),'present_keys':[k for k in %s if os.environ.get(k)],'profiles':[os.environ.get(k) for k in ('R_PROFILE','R_PROFILE_USER','R_ENVIRON','R_ENVIRON_USER')],'simulation':payload.get('simulate'),'payload_fields':sorted(payload)}
with (project/'calls.jsonl').open('a') as f: f.write(json.dumps(call)+'\n')
if operation=='suggestion_request':
 atomic(project/'fake-ledger.json',{'dispatch':'sent_simulated','usage':'unknown','hold':True})
 time.sleep(mode.get('sleep',0.03))
 if mode.get('request')=='exit': sys.exit(7)
 if mode.get('request')=='badjson': output.write_text('{truncated'); sys.exit(0)
 descriptor.update(revision=descriptor['revision']+1,status='failed' if mode.get('request')=='truncated' else 'validated',can_request=False,can_adopt=mode.get('request')!='truncated',candidate=None if mode.get('request')=='truncated' else {'schema':'typed-fixture'})
 descriptor['response']={'status':'truncated' if mode.get('request')=='truncated' else 'ok','cost_state':'held_unknown' if mode.get('request')=='truncated' else 'known_zero','simulated':True}
 if mode.get('request')!='truncated': atomic(project/'fake-ledger.json',{'dispatch':'sent_simulated','usage':'known_zero','hold':False})
 atomic(project/'fixture.json',descriptor)
 run=json.loads((project/'status.json').read_text());run['revision']=descriptor['revision'];atomic(project/'status.json',run)
elif operation=='suggestion_approve':
 descriptor.update(revision=descriptor['revision']+1,status='approved',can_approve=False,can_request=True);atomic(project/'fixture.json',descriptor)
 run=json.loads((project/'status.json').read_text());run['revision']=descriptor['revision'];atomic(project/'status.json',run)
elif operation=='suggestion_adopt':
 descriptor.update(revision=descriptor['revision']+1,status='adopted',can_adopt=False,can_request=False);atomic(project/'fixture.json',descriptor)
 run=json.loads((project/'status.json').read_text());run.update(revision=descriptor['revision'],status='awaiting_review');atomic(project/'status.json',run)
if mode.get('foreign'): descriptor['project_id']='foreign'
atomic(output,{'ok':True,'result':descriptor,'error':None})
''' % repr(module.KEYS)


@unittest.skipIf(module.fcntl is None, 'POSIX flock required')
class SuggestionRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='scagentkit-suggestion-mechanism-')
        self.root = Path(self.temp.name)
        self.project = self.root / 'project'; self.project.mkdir()
        (self.project / 'state.rds').write_bytes(b'explicit-simulated-R-authority')
        self.run = {'schema':'scagentkit.run.v1','project_id':'project-literal','input_hash':'a'*64,'revision':9,'status':'awaiting_configuration','stage':'strategy_propose'}
        module._atomic(self.project/'status.json',self.run)
        self.descriptor = {'schema':'scagentkit.run-suggestion.v1','project_id':'project-literal','input_hash':'a'*64,'revision':9,'kind':'strategy','available':True,'blocked_reason':None,'suggestion_hash':'b'*64,'status':'approved','preview':{'request_hash':'c'*64,'provider':{'name':'mock','model':'simulated','generation':{},'external':False,'reservation_usd':0,'pricing':{},'api_key_env':None},'external':False,'simulated':True,'system_prompt':'Simulated aggregate-only fixture','user_prompt':'No raw cells or barcodes','budget':{'max_usd':0}},'candidate':None,'response':None,'can_approve':False,'can_request':True,'can_adopt':False,'can_discard':False}
        module._atomic(self.project/'fixture.json',self.descriptor)
        module._atomic(self.project/'mode.json',{})
        self.fake = self.root/'fake-rscript'; self.fake.write_text(FAKE_R); self.fake.chmod(0o700)
        self.runtime = RunSuggestionRuntime(self.project,rscript=str(self.fake),simulate=True)
        self.payload = {'project_id':'project-literal','input_hash':'a'*64,'expected_revision':9,'suggestion_hash':'b'*64,'reviewer':'local-reviewer','reason':'Explicit simulated mechanism test','request_id':'click-001'}

    def tearDown(self):
        for process in list(self.runtime._workers.values()):
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=5)
        self.temp.cleanup()

    def calls(self, operation=None):
        path=self.project/'calls.jsonl'
        calls=[json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        return [call for call in calls if operation is None or call['operation']==operation]

    def mode(self, **fields): module._atomic(self.project/'mode.json',fields)

    def terminal(self, runtime=None):
        runtime=runtime or self.runtime
        deadline=time.monotonic()+12
        while time.monotonic()<deadline:
            job=runtime.job_status()
            if job and job['status'] in module.TERMINAL:
                return runtime.describe()
            time.sleep(.02)
        self.fail('Simulated worker did not reach a terminal record')

    def test_preview_readonly_never_dispatches_and_uses_secret_free_environment(self):
        with patch.dict(os.environ,{name:'SIMULATED-ENV-SENTINEL' for name in module.KEYS}):
            before=hashlib.sha256((self.project/'state.rds').read_bytes()).hexdigest()
            view=self.runtime.describe()
        self.assertEqual(view['schema'],module.SCHEMA)
        self.assertEqual(self.calls()[0]['operation'],'suggestion_preview')
        self.assertEqual(self.calls()[0]['present_keys'],[])
        self.assertEqual(self.calls()[0]['profiles'],[os.devnull]*4)
        self.assertEqual(before,hashlib.sha256((self.project/'state.rds').read_bytes()).hexdigest())
        self.assertIsNone(view['job']);self.assertEqual(self.calls('suggestion_request'),[])

    def test_browser_configuration_and_invalid_binding_fields_rejected_before_worker(self):
        bad=[{},dict(self.payload,provider={'name':'deepseek'}),dict(self.payload,endpoint='https://invalid'),dict(self.payload,code='system()'),dict(self.payload,simulate=False),dict(self.payload,expected_revision=True),dict(self.payload,suggestion_hash='C'*64),dict(self.payload,request_id='bad\nline')]
        with patch.object(module.subprocess,'Popen') as launch:
            for payload in bad:
                with self.subTest(payload=payload),self.assertRaises(StoreError): self.runtime.submit(payload)
            launch.assert_not_called()
        self.assertEqual(list((self.runtime.base/'jobs').iterdir()),[])

    def test_exact_snapshot_stale_input_revision_and_unapproved_hash_fail_closed(self):
        for fields in ({'expected_revision':8},{'input_hash':'d'*64},{'project_id':'foreign'},{'suggestion_hash':'d'*64}):
            with self.subTest(fields=fields),self.assertRaises(StoreError): self.runtime.submit(dict(self.payload,**fields))
        self.assertEqual(self.calls('suggestion_request'),[])

    def test_csrf_required_for_all_mutations(self):
        for token in (None,'bad-token'):
            with self.assertRaises(StoreError): self.runtime.operate('request',self.payload,token)
        self.assertEqual(self.calls(),[])
        self.runtime.operate('request',self.payload,self.runtime.csrf_token)
        self.assertEqual(self.terminal()['job']['status'],'succeeded')

    def test_duplicate_click_different_request_id_and_reload_reuse_one_job(self):
        self.mode(sleep=.35)
        first=self.runtime.submit(self.payload)
        second=self.runtime.submit(dict(self.payload,request_id='click-002'))
        self.assertEqual(first['job']['job_id'],second['job']['job_id']);self.assertTrue(second['duplicate'])
        fresh=RunSuggestionRuntime(self.project,rscript=str(self.fake),simulate=True)
        with patch.object(fresh,'_call_suggestion',side_effect=AssertionError('Active polling must not spawn R')):
            poll=fresh.describe()
        self.assertEqual(poll['job']['job_id'],first['job']['job_id'])
        done=self.terminal(fresh)
        replay=fresh.submit(self.payload)
        self.assertEqual(done['job']['status'],'succeeded');self.assertTrue(replay['duplicate'])
        self.assertEqual(len(self.calls('suggestion_request')),1)

    def test_completed_scope_different_new_request_id_never_recharges(self):
        self.runtime.submit(self.payload);self.terminal()
        replay=self.runtime.submit(dict(self.payload,request_id='newtab-completed'))
        self.assertTrue(replay['duplicate']);self.assertEqual(replay['job']['status'],'succeeded')
        self.assertEqual(len(self.calls('suggestion_request')),1)

    def test_saved_receipt_after_changed_input_never_reauthorizes_actions(self):
        self.runtime.submit(self.payload);self.terminal()
        run=module._read(self.project/'status.json');run.update(input_hash='d'*64,revision=30)
        module._atomic(self.project/'status.json',run)
        replay=self.runtime.submit(self.payload)
        self.assertTrue(replay['historical_receipt']);self.assertTrue(replay['suggestion']['replay_only'])
        self.assertTrue(all(replay['suggestion'][name] is False for name in ('can_approve','can_request','can_adopt','can_discard')))
        self.assertEqual(len(self.calls('suggestion_request')),1)

    def test_request_id_reuse_for_different_fields_rejected(self):
        self.runtime.submit(self.payload);self.terminal()
        with self.assertRaises(StoreError):self.runtime.submit(dict(self.payload,reason='different binding'))

    def test_foreign_mock_and_custom_provider_require_operator_policy(self):
        self.descriptor['preview']['provider']['name']='deepseek';module._atomic(self.project/'fixture.json',self.descriptor)
        with self.assertRaises(StoreError):self.runtime.submit(self.payload)
        other=RunSuggestionRuntime(self.project,rscript=str(self.fake),simulate=False)
        self.descriptor['preview']['provider']['name']='custom';module._atomic(self.project/'fixture.json',self.descriptor)
        with self.assertRaises(StoreError):other.submit(self.payload)
        self.assertEqual(self.calls('suggestion_request'),[])

    def test_named_saved_provider_key_only_reaches_request_worker_never_disk_or_preview(self):
        self.descriptor['preview'].update(external=True,simulated=False)
        self.descriptor['preview']['provider'].update(name='deepseek',model='fake-http-free',external=True,api_key_env='DEEPSEEK_API_KEY')
        module._atomic(self.project/'fixture.json',self.descriptor)
        runtime=RunSuggestionRuntime(self.project,rscript=str(self.fake),simulate=False)
        self.runtime=runtime
        sentinel='SIMULATED-PRIVATE-CREDENTIAL-SENTINEL'
        with patch.dict(os.environ,{**{key:sentinel for key in module.KEYS},'UNRELATED_SECRET':sentinel}):
            runtime.describe();runtime.submit(self.payload);self.terminal(runtime)
        previews=self.calls('suggestion_preview');requests=self.calls('suggestion_request')
        self.assertTrue(all(call['present_keys']==[] for call in previews))
        self.assertEqual(requests[0]['present_keys'],['DEEPSEEK_API_KEY'])
        for path in self.runtime.base.rglob('*'):
            if path.is_file():self.assertNotIn(sentinel.encode(),path.read_bytes())
        self.assertNotIn('request_id',requests[0]['payload_fields'])

    def test_truncated_json_response_is_durable_failure_no_retry_and_simulated_hold(self):
        self.mode(request='truncated')
        self.runtime.submit(self.payload);view=self.terminal()
        self.assertEqual(view['job']['status'],'failed');self.assertTrue(view['job']['requires_reconciliation'])
        self.assertFalse(view['job']['retry_permitted']);self.assertFalse(view['suggestion']['can_request'])
        ledger=json.loads((self.project/'fake-ledger.json').read_text());self.assertTrue(ledger['hold'])
        self.runtime.submit(dict(self.payload,request_id='again'))
        self.assertEqual(len(self.calls('suggestion_request')),1)
        self.assertEqual(view['suggestion']['response']['cost_state'],'held_unknown')

    def test_bad_response_persists_sanitized_failure_no_auto_retry(self):
        self.mode(request='badjson');self.runtime.submit(self.payload);view=self.terminal()
        self.assertEqual(view['job']['status'],'failed');self.assertEqual(view['job']['dispatch_state'],'unknown_hold_possible')
        self.runtime.describe();self.runtime.describe();self.assertEqual(len(self.calls('suggestion_request')),1)

    def test_early_request_process_exit_persists_failure_no_auto_retry(self):
        self.mode(request='exit');self.runtime.submit(self.payload);view=self.terminal()
        self.assertEqual(view['job']['status'],'failed');self.assertEqual(view['job']['dispatch_state'],'unknown_hold_possible')
        self.assertTrue(view['job']['requires_reconciliation'])
        self.runtime.submit(dict(self.payload,request_id='after-exit'));self.assertEqual(len(self.calls('suggestion_request')),1)

    def test_operator_timeout_kills_only_owned_process_and_retains_unknown_hold(self):
        self.runtime=RunSuggestionRuntime(self.project,rscript=str(self.fake),simulate=True,worker_timeout=1)
        self.mode(sleep=3)
        self.runtime.submit(self.payload);view=self.terminal()
        self.assertEqual(view['job']['status'],'timed_out');self.assertTrue(view['job']['requires_reconciliation'])
        owner=module._read(module._job_dir(self.runtime.base,view['job']['job_id'])/'owner.json')
        self.assertFalse(module._alive(owner['r_pid']))
        self.assertTrue(json.loads((self.project/'fake-ledger.json').read_text())['hold'])
        self.runtime.submit(dict(self.payload,request_id='timeout-repeat'))
        self.assertEqual(len(self.calls('suggestion_request')),1)

    def test_request_worker_survives_http_owner_process_exit(self):
        self.mode(sleep=.4)
        command='import json,sys;from run_suggestion_runtime import RunSuggestionRuntime;r=RunSuggestionRuntime(sys.argv[1],rscript=sys.argv[2],simulate=True);print(json.dumps(r.submit(json.loads(sys.argv[3]))))'
        env=module._environment();env['PYTHONPATH']=str(module.ROOT);env['PYTHONPYCACHEPREFIX']=str(self.root/'pycache')
        result=subprocess.run([sys.executable,'-c',command,str(self.project),str(self.fake),json.dumps(self.payload)],env=env,capture_output=True,timeout=5)
        self.assertEqual(result.returncode,0,result.stderr)
        view=self.terminal(RunSuggestionRuntime(self.project,rscript=str(self.fake),simulate=True))
        self.assertEqual(view['job']['status'],'succeeded');self.assertEqual(len(self.calls('suggestion_request')),1)

    def test_killed_worker_and_r_child_reconcile_without_resending(self):
        self.mode(sleep=4)
        self.runtime.submit(self.payload)
        deadline=time.monotonic()+5
        owner=None
        while time.monotonic()<deadline:
            job=module._current(self.runtime.base)[0]
            owner=module._read(module._job_dir(self.runtime.base,job['job_id'])/'owner.json',optional=True)
            if owner and owner.get('r_pid') and self.calls('suggestion_request'):break
            time.sleep(.02)
        self.assertIsNotNone(owner);os.killpg(owner['r_pid'],signal.SIGKILL)
        process=next(iter(self.runtime._workers.values()));process.kill();process.wait(timeout=5)
        # Owned detached R child may be reaped by init slightly later.
        deadline=time.monotonic()+5
        while module._alive(owner['r_pid']) and time.monotonic()<deadline:time.sleep(.03)
        view=self.runtime.describe()
        self.assertEqual(view['job']['status'],'interrupted');self.assertTrue(view['job']['requires_reconciliation'])
        self.runtime.submit(dict(self.payload,request_id='crash-repeat'));self.assertEqual(len(self.calls('suggestion_request')),1)

    def test_launch_failure_stays_failed_and_replay_cannot_launch_again(self):
        # Preview subprocess.run uses Popen, so isolate only detached launch.
        real=module.subprocess.Popen
        def launcher(argv,*args,**kwargs):
            if argv[0]==sys.executable:raise OSError('Do not expose simulated credential error')
            return real(argv,*args,**kwargs)
        with patch.object(module.subprocess,'Popen',side_effect=launcher): first=self.runtime.submit(self.payload)
        self.assertEqual(first['job']['status'],'failed');self.assertEqual(first['job']['dispatch_state'],'not_started')
        replay=self.runtime.submit(dict(self.payload,request_id='launch-repeat'))
        self.assertTrue(replay['duplicate']);self.assertEqual(self.calls('suggestion_request'),[])

    def test_tampered_config_fails_closed(self):
        self.runtime.submit(self.payload);view=self.terminal()
        directory=module._job_dir(self.runtime.base,view['job']['job_id'])
        contents=json.loads((directory/'config.json').read_text());contents['payload']['suggestion_hash']='d'*64
        module._atomic(directory/'config.json',contents)
        with self.assertRaises(StoreError):self.runtime.describe()

    def test_replaced_and_symlink_job_directories_fail_closed(self):
        jobs=self.runtime.base/'jobs';renamed=self.runtime.base/'jobs-original'
        jobs.rename(renamed);jobs.symlink_to(renamed,target_is_directory=True)
        with self.assertRaises(StoreError):self.runtime.describe()

    def test_provider_credential_environment_cannot_be_execution_control(self):
        for name in ('PYTHONPATH','R_PROFILE_USER','LD_PRELOAD','DYLD_INSERT_LIBRARIES','PATH'):
            with self.subTest(name=name),self.assertRaises(StoreError):module._environment(key_name=name)

    def test_timeout_range_and_boolean_operator_settings_validated(self):
        for kwargs in ({'worker_timeout':0},{'worker_timeout':True},{'worker_timeout':3601},{'simulate':'yes'},{'threads':0}):
            with self.subTest(kwargs=kwargs),self.assertRaises(StoreError):RunSuggestionRuntime(self.project,rscript=str(self.fake),**kwargs)


if __name__=='__main__':unittest.main()
