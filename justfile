test-touch:
    uv venv
    source ./.venv/bin/activate
    uv pip install libevdev
    uv run ./tests/touch.py

test-tablet-tool:
    uv venv
    source ./.venv/bin/activate
    uv pip install libevdev
    uv run ./tests/tablet-tool-1.py
    uv run ./tests/tablet-tool-2.py

test-tablet-tool-1:
    uv venv
    source ./.venv/bin/activate
    uv pip install libevdev
    uv run ./tests/tablet-tool-1.py

test-tablet-tool-2:
    uv venv
    source ./.venv/bin/activate
    uv pip install libevdev
    uv run ./tests/tablet-tool-2.py
