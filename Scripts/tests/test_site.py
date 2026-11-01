"""Check the published website and, optionally, its running container."""

import json
import os
from html.parser import HTMLParser
from pathlib import Path
import re
import unittest
from urllib.error import HTTPError
from urllib.parse import unquote, urljoin, urlsplit
from urllib.request import Request, urlopen


SITE = Path(__file__).resolve().parents[2] / "marketing/site/dist"
PAGES = ("/", "/en/", "/download/", "/en/download/", "/guide/", "/privacy/", "/faq/", "/press/")
BASE_URL = os.environ.get("SAYKUKU_SITE_URL", "").rstrip("/")
REVISION = os.environ.get("SAYKUKU_SITE_REVISION", "")


class References(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = []

    def handle_starttag(self, tag, attrs):
        self.urls.extend(value for name, value in attrs if name in ("src", "href") and value)


class SiteTests(unittest.TestCase):
    def test_required_pages_exist(self):
        for route in PAGES:
            with self.subTest(route=route):
                self.assertTrue((SITE / route.lstrip("/") / "index.html").is_file())

    def test_internal_links_and_assets_exist(self):
        missing = []
        for page in SITE.rglob("*.html"):
            references = References()
            references.feed(page.read_text())
            route = "/" + page.relative_to(SITE).as_posix()
            for url in references.urls:
                if url.startswith("#"):
                    continue
                target = urlsplit(urljoin("https://say.anikuku.com" + route, url))
                if target.scheme != "https" or target.hostname != "say.anikuku.com":
                    continue
                path = SITE / unquote(target.path).lstrip("/")
                if not path.is_file() and not (path / "index.html").is_file():
                    missing.append(f"{page.relative_to(SITE)}: {url}")
        self.assertEqual(missing, [])

    def test_download_pages_match_the_legacy_feed(self):
        feed = json.loads((SITE / "ver.json").read_text())
        self.assertRegex(feed["version"], r"^\d+(?:\.\d+)+$")
        self.assertGreater(feed["build"], 0)
        self.assertEqual(feed["url"], "https://say.anikuku.com/download/")
        hashes = []
        for page in ("download/index.html", "en/download/index.html"):
            text = (SITE / page).read_text()
            with self.subTest(page=page):
                self.assertIn("SayKuku-" + feed["version"] + ".dmg", text)
                self.assertIn('data-umami-event-version="' + feed["version"] + '"', text)
                checksums = re.findall(r"<code>([a-f0-9]{64})</code>", text)
                self.assertEqual(len(checksums), 1)
                hashes.append(checksums)
        self.assertEqual(hashes[0], hashes[1])


@unittest.skipUnless(BASE_URL, "Set SAYKUKU_SITE_URL to test a running deployment")
class DeployedSiteTests(unittest.TestCase):
    def fetch(self, route):
        request = Request(BASE_URL + route, headers={"Cache-Control": "no-cache"})
        return urlopen(request, timeout=15)

    def test_health(self):
        with self.fetch("/healthz") as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read().strip(), b"ok")

    def test_pages_and_release_match_the_checkout(self):
        for route in PAGES:
            with self.subTest(route=route), self.fetch(route) as response:
                self.assertEqual(response.status, 200)
                self.assertIn(b"SayKuku", response.read())
        with self.fetch("/ver.json") as response:
            self.assertEqual(json.load(response), json.loads((SITE / "ver.json").read_text()))
            self.assertIn("no-store", response.headers.get("Cache-Control", ""))

    def test_assets_are_served_with_their_content_types(self):
        for path, mime in (("/assets/site.css", "text/css"), ("/assets/site.js", "application/javascript"), ("/assets/favicon.svg", "image/svg+xml")):
            with self.subTest(path=path), self.fetch(path) as response:
                self.assertEqual(response.headers.get_content_type(), mime)
                self.assertEqual(response.read(), (SITE / path.lstrip("/")).read_bytes())

    @unittest.skipUnless(REVISION, "Set SAYKUKU_SITE_REVISION to verify the deployed commit")
    def test_deployed_commit_matches_the_workflow(self):
        with self.fetch("/revision.txt") as response:
            self.assertEqual(response.read().decode().strip(), REVISION)
            self.assertIn("no-store", response.headers.get("Cache-Control", ""))

    def test_unknown_page_is_not_a_successful_homepage(self):
        with self.assertRaises(HTTPError) as failure:
            self.fetch("/this-page-does-not-exist")
        self.assertEqual(failure.exception.code, 404)
        failure.exception.close()


if __name__ == "__main__":
    unittest.main()
