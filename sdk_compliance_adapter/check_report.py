#!/usr/bin/env python3
"""Fail on missing, duplicate or unexpected cases, independently of compliance."""
import json
from pathlib import Path
import sys

expected = json.loads((Path(__file__).parent / 'expected-tests.json').read_text())
report = json.loads(Path(sys.argv[1]).read_text())
actual = [f"{suite['name']}.{case['name']}"
          for suite in report['suites'] for case in suite['tests']]
assert expected and sorted(actual) == sorted(expected), (
    f'Inventory mismatch: missing={set(expected) - set(actual)}, '
    f'extra={set(actual) - set(expected)}, count={len(actual)}')
assert report['summary']['total'] == len(expected)
print(f"Verified {len(actual)} macOS Flutter cases: {report['summary']}")
for suite in report['suites']:
    for case in suite['tests']:
        if not case['passed']:
            print(f"FAIL {suite['name']}.{case['name']}: {case['message']}")
