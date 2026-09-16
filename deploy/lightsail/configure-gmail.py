#!/usr/bin/env python3
"""Run on the server in deploy/lightsail; never prints the App Password."""
from pathlib import Path
import getpass
import os
import tempfile

path = Path(__file__).resolve().parent / '.env'
password = getpass.getpass('Google App Password for admin@mobilityexchange.org (hidden): ').replace(' ', '')
if not password or '\n' in password or '\r' in password or not password.isalnum():
    raise SystemExit('Enter a valid Google App Password; no settings changed.')
lines = path.read_text().splitlines()
updates = {'SMTP_PASSWORD': password, 'MAIL_DELIVERY_METHOD': 'smtp'}
kept = [line for line in lines if line.split('=', 1)[0] not in updates]
fd, temp = tempfile.mkstemp(dir=path.parent, prefix='.env-')
try:
    with os.fdopen(fd, 'w') as f:
        f.write('\n'.join(kept + [key + '=' + value for key, value in updates.items()]) + '\n')
    os.replace(temp, path)
finally:
    if os.path.exists(temp):
        os.unlink(temp)
print('Gmail settings saved. Restart web and worker with: sudo docker compose up -d --force-recreate web worker')
