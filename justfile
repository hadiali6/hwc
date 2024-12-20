test-touch:
    uv venv
    source ./.venv/bin/activate
    uv pip install libevdev
    uv run ./tests/touch.py
