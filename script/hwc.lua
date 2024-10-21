--Example configuation. 
--Lives in $XDG_CONFIG_HOME/hwc/hwc.lua or $HOME/.config/hwc/hwc.lua

local hwc = hwc

hwc.spawn("foot")

hwc.add_keybind("return", "Alt", false, false, nil, function()
	hwc.spawn("foot")
end)

hwc.add_keybind("r", "Alt", false, false, nil, hwc.reload)

hwc.add_keybind("escape", "Alt", false, false, nil, hwc.exit)

local id = hwc.add_keybind("f", "Alt", true, false, nil, function()
	print("remove me!")
end)

hwc.add_keybind("d", "Alt", false, false, nil, function()
	hwc.remove_keybind_by_id(id)
end)

hwc.add_keybind("f", "Alt+Shift", false, false, nil, function()
	print("remove me too!")
end)

hwc.add_keybind("d", "Alt+Shift", false, false, nil, function()
	hwc.remove_keybind("f", "Alt+Shift")
end)

hwc.add_keybind("x", "Alt", false, true, nil, function()
    print("on release!")
end)

hwc.add_keybind("v", "Alt", true, false, nil, function()
    print("repeated!")
end)
