#!/usr/bin/env python3
"""Retry only a release build that GitHub could not assign to a hosted runner."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

MAX_ATTEMPTS = 4  # Initial attempt plus at most three retries.
RUNNER_FAILURE = 'The job was not acquired by Runner of type hosted even after multiple attempts'


def api(path):
    return json.loads(subprocess.check_output(['gh', 'api', path], text=True))


def post(path):
    subprocess.run(['gh', 'api', '--method', 'POST', path], check=True)


def pages(get, path, key=None):
    result = []
    page = 1
    while True:
        data = get(f'{path}?per_page=100&page={page}')
        items = data[key] if key else data
        result.extend(items)
        if len(items) < 100:
            return result
        page += 1


def ineligible(run, repo):
    if run.get('head_repository', {}).get('full_name') != repo:
        return 'Run belongs to another repository.'
    if run.get('event') != 'push' or not re.fullmatch(r'v\d+\.\d+\.\d+', run.get('head_branch', '')):
        return 'Only version-tag pushes are eligible.'
    if run.get('path', '').split('@')[0] != '.github/workflows/build.yml':
        return 'Not the release workflow.'
    if run.get('status') != 'completed' or run.get('conclusion') not in ('failure', 'cancelled'):
        return 'Run is successful, still active, or not a retryable failure.'
    attempt = run.get('run_attempt', 0)
    if not isinstance(attempt, int) or attempt < 1 or attempt >= MAX_ATTEMPTS:
        return 'Retry limit reached (four attempts total), or attempt is unknown.'
    return None


def retry(repo, run_id, dry_run=False, get=api, send=post):
    base = f'repos/{repo}/actions/runs/{run_id}'
    run = get(base)
    reason = ineligible(run, repo)
    if reason:
        return 'Skipped: ' + reason
    attempt = run['run_attempt']
    jobs = pages(get, f'{base}/attempts/{attempt}/jobs', 'jobs')
    build_jobs = [job for job in jobs if job.get('name') == 'Build Apple Silicon DMG']
    if len(build_jobs) != 1:
        return 'Skipped: expected build job was not found.'
    build = build_jobs[0]
    if build.get('conclusion') not in ('failure', 'cancelled') or build.get('steps') != []:
        return 'Skipped: build already started, or did not fail waiting for a runner.'
    if any(job.get('conclusion') != 'skipped' for job in jobs if job['id'] != build['id']):
        return 'Skipped: another job ran; do not retry compilation, packaging, or publication failures.'
    # GitHub Actions job IDs are also their check-run IDs. Read the exact failure annotation.
    annotations = pages(get, f'repos/{repo}/check-runs/{build["id"]}/annotations')
    if not any(item.get('annotation_level') == 'failure' and item.get('message', '').strip() == RUNNER_FAILURE for item in annotations):
        return 'Skipped: no confirmed hosted-runner acquisition failure.'
    if dry_run:
        return f'Dry run: attempt {attempt} is eligible for retry {attempt + 1}/{MAX_ATTEMPTS}. Nothing restarted.'
    # A human may have restarted it since this job began. Never submit a duplicate retry.
    latest = get(base)
    if ineligible(latest, repo) or latest.get('run_attempt') != attempt:
        return 'Skipped: the run changed during inspection.'
    send(f'{base}/rerun-failed-jobs')
    return f'Requested attempt {attempt + 1}/{MAX_ATTEMPTS} for release {run["head_branch"]}, run {run_id}.'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_id', type=int)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    repo = os.environ['GITHUB_REPOSITORY']
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo) or args.run_id <= 0:
        parser.error('Invalid repository or run ID')
    result = retry(repo, args.run_id, args.dry_run)
    print(result)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a') as summary:
            summary.write(result + '\n')


if __name__ == '__main__':
    main()
