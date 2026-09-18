#!/usr/bin/env python3
"""Run on the server to save Stripe test credentials without echoing them."""
from pathlib import Path
import getpass
import os
import re
import tempfile

path = Path(__file__).resolve().parent / '.env'
key = getpass.getpass('Stripe TEST secret key (sk_test_..., hidden): ').strip()
secret = getpass.getpass('Stripe webhook signing secret (whsec_..., hidden): ').strip()
if not re.fullmatch(r'sk_test_[A-Za-z0-9]+', key) or not re.fullmatch(r'whsec_[A-Za-z0-9]+', secret):
    raise SystemExit('Expected a test secret key and webhook signing secret. No settings changed.')
updates = {'STRIPE_SECRET_KEY': key, 'STRIPE_WEBHOOK_SECRET': secret}
lines = path.read_text().splitlines()
kept = [line for line in lines if line.split('=', 1)[0] not in updates]
fd, temp = tempfile.mkstemp(dir=path.parent, prefix='.env-')
try:
    with os.fdopen(fd, 'w') as handle:
        handle.write('\n'.join(kept + [name + '=' + value for name, value in updates.items()]) + '\n')
    os.replace(temp, path)
finally:
    if os.path.exists(temp):
        os.unlink(temp)
print('Stripe test settings saved. Run: sudo docker compose up -d --force-recreate web worker')
