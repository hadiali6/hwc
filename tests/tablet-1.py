import libevdev
import time

def main():
    dev = libevdev.Device()
    dev.name = "vtablet"
    dev.enable(libevdev.INPUT_PROP_DIRECT)
    dev.enable(libevdev.EV_KEY.BTN_TOOL_PEN)
    dev.enable(libevdev.EV_KEY.BTN_TOOL_RUBBER)
    dev.enable(libevdev.EV_KEY.BTN_TOUCH)
    dev.enable(libevdev.EV_KEY.BTN_STYLUS)
    dev.enable(libevdev.EV_KEY.BTN_STYLUS2)
    dev.enable(libevdev.EV_ABS.ABS_X, libevdev.InputAbsInfo(minimum=0, maximum=32767, resolution=100))
    dev.enable(libevdev.EV_ABS.ABS_Y, libevdev.InputAbsInfo(minimum=0, maximum=32767, resolution=100))
    dev.enable(libevdev.EV_ABS.ABS_PRESSURE, libevdev.InputAbsInfo(minimum=0, maximum=8191))
    dev.enable(libevdev.EV_SYN.SYN_REPORT)
    dev.enable(libevdev.EV_SYN.SYN_DROPPED)
    try:
        uinput = dev.create_uinput_device()
        print("new device at {} ({})".format(uinput.devnode, uinput.syspath))
        time.sleep(1)

        uinput.send_events([
            libevdev.InputEvent(libevdev.EV_KEY.BTN_TOUCH, value=0),
            libevdev.InputEvent(libevdev.EV_KEY.BTN_TOOL_PEN, value=1),
            libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, value=0),
        ])
        uinput.send_events([
            libevdev.InputEvent(libevdev.EV_KEY.BTN_TOUCH, value=0),
            libevdev.InputEvent(libevdev.EV_KEY.BTN_TOOL_PEN, value=0),
            libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, value=0),
        ])

        pc = 0
        direc = +1
        already_pressed_one = False
        for _ in range(250):
            pc_ = pc/100
            val_x = int(pc_*10000 + (1-pc_)*17767)
            val_y = int(pc_*5000 + (1-pc_)*22767)
            val_pres = int(pc_*10 + (1-pc_)*6000)
            print("send: x={}, y={}, press={} (pc={})".format(
                val_x,
                val_y,
                val_pres,
                pc))
            uinput.send_events([
                libevdev.InputEvent(libevdev.EV_ABS.ABS_X, value=val_y),
                libevdev.InputEvent(libevdev.EV_ABS.ABS_Y, value=val_y),
                libevdev.InputEvent(libevdev.EV_ABS.ABS_PRESSURE, value=val_pres),
                libevdev.InputEvent(libevdev.EV_KEY.BTN_TOUCH, value=1),
                libevdev.InputEvent(libevdev.EV_KEY.BTN_STYLUS, value=0),
                libevdev.InputEvent(libevdev.EV_KEY.BTN_STYLUS2, value=0),
                libevdev.InputEvent(libevdev.EV_KEY.BTN_TOOL_PEN, value=1),
                libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, value=0),
            ])
            pc += direc
            if not already_pressed_one:
                print("press")
                uinput.send_events([
                    libevdev.InputEvent(libevdev.EV_KEY.BTN_TOOL_PEN, value=1),
                    libevdev.InputEvent(libevdev.EV_KEY.BTN_TOUCH, value=1),
                    libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, value=0),
                ])
                already_pressed_one = True
            if pc >= 100 or pc <=0 :
                print("release")
                uinput.send_events([
                    libevdev.InputEvent(libevdev.EV_KEY.BTN_TOUCH, value=0),
                    libevdev.InputEvent(libevdev.EV_KEY.BTN_TOOL_PEN, value=0),
                    libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, value=0),
                ])
                if pc >= 100:
                    pc = 100
                    direc = -1
                if pc <= 0:
                    pc = 0
                    direc = +1
                time.sleep(5)
                print("press")
                uinput.send_events([
                    libevdev.InputEvent(libevdev.EV_KEY.BTN_TOOL_PEN, value=1),
                    libevdev.InputEvent(libevdev.EV_KEY.BTN_TOUCH, value=1),
                    libevdev.InputEvent(libevdev.EV_SYN.SYN_REPORT, value=0),
                ])
                already_pressed_one = True
            time.sleep(0.1)

    except Exception as e:
        print(e)


if __name__ == "__main__":
    main()
