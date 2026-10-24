import contextlib
import importlib.util
import io
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location("export_typeless", Path(__file__).parents[1] / "export-typeless.py")
export_typeless = importlib.util.module_from_spec(spec)
spec.loader.exec_module(export_typeless)


class TypelessExportTests(unittest.TestCase):
    def test_merge_and_recording_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            recordings = source / "Recordings"
            (recordings / "nested").mkdir(parents=True)
            audio = recordings / "nested/sample.ogg"
            audio.write_bytes(b"fixture audio")
            (recordings / "nested/debug.pcm").write_bytes(b"fixture fragment")
            database = source / "typeless.db"
            with sqlite3.connect(database) as connection:
                connection.execute("""CREATE TABLE history (
                    id TEXT, created_at TEXT, refined_text TEXT, audio_local_path TEXT,
                    edited_text TEXT, edited_text_status TEXT, hasRevertedAI INTEGER
                )""")
                connection.execute("""CREATE TABLE history_v2 (
                    id TEXT, created_at TEXT, refined_text TEXT, audio_local_path TEXT,
                    mode_meta BLOB
                )""")
                connection.executemany("INSERT INTO history VALUES (?, ?, ?, ?, ?, ?, ?)", [
                    ("both", "2026-01-01", "old", str(audio), "user edit", "EXTRACTED", 1),
                    ("legacy", "2026-01-02", "legacy text", str(recordings / "missing.ogg"), "legacy edit", "EXTRACTED", 0),
                ])
                connection.executemany("INSERT INTO history_v2 VALUES (?, ?, ?, ?, ?)", [
                    ("both", "2026-01-01", "current", str(audio), b"binary metadata"),
                    ("current", "2026-01-03", "new text", None, None),
                ])
            original_database = database.read_bytes()
            destination = root / "export"

            with contextlib.redirect_stdout(io.StringIO()):
                export_typeless.export(source, destination)

            records = [json.loads(line) for line in (destination / "history.jsonl").read_text().splitlines()]
            self.assertEqual(len(records), 3)
            overlap = records[0]
            self.assertEqual(overlap["refined_text"], "current")
            self.assertEqual(overlap["edited_text"], "user edit")
            self.assertEqual(overlap["edited_text_status"], "EXTRACTED")
            self.assertEqual(overlap["hasRevertedAI"], 1)
            self.assertEqual(overlap["source_tables"], ["history", "history_v2"])
            self.assertEqual(overlap["mode_meta"], {"base64": "YmluYXJ5IG1ldGFkYXRh"})
            self.assertEqual(overlap["exported_audio_path"], "Recordings/nested/sample.ogg")
            self.assertEqual(records[1]["edited_text"], "legacy edit")
            manifest = json.loads((destination / "manifest.json").read_text())
            self.assertEqual(manifest["unique_records"], 3)
            self.assertEqual(manifest["records_with_audio"], 1)
            self.assertCountEqual(manifest["missing_audio_ids"], ["legacy", "current"])
            self.assertEqual(manifest["recording_files"], 2)
            self.assertEqual((destination / "Recordings/nested/sample.ogg").read_bytes(), b"fixture audio")
            self.assertEqual((destination / "Recordings/nested/debug.pcm").read_bytes(), b"fixture fragment")
            self.assertEqual(database.read_bytes(), original_database)


if __name__ == "__main__":
    unittest.main()
