#!/usr/bin/env python3
"""Mock core-banking API for Ngao, standard library only.

Implements the handful of endpoints the app needs, with the two behaviours that matter
for the client's correctness story:

  * Idempotency: POST /transfers honours the Idempotency-Key header. A replayed key returns
    the original response and never debits twice.
  * Fault injection: send header `X-Fault: drop-after-commit` and the server debits, then
    closes the socket without answering. `X-Fault: timeout` hangs 30 s before committing.

Run:  python3 tools/mockbank.py [port]     (default 8090)
PIN for the demo customer is 739142.
"""
import hashlib
import http.server
import json
import secrets
import socketserver
import sys
import threading
import time
import uuid
from datetime import datetime, timezone

PIN_HASH = hashlib.sha256(b"739142").hexdigest()
LOCK = threading.Lock()

STATE = {
    "accounts": {
        "0110012345678": {"id": "0110012345678", "name": "Current account", "balance_cents": 184_520_00, "currency": "KES"},
        "0110098765432": {"id": "0110098765432", "name": "Savings", "balance_cents": 1_250_000_00, "currency": "KES"},
    },
    "cards": {
        "card-1": {"id": "card-1", "last4": "4521", "brand": "Visa", "frozen": False, "account": "0110012345678"},
    },
    "transfers": {},        # idempotency key -> response dict
    "sessions": {},         # token -> customer
    "pin_failures": 0,
}


def now():
    return datetime.now(timezone.utc).isoformat()


def charge_for(destination):
    kind = destination.get("type")
    return {"mpesa": 33_00, "paybill": 23_00, "till": 0, "pesalink": 55_00, "ownBank": 0}.get(kind, 0)


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.command, self.path))

    # -- helpers -----------------------------------------------------------

    def body(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length) or b"{}")

    def send(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authed(self):
        auth = self.headers.get("Authorization", "")
        token = auth.removeprefix("Bearer ")
        return STATE["sessions"].get(token)

    # -- routes ------------------------------------------------------------

    def do_POST(self):
        if self.path == "/auth/pin":
            return self.login()
        if self.path == "/transfers":
            return self.transfer()
        if self.path.startswith("/cards/") and self.path.endswith("/freeze"):
            return self.freeze(self.path.split("/")[2], True)
        if self.path.startswith("/cards/") and self.path.endswith("/unfreeze"):
            return self.freeze(self.path.split("/")[2], False)
        self.send(404, {"error": "not found"})

    def do_GET(self):
        if self.path == "/health":
            return self.send(200, {"status": "ok"})
        if not self.authed():
            return self.send(401, {"error": "unauthenticated"})
        if self.path == "/accounts":
            return self.send(200, {"accounts": list(STATE["accounts"].values())})
        if self.path == "/cards":
            return self.send(200, {"cards": list(STATE["cards"].values())})
        if self.path == "/transfers":
            return self.send(200, {"transfers": sorted(STATE["transfers"].values(), key=lambda t: t["completedAt"], reverse=True)})
        if self.path.startswith("/transfers/"):
            key = self.path.split("/")[2]
            found = STATE["transfers"].get(key)
            return self.send(200, found) if found else self.send(404, {"error": "unknown idempotency key"})
        self.send(404, {"error": "not found"})

    def login(self):
        pin = self.body().get("pin", "")
        with LOCK:
            if STATE["pin_failures"] >= 5:
                return self.send(423, {"error": "locked", "message": "Too many attempts. Call the bank."})
            if hashlib.sha256(pin.encode()).hexdigest() != PIN_HASH:
                STATE["pin_failures"] += 1
                return self.send(401, {"error": "wrong_pin", "attemptsLeft": 5 - STATE["pin_failures"]})
            STATE["pin_failures"] = 0
            token = secrets.token_urlsafe(32)
            STATE["sessions"][token] = "cust-1"
        self.send(200, {"token": token, "customer": {"id": "cust-1", "name": "Wanjiru Kamau"}})

    def transfer(self):
        if not self.authed():
            return self.send(401, {"error": "unauthenticated"})
        key = self.headers.get("Idempotency-Key")
        if not key:
            return self.send(400, {"error": "Idempotency-Key header required"})
        fault = self.headers.get("X-Fault", "")
        if fault == "timeout":
            time.sleep(30)
        payload = self.body()
        with LOCK:
            if key in STATE["transfers"]:
                # Replay: identical answer, no second debit.
                return self.send(200, STATE["transfers"][key])
            account = STATE["accounts"].get(payload.get("sourceAccount"))
            amount = int(payload.get("amountCents", 0))
            if not account:
                return self.send(404, {"error": "UNKNOWN_ACCOUNT", "message": "No such account", "retryable": False})
            if amount <= 0 or amount % 100:
                return self.send(400, {"error": "INVALID_AMOUNT", "message": "Whole shillings only", "retryable": False})
            charge = charge_for(payload.get("destination", {}))
            if account["balance_cents"] < amount + charge:
                return self.send(402, {"error": "INSUFFICIENT_FUNDS", "message": "Insufficient funds", "retryable": False})
            account["balance_cents"] -= amount + charge
            receipt = {
                "reference": "FT" + uuid.uuid4().hex[:10].upper(),
                "amountCents": amount,
                "chargeCents": charge,
                "completedAt": now(),
                "destination": payload.get("destination"),
                "idempotencyKey": key,
            }
            STATE["transfers"][key] = receipt
        if fault == "drop-after-commit":
            # Money moved; client hears nothing. This is the double-charge trap.
            self.close_connection = True
            self.connection.close()
            return
        self.send(201, receipt)

    def freeze(self, card_id, frozen):
        if not self.authed():
            return self.send(401, {"error": "unauthenticated"})
        card = STATE["cards"].get(card_id)
        if not card:
            return self.send(404, {"error": "unknown card"})
        card["frozen"] = frozen
        self.send(200, card)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8090
    print(f"mock bank on http://127.0.0.1:{port}  (PIN 739142)")
    Server(("127.0.0.1", port), Handler).serve_forever()
