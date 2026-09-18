#!/usr/bin/env python3
"""Check the metadata connecting the app, feed, and downloadable archive."""
import pathlib
import plistlib
import sys
import xml.etree.ElementTree as ET

app, feed, archive = map(pathlib.Path, sys.argv[1:])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
items = ET.parse(feed).findall('./channel/item')
assert len(items) == 1, 'Expected exactly one new release'
item = items[0]
enclosure = item.find('enclosure')
assert enclosure is not None
assert info['CFBundleIdentifier'] == 'com.tatoalo.strafe'
assert info['CFBundleExecutable'] == 'strafe-tatoalo'
assert item.findtext('sparkle:version', namespaces=ns) == info['CFBundleVersion']
assert item.findtext('sparkle:shortVersionString', namespaces=ns) == info['CFBundleShortVersionString']
assert enclosure.attrib['url'].startswith('https://github.com/tatoalo/strafe/releases/download/')
assert enclosure.attrib['url'].endswith('/' + archive.name)
assert int(enclosure.attrib['length']) == archive.stat().st_size
assert enclosure.attrib['{' + ns['sparkle'] + '}edSignature']
assert info['SUFeedURL'] == 'https://github.com/tatoalo/strafe/releases/latest/download/appcast.xml'
assert info['SUPublicEDKey'] == pathlib.Path('Resources/SparklePublicKey.txt').read_text().strip()
print('Verified release identity, version, signature metadata, feed, and archive size.')
