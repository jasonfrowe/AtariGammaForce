-- Take screenshots at the frames listed in SNAP_FRAMES (comma separated),
-- then exit after the last one. Used by tools/snap.sh.
local frames = {}
local last = 0
for n in string.gmatch(os.getenv("SNAP_FRAMES") or "120", "%d+") do
  frames[tonumber(n)] = true
  if tonumber(n) > last then last = tonumber(n) end
end
local f = 0
emu.register_frame_done(function()
  f = f + 1
  if frames[f] then manager:machine().screens[":screen"]:snapshot() end
  if f > last then manager:machine():exit() end
end)
