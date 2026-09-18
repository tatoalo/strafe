#!/usr/bin/env python3
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

REPO = 'tatoalo/strafe'


class FeedNotCurrent(Exception):
    pass


def read_feed(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        assert response.url.startswith('https://')
        return ET.fromstring(response.read())


def verify_downloads(tag, prerelease):
    feed = read_feed(f'https://github.com/{REPO}/releases/download/{tag}/appcast.xml')
    url = feed.find('./channel/item/enclosure').attrib['url']
    assert url.startswith(f'https://github.com/{REPO}/releases/download/{tag}/')
    with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=30) as response:
        assert response.status == 200 and response.url.startswith('https://')
    if not prerelease:
        stable = read_feed(f'https://github.com/{REPO}/releases/latest/download/appcast.xml')
        if stable.find('./channel/item/enclosure').attrib['url'] != url:
            raise FeedNotCurrent('The latest release URL still serves the previous feed')
    return url


def verify_published(tag, attempts=12, delay=5):
    release = json.loads(subprocess.check_output(['gh', 'release', 'view', tag, '--repo', REPO,
        '--json', 'isDraft,isPrerelease,assets'], text=True))
    assert not release['isDraft']
    assets = release['assets']
    assert any(asset['name'] == 'appcast.xml' for asset in assets)
    assert any(asset['name'] == 'SHA256SUMS' for asset in assets)
    for attempt in range(attempts):
        try:
            url = verify_downloads(tag, release['isPrerelease'])
        except (urllib.error.URLError, TimeoutError, FeedNotCurrent) as error:
            if isinstance(error, urllib.error.HTTPError):
                error.close()
                if error.code not in (404, 429, 500, 502, 503, 504):
                    raise
            if attempt == attempts - 1:
                raise
            print(f'Waiting for published assets ({attempt + 1}/{attempts}): {error}', flush=True)
            time.sleep(delay)
        else:
            print('Verified public HTTPS appcast and download:', url)
            return url


if __name__ == '__main__':
    verify_published(sys.argv[1])
