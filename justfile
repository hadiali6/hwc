test-touch:
    uv venv
    source ./.venv/bin/activate
    uv pip install libevdev
    uv run ./tests/touch.py

test-tablet:
    uv venv
    source ./.venv/bin/activate
    uv pip install libevdev
    uv run ./tests/tablet-1.py
    uv run ./tests/tablet-2.py
