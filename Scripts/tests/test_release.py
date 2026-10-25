import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("release", Path(__file__).parents[1] / "release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.patch_root = patch.object(release, "ROOT", self.root)
        self.patch_root.start()
        self.addCleanup(self.patch_root.stop)
        self.dmg = self.root / "SayKuku-1.1.0.dmg"
        self.dmg.write_bytes(b"verified archive")
        self.feed = self.root / "ver.json"
        legacy = {"version": "1.1.0", "build": 20, "url": release.WEBSITE + "download/", "notes": "Release notes"}
        self.feed.write_text(json.dumps(legacy))
        self.appcast = self.root / "appcast.xml"
        self.appcast.write_text(f'<rss xmlns:sparkle="{release.SPARKLE}"><channel><item><sparkle:version>20</sparkle:version><sparkle:shortVersionString>1.1.0</sparkle:shortVersionString><enclosure url="{release.DOWNLOADS}{self.dmg.name}" length="{self.dmg.stat().st_size}" sparkle:edSignature="signature" /></item></channel></rss>')
        self.meta = {**legacy, "commit": "a" * 40, "dmg": str(self.dmg), "sha256": release.sha256(self.dmg),
                     "size": self.dmg.stat().st_size, "download_url": release.DOWNLOADS + self.dmg.name,
                     "website": release.WEBSITE, "appcast": str(self.appcast), "appcast_sha256": release.sha256(self.appcast),
                     "legacy_feed": str(self.feed), "legacy_sha256": release.sha256(self.feed), "ed_signature": "signature"}
        site = self.root / "marketing/site/dist"
        site.mkdir(parents=True)
        (site / "ver.json").write_text('{"version":"1.0.9"}')
        for name in ["download/index.html", "en/download/index.html", "index.html"]:
            file = site / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('Version 1.0.9 https://saykuku.ullrai.com/SayKuku-1.0.9.dmg 5.6 MB ' + "b" * 64 + '<h2>1.0.9 Release notes</h2><ul><li>Old notes</li></ul>')

    def test_versions(self):
        self.assertEqual(release.version_parts("1.2.0"), release.version_parts("1.2"))
        self.assertGreater(release.version_parts("1.10"), release.version_parts("1.9.9"))
        for invalid in ["v1.0", "1..2", "1/2", "1.2-beta"]:
            with self.assertRaises(ValueError):
                release.version_parts(invalid)

    def test_public_requests_identify_the_release_client(self):
        from unittest.mock import MagicMock
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b"feed"
        with patch.object(release.urllib.request, "urlopen", return_value=response) as open_url:
            self.assertEqual(release.read_url("https://example.test/feed"), b"feed")
            request = open_url.call_args.args[0]
            self.assertEqual(request.get_header("User-agent"), "SayKuku-Release/1.0")

    def test_feed_generation_failure_keeps_a_resumable_archive_checkpoint(self):
        import plistlib
        app = self.root / "SayKuku.app"
        (app / "Contents").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleShortVersionString": "1.1.0", "CFBundleVersion": "20", "SUPublicEDKey": "public"}))
        with patch.object(release, "optional_url", side_effect=ConnectionError("offline")):
            with self.assertRaises(ConnectionError):
                release.prepare(self.dmg, app, "Release notes", self.root, self.meta["commit"])
        checkpoint = self.root / "Dist/releases/1.1.0/release.json"
        metadata = json.loads(checkpoint.read_text())
        self.assertEqual(metadata["sha256"], release.sha256(self.dmg))
        def generate(args, **kwargs):
            self.appcast.replace(checkpoint.parent / "appcast.xml")
        with patch.object(release, "optional_url", return_value=None), patch.object(release, "run", side_effect=generate) as run, patch.object(release, "validate"):
            release.complete_preparation(checkpoint, self.root)
            self.assertEqual(run.call_count, 1)
            self.assertIn("generate_appcast", str(run.call_args.args[0][0]))
        completed = json.loads(checkpoint.read_text())
        self.assertEqual(completed["sha256"], metadata["sha256"])
        self.assertIn("ed_signature", completed)

    def test_preflight_rejects_old_version_and_build_before_authentication(self):
        with patch.object(release, "read_url", return_value=b'{"version":"1.0.9","build":19}'), patch.object(release, "run") as run:
            for version, build in [("1.0.9", 20), ("1.1.0", 19), ("1.1.0", 18)]:
                with self.assertRaises(ValueError):
                    release.preflight(version, build)
            run.assert_not_called()

    def test_legacy_build_is_read_from_mounted_archive_and_detached(self):
        import plistlib
        def command(args, **kwargs):
            if args[:2] == ["hdiutil", "attach"]:
                info = Path(args[-1]) / "SayKuku.app/Contents/Info.plist"
                info.parent.mkdir(parents=True)
                info.write_bytes(plistlib.dumps({"CFBundleVersion": "19"}))
        with patch.object(release, "read_url", return_value=b"old archive"), patch.object(release, "run", side_effect=command) as run:
            self.assertEqual(release.published_build({"version": "1.0.9"}), 19)
            self.assertEqual(run.call_args_list[-1].args[0][:2], ["hdiutil", "detach"])

    def test_archive_conflict_stops_without_writing(self):
        with patch.object(release, "existing_archive_matches", side_effect=ValueError("conflict")), patch.object(release, "put_object") as put:
            with self.assertRaises(ValueError):
                release.upload_archive(self.meta, {})
            put.assert_not_called()

    def test_matching_archive_is_reused(self):
        with patch.object(release, "existing_archive_matches", return_value=True), patch.object(release, "put_object") as put, patch.object(release, "verify_public") as verify:
            release.upload_archive(self.meta, {})
            put.assert_not_called()
            verify.assert_called_once_with(self.meta["download_url"], self.meta["sha256"])

    def test_new_archive_is_verified_after_upload(self):
        calls = []
        with patch.object(release, "existing_archive_matches", return_value=False), patch.object(release, "put_object", side_effect=lambda *a: calls.append("upload")), patch.object(release, "verify_public", side_effect=lambda *a: calls.append("verify")):
            release.upload_archive(self.meta, {})
        self.assertEqual(calls, ["upload", "verify"])

    def test_existing_archive_is_checked_at_r2_without_public_404_probe(self):
        def download(args, **kwargs):
            Path(args[args.index("--file") + 1]).write_bytes(self.dmg.read_bytes())
            return subprocess.CompletedProcess(args, 0)
        with patch.object(release.subprocess, "run", side_effect=download) as command, patch.object(release, "read_url") as public:
            self.assertTrue(release.existing_archive_matches(self.meta, {}))
            self.assertEqual(command.call_args.args[0][:4], ["wrangler", "r2", "object", "get"])
            public.assert_not_called()

    def test_origin_conflict_is_rejected_before_any_upload(self):
        def download(args, **kwargs):
            Path(args[args.index("--file") + 1]).write_bytes(b"different archive")
            return subprocess.CompletedProcess(args, 0)
        with patch.object(release.subprocess, "run", side_effect=download), patch.object(release, "put_object") as put:
            with self.assertRaisesRegex(ValueError, "different archive"):
                release.upload_archive(self.meta, {})
            put.assert_not_called()

    def test_only_origin_not_found_allows_a_new_upload(self):
        missing = subprocess.CompletedProcess([], 1, stdout="", stderr="The specified key does not exist.")
        denied = subprocess.CompletedProcess([], 1, stdout="", stderr="Authentication error")
        with patch.object(release.subprocess, "run", return_value=missing), patch.object(release, "read_url") as public:
            self.assertFalse(release.existing_archive_matches(self.meta, {}))
            public.assert_not_called()
        with patch.object(release.subprocess, "run", return_value=denied), patch.object(release, "put_object") as put:
            with self.assertRaises(subprocess.CalledProcessError):
                release.upload_archive(self.meta, {})
            put.assert_not_called()

    def test_site_fields_and_locales_come_from_one_metadata(self):
        output = self.root / "staged"
        release.stage_site(self.meta, output)
        for name in ["download/index.html", "en/download/index.html", "index.html"]:
            html = (output / name).read_text()
            for value in ["1.1.0", self.meta["sha256"], "0.0 MB", self.meta["download_url"]]:
                self.assertIn(value, html)
            self.assertNotIn("1.0.9", html)
            if "download/" in name:
                self.assertIn("<li>Release notes</li>", html)
                self.assertNotIn("Old notes", html)
        self.assertEqual((output / "ver.json").read_bytes(), self.feed.read_bytes())
        self.assertIn("1.0.9", (self.root / "marketing/site/dist/index.html").read_text())

    def test_tampered_archive_or_feed_fails_before_external_commands(self):
        for file in [self.dmg, self.feed, self.appcast]:
            original = file.read_bytes()
            file.write_bytes(original + b"tamper")
            with patch.object(release, "run") as run:
                with self.assertRaises(ValueError):
                    release.validate(self.meta, self.root)
                run.assert_not_called()
            file.write_bytes(original)

    def test_release_notes_are_escaped_on_both_download_pages(self):
        self.meta["notes"] = '- Fix <script>alert("x")</script> & preserve data'
        release.stage_site(self.meta, self.root / "staged")
        for name in ["download/index.html", "en/download/index.html"]:
            page = (self.root / "staged" / name).read_text()
            self.assertIn("&lt;script&gt;", page)
            self.assertNotIn("<script>", page)

    def test_tag_for_a_different_build_is_rejected(self):
        with patch.object(release, "run"), patch.object(release.subprocess, "check_output", return_value=self.meta["commit"]), patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout="another-commit\n")):
            with self.assertRaisesRegex(ValueError, "different build"):
                release.validate(self.meta, self.root)

    def test_feed_field_mismatch_rejected_even_with_updated_file_hash(self):
        self.appcast.write_text(self.appcast.read_text().replace('length="16"', 'length="99"'))
        # Independently change a field regardless of the archive fixture's byte count.
        self.appcast.write_text(self.appcast.read_text().replace('edSignature="signature"', 'edSignature="other"'))
        self.meta["appcast_sha256"] = release.sha256(self.appcast)
        with patch.object(release, "run") as run:
            with self.assertRaises(ValueError):
                release.validate(self.meta, self.root)
            run.assert_not_called()

    def test_public_readback_retries_then_fails(self):
        with patch.object(release, "read_url", return_value=b"old"), patch.object(release.time, "sleep"), self.assertRaises(ValueError):
            release.verify_public("https://example.test/feed", hashlib.sha256(b"new").hexdigest())

    def publish_fixture(self, failure=None):
        events = []
        metadata = self.root / "release.json"
        metadata.write_text(json.dumps(self.meta))
        def output(args, **kwargs):
            if args[1:3] == ["branch", "--show-current"]:
                return "main\n"
            return ""
        def command(args, **kwargs):
            if args[0] == "npx":
                events.append("website")
                if failure == "website":
                    raise subprocess.CalledProcessError(1, args)
            return subprocess.CompletedProcess(args, 0)
        def upload(*args):
            events.append("archive")
            if failure == "archive":
                raise ValueError("upload/readback failed")
        def put(file, key, *args):
            events.append(key)
            if failure == key:
                raise ValueError("feed upload failed")
        def verify(url, digest):
            events.append("verified:" + url.rsplit("/", 1)[-1])
        with patch.object(release.subprocess, "check_output", side_effect=output), patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)), patch.object(release, "run", side_effect=command), patch.object(release, "deployment_config", return_value={"ZEABUR_PROJECT_ID": "project", "ZEABUR_SERVICE_ID": "service"}), patch.object(release, "validate"), patch.object(release, "read_url", return_value=b'{"version":"1.0.9","build":19}'), patch.object(release, "upload_archive", side_effect=upload), patch.object(release, "put_object", side_effect=put), patch.object(release, "verify_public", side_effect=verify):
            if failure:
                with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                    release.publish(metadata, self.root)
            else:
                release.publish(metadata, self.root)
        return events

    def test_publish_order_and_failure_recovery(self):
        events = self.publish_fixture()
        self.assertLess(events.index("archive"), events.index("website"))
        self.assertLess(events.index("verified:ver.json"), events.index("appcast.xml"))
        self.assertLess(events.index("appcast.xml"), events.index("ver.json"))
        self.assertEqual(json.loads((self.root / "marketing/site/dist/ver.json").read_text())["version"], "1.1.0")
        # Repeating a publication uses the same validated metadata and archive.
        self.publish_fixture()

    def test_failed_upload_never_deploys_website_or_feeds(self):
        self.assertEqual(self.publish_fixture("archive"), ["archive"])

    def test_failed_website_never_publishes_feeds_or_changes_local_site(self):
        self.assertEqual(self.publish_fixture("website"), ["archive", "website"])
        self.assertIn("1.0.9", (self.root / "marketing/site/dist/index.html").read_text())

    def test_failed_appcast_stops_legacy_feed_and_keeps_local_site(self):
        events = self.publish_fixture("appcast.xml")
        self.assertNotIn("ver.json", events)
        self.assertIn("1.0.9", (self.root / "marketing/site/dist/index.html").read_text())


if __name__ == "__main__":
    unittest.main()
