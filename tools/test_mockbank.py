#!/usr/bin/env python3
"""Checks the mock bank's idempotency and fault injection. Run: python3 -I tools/test_mockbank.py"""
import http.client
import json
import os
import socket
import subprocess
import sys
import time
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = 8099


def request(method, path, body=None, headers=None, token=None):
    conn = http.client.HTTPConnection("127.0.0.1", PORT, timeout=5)
    hdrs = {"Content-Type": "application/json", **(headers or {})}
    if token:
        hdrs["Authorization"] = "Bearer " + token
    conn.request(method, path, json.dumps(body) if body is not None else None, hdrs)
    resp = conn.getresponse()
    data = resp.read()
    return resp.status, json.loads(data) if data else None


def main():
    server = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "mockbank.py"), str(PORT)],
                              stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                socket.create_connection(("127.0.0.1", PORT), timeout=0.2).close()
                break
            except OSError:
                time.sleep(0.1)

        status, body = request("POST", "/auth/pin", {"pin": "000000"})
        assert status == 401, status
        status, body = request("POST", "/auth/pin", {"pin": "739142"})
        assert status == 200, status
        token = body["token"]

        _, accounts = request("GET", "/accounts", token=token)
        before = accounts["accounts"][0]["balance_cents"]

        key = str(uuid.uuid4())
        transfer = {"sourceAccount": "0110012345678", "amountCents": 5_000_00,
                    "destination": {"type": "mpesa", "phone": "254712345678"}, "narration": "Rent"}
        status, first = request("POST", "/transfers", transfer, {"Idempotency-Key": key}, token)
        assert status == 201, status
        status, replay = request("POST", "/transfers", transfer, {"Idempotency-Key": key}, token)
        assert status == 200 and replay["reference"] == first["reference"], "replay must return the original"

        _, accounts = request("GET", "/accounts", token=token)
        after = accounts["accounts"][0]["balance_cents"]
        assert before - after == 5_000_00 + 33_00, "debited exactly once including charge"

        # Drop after commit: the client sees a dead socket, the bank has the money.
        key2 = str(uuid.uuid4())
        try:
            request("POST", "/transfers", transfer, {"Idempotency-Key": key2, "X-Fault": "drop-after-commit"}, token)
            raise AssertionError("expected the connection to drop")
        except (http.client.RemoteDisconnected, http.client.BadStatusLine, ConnectionResetError):
            pass
        status, found = request("GET", f"/transfers/{key2}", token=token)
        assert status == 200 and found["amountCents"] == 5_000_00, "status query must find the committed transfer"
        status, _ = request("GET", f"/transfers/{uuid.uuid4()}", token=token)
        assert status == 404

        print("mock bank: 8 checks passed")
    finally:
        server.terminate()


if __name__ == "__main__":
    main()
