import time
import libevdev

def emit_touch(device, x, y, touch_down):
    events = [
        libevdev.InputEvent(libevdev.EV_ABS.ABS_X, x),
        libevdev.InputEvent(libevdev.EV_ABS.ABS_Y, y),
        libevdev.InputEvent(libevdev.EV_KEY.BTN_TOUCH, 1 if touch_down else 0),
        libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, 0)
    ]
    for event in events:
        device.send_events([event])

def swipe(device, start_x, start_y, end_x, end_y, steps=10):
    x_step = (end_x - start_x) // steps
    y_step = (end_y - start_y) // steps

    device.send_events([
        libevdev.InputEvent(libevdev.EV_KEY.BTN_TOUCH, 1),
        libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, 0)
    ])
    for i in range(steps + 1):
        device.send_events([
            libevdev.InputEvent(libevdev.EV_ABS.ABS_X, start_x + i * x_step),
            libevdev.InputEvent(libevdev.EV_ABS.ABS_Y, start_y + i * y_step),
            libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, 0)
        ])
        time.sleep(0.05)
    device.send_events([
        libevdev.InputEvent(libevdev.EV_KEY.BTN_TOUCH, 0),
        libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, 0)
    ])

def multitouch(device, points):
    for x, y in points:
        device.send_events([
            libevdev.InputEvent(libevdev.EV_ABS.ABS_X, x),
            libevdev.InputEvent(libevdev.EV_ABS.ABS_Y, y),
            libevdev.InputEvent(libevdev.EV_KEY.BTN_TOUCH, 1),
            libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, 0)
        ])
        time.sleep(0.2)
    device.send_events([
        libevdev.InputEvent(libevdev.EV_KEY.BTN_TOUCH, 0),
        libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, 0)
    ])

def main():
    dev = libevdev.Device()
    dev.name = "vtouch"
    dev.enable(libevdev.EV_KEY.BTN_TOUCH)
    dev.enable(libevdev.EV_ABS.ABS_X, libevdev.InputAbsInfo(minimum=0, maximum=4096))
    dev.enable(libevdev.EV_ABS.ABS_Y, libevdev.InputAbsInfo(minimum=0, maximum=4096))
    try:
        uinput = dev.create_uinput_device()
        print("new device at {} ({})".format(uinput.devnode, uinput.syspath))
        time.sleep(1)

        print("testing single touch at (1000, 1000)")
        emit_touch(uinput, 1000, 1000, True)
        time.sleep(0.5)
        emit_touch(uinput, 1000, 1000, False)

        print("testing swipe guesture at (500, 500) to (2000, 2000)")
        swipe(uinput, 500, 500, 2000, 2000)

        print("testing multitouch with points [(500, 500), (1500, 1500)]")
        multitouch(uinput, [(500, 500), (1500, 1500)])

        print("complete")

    except Exception as e:
        print("An error occurred:", e)

if __name__ == "__main__":
    main()
