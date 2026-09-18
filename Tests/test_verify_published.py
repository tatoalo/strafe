import importlib.util
import io
import json
import pathlib
import unittest
import urllib.error
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('verify_published', pathlib.Path(__file__).parents[1] / 'Scripts/verify-published.py')
published = importlib.util.module_from_spec(spec)
spec.loader.exec_module(published)
TAG = 'strafe-tatoalo-v0.2.0'
DOWNLOAD = f'https://github.com/tatoalo/strafe/releases/download/{TAG}/app.dmg'
RELEASE = json.dumps({'isDraft': False, 'isPrerelease': False,
    'assets': [{'name': 'appcast.xml'}, {'name': 'SHA256SUMS'}]})


def response(url=DOWNLOAD):
    result = io.BytesIO(f'<rss><channel><item><enclosure url="{url}" /></item></channel></rss>'.encode())
    result.url = 'https://release-assets.githubusercontent.com/asset'
    result.status = 200
    return result


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.gh = patch.object(published.subprocess, 'check_output', return_value=RELEASE).start()
        self.sleep = patch.object(published.time, 'sleep').start()
        self.addCleanup(patch.stopall)

    def test_first_stable_feed_404_is_retried(self):
        missing = urllib.error.HTTPError('https://github.com/latest', 404, 'Not Found', {}, io.BytesIO())
        with patch.object(published.urllib.request, 'urlopen', side_effect=[
            response(), response(), missing, response(), response(), response()
        ]):
            self.assertEqual(published.verify_published(TAG), DOWNLOAD)
        self.sleep.assert_called_once_with(5)

    def test_stale_latest_feed_is_retried(self):
        with patch.object(published.urllib.request, 'urlopen', side_effect=[
            response(), response(), response('https://github.com/old.dmg'),
            response(), response(), response()
        ]):
            self.assertEqual(published.verify_published(TAG), DOWNLOAD)
        self.sleep.assert_called_once_with(5)

    def test_wrong_release_download_fails_immediately(self):
        with patch.object(published.urllib.request, 'urlopen', return_value=response('https://example.com/app.dmg')):
            with self.assertRaises(AssertionError):
                published.verify_published(TAG)
        self.sleep.assert_not_called()

    def test_persistent_missing_feed_fails_after_bounded_retries(self):
        missing = urllib.error.HTTPError('https://github.com/latest', 404, 'Not Found', {}, io.BytesIO())
        with patch.object(published.urllib.request, 'urlopen', side_effect=missing) as fetch:
            with self.assertRaises(urllib.error.HTTPError):
                published.verify_published(TAG, attempts=3)
        self.assertEqual(fetch.call_count, 3)
        self.assertEqual(self.sleep.call_count, 2)

    def test_forbidden_feed_fails_immediately(self):
        forbidden = urllib.error.HTTPError('https://github.com/latest', 403, 'Forbidden', {}, io.BytesIO())
        with patch.object(published.urllib.request, 'urlopen', side_effect=forbidden):
            with self.assertRaises(urllib.error.HTTPError):
                published.verify_published(TAG)
        self.sleep.assert_not_called()


if __name__ == '__main__':
    unittest.main()
