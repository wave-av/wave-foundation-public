# Provenance: test path setup for the local-offload chassis. See CHASSIS.md.
"""Put `frameworks/model-routing/` on sys.path so `import local_offload` works under any cwd."""
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
