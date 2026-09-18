#!/usr/bin/env python3
"""Merge older stable entries before atomically publishing the new release."""
import pathlib
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
FEED_URL = 'https://github.com/tatoalo/strafe/releases/latest/download/appcast.xml'
ET.register_namespace('sparkle', SPARKLE)
path = pathlib.Path(sys.argv[1])
feed = ET.parse(path)
channel = feed.find('channel')
assert channel is not None
new = channel.find('item')
assert new is not None
build = int(new.findtext('{' + SPARKLE + '}version'))
try:
    with urllib.request.urlopen(FEED_URL, timeout=60) as response:
        assert response.url.startswith('https://')
        previous = ET.fromstring(response.read())
except urllib.error.HTTPError as error:
    if error.code != 404:
        raise
else:
    for item in previous.findall('./channel/item')[:19]:
        previous_build = int(item.findtext('{' + SPARKLE + '}version'))
        assert previous_build < build, 'Release build number must increase'
        channel.append(item)
feed.write(path, encoding='utf-8', xml_declaration=True)
print('Prepared stable update metadata; previous compatible releases retained.')
