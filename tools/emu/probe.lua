-- At each frame in SNAP_FRAMES, save a screenshot and append the engine
-- state (frame, scroll position, fine scroll) to PROBE_OUT.
local frames, last = {}, 0
for n in string.gmatch(os.getenv("SNAP_FRAMES") or "120", "%d+") do
  frames[tonumber(n)] = true
  if tonumber(n) > last then last = tonumber(n) end
end
local out = io.open(os.getenv("PROBE_OUT") or "probe.txt", "w")
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if frames[f] then
    local mem = manager:machine().devices[":maincpu"].spaces["program"]
    manager:machine().screens[":screen"]:snapshot()
    out:write(string.format("%d %d %d %d %d\n", f, mem:read_u8(0x2231) + 256 * mem:read_u8(0x2232),
      mem:read_u8(0xA5), mem:read_u8(0xB4), mem:read_u8(0x2235)))
    out:flush()
  end
  if f > last then out:close(); manager:machine():exit() end
end)
