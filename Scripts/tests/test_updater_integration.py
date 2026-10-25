#!/usr/bin/env python3
"""Opt-in real signed/notarized Sparkle installation on a unique disposable app.

Run: SAYKUKU_UPDATE_INTEGRATION=1 python3 Scripts/tests/test_updater_integration.py
Uses the configured Developer ID and SayKuku-Notary profile. Never publishes feeds.
"""
import functools
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
import urllib.parse
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def wait_for(condition, description, timeout=180):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if condition():
            print("PASS: " + description, flush=True)
            return
        time.sleep(0.3)
    raise AssertionError("Timed out: " + description)


def main():
    if os.environ.get("SAYKUKU_UPDATE_INTEGRATION") != "1":
        raise SystemExit("Opt in with SAYKUKU_UPDATE_INTEGRATION=1; this submits disposable apps to Apple")
    reuse = os.environ.get("SAYKUKU_UPDATE_FIXTURE")
    folder = Path(reuse).resolve() if reuse else Path(tempfile.mkdtemp(prefix="updater-", dir=ROOT / "Build"))
    if not folder.is_relative_to(ROOT / "Build"):
        raise ValueError("Fixture must stay inside this checkout's Build directory")
    folder.chmod(0o700)
    bundle_id = "com.saykuku.tests.updater." + uuid.uuid4().hex
    port = 0
    if reuse:
        previous = plistlib.loads((folder / "100/SayKuku.app/Contents/Info.plist").read_bytes())
        bundle_id = previous["CFBundleIdentifier"]
        assert bundle_id.startswith("com.saykuku.tests.updater.")
        address = urllib.parse.urlparse(previous["SUFeedURL"])
        assert address.hostname == "127.0.0.1"
        port = address.port
    tools = ROOT / "Build/sparkle-tools-2.10.0/bin"
    framework = tools.parent / "Sparkle.framework"
    web = folder / "web"
    web.mkdir(exist_ok=True)
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(web))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_port}/"
    process = None
    print("Integration artifacts: " + str(folder), flush=True)
    try:
        if not reuse:
            # A fresh Curve25519 key in a mode-600 file; no test keys enter the Keychain.
            key = folder / "key"
            key_script = folder / "key.swift"
            key_script.write_text('import CryptoKit\nimport Foundation\nlet k = Curve25519.Signing.PrivateKey()\ntry k.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)\nprint(k.publicKey.rawRepresentation.base64EncodedString())\n')
            public_key = subprocess.check_output(["swift", str(key_script), str(key)], text=True).strip()
            key.chmod(0o600)
            binary = folder / "TestHost"
            sources = [ROOT / "Scripts/tests/UpdaterTestHost.swift", ROOT / "Sources/SayKuku/SoftwareUpdater.swift", ROOT / "Sources/SayKuku/AppTermination.swift"]
            run(["swiftc", "-parse-as-library", "-swift-version", "6", "-target", "arm64-apple-macos14.0", "-F", framework.parent,
                 "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", *sources, "-o", binary])
            identity = subprocess.check_output(["zsh", "-c", 'source "$1/Scripts/signing-identity.sh"; resolve_signing_identity release', "zsh", str(ROOT)], text=True).strip()
            apps = []
            for build in [100, 101]:
                app = folder / str(build) / "SayKuku.app"
                (app / "Contents/MacOS").mkdir(parents=True)
                (app / "Contents/Frameworks").mkdir()
                shutil.copy2(binary, app / "Contents/MacOS/TestHost")
                info = {"CFBundleExecutable": "TestHost", "CFBundleIdentifier": bundle_id,
                        "CFBundleName": "SayKuku Update Test", "CFBundlePackageType": "APPL",
                        "CFBundleVersion": str(build), "CFBundleShortVersionString": str(build - 99),
                        "LSMinimumSystemVersion": "14.0", "LSUIElement": True,
                        "SUFeedURL": url + "appcast.xml", "SUPublicEDKey": public_key,
                        "SUEnableAutomaticChecks": True, "SUAutomaticallyUpdate": True,
                        "SUAllowsAutomaticUpdates": True, "SUVerifyUpdateBeforeExtraction": True,
                        "SUEnableSystemProfiling": False,
                        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True, "NSAllowsArbitraryLoads": True}}
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
                run(["ditto", framework, app / "Contents/Frameworks/Sparkle.framework"])
                # Framework helpers remain universal; only the disposable host is arm64.
                run(["zsh", "-c", 'set -e; CODESIGN_ARGS=(--force --sign "$2" --options runtime --timestamp); CONFIGURATION=release; source "$1/Scripts/sign-sparkle.sh"; sign_sparkle_framework "$3"', "zsh", ROOT, identity, app / "Contents/Frameworks/Sparkle.framework"])
                run(["codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp", app])
                archive = folder / f"{build}.zip"
                run(["ditto", "-c", "-k", "--keepParent", app, archive])
                result = folder / f"notary-{build}.json"
                with result.open("w") as stream:
                    run(["xcrun", "notarytool", "submit", archive, "--keychain-profile", "SayKuku-Notary", "--wait", "--output-format", "json"], stdout=stream)
                assert json.loads(result.read_text())["status"] == "Accepted"
                run(["xcrun", "stapler", "staple", app])
                run(["spctl", "--assess", "--type", "execute", app])
                apps.append(app)
                print(f"Notarized test build {build}", flush=True)
            dmg = web / "SayKuku-Test.dmg"
            # Reuse the production DMG signing, notarization and Gatekeeper checks.
            run([ROOT / "Scripts/make-dmg.sh", apps[1], dmg])
            run([tools / "generate_appcast", "--ed-key-file", key, "--maximum-deltas", "0", "--download-url-prefix", url, web])
            key.unlink()
        else:
            apps = [folder / str(build) / "SayKuku.app" for build in [100, 101]]
        installed = folder / "installed/SayKuku.app"
        installed.parent.mkdir(exist_ok=True)
        if installed.exists():
            shutil.rmtree(installed)
        for name in ["events.log", "command", "status.json", "save-fails", "saved", "PASS"]:
            (folder / name).unlink(missing_ok=True)
        run(["ditto", apps[0], installed])
        marker = folder / "history-and-memory.json"
        marker.write_text('{"history":["keep"],"memory":["keep"]}')
        original = marker.read_bytes()
        env = dict(os.environ, SAYKUKU_UPDATE_TEST_ROOT=str(folder))
        output = (folder / "host.log").open("w")
        process = subprocess.Popen([str(installed / "Contents/MacOS/TestHost")], env=env, stdout=output, stderr=subprocess.STDOUT)

        def status():
            try:
                return json.loads((folder / "status.json").read_text())
            except (FileNotFoundError, json.JSONDecodeError):
                return {}

        def command(text):
            (folder / "command").write_text(text)

        def build():
            return plistlib.loads((installed / "Contents/Info.plist").read_bytes())["CFBundleVersion"]

        wait_for(lambda: status().get("ready"), "background download is ready while work continues")
        assert build() == "100" and process.poll() is None
        command("quit")
        wait_for(lambda: "waiting" in (folder / "events.log").read_text(), "Quit waits for active work")
        assert process.poll() is None and build() == "100"
        (folder / "save-fails").touch()
        command("idle")
        wait_for(lambda: "saved=false" in (folder / "events.log").read_text(), "failed save cancels quit")
        time.sleep(2)
        assert process.poll() is None and build() == "100"
        assert "paused=false" in (folder / "events.log").read_text()
        (folder / "save-fails").unlink()
        command("quit-again")
        wait_for(lambda: process.poll() is not None, "normal quit saves and exits")
        wait_for(lambda: build() == "101", "Sparkle replaces the app after normal quit")
        time.sleep(3)
        old_status = status()
        assert old_status["pid"] == process.pid, "Normal Quit must not relaunch the app"
        assert marker.read_bytes() == original and (folder / "saved").exists()
        command("idle")
        process = subprocess.Popen([str(installed / "Contents/MacOS/TestHost")], env=env, stdout=output, stderr=subprocess.STDOUT)
        wait_for(lambda: status().get("version") == "101", "next manual launch runs the updated app")
        command("quit-again")
        wait_for(lambda: process.poll() is not None, "updated app quits normally")
        # Reinstall the same notarized old fixture and serve a feed with an invalid EdDSA signature.
        shutil.rmtree(installed)
        run(["ditto", apps[0], installed])
        subprocess.run(["defaults", "delete", bundle_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        shutil.rmtree(Path.home() / "Library/Caches" / bundle_id, ignore_errors=True)
        for name in ["command", "status.json"]:
            (folder / name).unlink(missing_ok=True)
        feed = web / "appcast.xml"
        original_feed = feed.read_bytes()
        try:
            tree = ET.fromstring(original_feed)
            enclosure = tree.find("channel/item/enclosure")
            field = "{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"
            signature = enclosure.attrib[field]
            enclosure.set(field, ("B" if signature[0] == "A" else "A") + signature[1:])
            feed.write_bytes(ET.tostring(tree))
            process = subprocess.Popen([str(installed / "Contents/MacOS/TestHost")], env=env, stdout=output, stderr=subprocess.STDOUT)
            wait_for(lambda: status().get("pid") == process.pid, "bad-signature test host launched")
            time.sleep(12)
            assert process.poll() is None and build() == "100" and not status().get("ready")
            assert marker.read_bytes() == original
            print("PASS: invalid update signature leaves the notarized old app running", flush=True)
            command("idle")
            time.sleep(0.3)
            command("quit")
            wait_for(lambda: process.poll() is not None, "old app remains usable after signature failure")
        finally:
            feed.write_bytes(original_feed)
        print("PASS: isolated data preserved; no automatic relaunch; production app/feed untouched", flush=True)
        (folder / "PASS").write_text("Signed/notarized background download, deferred Quit, save failure, install on Quit, manual relaunch and invalid signature passed.\n")
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
        server.shutdown()
        (folder / "key").unlink(missing_ok=True)
        subprocess.run(["defaults", "delete", bundle_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        shutil.rmtree(Path.home() / "Library/Caches" / bundle_id, ignore_errors=True)


if __name__ == "__main__":
    main()
