#!/usr/bin/env python3
"""Make (and optionally verify) a QR code PNG for a node link or subscription URL.

Adapted from the CF skill package's templates/make_sub_qr.py (same author,
same workflow): that version only accepted an https://<HOST>/sub?token=...
subscription URL. This version also accepts a single vless:// node link,
which is what the homeline stack delivers per country line.

Usage:
  NODE_LINK="vless://<UUID>@<VPS_IP>:<PORT>?...#Home-<CC>" python3 make_sub_qr.py --output node-qr.png
  python3 make_sub_qr.py --url "vless://..." --output node-qr.png
  SUB_URL="https://<HOST>/sub?token=<TOKEN>" python3 make_sub_qr.py --output sub-qr.png
  python3 make_sub_qr.py --verify node-qr.png --expect-env NODE_LINK

The link/URL is a credential. Pass it via environment or argument at run
time; never hard-code a real link into this file or commit the PNG.
Requires: pip install "qrcode[pil]"   (verify step also uses opencv-python if present)
"""
import argparse, os, sys

def check_link(url: str) -> None:
    if url.startswith("vless://"):
        if "@" not in url or "security=reality" not in url:
            sys.exit("Refusing: vless link must contain @ and security=reality")
    elif url.startswith("https://"):
        pass  # subscription URL; format is the subscription server's business
    else:
        sys.exit("Refusing: link must start with vless:// or https://")

def make_qr(url: str, output: str) -> None:
    try:
        import qrcode
    except ImportError:
        sys.exit("Missing dependency: pip install \"qrcode[pil]\"")
    check_link(url)
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=10, border=4)
    qr.add_data(url)
    qr.make(fit=True)
    qr.make_image(fill_color="black", back_color="white").save(output)
    print(f"saved {output} ({os.path.getsize(output)} bytes)")

def verify(path: str, expected: str) -> None:
    try:
        import cv2
    except ImportError:
        print("QR_DECODE_SKIPPED: opencv not installed; scan-test with the real phone before delivery")
        return
    data, _, _ = cv2.QRCodeDetector().detectAndDecode(cv2.imread(path))
    print("decoded: <link redacted; length %d>" % len(data))
    print(f"QR_DECODE_MATCH={data == expected}")
    if data != expected:
        sys.exit(1)

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=os.environ.get("NODE_LINK", "") or os.environ.get("SUB_URL", ""))
    ap.add_argument("--output", default="node-qr.png")
    ap.add_argument("--verify", metavar="PNG", help="decode-check an existing PNG instead of creating one")
    ap.add_argument("--expect-env", default="NODE_LINK", help="env var holding the expected link for --verify")
    args = ap.parse_args()
    if args.verify:
        expected = os.environ.get(args.expect_env, "")
        if not expected:
            sys.exit(f"Set {args.expect_env} to the expected link first")
        verify(args.verify, expected)
    else:
        if not args.url:
            sys.exit("Set NODE_LINK (or SUB_URL) env var or pass --url")
        make_qr(args.url, args.output)
        verify(args.output, args.url)

if __name__ == "__main__":
    main()
