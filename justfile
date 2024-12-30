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

# note:
# this test only works under DRM backend
# not sure why as `libinput debug-events` shows the events happening properly
# also by default systemd-logind does a suspend (aka set computer to sleep) upon switch on
test-switch:
    uv venv
    source ./.venv/bin/activate
    uv pip install libevdev
    uv run ./tests/switch.py
