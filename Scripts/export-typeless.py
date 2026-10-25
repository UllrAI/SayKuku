#!/usr/bin/env python3
"""Export local Typeless history and recordings without modifying its database."""

import argparse
import base64
import csv
import hashlib
import json
import shutil
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


def export(source, destination):
    source, destination = source.resolve(), destination.resolve()
    if any(destination.is_relative_to(folder) for folder in [source, (source / "Recordings").resolve()]):
        raise ValueError("Export destination must be outside the source and recordings directories")
    destination.mkdir(parents=True, exist_ok=False)
    database = destination / "typeless.db"
    with sqlite3.connect((source / "typeless.db").as_uri() + "?mode=ro", uri=True) as original:
        with sqlite3.connect(database) as snapshot:
            original.backup(snapshot)

    recordings = destination / "Recordings"
    # Do not copy files outside the selected recordings tree through symbolic links.
    shutil.copytree(source / "Recordings", recordings, ignore=lambda directory, names: [
        name for name in names if (Path(directory) / name).is_symlink()
    ])
    with sqlite3.connect(database) as snapshot:
        snapshot.row_factory = sqlite3.Row
        assert snapshot.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        legacy = {row["id"]: dict(row) for row in snapshot.execute("SELECT * FROM history")}
        current = {row["id"]: dict(row) for row in snapshot.execute("SELECT * FROM history_v2")}

    records = []
    missing_audio = []
    for identifier in legacy.keys() | current.keys():
        old, new = legacy.get(identifier, {}), current.get(identifier, {})
        # Keep legacy-only edit fields; current rows take precedence for shared fields.
        record = {**old, **new}
        # Keep opaque/encrypted context and debug fields in the SQLite snapshot.
        for field in ("audio", "audio_context", "debug_info", "mic_device_info", "client_metadata"):
            record.pop(field, None)
        path = record.get("audio_local_path")
        relative = None
        if path:
            original_path = Path(path).resolve()
            try:
                relative = Path("Recordings") / original_path.relative_to((source / "Recordings").resolve())
            except ValueError:
                relative = Path("Recordings") / original_path.name
        if relative and (destination / relative).is_file():
            record["exported_audio_path"] = str(relative)
        else:
            record["exported_audio_path"] = None
            missing_audio.append(identifier)
        record["source_tables"] = [name for name, rows in (("history", legacy), ("history_v2", current)) if identifier in rows]
        records.append(record)
    records.sort(key=lambda record: (record.get("created_at") or "", record["id"]))

    with (destination / "history.jsonl").open("w") as output:
        for record in records:
            output.write(json.dumps(record, ensure_ascii=False,
                                    default=lambda value: {"base64": base64.b64encode(value).decode("ascii")}) + "\n")
    fields = ["id", "created_at", "mode", "status", "duration", "refined_text", "edited_text", "exported_audio_path"]
    with (destination / "history.csv").open("w", newline="", encoding="utf-8-sig") as output:
        writer = csv.DictWriter(output, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(records)

    inventory = []
    for path in sorted(recordings.rglob("*")):
        if path.is_file():
            inventory.append({"path": str(path.relative_to(destination)), "bytes": path.stat().st_size,
                              "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    manifest = {
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "source": str(source),
        "history_rows": len(legacy), "history_v2_rows": len(current),
        "unique_records": len(records),
        "records_with_text": sum(bool(record.get("refined_text")) for record in records),
        "records_with_audio": sum(bool(record["exported_audio_path"]) for record in records),
        "missing_audio_ids": missing_audio,
        "first_record": records[0]["created_at"] if records else None,
        "last_record": records[-1]["created_at"] if records else None,
        "recording_files": len(inventory),
        "recording_bytes": sum(item["bytes"] for item in inventory),
        "files": inventory,
    }
    (destination / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: value for key, value in manifest.items() if key != "files"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path.home() / "Library/Application Support/Typeless")
    parser.add_argument("--output", type=Path, required=True, help="New export directory, outside the repository")
    arguments = parser.parse_args()
    export(arguments.source.expanduser().resolve(), arguments.output.expanduser().resolve())
