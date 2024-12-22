import time
import libevdev

def main():
    dev = libevdev.Device()
    dev.name = "vswitch"
    dev.enable(libevdev.EV_SW.SW_LID)
    dev.enable(libevdev.EV_SW.SW_TABLET_MODE)


    try:
        uinput = dev.create_uinput_device();
        print("new device at {} ({})".format(uinput.devnode, uinput.syspath))
        time.sleep(1)

        uinput.send_events([
            libevdev.InputEvent(libevdev.EV_SW.SW_LID, 1),
            libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, 0)
        ])

        time.sleep(0.5)

        uinput.send_events([
            libevdev.InputEvent(libevdev.EV_SW.SW_LID, 0),
            libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, 0)
        ])

        time.sleep(0.5)

        uinput.send_events([
            libevdev.InputEvent(libevdev.EV_SW.SW_TABLET_MODE, 1),
            libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, 0)
        ])

        time.sleep(0.5)

        uinput.send_events([
            libevdev.InputEvent(libevdev.EV_SW.SW_TABLET_MODE, 0),
            libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, 0)
        ])

    except Exception as e:
        print("An error occurred:", e)


if __name__ == "__main__":
    main()
