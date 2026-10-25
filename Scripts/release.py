#!/usr/bin/env python3
"""Prepare and publish one verified SayKuku release; never rebuild during resume."""

import argparse
import hashlib
import html
import json
import os
import plistlib
import re
import shlex
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOWNLOADS = "https://saykuku.ullrai.com/"
WEBSITE = "https://say.anikuku.com/"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ACCOUNT = "com.saykuku.app"


def run(arguments, **kwargs):
    return subprocess.run([str(item) for item in arguments], check=True, **kwargs)


def sha256(file):
    digest = hashlib.sha256()
    with Path(file).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_url(url):
    request = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def optional_url(url):
    try:
        return read_url(url)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def version_parts(version):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", version):
        raise ValueError("Expected a numeric dotted version")
    parts = [int(part) for part in version.split(".")]
    while parts and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def published_build(feed):
    if "build" in feed:
        return int(feed["build"])
    # The last pre-Sparkle feed has no build number. Inspect its signed public DMG once.
    with tempfile.TemporaryDirectory(prefix="saykuku-previous-release-") as folder:
        folder = Path(folder)
        dmg = folder / "previous.dmg"
        dmg.write_bytes(read_url(DOWNLOADS + "SayKuku-" + feed["version"] + ".dmg"))
        run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", dmg])
        mount = folder / "mounted"
        run(["hdiutil", "attach", dmg, "-readonly", "-nobrowse", "-mountpoint", mount], stdout=subprocess.DEVNULL)
        try:
            return int(plistlib.loads((mount / "SayKuku.app/Contents/Info.plist").read_bytes())["CFBundleVersion"])
        finally:
            run(["hdiutil", "detach", mount], stdout=subprocess.DEVNULL)


def preflight(version, build):
    feed = json.loads(read_url(WEBSITE + "ver.json"))
    if version_parts(version) <= version_parts(feed["version"]):
        raise ValueError("Release version must exceed the published version")
    if build <= published_build(feed):
        raise ValueError("Release build must exceed the published build")
    env = deployment_config()  # Check local identifiers before building or notarizing.
    run(["wrangler", "whoami"], stdout=subprocess.DEVNULL, env=env)
    run(["npx", "zeabur@latest", "auth", "status", "-i=false"], stdout=subprocess.DEVNULL, env=env)


def deployment_config():
    config = Path.home() / ".config/saykuku/deploy.env"
    values = os.environ.copy()
    if config.exists():
        for line in config.read_text().splitlines():
            fields = shlex.split(line, comments=True)
            if fields and fields[0] == "export":
                fields = fields[1:]
            if len(fields) == 1 and "=" in fields[0]:
                name, value = fields[0].split("=", 1)
                values.setdefault(name, value)
    for name in ["CLOUDFLARE_ACCOUNT_ID", "ZEABUR_PROJECT_ID", "ZEABUR_SERVICE_ID"]:
        if not values.get(name):
            raise ValueError("Missing deployment setting: " + name)
    return values


def prepare(dmg, app, notes, tools, commit):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], int(info["CFBundleVersion"])
    version_parts(version)
    if dmg.name != "SayKuku-" + version + ".dmg":
        raise ValueError("Archive filename must match the App version")
    if not notes.strip():
        raise ValueError("Release notes must not be empty")
    destination = ROOT / "Dist/releases" / version
    destination.mkdir(parents=True, exist_ok=True)
    if (destination / "release.json").exists():
        raise ValueError("A prepared release already exists; use --resume or preserve it before rebuilding")
    link = destination / dmg.name
    if link.exists() or link.is_symlink():
        link.unlink()
    link.symlink_to(dmg.resolve())
    (destination / (dmg.stem + ".md")).write_text(notes)
    old_appcast = optional_url(DOWNLOADS + "appcast.xml")
    if old_appcast:
        (destination / "appcast.xml").write_bytes(old_appcast)
    run([tools / "generate_appcast", "--account", ACCOUNT, "--maximum-deltas", "0",
         "--maximum-versions", "0", "--embed-release-notes", "--download-url-prefix", DOWNLOADS, destination])
    appcast = destination / "appcast.xml"
    channel = ET.parse(appcast).getroot().find("channel")
    item = next(item for item in channel.findall("item") if item.findtext(f"{{{SPARKLE}}}version") == str(build))
    enclosure = item.find("enclosure")
    metadata = {
        "version": version, "build": build, "commit": commit, "dmg": str(dmg.resolve()),
        "sha256": sha256(dmg), "size": dmg.stat().st_size, "notes": notes,
        "download_url": DOWNLOADS + dmg.name, "website": WEBSITE,
        "appcast": str(appcast.resolve()), "appcast_sha256": sha256(appcast),
        "ed_signature": enclosure.attrib[f"{{{SPARKLE}}}edSignature"],
        "public_key": info["SUPublicEDKey"],
    }
    if enclosure.attrib["url"] != metadata["download_url"] or int(enclosure.attrib["length"]) != metadata["size"]:
        raise ValueError("Generated appcast does not match the final archive")
    legacy = {"version": version, "build": build, "url": WEBSITE + "download/", "notes": notes}
    (destination / "ver.json").write_text(json.dumps(legacy, ensure_ascii=False, indent=2) + "\n")
    metadata["legacy_feed"] = str((destination / "ver.json").resolve())
    metadata["legacy_sha256"] = sha256(destination / "ver.json")
    metadata_file = destination / "release.json"
    metadata_file.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
    return metadata_file


def validate(metadata, tools):
    version_parts(metadata["version"])
    dmg = Path(metadata["dmg"])
    for filename, digest in [(dmg, metadata["sha256"]),
                             (metadata["appcast"], metadata["appcast_sha256"]),
                             (metadata["legacy_feed"], metadata["legacy_sha256"])]:
        if sha256(filename) != digest:
            raise ValueError("Release artifact changed: " + Path(filename).name)
    if dmg.stat().st_size != metadata["size"]:
        raise ValueError("Release archive length changed")
    if metadata["download_url"] != DOWNLOADS + "SayKuku-" + metadata["version"] + ".dmg":
        raise ValueError("Release archive URL does not match its version")
    items = ET.parse(metadata["appcast"]).getroot().findall("channel/item")
    item = next(item for item in items if item.findtext(f"{{{SPARKLE}}}version") == str(metadata["build"]))
    enclosure = item.find("enclosure")
    if item.findtext(f"{{{SPARKLE}}}shortVersionString") != metadata["version"]:
        raise ValueError("Appcast display version does not match the release")
    if (enclosure.attrib["url"], int(enclosure.attrib["length"]), enclosure.attrib[f"{{{SPARKLE}}}edSignature"]) != (
            metadata["download_url"], metadata["size"], metadata["ed_signature"]):
        raise ValueError("Appcast release fields do not match the archive")
    legacy = json.loads(Path(metadata["legacy_feed"]).read_text())
    if (legacy["version"], legacy["build"], legacy["url"], legacy["notes"]) != (
            metadata["version"], metadata["build"], WEBSITE + "download/", metadata["notes"]):
        raise ValueError("Legacy feed does not match the release")
    if metadata["website"] != WEBSITE:
        raise ValueError("Unexpected website destination")
    run(["codesign", "--verify", "--strict", dmg])
    run(["xcrun", "stapler", "validate", dmg], stdout=subprocess.DEVNULL)
    run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", dmg])
    run([tools / "sign_update", "--account", ACCOUNT, "--verify", dmg, metadata["ed_signature"]])
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if head != metadata["commit"]:
        # A resumed publication may already have committed website-only changes.
        run(["git", "diff", "--exit-code", metadata["commit"], "HEAD", "--", "Sources", "Scripts", "Package.swift", "Package.resolved"], cwd=ROOT)
    tag = "v" + metadata["version"]
    existing = subprocess.run(["git", "rev-parse", "--verify", tag], cwd=ROOT, capture_output=True, text=True)
    if existing.returncode == 0 and existing.stdout.strip() != metadata["commit"]:
        raise ValueError("Existing release tag points to a different build")


def put_object(file, key, content_type, env):
    run(["wrangler", "r2", "object", "put", "saykuku/" + key, "--file", file,
         "--content-type", content_type, "--cache-control", "public, max-age=0, must-revalidate", "--remote"], env=env)


def upload_archive(metadata, env):
    existing = optional_url(metadata["download_url"])
    if existing is not None:
        if len(existing) != metadata["size"] or hashlib.sha256(existing).hexdigest() != metadata["sha256"]:
            raise ValueError("A different archive already exists at the versioned public URL")
        print("Reusing verified public archive", flush=True)
        return
    put_object(metadata["dmg"], Path(metadata["dmg"]).name, "application/x-apple-diskimage", env)
    verify_public(metadata["download_url"], metadata["sha256"])


def verify_public(url, digest):
    for attempt in range(6):
        try:
            if hashlib.sha256(read_url(url)).hexdigest() == digest:
                return
        except (urllib.error.URLError, TimeoutError):
            pass
        if attempt < 5:
            time.sleep(5)
    raise ValueError("Public content does not match the release: " + url)


def stage_site(metadata, destination):
    source = ROOT / "marketing/site/dist"
    shutil.copytree(source, destination)
    old_version = json.loads((source / "ver.json").read_text())["version"]
    old_hashes = set(re.findall(r"\b[a-f0-9]{64}\b", (source / "download/index.html").read_text()))
    size = f'{metadata["size"] / 1_000_000:.1f} MB'
    for file in destination.rglob("*.html"):
        text = file.read_text().replace(old_version, metadata["version"])
        for digest in old_hashes:
            text = text.replace(digest, metadata["sha256"])
        text = re.sub(r"\b[0-9]+(?:\.[0-9]+)? MB\b", size, text)
        file.write_text(text)
    shutil.copy2(metadata["legacy_feed"], destination / "ver.json")
    for name in ["download/index.html", "en/download/index.html"]:
        file = destination / name
        text = file.read_text()
        notes = "<ul>" + "".join("<li>" + html.escape(line.removeprefix("- ")) + "</li>"
                                    for line in metadata["notes"].splitlines() if line.strip()) + "</ul>"
        text, count = re.subn(r"(<h2>[^<]*" + re.escape(metadata["version"]) + r"[^<]*</h2>)<ul>.*?</ul>",
                             lambda match: match[1] + notes, text, count=1, flags=re.DOTALL)
        if count != 1:
            raise ValueError("Cannot locate website release notes: " + name)
        file.write_text(text)
        if not all(value in text for value in [metadata["version"], metadata["sha256"], size]):
            raise ValueError("Website release fields are incomplete: " + name)


def publish(metadata_file, tools):
    metadata = json.loads(metadata_file.read_text())
    branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    if branch != "main" or dirty:
        raise ValueError("Publish requires a clean main checkout")
    run(["git", "fetch", "origin", "main", "--tags"], cwd=ROOT)
    run(["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"], cwd=ROOT)
    env = deployment_config()
    validate(metadata, tools)
    current = json.loads(read_url(WEBSITE + "ver.json"))
    if version_parts(current["version"]) > version_parts(metadata["version"]):
        raise ValueError("A newer version is already published; refusing to roll back")
    if current["version"] == metadata["version"] and current.get("build") != metadata["build"]:
        raise ValueError("Published version has a different build")
    if version_parts(current["version"]) < version_parts(metadata["version"]) and published_build(current) >= metadata["build"]:
        raise ValueError("Release build must exceed the published build")
    upload_archive(metadata, env)  # No website or feed may advertise a missing archive.
    with tempfile.TemporaryDirectory(prefix="saykuku-site-publish-") as folder:
        site = Path(folder) / "site"
        stage_site(metadata, site)
        args = ["npx", "zeabur@latest", "deploy", "--project-id", env["ZEABUR_PROJECT_ID"],
                "--service-id", env["ZEABUR_SERVICE_ID"], "--json", "-i=false"]
        if env.get("ZEABUR_ENVIRONMENT_ID"):
            args += ["--environment-id", env["ZEABUR_ENVIRONMENT_ID"]]
        run(args, cwd=site, env=env)
        verify_public(metadata["website"] + "ver.json", metadata["legacy_sha256"])
        for name in ["download/index.html", "en/download/index.html"]:
            verify_public(metadata["website"] + name.removesuffix("index.html"), sha256(site / name))
        put_object(metadata["appcast"], "appcast.xml", "application/rss+xml", env)
        put_object(metadata["legacy_feed"], "ver.json", "application/json", env)
        verify_public(DOWNLOADS + "appcast.xml", metadata["appcast_sha256"])
        verify_public(DOWNLOADS + "ver.json", metadata["legacy_sha256"])
        # Only copy generated website changes back after the public release passes verification.
        shutil.copytree(site, ROOT / "marketing/site/dist", dirs_exist_ok=True)
    tag = "v" + metadata["version"]
    if subprocess.run(["git", "rev-parse", "--verify", tag], cwd=ROOT, capture_output=True).returncode:
        run(["git", "tag", tag, metadata["commit"]], cwd=ROOT)
    changed = subprocess.check_output(["git", "status", "--porcelain", "--", "marketing/site/dist"], cwd=ROOT, text=True)
    if changed:
        run(["git", "add", "marketing/site/dist"], cwd=ROOT)
        run(["git", "commit", "-m", "Publish SayKuku " + metadata["version"] + " website"], cwd=ROOT)
    run(["git", "push", "origin", "HEAD:main", "refs/tags/" + tag], cwd=ROOT)
    print("Published and verified SayKuku " + metadata["version"], flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("preflight")
    check.add_argument("version")
    check.add_argument("build", type=int)
    prep = sub.add_parser("prepare")
    for option in ["dmg", "app", "notes", "tools"]:
        prep.add_argument("--" + option, type=Path, required=True)
    prep.add_argument("--commit", required=True)
    pub = sub.add_parser("publish")
    pub.add_argument("metadata", type=Path)
    pub.add_argument("--tools", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "preflight":
        preflight(args.version, args.build)
    elif args.command == "prepare":
        print(prepare(args.dmg, args.app, args.notes.read_text(), args.tools, args.commit))
    else:
        publish(args.metadata, args.tools)


if __name__ == "__main__":
    main()
