import time
import uinput

def emit_touch(device, x, y, touch_down):
    """emulates a single touch event"""
    device.emit(uinput.ABS_X, x)
    device.emit(uinput.ABS_Y, y)
    device.emit(uinput.BTN_TOUCH, 1 if touch_down else 0)

def swipe(device, start_x, start_y, end_x, end_y, steps=10):
    """simulates a swipe gesture from start to end coordinates"""
    x_step = (end_x - start_x) // steps
    y_step = (end_y - start_y) // steps

    # Start touch
    device.emit(uinput.BTN_TOUCH, 1)
    for i in range(steps + 1):
        device.emit(uinput.ABS_X, start_x + i * x_step)
        device.emit(uinput.ABS_Y, start_y + i * y_step)
        time.sleep(0.05)  # Mimic natural touch delay
    # End touch
    device.emit(uinput.BTN_TOUCH, 0)

def multitouch(device, points):
    """simulates multitouch events by emulating multiple sequential touches"""
    for x, y in points:
        device.emit(uinput.ABS_X, x)
        device.emit(uinput.ABS_Y, y)
        device.emit(uinput.BTN_TOUCH, 1)
        time.sleep(0.2)  # Brief pause for demonstration
    # End all touches
    device.emit(uinput.BTN_TOUCH, 0)

def main():
    events = [
        uinput.ABS_X + (0, 4096, 0, 0),
        uinput.ABS_Y + (0, 4096, 0, 0),
        uinput.BTN_TOUCH,
    ]

    with uinput.Device(events, name="TestTouchDevice") as device:
        print("Virtual touchscreen device initialized.")
        time.sleep(1)  # required allow compositor to detect the device

        # Single touch
        print("Testing single touch at (1000, 1000)")
        emit_touch(device, 1000, 1000, True)
        time.sleep(0.5)
        emit_touch(device, 1000, 1000, False)

        # Swipe gesture
        print("Testing swipe from (500, 500) to (2000, 2000)")
        swipe(device, 500, 500, 2000, 2000)

        # Multitouch gesture
        print("Testing multitouch with points [(500, 500), (1500, 1500)]")
        multitouch(device, [(500, 500), (1500, 1500)])

        print("All tests completed.")

if __name__ == "__main__":
    main()
