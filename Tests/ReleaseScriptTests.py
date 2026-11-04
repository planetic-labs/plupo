#!/usr/bin/env python3
"""Exercise release publication against disposable local Git remotes; no network or real releases."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'release.sh'

class ReleaseScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='plupo-release-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.remote = self.root / 'origin.git'
        self.repo.mkdir()
        self.git('init', '--bare', str(self.remote))
        self.git('init', '-b', 'main')
        self.git('config', 'user.name', 'Release Tests')
        self.git('config', 'user.email', 'tests@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        self.git('config', 'tag.gpgsign', 'false')
        self.git('remote', 'add', 'origin', str(self.remote))
        (self.repo / 'scripts').mkdir()
        shutil.copyfile(SCRIPT, self.repo / 'scripts/release.sh')
        (self.repo / 'Tests').mkdir()
        (self.repo / 'Tests/run.sh').write_text('echo tests >> "$CHECK_LOG"\nexit "${FAIL_TESTS:-0}"\n')
        (self.repo / 'Plupo.xcodeproj').mkdir()
        self.project = self.repo / 'Plupo.xcodeproj/project.pbxproj'
        self.project.write_text('MARKETING_VERSION = 0.1.9;\nMARKETING_VERSION = 0.1.9;\n')
        self.git('add', '.')
        self.git('commit', '-m', 'Initial source')
        self.git('push', 'origin', 'main')
        self.initial = self.git('rev-parse', 'HEAD').stdout.strip()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name, body in {
            'xcodebuild': 'echo build >> "$CHECK_LOG"\nexit "${FAIL_BUILD:-0}"\n',
            'xcrun': 'exit 0\n',
        }.items():
            p = self.bin / name
            p.write_text('#!/bin/sh\n' + body)
            p.chmod(0o755)
        self.log = self.root / 'checks.log'
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'], CHECK_LOG=str(self.log))

    def git(self, *args, cwd=None):
        return subprocess.run(['git', *args], cwd=cwd or self.repo, text=True, capture_output=True, check=True)

    def run_release(self, *args, success=True, **env):
        result = subprocess.run(['bash', 'scripts/release.sh', *args], cwd=self.repo,
                                env=dict(self.env, **env), text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def remote_tags(self):
        return self.git('--git-dir=' + str(self.remote), 'tag', '--list').stdout.splitlines()

    def assert_untouched(self):
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout.strip(), self.initial)
        self.assertEqual(self.project.read_text().count('MARKETING_VERSION = 0.1.9;'), 2)
        self.assertEqual(self.remote_tags(), [])

    def test_success_updates_both_versions_and_publishes_matching_commit(self):
        self.run_release('0.1.10')
        self.assertEqual(self.project.read_text().count('MARKETING_VERSION = 0.1.10;'), 2)
        self.assertEqual(self.remote_tags(), ['v0.1.10'])
        remote_head = self.git('--git-dir=' + str(self.remote), 'rev-parse', 'refs/heads/main').stdout
        tag_head = self.git('--git-dir=' + str(self.remote), 'rev-parse', 'v0.1.10^{}').stdout
        self.assertEqual(remote_head, tag_head)
        self.assertEqual(self.log.read_text().splitlines(), ['tests', 'build'])

    def test_dry_run_has_no_mutations_or_verification_commands(self):
        self.run_release('--dry-run', '0.1.10')
        self.assert_untouched()
        self.assertFalse(self.log.exists())

    def test_invalid_and_older_versions_are_rejected(self):
        for value in ['v0.1.10', '0.1', '0.01.10', '0.1.10-beta', '0.1.8']:
            with self.subTest(value=value):
                self.run_release(value, success=False)
                self.assert_untouched()

    def test_dirty_and_untracked_files_are_rejected(self):
        (self.repo / 'unfinished.txt').write_text('work in progress')
        self.run_release('0.1.10', success=False)
        self.assert_untouched()

    def test_existing_remote_tag_is_rejected_even_when_not_local(self):
        self.git('tag', 'v0.1.10')
        self.git('push', 'origin', 'refs/tags/v0.1.10')
        self.git('tag', '-d', 'v0.1.10')
        self.run_release('0.1.10', success=False)
        self.assertEqual(self.git('rev-parse', 'HEAD').stdout.strip(), self.initial)
        self.assertFalse(self.log.exists())

    def test_lower_version_than_existing_tag_is_rejected(self):
        self.git('tag', 'v0.2.0')
        self.run_release('0.1.10', success=False)
        self.assert_untouched()

    def test_local_main_behind_remote_is_rejected(self):
        self.git('commit', '--allow-empty', '-m', 'New source')
        self.git('push', 'origin', 'main')
        self.git('reset', '--hard', self.initial)
        self.run_release('0.1.10', success=False)
        self.assert_untouched()

    def test_wrong_branch_is_rejected(self):
        self.git('switch', '-c', 'feature')
        self.run_release('0.1.10', success=False)
        self.assert_untouched()

    def test_test_failure_does_not_change_version_or_publish(self):
        self.run_release('0.1.10', success=False, FAIL_TESTS='1')
        self.assert_untouched()
        self.assertEqual(self.log.read_text().splitlines(), ['tests'])

    def test_build_failure_does_not_change_version_or_publish(self):
        self.run_release('0.1.10', success=False, FAIL_BUILD='1')
        self.assert_untouched()

    def test_rejected_branch_push_cannot_publish_tag(self):
        hook = self.remote / 'hooks/update'
        hook.write_text('#!/bin/sh\n[ "$1" != refs/heads/main ]\n')
        hook.chmod(0o755)
        result = self.run_release('0.1.10', success=False)
        self.assertEqual(self.remote_tags(), [])
        self.assertEqual(self.git('--git-dir=' + str(self.remote), 'rev-parse', 'refs/heads/main').stdout.strip(), self.initial)
        self.assertEqual(self.git('tag', '--list').stdout.strip(), 'v0.1.10')
        self.assertIn('local release commit and tag were kept', result.stderr)

if __name__ == '__main__':
    unittest.main(verbosity=2)
