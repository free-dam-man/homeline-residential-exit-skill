#!/usr/bin/env python3
# usage: fetch.py CC OUTDIR LIMIT [exclude_ovpn] [--tcp-only] [--allow-softether]
# Writes cand-CC-NN.ovpn ranked: TCP first, then UDP; inside each group lower ping, then higher speed.
# Ranking/UDP ideas adapted from vpnbox (MIT, https://github.com/sajadinmaker/vpnbox); no code copied verbatim.
# SoftEther space (VPN Gate operator, AS36599, e.g. 219.100.37.x) is skipped by default: it is not consumer broadband.
import urllib.request, csv, io, base64, os, sys, glob
args = [a for a in sys.argv[1:] if not a.startswith('--')]
flags = {a for a in sys.argv[1:] if a.startswith('--')}
cc, out, lim = args[0], args[1], int(args[2])
excl = set()
if len(args) > 3 and os.path.exists(args[3]):
    excl = {l.split()[1] for l in open(args[3]) if l.startswith('remote ')}
SOFTETHER_PREFIXES = ('219.100.37.',)   # AS36599 SoftEther Telecommunication Research Institute
for f in glob.glob(f"{out}/cand-{cc}-*.ovpn"): os.remove(f)
raw = urllib.request.urlopen("https://www.vpngate.net/api/iphone/", timeout=40).read().decode(errors='ignore')
lines = [l for l in raw.splitlines() if l and not l.startswith('*')]
h = next(i for i, l in enumerate(lines) if l.startswith('#HostName'))
lines[h] = lines[h][1:]
rows = [r for r in csv.DictReader(io.StringIO("\n".join(lines[h:]))) if r.get('CountryShort') == cc]
def num(v):
    try: return int(v)
    except Exception: return 0
cands = []; softether = 0
for r in rows:
    ping = num(r.get('Ping'))
    if ping <= 0: continue                      # no valid ping -> skip
    try: cfg = base64.b64decode(r['OpenVPN_ConfigData_Base64']).decode(errors='ignore')
    except Exception: continue
    proto = 'udp' if any(l.strip().startswith('proto udp') for l in cfg.splitlines()) else 'tcp'
    if proto == 'udp' and '--tcp-only' in flags: continue
    rem = [l.split()[1] for l in cfg.splitlines() if l.startswith('remote ')]
    if not rem or rem[0] in excl: continue
    if rem[0].startswith(SOFTETHER_PREFIXES) and '--allow-softether' not in flags:
        softether += 1; continue
    cands.append((0 if proto == 'tcp' else 1, ping, -num(r.get('Speed')), proto, cfg))
cands.sort(key=lambda c: c[:3])
for n, c in enumerate(cands[:lim], 1):
    p = f"{out}/cand-{cc}-{n:02d}.ovpn"; open(p, 'w').write(c[4]); os.chmod(p, 0o600)
tcp = sum(1 for c in cands if c[3] == 'tcp')
print(f"candidates_written={min(lim, len(cands))} tcp={tcp} udp={len(cands)-tcp} all_rows={len(rows)} softether_skipped={softether}")
if softether and not cands:
    print("WARNING: only SoftEther (AS36599) nodes listed; rerun with --allow-softether and label the line 'not residential'", file=sys.stderr)
