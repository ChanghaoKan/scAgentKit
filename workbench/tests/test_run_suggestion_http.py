"""Loopback suggestion contracts with explicit HTTP/R stand-ins; zero API/R."""
from __future__ import annotations

import copy
import http.client
import json
from pathlib import Path
import secrets
import sys
import tempfile
import threading
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from server import WorkbenchServer, main
from run_suggestion_runtime import RunSuggestionRuntime, SCHEMA
from store import StoreError


def binding(request=False):
    payload={'project_id':'literal-project','input_hash':'a'*64,'expected_revision':12,'suggestion_hash':'b'*64,'reviewer':'reviewer','reason':'Approve simulated aggregate preview'}
    if request:payload['request_id']='click-01'
    return payload


class ReviewFixture:
    csrf_token='scientific-token'
    def describe(self):
        return {'schema':'scagentkit.run-review.workbench.v1','csrf_token':self.csrf_token,'run':{'schema':'scagentkit.run.v1','project_id':'literal-project','input_hash':'a'*64,'revision':12,'status':'awaiting_configuration','stage':'strategy_propose'}}
    def decide(self,payload,token):return self.describe()


class SuggestionsFixture:
    csrf_token='suggestion-token'
    def __init__(self):self.operations=[];self.reads=0;self.job=None
    def describe(self):
        self.reads+=1
        return {'schema':SCHEMA,'enabled':True,'simulated':True,'csrf_token':self.csrf_token,'suggestion':{'schema':'scagentkit.run-suggestion.v1','project_id':'literal-project','input_hash':'a'*64,'revision':12,'suggestion_hash':'b'*64,'available':True,'status':'approved'},'job':self.job}
    def job_status(self):return self.job
    def operate(self,action,payload,token):
        if token!=self.csrf_token:raise StoreError('Suggestions require this server token',403)
        RunSuggestionRuntime.validate(action,payload)
        if action!='preview' and any(payload[k]!=binding(request=action=='request')[k] for k in ('project_id','input_hash','expected_revision','suggestion_hash')):raise StoreError('Stale exact suggestion scope',409)
        self.operations.append((action,copy.deepcopy(payload)))
        return self.describe()


class ContinueFixture:
    def __init__(self):self.active=False;self.calls=[]
    def describe(self,run=None):return {'job':{'status':'running'} if self.active else None}
    def submit(self,payload):self.calls.append(payload);return {'accepted':True}


class SuggestionHTTPTests(unittest.TestCase):
    def setUp(self):
        self.review=ReviewFixture();self.suggestions=SuggestionsFixture();self.continuation=ContinueFixture()
        self.server=WorkbenchServer(('127.0.0.1',0),None,None,run_review=self.review,run_continue=self.continuation,run_suggestion=self.suggestions)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.port=self.server.server_address[1]
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join(timeout=5)
    def request(self,method,path,payload=None,token='suggestion-token',headers=None):
        conn=http.client.HTTPConnection('127.0.0.1',self.port,timeout=5)
        request_headers={'Content-Type':'application/json','Origin':'http://127.0.0.1:%s'%self.port}
        if token is not None:request_headers['X-ScAgentKit-Suggestion-Token']=token
        request_headers.update(headers or {})
        body=json.dumps(payload or {}) if method=='POST' else None
        conn.request(method,path,body=body,headers=request_headers)
        response=conn.getresponse();raw=response.read();result=json.loads(raw);status=response.status;response_headers=dict(response.getheaders());conn.close()
        return status,result,response_headers

    def test_normal_inspect_declares_operator_enabled_and_get_preview_never_requests(self):
        status,view,_=self.request('GET','/api/run-review/inspect')
        self.assertEqual(status,200);self.assertTrue(view['suggestion_enabled'])
        status,view,headers=self.request('GET','/api/run-review/suggestion')
        self.assertEqual(status,200);self.assertEqual(view['schema'],SCHEMA)
        self.assertEqual(self.suggestions.operations,[]);self.assertEqual(self.suggestions.reads,1)
        self.assertEqual(headers['Cache-Control'],'no-store');self.assertIn("connect-src 'self'",headers['Content-Security-Policy'])

    def test_allowlisted_routes_fixed_payloads_and_request_async202(self):
        for action in ('preview','approve','request','adopt','discard'):
            payload={} if action=='preview' else binding(request=action=='request')
            status,view,_=self.request('POST','/api/run-review/suggestion/'+action,payload)
            self.assertEqual(status,202 if action=='request' else 200)
            self.assertEqual(view['schema'],SCHEMA)
        self.assertEqual([op[0] for op in self.suggestions.operations],['preview','approve','request','adopt','discard'])
        status,_,_=self.request('POST','/api/run-review/suggestion/retry',binding(True))
        self.assertEqual(status,409);self.assertEqual(len(self.suggestions.operations),5)

    def test_provider_endpoint_script_key_and_budget_browser_fields_fail_closed(self):
        for field in ('provider','endpoint','code','api_key','chat_fn','budget','rscript','project_dir','simulate'):
            status,_,_=self.request('POST','/api/run-review/suggestion/request',dict(binding(True),**{field:'malicious literal'}))
            self.assertEqual(status,422)
        self.assertEqual(self.suggestions.operations,[])

    def test_origin_host_csrf_and_stale_binding_rejected_before_request(self):
        for headers in ({'Origin':'https://evil.invalid'},{'Host':'evil.invalid'},{'Sec-Fetch-Site':'cross-site'}):
            status,_,_=self.request('POST','/api/run-review/suggestion/request',binding(True),headers=headers)
            self.assertEqual(status,403)
        for token in (None,'scientific-token','incorrect'):
            status,_,_=self.request('POST','/api/run-review/suggestion/request',binding(True),token=token)
            self.assertEqual(status,403)
        for fields in ({'expected_revision':11},{'input_hash':'d'*64},{'suggestion_hash':'d'*64},{'project_id':'foreign'}):
            status,_,_=self.request('POST','/api/run-review/suggestion/request',dict(binding(True),**fields))
            self.assertEqual(status,409)
        self.assertEqual(self.suggestions.operations,[])

    def test_other_active_worker_blocks_suggestion_and_active_suggestion_blocks_continue(self):
        self.continuation.active=True
        status,_,_=self.request('POST','/api/run-review/suggestion/request',binding(True));self.assertEqual(status,409)
        self.continuation.active=False;self.suggestions.job={'status':'running'}
        status,_,_=self.request('POST','/api/run-review/continue',{},headers={'X-ScAgentKit-Run-Token':'scientific-token'})
        self.assertEqual(status,409);self.assertEqual(self.continuation.calls,[])
        status,_,_=self.request('POST','/api/run-review/decision',{},headers={'X-ScAgentKit-Run-Token':'scientific-token'})
        self.assertEqual(status,409)

    def test_disabled_operator_mode_declares_false_and_cannot_dispatch(self):
        self.server.run_suggestion=None
        status,view,_=self.request('GET','/api/run-review/inspect');self.assertEqual(status,200);self.assertFalse(view['suggestion_enabled'])
        status,_,_=self.request('GET','/api/run-review/suggestion');self.assertEqual(status,409)
        status,_,_=self.request('POST','/api/run-review/suggestion/request',binding(True));self.assertEqual(status,409)
        self.assertEqual(self.suggestions.operations,[])

    def test_registered_child_reuses_same_component_frozen_parent_has_no_suggestion_writes(self):
        child_review=ReviewFixture();child_review.project=Path('/operator-registered-child');child_review.library=None;child_review.rscript='Rscript'
        scoped=MagicMock();scoped.child_context.return_value=(child_review,None,None)
        scoped.readiness.return_value={'frozen':True,'parent_run':{'project_id':'literal-project'}}
        self.server.run_subcluster=scoped;self.server.run_suggestion=None;self.server.model_suggestion_options={'simulate':True,'worker_timeout':300}
        status,_,_=self.request('POST','/api/run-review/suggestion/request',binding(True));self.assertEqual(status,409)
        with patch('server.RunSuggestionRuntime',return_value=self.suggestions) as construct:
            status,view,_=self.request('GET','/api/run-review/inspect?child_id=literal-child');self.assertEqual(status,200);self.assertTrue(view['suggestion_enabled'])
            status,_,_=self.request('GET','/api/run-review/suggestion?child_id=literal-child');self.assertEqual(status,200)
            status,_,_=self.request('POST','/api/run-review/suggestion/request?child_id=literal-child',binding(True));self.assertEqual(status,409)
            construct.assert_called_once_with(child_review.project,None,'Rscript',simulate=True,worker_timeout=300)
        self.assertEqual(scoped.child_context.call_count,2)
        for query in ('project_dir=/arbitrary','child_id=a&child_id=b','child_id=','child_id=a&provider=x'):
            status,_,_=self.request('GET','/api/run-review/suggestion?'+query);self.assertEqual(status,422)


class OperatorSuggestionCLITests(unittest.TestCase):
    def test_flags_require_run_project_valid_timeout_and_exclusive_mode(self):
        for args in (['--project','fixture','--model-mock'],['--run-project','fixture','--model-mock','--model-suggestions'],['--run-project','fixture','--model-timeout','0'],['--run-project','fixture','--subcluster-inherit-model']):
            with self.subTest(args=args),self.assertRaises(SystemExit) as error:main(args)
            self.assertEqual(error.exception.code,2)

    def test_operator_childinherit_and_mock_are_fixed_server_configuration(self):
        fake_server=MagicMock();fake_server.server_address=('127.0.0.1',18099)
        scope=MagicMock();scope.readiness.return_value={'frozen':True,'parent_run':{'status':'complete','revision':50}}
        with patch('server.QCRuntime'),patch('server.RunReviewRuntime'),patch('server.RunContinueRuntime') as continuation,patch('server.RunSuggestionRuntime') as model,patch('server.RunSubclusterRuntime',return_value=scope) as children,patch('server.WorkbenchServer',return_value=fake_server) as server:
            main(['--run-project','operator-parent','--subcluster-workspace','operator-childworkspace','--subcluster-inherit-model','--local-continue','--model-mock'])
        children.assert_called_once_with('operator-parent','operator-childworkspace',None,'Rscript',True,inherit_model=True)
        continuation.assert_not_called();model.assert_not_called()
        self.assertEqual(server.call_args.kwargs['model_suggestion_options'],{'simulate':True,'worker_timeout':300})
        self.assertIsNone(server.call_args.kwargs['run_suggestion'])


if __name__=='__main__':unittest.main()
