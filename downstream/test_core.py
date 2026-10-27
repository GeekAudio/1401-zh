#!/usr/bin/env python3
"""Run the unmodified upstream Python suite with its supported interpreter."""
import pathlib
import sys
import unittest
import contextlib
if sys.version_info < (3, 10):
    raise SystemExit('Upstream tests require Python 3.10 or later (traceback API). Use Python 3.12.')
root = pathlib.Path(__file__).resolve().parents[1]
suite = unittest.defaultTestLoader.discover(str(root / 'tests'), pattern='test_*.py', top_level_dir=str(root))
destination = root / 'dist'; destination.mkdir(exist_ok=True)
logfile = destination / 'test-core.log'
with logfile.open('w') as log, contextlib.redirect_stdout(log), contextlib.redirect_stderr(log):
    result = unittest.TextTestRunner(stream=log, verbosity=1).run(suite)
print(f'Upstream core: {result.testsRun} tests, {len(result.failures)} failures, {len(result.errors)} errors, {len(result.skipped)} skipped')
if not result.wasSuccessful(): print('\n'.join(logfile.read_text().splitlines()[-120:]))
raise SystemExit(not result.wasSuccessful())
