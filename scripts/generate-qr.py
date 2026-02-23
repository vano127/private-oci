#!/usr/bin/env python3
"""Generate QR code from Terraform output values."""

import subprocess
import sys

try:
    import qrcode
except ImportError:
    print("Installing qrcode dependency...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "qrcode[pil]", "-q"])
    import qrcode


def get_terraform_output(name):
    result = subprocess.run(
        ["terraform", "output", "-raw", name],
        capture_output=True, text=True, cwd="terraform"
    )
    if result.returncode != 0:
        print(f"Error getting output '{name}': {result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def main():
    if len(sys.argv) > 1:
        data = sys.argv[1]
        output_file = sys.argv[2] if len(sys.argv) > 2 else "/tmp/qr.png"
    else:
        data = get_terraform_output("v2raytun_subscription_link")
        output_file = "/tmp/v2raytun-sub-qr.png"

    img = qrcode.make(data)
    img.save(output_file)
    print(f"QR code saved to {output_file}")


if __name__ == "__main__":
    main()
