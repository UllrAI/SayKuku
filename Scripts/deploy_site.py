#!/usr/bin/env python3
"""Trigger one Coolify deployment and wait for its final status."""

import json
import os
import time
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


def main():
    webhook = os.environ["COOLIFY_WEBHOOK"]
    token = os.environ["COOLIFY_TOKEN"]
    address = urlsplit(webhook)
    if address.scheme != "https" or address.hostname != "c.ullrai.com":
        raise ValueError("COOLIFY_WEBHOOK must use https://c.ullrai.com")
    headers = {"Authorization": "Bearer " + token, "Accept": "application/json", "User-Agent": "SayKuku-Deploy/1.0"}
    request = Request(webhook, data=b"", headers=headers, method="POST")
    # Do not retry POST: an interrupted response may already have queued a deployment.
    with urlopen(request, timeout=30) as response:
        result = json.load(response)
    deployments = result.get("deployments", [])
    if len(deployments) != 1 or not deployments[0].get("deployment_uuid"):
        raise RuntimeError("Coolify did not queue exactly one application deployment")
    deployment_id = deployments[0]["deployment_uuid"]
    print("Coolify deployment: " + deployment_id, flush=True)
    status_url = "https://c.ullrai.com/api/v1/deployments/" + deployment_id
    deadline = time.monotonic() + 600
    previous = None
    while time.monotonic() < deadline:
        with urlopen(Request(status_url, headers=headers), timeout=30) as response:
            status = json.load(response)["status"]
        if status != previous:
            print("Deployment status: " + status, flush=True)
            previous = status
        if status == "finished":
            return
        if status in ("failed", "cancelled", "canceled"):
            raise RuntimeError("Coolify deployment " + status)
        time.sleep(5)
    raise TimeoutError("Coolify deployment did not finish within ten minutes")


if __name__ == "__main__":
    main()
