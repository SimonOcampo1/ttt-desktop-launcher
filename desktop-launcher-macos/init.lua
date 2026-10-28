local ttt = require("ttt")
local sys = require("ttt.system")

local function launcher(action)
  local exe = ttt.executable_path and ttt.executable_path() or ""
  local res = sys.exec("sh", { ttt.plugin_dir() .. "/launcher.sh", action, exe or "" })
  if res.exit_code ~= 0 then
    local msg = res.stderr:gsub("%s+$", "")
    error(msg ~= "" and msg or ("launcher.sh " .. action .. " failed"), 0)
  end
end

local function command(action, done)
  return function()
    local ok, err = pcall(launcher, action)
    ttt.notify(ok and done or ("Desktop launcher: " .. tostring(err)))
  end
end

ttt.on_install(function() launcher("install") end)
ttt.on_uninstall(function() launcher("remove") end)

ttt.register({
  commands = {
    {
      id = "desktopLauncher.repair",
      title = "Desktop Launcher: Repair",
      handler = command("repair", "TTT.app reinstalled"),
    },
    {
      id = "desktopLauncher.setDefaults",
      title = "Desktop Launcher: Open Markdown and JSON with ttt",
      handler = command("set-defaults", "Finder now opens Markdown and JSON files in ttt"),
    },
  },
})
