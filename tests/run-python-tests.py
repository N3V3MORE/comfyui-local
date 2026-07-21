import sys
import unittest
from pathlib import Path


TEST_ROOT = Path(__file__).resolve().parent
suite = unittest.defaultTestLoader.discover(TEST_ROOT / "unit", pattern="test_*.py")
result = unittest.TextTestRunner(stream=sys.stdout, verbosity=2).run(suite)
raise SystemExit(0 if result.wasSuccessful() else 1)
