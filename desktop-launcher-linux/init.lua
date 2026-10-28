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

ttt.on_install(function() launcher("install") end)
ttt.on_uninstall(function() launcher("remove") end)

ttt.register({
  commands = {
    {
      id = "desktopLauncher.repair",
      title = "Desktop Launcher: Repair",
      handler = function()
        local ok, err = pcall(launcher, "repair")
        ttt.notify(ok and "Desktop launcher reinstalled" or ("Desktop launcher: " .. tostring(err)))
      end,
    },
  },
})
