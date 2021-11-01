from pathlib import Path
with open(Path(__file__).parent / 'VERSION', 'r') as f:
    version = f.read().strip()