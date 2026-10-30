-- Scripted play for headless tests (tools/play.sh).
--
-- PLAY_SCRIPT names a text file of "<frame> <command> [args]" lines:
--   600 press P1 Button 1     hold an input (field names as in the a7800
--   700 release P1 Button 1     input menu: P1 Up/Down/Left/Right, P1 Button 1/2,
--                               Pause, Reset, Select)
--   650 snap                  save a screenshot
--   650 peek 2312 4           log 4 bytes from $2312 to PLAY_OUT
--   650 poke 2621 01 02      write bytes from $2621
--   650 pc                    log the CPU registers
--   650 dma                   log MARIA's figures for the last frame: DMA cycles,
--                               CPU cycles stolen, lines cut short, busiest line
--                               (needs the a7800 fork's outputs)
--   650 prof on / prof off    start / pause the emulator's cycle profiler
--                               (A7800_PROFILE; see tools/pcprof.py)
--   900 exit
-- Lines starting with # are comments.

local actions = {}
local last = 0
for line in io.lines(os.getenv("PLAY_SCRIPT")) do
  local f, rest = line:match("^%s*(%d+)%s+(.+)$")
  if f then
    f = tonumber(f)
    actions[f] = actions[f] or {}
    table.insert(actions[f], rest)
    if f > last then last = f end
  end
end

local fields = {}
for tag, port in pairs(manager:machine():ioport().ports) do
  if tag:find("joy2") == nil then
    for name, field in pairs(port.fields) do fields[name] = field end
  end
end

local out = io.open(os.getenv("PLAY_OUT") or "play.txt", "w")
local held = {}
local f = 0
emu.register_frame_done(function()
  f = f + 1
  for name, _ in pairs(held) do fields[name]:set_value(1) end
  for _, cmd in ipairs(actions[f] or {}) do
    local verb, arg = cmd:match("^(%S+)%s*(.*)$")
    if verb == "press" then
      held[arg] = true
      fields[arg]:set_value(1)
    elseif verb == "release" then
      held[arg] = nil
      fields[arg]:set_value(0)
    elseif verb == "snap" then
      manager:machine().screens[":screen"]:snapshot()
    elseif verb == "peek" then
      local a, n = arg:match("(%x+)%s*(%d*)")
      a = tonumber(a, 16); n = tonumber(n) or 1
      local mem = manager:machine().devices[":maincpu"].spaces["program"]
      local vals = {}
      for i = 0, n - 1 do vals[#vals + 1] = string.format("%02x", mem:read_u8(a + i)) end
      out:write(string.format("%d %04x %s\n", f, a, table.concat(vals, " ")))
      out:flush()
    elseif verb == "poke" then
      local a, rest2 = arg:match("(%x+)%s*(.*)$")
      a = tonumber(a, 16)
      local mem = manager:machine().devices[":maincpu"].spaces["program"]
      for v in rest2:gmatch("%x+") do mem:write_u8(a, tonumber(v, 16)); a = a + 1 end
    elseif verb == "pc" then
      local st = manager:machine().devices[":maincpu"].state
      out:write(string.format("%d pc %04x sp %02x a %02x x %02x y %02x\n", f, st["PC"].value,
        st["SP"].value, st["A"].value, st["X"].value, st["Y"].value))
      out:flush()
    elseif verb == "dma" then
      local o = manager:machine():outputs()
      out:write(string.format("%d dma %d stolen %d over %d peak %d line %d\n", f,
        o:get_value("maria_cycles"), o:get_value("maria_stolen"), o:get_value("maria_over"),
        o:get_value("maria_peak"), o:get_value("maria_peak_line")))
      out:flush()
    elseif verb == "prof" then
      manager:machine():outputs():set_value("a7800_prof", arg == "on" and 1 or 2)
    elseif verb == "exit" then
      out:close()
      manager:machine():exit()
    end
  end
  if f > last then out:close(); manager:machine():exit() end
end)
