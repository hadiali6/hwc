test-touch:
    uv venv
    source ./.venv/bin/activate
    uv pip install python-uinput
    uv run ./tests/touch.py
