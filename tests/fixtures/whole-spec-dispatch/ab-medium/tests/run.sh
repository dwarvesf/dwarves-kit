#!/bin/bash
# Project test entry point: runs every tests/test_*.py with the stdlib runner.
cd "$(dirname "$0")/.." && exec python3 -m unittest discover -s tests -p 'test_*.py' -v
