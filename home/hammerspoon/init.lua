-- Menu-bar toggle + hotkey for `pmset disablesleep`, so the lid can be
-- closed (Intel Mac - no external display needed, unlike Apple Silicon's
-- hardware-enforced clamshell requirement) while background/agent work
-- keeps running. Toggling prompts for the admin password via a native
-- macOS dialog each time (via `osascript ... with administrator
-- privileges`), not a broken terminal-style sudo prompt.

local sleepDisableMenu = hs.menubar.new()

local function isSleepDisabled()
  local output = hs.execute("/usr/bin/pmset -g | /usr/bin/grep -i SleepDisabled")
  return output:match("1") ~= nil
end

local function updateMenuIcon(disabled)
  -- Rocket = sleep disabled (awake-while-closed active), moon = normal.
  sleepDisableMenu:setIcon(nil)
  sleepDisableMenu:setTitle(disabled and "🚀" or "🌙")
  sleepDisableMenu:setTooltip(disabled
    and "Lid-close sleep: DISABLED (lid can be closed, machine stays awake)"
    or "Lid-close sleep: normal")
end

local function setDisableSleep(disabled)
  local value = disabled and "1" or "0"
  local script = string.format(
    'do shell script "/usr/bin/pmset -a disablesleep %s" with administrator privileges',
    value
  )
  local ok, _, descriptor = hs.osascript.applescript(script)
  if not ok then
    hs.alert.show("Failed to change sleep setting")
    return
  end
  updateMenuIcon(disabled)
  hs.alert.show(disabled and "Lid-close sleep disabled" or "Lid-close sleep re-enabled")
end

local function toggleDisableSleep()
  setDisableSleep(not isSleepDisabled())
end

sleepDisableMenu:setClickCallback(toggleDisableSleep)
updateMenuIcon(isSleepDisabled())

hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "S", toggleDisableSleep)

-- Optional machine-local extension. If ~/.hammerspoon/work.lua exists, load
-- it after the base config. A generic extension point - this file stays
-- agnostic about what the extra config is; whatever drops a work.lua there
-- owns its content. Absent on a machine without one, this is a no-op.
local workFile = os.getenv("HOME") .. "/.hammerspoon/work.lua"
if hs.fs.attributes(workFile) then
  local ok, err = pcall(dofile, workFile)
  if not ok then
    hs.printf("work.lua failed to load: %s", tostring(err))
  end
end
