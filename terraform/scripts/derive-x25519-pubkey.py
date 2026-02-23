#!/usr/bin/env python3
"""Terraform external data source: derive x25519 public key from private key bytes.

Input (JSON on stdin):
  {"private_key_hex": "64-char hex string (32 bytes)"}

Output (JSON on stdout):
  {"private_key": "base64url-no-padding", "public_key": "base64url-no-padding"}

Requires: openssl with x25519 support (LibreSSL 3.3+ / OpenSSL 1.1+)
"""

import base64
import json
import os
import subprocess
import sys
import tempfile


def main():
    input_data = json.load(sys.stdin)
    private_key_hex = input_data["private_key_hex"]

    # X25519 PKCS#8 DER structure (RFC 8410):
    # SEQUENCE {
    #   INTEGER 0,
    #   SEQUENCE { OID 1.3.101.110 },
    #   OCTET STRING { OCTET STRING { 32-byte-key } }
    # }
    der_header = bytes.fromhex("302e020100300506032b656e04220420")
    private_key_bytes = bytes.fromhex(private_key_hex)
    der_encoded = der_header + private_key_bytes

    with tempfile.NamedTemporaryFile(delete=False, suffix=".der") as f:
        f.write(der_encoded)
        tmpfile = f.name

    try:
        result = subprocess.run(
            ["openssl", "pkey", "-in", tmpfile, "-inform", "DER",
             "-pubout", "-outform", "DER"],
            capture_output=True, check=True,
        )
        # Last 32 bytes of the SubjectPublicKeyInfo DER are the raw public key
        public_key_bytes = result.stdout[-32:]

        # Base64url without padding — the format Xray expects
        priv = base64.urlsafe_b64encode(private_key_bytes).rstrip(b"=").decode()
        pub = base64.urlsafe_b64encode(public_key_bytes).rstrip(b"=").decode()

        json.dump({"private_key": priv, "public_key": pub}, sys.stdout)
    finally:
        os.unlink(tmpfile)


if __name__ == "__main__":
    main()
