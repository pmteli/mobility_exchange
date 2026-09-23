#!/usr/bin/env python3
"""Run on the Lightsail server, alongside the private Compose .env file."""
import getpass
import os
from pathlib import Path
import tempfile


def configure():
    target = Path(__file__).resolve().with_name('.env')
    if not target.is_file():
        raise SystemExit('Existing .env not found; run from the deployed Lightsail directory.')
    client_id = input('Google OAuth client ID: ').strip()
    secret = getpass.getpass('Google OAuth client secret (hidden): ').strip()
    if not client_id.endswith('.apps.googleusercontent.com') or not secret:
        raise SystemExit('A Google Web application client ID and secret are required.')
    if any(c in client_id + secret for c in "\r\n'\\"):
        raise SystemExit('Unexpected characters in credentials; copy them directly from Google.')
    values = {'GOOGLE_CLIENT_ID': client_id, 'GOOGLE_CLIENT_SECRET': secret,
              'GOOGLE_REDIRECT_URI': 'https://test.mobilityexchange.org/auth/google/callback'}
    lines = [line for line in target.read_text().splitlines()
             if line.split('=', 1)[0].strip() not in values]
    lines += [f"{key}='{value}'" for key, value in values.items()]
    fd, name = tempfile.mkstemp(dir=target.parent, prefix='.google-env-')
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write('\n'.join(lines) + '\n')
        os.chmod(name, 0o600)
        os.replace(name, target)
    finally:
        if os.path.exists(name):
            os.unlink(name)
    print('Google settings saved privately. Recreate web and worker to activate them.')


if __name__ == '__main__':
    configure()
