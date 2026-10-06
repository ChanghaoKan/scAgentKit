"""The shared display helper is an explicit fixed local asset."""
import http.client
import sys
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server import WorkbenchServer


class GeneLinksHTTPTests(unittest.TestCase):
    def setUp(self):
        self.server = WorkbenchServer(("127.0.0.1", 0), None, None)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, route):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=5)
        connection.request("GET", route)
        response = connection.getresponse()
        result = response.status, response.read()
        connection.close()
        return result

    def test_exact_shared_helper_asset(self):
        status, body = self.request("/gene-links.js")
        self.assertEqual(status, 200)
        self.assertEqual(body, (Path(__file__).resolve().parents[1] / "static/gene-links.js").read_bytes())

    def test_exact_local_official_mapping_asset(self):
        status, body = self.request("/ortholog-map.js")
        self.assertEqual(status, 200)
        self.assertEqual(body, (Path(__file__).resolve().parents[1] / "static/ortholog-map.js").read_bytes())
        self.assertTrue(body.startswith(b"/* Public MGI"))

    def test_all_gene_display_pages_load_local_mapping_before_helper(self):
        for route, application in (("/index.html", b"/app.js"), ("/review", b"/review.js"), ("/workbench", b"/workbench.js")):
            status, body = self.request(route)
            self.assertEqual(status, 200)
            self.assertLess(body.index(b"/ortholog-map.js"), body.index(b"/gene-links.js"))
            self.assertLess(body.index(b"/gene-links.js"), body.index(application))
            self.assertNotIn(b"src=\"https://www.genecards.org", body)

    def test_asset_route_cannot_read_arbitrary_source(self):
        for route in ("/gene-links.js/../server.py", "/../gene-links.js", "/%67ene-links.js", "/gene-links.js.map", "/ortholog-map.js/../server.py", "/%6frtholog-map.js", "/ortholog-map.js.map", "/../ortholog-map.js"):
            self.assertEqual(self.request(route)[0], 404)

    def test_missing_or_symlink_mapping_asset_is_not_served(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            previous = self.server.static_dir
            try:
                self.server.static_dir = Path(directory)
                self.assertEqual(self.request("/ortholog-map.js")[0], 404)
                (Path(directory) / "ortholog-map.js").symlink_to(previous / "ortholog-map.js")
                self.assertEqual(self.request("/ortholog-map.js")[0], 404)
            finally:
                self.server.static_dir = previous


if __name__ == "__main__":
    unittest.main()
