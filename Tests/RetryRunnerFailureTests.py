import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('retry_runner', Path(__file__).resolve().parents[1] / 'scripts/retry-runner-failure.py')
retry_runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retry_runner)

class RetryTests(unittest.TestCase):
    def setUp(self):
        self.run = dict(head_repository={'full_name': 'planetic-labs/plupo'}, event='push', head_branch='v0.1.3',
                        path='.github/workflows/build.yml', status='completed', conclusion='failure', run_attempt=1)
        self.jobs = [dict(id=12, name='Build Apple Silicon DMG', conclusion='cancelled', steps=[]),
                     dict(id=13, name='Publish GitHub Release', conclusion='skipped', steps=[])]
        self.annotations = [dict(annotation_level='failure', message=retry_runner.RUNNER_FAILURE)]
        self.posts = []
        self.run_reads = 0
        self.changed = False

    def get(self, path):
        if '/annotations?' in path:
            return self.annotations
        if '/jobs?' in path:
            return {'jobs': self.jobs}
        self.run_reads += 1
        run = copy.deepcopy(self.run)
        if self.changed and self.run_reads > 1:
            run.update(status='queued', run_attempt=2)
        return run

    def check(self, dry=False):
        return retry_runner.retry('planetic-labs/plupo', 42, dry, self.get, self.posts.append)

    def test_capacity_failure_retries_same_run(self):
        self.assertIn('Requested attempt 2/4', self.check())
        self.assertEqual(self.posts, ['repos/planetic-labs/plupo/actions/runs/42/rerun-failed-jobs'])

    def test_dry_run_never_restarts(self):
        self.assertIn('eligible', self.check(True))
        self.assertEqual(self.posts, [])

    def test_third_retry_is_allowed_but_fourth_is_not(self):
        self.run['run_attempt'] = 3
        self.assertIn('Requested attempt 4/4', self.check())
        self.posts.clear()
        self.run['run_attempt'] = 4
        self.assertIn('limit', self.check())
        self.assertEqual(self.posts, [])

    def test_compilation_failure_is_not_retried(self):
        self.jobs[0].update(conclusion='failure', steps=[{'name': 'Build and package', 'conclusion': 'failure'}])
        self.assertIn('Skipped', self.check())
        self.assertEqual(self.posts, [])

    def test_manual_cancellation_without_annotation_is_not_retried(self):
        self.annotations = []
        self.run['conclusion'] = 'cancelled'
        self.assertIn('Skipped', self.check())
        self.assertEqual(self.posts, [])

    def test_notice_alone_is_insufficient(self):
        self.annotations[0]['annotation_level'] = 'notice'
        self.assertIn('Skipped', self.check())
        self.assertEqual(self.posts, [])

    def test_publication_failure_is_not_retried(self):
        self.jobs[1]['conclusion'] = 'failure'
        self.assertIn('Skipped', self.check())
        self.assertEqual(self.posts, [])

    def test_ineligible_runs_are_not_retried(self):
        for update in [dict(status='queued'), dict(conclusion='success'), dict(event='workflow_dispatch'),
                       dict(event='pull_request'), dict(head_branch='main'), dict(path='.github/workflows/pages.yml'),
                       dict(head_repository={'full_name': 'someone/fork'})]:
            with self.subTest(update=update):
                original = copy.deepcopy(self.run)
                self.run.update(update)
                self.assertIn('Skipped', self.check())
                self.assertEqual(self.posts, [])
                self.run = original

    def test_concurrent_manual_restart_is_not_duplicated(self):
        self.changed = True
        self.assertIn('changed', self.check())
        self.assertEqual(self.posts, [])

if __name__ == '__main__':
    unittest.main(verbosity=2)
