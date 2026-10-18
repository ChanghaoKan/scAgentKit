"""Operator mode wiring and credential scoping without R, HTTP or providers."""
import json,os,tempfile,unittest
from pathlib import Path
from unittest.mock import patch,Mock
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import open_results as launcher

class ModelLauncherTests(unittest.TestCase):
    def test_modes_have_distinct_identities_and_only_explicit_configured_mode_keeps_named_key(self):
        for mode in ['off','configured','simulate']:
            with self.subTest(mode=mode),tempfile.TemporaryDirectory() as temporary:
                root=Path(temporary);calls=[]
                runtime=Mock();runtime.describe.return_value={'run':{'project_id':'literal-project','input_hash':'a'*64}}
                def launch(*args,**kwargs):
                    calls.append(kwargs)
                    (root/'.workbench-review-launcher/service.json').write_text(json.dumps({'port':12345,'pid':987654}))
                    return Mock(pid=987654,poll=lambda:None)
                with patch.object(launcher,'RunWorkbenchRuntime',return_value=runtime),patch.object(launcher,'probe',side_effect=lambda record,identity:record is not None),patch.object(launcher.subprocess,'Popen',side_effect=launch),patch.dict(os.environ,{'SCAGENTKIT_TEST_KEY':'SOFTWARE_SENTINEL_ONLY','UNRELATED_API_KEY':'DO_NOT_FORWARD'},clear=True):
                    launcher.open_results(root,browse=False,review_mode=True,model_mode=mode,key_env='SCAGENTKIT_TEST_KEY')
                config=json.loads((root/'.workbench-review-launcher/config.json').read_text())
                self.assertEqual(config['identity']['model_mode'],mode)
                self.assertNotIn('SOFTWARE_SENTINEL_ONLY',json.dumps(config))
                env=calls[0]['env'];self.assertTrue('UNRELATED_API_KEY' not in env,'Unrelated test credential forwarded')
                if mode=='configured':self.assertEqual(env['SCAGENTKIT_TEST_KEY'],'SOFTWARE_SENTINEL_ONLY')
                else:self.assertTrue('SCAGENTKIT_TEST_KEY' not in env,'Named test credential forwarded while disabled')
                launcher._LAUNCHED.pop(987654,None)
    def test_readonly_without_named_key_uses_allowlisted_environment(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);calls=[]
            runtime=Mock();runtime.describe.return_value={'run':{'project_id':'literal-project','input_hash':'a'*64}}
            def launch(*args,**kwargs):
                calls.append(kwargs)
                (root/'.workbench-launcher/service.json').write_text(json.dumps({'port':12345,'pid':987654}))
                return Mock(pid=987654,poll=lambda:None)
            with patch.object(launcher,'RunWorkbenchRuntime',return_value=runtime),patch.object(launcher,'probe',side_effect=lambda record,identity:record is not None),patch.object(launcher.subprocess,'Popen',side_effect=launch),patch.dict(os.environ,{'CUSTOM_PROVIDER_KEY':'SOFTWARE_SENTINEL_ONLY'},clear=True):
                launcher.open_results(root,browse=False)
            self.assertTrue('CUSTOM_PROVIDER_KEY' not in calls[0]['env'],'Unselected credential forwarded by readonly launcher')
            launcher._LAUNCHED.pop(987654,None)
    def test_readonly_cannot_enable_model_requests(self):
        with self.assertRaises(ValueError):launcher.open_results('.',review_mode=False,model_mode='configured')

if __name__=='__main__':unittest.main()
