import importlib.util
import pathlib
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('upstream_check', pathlib.Path(__file__).parents[1] / 'Scripts/upstream-check.py')
upstream_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upstream_check)


class MergeAnalysisTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.git('init', '-b', 'main')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.commit_file('shortcut.txt', 'ctrl+opt\n')
        self.git('branch', 'upstream')
        self.commit_file('shortcut.txt', 'ctrl\n')

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, stderr=subprocess.DEVNULL, text=True).strip()

    def commit_file(self, name, content):
        (self.root / name).write_text(content)
        self.git('add', name)
        self.git('commit', '-m', name)

    def test_no_incoming_changes(self):
        result = upstream_check.inspect_merge('main', 'upstream', cwd=self.root)
        self.assertEqual(result['incoming'], [])

    def test_clean_merge_preserves_fork_and_worktree(self):
        before = self.git('rev-parse', 'main')
        self.git('checkout', 'upstream')
        self.commit_file('new.txt', 'upstream feature\n')
        self.git('checkout', 'main')
        result = upstream_check.inspect_merge('main', 'upstream', cwd=self.root)
        self.assertTrue(result['clean'])
        self.assertEqual(len(result['incoming']), 1)
        self.assertEqual(self.git('show', result['tree'] + ':shortcut.txt'), 'ctrl')
        self.assertEqual(self.git('rev-parse', 'HEAD'), before)
        self.assertEqual(self.git('status', '--porcelain'), '')
        self.assertFalse((self.root / 'new.txt').exists())

    def test_conflict_is_reported_without_modifying_fork(self):
        self.git('checkout', 'upstream')
        self.commit_file('shortcut.txt', 'cmd+opt\n')
        self.git('checkout', 'main')
        result = upstream_check.inspect_merge('main', 'upstream', cwd=self.root)
        self.assertFalse(result['clean'])
        self.assertIn('shortcut.txt', result['conflicts'])
        self.assertIn('shortcut.txt', result['overlap'])
        self.assertEqual((self.root / 'shortcut.txt').read_text(), 'ctrl\n')
        self.assertEqual(self.git('status', '--porcelain'), '')

    def test_missing_fork_invariants_require_review(self):
        checks = upstream_check.check_invariants(self.git('rev-parse', 'HEAD'), cwd=self.root)
        self.assertFalse(any(checks.values()))


if __name__ == '__main__':
    unittest.main()
