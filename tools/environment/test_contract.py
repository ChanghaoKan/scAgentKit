"""Offline contracts for the evidence-backed release environment recipe."""
import hashlib,json,pathlib,unittest,io,tarfile,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
class Recipe(unittest.TestCase):
 def test_lock(self):
  x=json.loads((ROOT/'tools/environment/v0.6.0-linux.json').read_text())
  self.assertEqual(len(x['packages']),140)
  self.assertEqual(len({p['package'] for p in x['packages']}),140)
  self.assertEqual(x['R'],'4.5.2')
  self.assertEqual(len(x['base_recommended']),29)
  self.assertEqual(next(p['version'] for p in x['base_recommended'] if p['package']=='Matrix'),'1.7-4')
  bh=next(p for p in x['packages'] if p['package']=='BH')
  self.assertIn('p3m.dev',bh['original_ci_url']);self.assertIn('cran.r-project.org',bh['url'])
  self.assertTrue(bh['fallback_reason'])
  self.assertIn('@sha256:',x['container'])
  for p in x['packages']:
   self.assertRegex(p['sha256'],r'^[0-9a-f]{64}$')
   self.assertTrue(p['url'].startswith(('https://p3m.dev/','https://cran.r-project.org/','https://cloud.r-project.org/','https://codeload.github.com/','https://github.com/')))
  self.assertEqual(x['bioconductor_packages'],[])
  self.assertIsNone(x['ci_python_version'])
  self.assertEqual({r['runtime']:r['version'] for r in x['runtime_sources']},{'Python':'3.9.6','R':'4.5.2'})
  for r in x['runtime_sources']:self.assertRegex(r['sha256'],r'^[0-9a-f]{64}$')
 def test_tamper(self):
  import importlib.util,tempfile
  s=importlib.util.spec_from_file_location('fetch',ROOT/'tools/environment/fetch.py'); m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'x';p.write_bytes(b'changed')
   with self.assertRaises(ValueError):m.fetch({'packages':[{'file':'x','sha256':'0'*64,'url':'https://invalid.example/never-requested'}]},pathlib.Path(d))
 def test_archive_identity_and_dag(self):
  import audit
  with tempfile.TemporaryDirectory() as d:
   cache=pathlib.Path(d);items=[]
   for name,dependency in [('a','b (>= 2.0)'),('b','')]:
    raw=('Package: '+name+'\nVersion: 2.0\nImports: '+dependency+'\n').encode()
    p=cache/(name+'_2.0.tar.gz')
    with tarfile.open(p,'w:gz') as t:
     member=tarfile.TarInfo(name+'/DESCRIPTION');member.size=len(raw);t.addfile(member,io.BytesIO(raw))
    items.append(dict(package=name,version='2.0',file=p.name,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
   lock={'R':'4.5.2','packages':items};audit.audit(lock,cache)
   rows=(cache/'verified-install-order.tsv').read_text().splitlines()
   self.assertTrue(rows[1].startswith('b\t'));self.assertTrue(rows[2].startswith('a\t'))
   items[0]['version']='3.0'
   with self.assertRaisesRegex(ValueError,'Identity mismatch'):audit.audit(lock,cache)
   items[0]['version']='2.0';items.pop()
   with self.assertRaisesRegex(ValueError,'Unlocked dependency'):audit.audit(lock,cache)
if __name__=='__main__':unittest.main()
