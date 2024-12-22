import libevdev
from libevdev import InputEvent, InputAbsInfo
import time


def prox_in(x, y, z=0, tilt=(0, 0), pressure=100, distance=0):
    return [
        InputEvent(libevdev.EV_ABS.ABS_X, x),
        InputEvent(libevdev.EV_ABS.ABS_Y, y),
        InputEvent(libevdev.EV_ABS.ABS_Z, z),
        # Note: wheel for pen/eraser must be 0
        InputEvent(libevdev.EV_ABS.ABS_WHEEL, 0),
        InputEvent(libevdev.EV_ABS.ABS_PRESSURE, pressure),
        InputEvent(libevdev.EV_ABS.ABS_DISTANCE, distance),
        InputEvent(libevdev.EV_ABS.ABS_TILT_X, tilt[0]),
        InputEvent(libevdev.EV_ABS.ABS_TILT_Y, tilt[1]),
        InputEvent(libevdev.EV_ABS.ABS_MISC, 2083),
        InputEvent(libevdev.EV_MSC.MSC_SERIAL, 297797542),
        # Change to BTN_TOOL_RUBBER for the eraser end
        InputEvent(libevdev.EV_KEY.BTN_TOOL_PEN, 1),
        InputEvent(libevdev.EV_SYN.SYN_REPORT, 0),
    ]


def prox_out():
    return [
        InputEvent(libevdev.EV_ABS.ABS_X, 0),
        InputEvent(libevdev.EV_ABS.ABS_Y, 0),
        InputEvent(libevdev.EV_ABS.ABS_Z, 0),
        InputEvent(libevdev.EV_ABS.ABS_WHEEL, 0),
        InputEvent(libevdev.EV_ABS.ABS_PRESSURE, 0),
        InputEvent(libevdev.EV_ABS.ABS_DISTANCE, 0),
        InputEvent(libevdev.EV_ABS.ABS_TILT_X, 0),
        InputEvent(libevdev.EV_ABS.ABS_TILT_Y, 0),
        InputEvent(libevdev.EV_ABS.ABS_MISC, 0),
        InputEvent(libevdev.EV_MSC.MSC_SERIAL, 297797542),
        InputEvent(libevdev.EV_KEY.BTN_TOOL_PEN, 0),
        InputEvent(libevdev.EV_SYN.SYN_REPORT, 0),
    ]


def motion(x, y, z=0, tilt=(0, 0), pressure=100, distance=0):
    return [
        InputEvent(libevdev.EV_ABS.ABS_X, x),
        InputEvent(libevdev.EV_ABS.ABS_Y, y),
        InputEvent(libevdev.EV_ABS.ABS_Z, z),
        InputEvent(libevdev.EV_ABS.ABS_WHEEL, 0),
        InputEvent(libevdev.EV_ABS.ABS_PRESSURE, pressure),
        InputEvent(libevdev.EV_ABS.ABS_DISTANCE, distance),
        InputEvent(libevdev.EV_ABS.ABS_TILT_X, tilt[0]),
        InputEvent(libevdev.EV_ABS.ABS_TILT_Y, tilt[1]),
        InputEvent(libevdev.EV_MSC.MSC_SERIAL, 297797542),
        InputEvent(libevdev.EV_SYN.SYN_REPORT, 0),
    ]


def main():
    dev = libevdev.Device()
    dev.name = "Wacom Cintiq Pro 16 Pen"
    dev.id = {'bustype': 0x3,
              'vendor': 0x56a,
              'product': 0x350,
              'version': 0xb}
    dev.enable(libevdev.EV_KEY.BTN_TOOL_PEN)
    dev.enable(libevdev.EV_KEY.BTN_TOOL_RUBBER)
    dev.enable(libevdev.EV_KEY.BTN_TOOL_BRUSH)
    dev.enable(libevdev.EV_KEY.BTN_TOOL_PENCIL)
    dev.enable(libevdev.EV_KEY.BTN_TOOL_AIRBRUSH)
    dev.enable(libevdev.EV_KEY.BTN_TOUCH)
    dev.enable(libevdev.EV_KEY.BTN_STYLUS)
    dev.enable(libevdev.EV_KEY.BTN_STYLUS2)
    dev.enable(libevdev.EV_KEY.BTN_STYLUS3)
    dev.enable(libevdev.EV_MSC.MSC_SERIAL)
    dev.enable(libevdev.INPUT_PROP_DIRECT)

    a = InputAbsInfo(minimum=0, maximum=69920, resolution=200)
    dev.enable(libevdev.EV_ABS.ABS_X, data=a)
    a = InputAbsInfo(minimum=0, maximum=39980, resolution=200)
    dev.enable(libevdev.EV_ABS.ABS_Y, data=a)
    a = InputAbsInfo(minimum=-900, maximum=899, resolution=287)
    dev.enable(libevdev.EV_ABS.ABS_Z, data=a)
    a = InputAbsInfo(minimum=0, maximum=2047)
    dev.enable(libevdev.EV_ABS.ABS_WHEEL, data=a)
    a = InputAbsInfo(minimum=0, maximum=8196)
    dev.enable(libevdev.EV_ABS.ABS_PRESSURE, data=a)
    a = InputAbsInfo(minimum=0, maximum=63)
    dev.enable(libevdev.EV_ABS.ABS_DISTANCE, data=a)
    a = InputAbsInfo(minimum=-64, maximum=63, resolution=57)
    dev.enable(libevdev.EV_ABS.ABS_TILT_X, data=a)
    dev.enable(libevdev.EV_ABS.ABS_TILT_Y, data=a)
    a = InputAbsInfo(minimum=0, maximum=0)
    dev.enable(libevdev.EV_ABS.ABS_MISC, data=a)

    try:
        uinput = dev.create_uinput_device()
        print("New device at {} ({})".format(uinput.devnode, uinput.syspath))

        # Sleep for a bit so udev, libinput, Xorg, Wayland, ... all have had
        # a chance to see the device and initialize it. Otherwise the event
        # will be sent by the kernel but nothing is ready to listen to the
        # device yet.
        time.sleep(1)

        x, y = 3000, 5000

        events = prox_in(x, y)
        uinput.send_events(events)
        time.sleep(0.012)

        for _ in range(20):
            x += 1000
            y += 1000
            events = motion(x, y)
            uinput.send_events(events)
            time.sleep(0.012)

        events = prox_out()
        uinput.send_events(events)
        time.sleep(0.012)
    except OSError as e:
        print(e)


if __name__ == "__main__":
    main()
