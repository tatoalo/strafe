#!/usr/bin/env python3
import json
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET

repo = 'tatoalo/strafe'
tag = sys.argv[1]
release = json.loads(subprocess.check_output(['gh', 'release', 'view', tag, '--repo', repo,
    '--json', 'isDraft,isPrerelease,assets'], text=True))
assert not release['isDraft']
assets = release['assets']
assert any(asset['name'] == 'appcast.xml' for asset in assets)
assert any(asset['name'] == 'SHA256SUMS' for asset in assets)
feed_url = f'https://github.com/{repo}/releases/download/{tag}/appcast.xml'
with urllib.request.urlopen(feed_url, timeout=60) as response:
    assert response.url.startswith('https://')
    feed = ET.fromstring(response.read())
item = feed.find('./channel/item')
url = item.find('enclosure').attrib['url']
assert url.startswith(f'https://github.com/{repo}/releases/download/{tag}/')
with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=60) as response:
    assert response.status == 200 and response.url.startswith('https://')
if not release['isPrerelease']:
    with urllib.request.urlopen(f'https://github.com/{repo}/releases/latest/download/appcast.xml', timeout=60) as response:
        stable = ET.fromstring(response.read())
    assert stable.find('./channel/item/enclosure').attrib['url'] == url
print('Verified public HTTPS appcast and download:', url)
