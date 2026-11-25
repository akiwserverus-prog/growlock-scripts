--[[
  GROWLOCK HUB - Rayfield (dengan fallback GUI kalau HttpGet gagal)
]]

-- ================= LOADER RAYFIELD =================
local function httpGet(url)
    local ok, body = pcall(function()
        if game.HttpGet then return game:HttpGet(url) end
        if httprequest then return httprequest({ Url = url, Method = "GET" }).Body end
        if request then return request({ Url = url, Method = "GET" }).Body end
        if syn and syn.request then return syn.request({ Url = url, Method = "GET" }).Body end
    end)
    return ok and body or nil
end

local urls = {
    "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua",
    "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua?nocache=1",
    "https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua?v=2",
}

local Rayfield
for _, url in ipairs(urls) do
    local src = httpGet(url)
    if src and #src > 500 then
        local ok, lib = pcall(function() return loadstring(src)() end)
        if ok and lib and type(lib.CreateWindow) == "function" then
            Rayfield = lib
            break
        end
    end
end

local USE_RAY = Rayfield ~= nil
if not USE_RAY then
    warn("[GrowlockHub] Rayfield gagal dimuat. Pakai GUI fallback.")
end

-- ================= DASAR =================
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local getgenv = getgenv or function() return _G end
local genv = getgenv()

local refreshInfo, resolveRemotes
local Remotes, learned, printed = {}, {}, {}
local worldFolder

local Config = {
    SelectedSeed = "Apple Seed",
    PunchDelay = 0.10, CollectDelay = 0.15, PlantDelay = 0.30, HarvestDelay = 0.20,
    PunchRange = 18, CollectRange = 22, PlantRange = 18, HarvestRange = 18,
    TreeKeywords = {"tree", "block", "crop", "plant", "bush", "ore", "log", "wood", "tile"},
    DropKeywords = {"drop", "item", "fruit", "apple", "seed", "loot", "drops"},
    SoilKeywords = {"soil", "tile", "grass", "plot", "farm", "ground", "dirt"},
}
local Names = { Punch = "PunchPlayer", Collect = "TakeDrop", Plant = "PlaceSeed", Harvest = "HarvestProvider" }
local TargetNames = {
    [Names.Punch] = true, [Names.Collect] = true,
    [Names.Plant] = true, [Names.Harvest] = true,
}

local function notify(title, content)
    if USE_RAY then
        pcall(function() Rayfield:Notify({ Title = title, Content = content, Duration = 4 }) end)
    end
    print("[GrowlockHub] " .. tostring(title) .. ": " .. tostring(content))
end

local function contains(str, list)
    if not str then return false end
    str = str:lower()
    for _, kw in ipairs(list) do if str:find(kw, 1, true) then return true end end
    return false
end

local function getHRP()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function fmt(v, depth)
    depth = depth or 0
    if depth > 3 then return "..." end
    local t = typeof(v)
    if t == "Instance" then return v.Name .. "[" .. v.ClassName .. "]" end
    if t == "Vector3" then return string.format("Vector3(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z) end
    if t == "Vector2" then return string.format("Vector2(%.1f,%.1f)", v.X, v.Y) end
    if t == "CFrame" then return "CFrame(" .. fmt(v.Position) .. ")" end
    if type(v) == "string" then return '"' .. v .. '"' end
    if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
    if type(v) == "table" then
        local p = {}
        for k, val in pairs(v) do table.insert(p, tostring(k) .. "=" .. fmt(val, depth + 1)) end
        return "{" .. table.concat(p, ", ") .. "}"
    end
    return tostring(v)
end

local function dumpArgs(args)
    local p = {}
    for i, v in ipairs(args) do table.insert(p, fmt(v)) end
    return "(" .. table.concat(p, ", ") .. ")"
end

-- ================= UI =================
local MainTab, SetTab, InfoTab
local lblRemote, lblLearn, lblSeed
local fbStatus, fbFrame

if USE_RAY then
    local W = Rayfield:CreateWindow({
        Name = "Growlock Hub", KeySystem = false,
        ConfigurationSaving = { Enabled = false },
    })
    MainTab = W:CreateTab("Main")
    SetTab  = W:CreateTab("Pengaturan")
    InfoTab = W:CreateTab("Info")

    MainTab:CreateSection("Auto Farm")
    MainTab:CreateToggle({ Name = "Auto Punch", CurrentValue = false, Flag = "GL_Punch",
        Callback = function(v) genv.GrowlockAutoPunch = v end })
    MainTab:CreateToggle({ Name = "Auto Collect", CurrentValue = false, Flag = "GL_Collect",
        Callback = function(v) genv.GrowlockAutoCollect = v end })
    MainTab:CreateToggle({ Name = "Auto Plant", CurrentValue = false, Flag = "GL_Plant",
        Callback = function(v) genv.GrowlockAutoPlant = v end })
    MainTab:CreateToggle({ Name = "Auto Harvest", CurrentValue = false, Flag = "GL_Harvest",
        Callback = function(v) genv.GrowlockAutoHarvest = v end })

    MainTab:CreateSection("Item / Seed")
    MainTab:CreateDropdown({
        Name = "Pilih Seed",
        Options = {"Apple Seed", "Banana Seed", "Cherry Seed", "Orange Seed", "Grape Seed", "Tree Seed"},
        CurrentOption = Config.SelectedSeed, Flag = "GL_Seed",
        Callback = function(o) Config.SelectedSeed = o; refreshInfo() end,
    })
    MainTab:CreateInput({ Name = "Seed custom", PlaceholderText = "Nama item...",
        RemoveTextAfterFocusLost = false, Flag = "GL_SeedCustom",
        Callback = function(t) if t and t ~= "" then Config.SelectedSeed = t; refreshInfo() end end })

    MainTab:CreateSection("Misc")
    MainTab:CreateButton({ Name = "Refresh Remote", Callback = function() resolveRemotes() end })
    MainTab:CreateButton({ Name = "Tes UI", Callback = function() notify("Tes UI", "Callback jalan.") end })
    MainTab:CreateButton({ Name = "Hapus UI", Callback = function() Rayfield:Destroy() end })

    SetTab:CreateSection("Delay")
    SetTab:CreateSlider({ Name = "Punch Delay", Range = {0.02, 1}, Increment = 0.02,
        CurrentValue = Config.PunchDelay, Flag = "GL_PD", Callback = function(v) Config.PunchDelay = v end })
    SetTab:CreateSlider({ Name = "Collect Delay", Range = {0.02, 1}, Increment = 0.02,
        CurrentValue = Config.CollectDelay, Flag = "GL_CD", Callback = function(v) Config.CollectDelay = v end })
    SetTab:CreateSlider({ Name = "Plant Delay", Range = {0.05, 2}, Increment = 0.05,
        CurrentValue = Config.PlantDelay, Flag = "GL_LD", Callback = function(v) Config.PlantDelay = v end })
    SetTab:CreateSection("Radius")
    SetTab:CreateSlider({ Name = "Punch Range", Range = {5, 60}, Increment = 1,
        CurrentValue = Config.PunchRange, Flag = "GL_PR", Callback = function(v) Config.PunchRange = v end })
    SetTab:CreateSlider({ Name = "Collect Range", Range = {5, 60}, Increment = 1,
        CurrentValue = Config.CollectRange, Flag = "GL_CR", Callback = function(v) Config.CollectRange = v end })
    SetTab:CreateSlider({ Name = "Plant Range", Range = {5, 60}, Increment = 1,
        CurrentValue = Config.PlantRange, Flag = "GL_TR", Callback = function(v) Config.PlantRange = v end })

    InfoTab:CreateSection("Status")
    lblRemote = InfoTab:CreateLabel("-")
    lblLearn  = InfoTab:CreateLabel("-")
    lblSeed   = InfoTab:CreateLabel("-")
    InfoTab:CreateSection("Cara pakai")
    InfoTab:CreateLabel("1. Nyalakan toggle.")
    InfoTab:CreateLabel("2. PUKUL & TANAM manual 1x untuk learn argumen.")
    InfoTab:CreateLabel("3. Lihat console: [GrowlockHub] ARG ...")
else
    -- ===== GUI FALLBACK (tanpa library) =====
    local sg = Instance.new("ScreenGui")
    sg.Name = "GrowlockHubFallback"
    sg.ResetOnSpawn = false
    sg.Parent = LocalPlayer:WaitForChild("PlayerGui")

    fbFrame = Instance.new("Frame")
    fbFrame.Size = UDim2.new(0, 300, 0, 360)
    fbFrame.Position = UDim2.new(0.05, 0, 0.25, 0)
    fbFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
    fbFrame.Parent = sg

    local head = Instance.new("TextLabel")
    head.Size = UDim2.new(1, 0, 0, 34)
    head.BackgroundColor3 = Color3.fromRGB(40, 180, 90)
    head.Text = "GROWLOCK HUB (fallback)"
    head.TextColor3 = Color3.new(1, 1, 1)
    head.Font = Enum.Font.GothamBold
    head.TextSize = 15
    head.Parent = fbFrame

    fbStatus = Instance.new("TextLabel")
    fbStatus.Size = UDim2.new(1, -10, 0, 42)
    fbStatus.Position = UDim2.new(0, 5, 0, 38)
    fbStatus.BackgroundTransparency = 1
    fbStatus.TextColor3 = Color3.fromRGB(200, 200, 200)
    fbStatus.Font = Enum.Font.Gotham
    fbStatus.TextSize = 11
    fbStatus.TextWrapped = true
    fbStatus.Parent = fbFrame

    local function fbToggle(name, y, key)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -20, 0, 32)
        b.Position = UDim2.new(0, 10, 0, y)
        b.BackgroundColor3 = Color3.fromRGB(55, 55, 70)
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.Gotham
        b.TextSize = 13
        b.Text = name .. " : OFF"
        b.Parent = fbFrame
        local s = false
        b.MouseButton1Click:Connect(function()
            s = not s
            b.Text = name .. " : " .. (s and "ON" or "OFF")
            b.BackgroundColor3 = s and Color3.fromRGB(40, 160, 80) or Color3.fromRGB(55, 55, 70)
            genv[key] = s
        end)
    end
    fbToggle("Auto Punch", 86, "GrowlockAutoPunch")
    fbToggle("Auto Collect", 124, "GrowlockAutoCollect")
    fbToggle("Auto Plant", 162, "GrowlockAutoPlant")
    fbToggle("Auto Harvest", 200, "GrowlockAutoHarvest")

    local seedBox = Instance.new("TextBox")
    seedBox.Size = UDim2.new(1, -20, 0, 30)
    seedBox.Position = UDim2.new(0, 10, 0, 240)
    seedBox.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
    seedBox.Text = Config.SelectedSeed
    seedBox.TextColor3 = Color3.new(1, 1, 1)
    seedBox.Font = Enum.Font.Gotham
    seedBox.TextSize = 13
    seedBox.Parent = fbFrame
    seedBox.FocusLost:Connect(function()
        if seedBox.Text ~= "" then Config.SelectedSeed = seedBox.Text; refreshInfo() end
    end)

    local rb = Instance.new("TextButton")
    rb.Size = UDim2.new(1, -20, 0, 30)
    rb.Position = UDim2.new(0, 10, 0, 280)
    rb.BackgroundColor3 = Color3.fromRGB(120, 80, 40)
    rb.Text = "Refresh Remote"
    rb.TextColor3 = Color3.new(1, 1, 1)
    rb.Font = Enum.Font.Gotham
    rb.TextSize = 12
    rb.Parent = fbFrame
    rb.MouseButton1Click:Connect(function() resolveRemotes() end)

    local xb = Instance.new("TextButton")
    xb.Size = UDim2.new(1, -20, 0, 28)
    xb.Position = UDim2.new(0, 10, 0, 320)
    xb.BackgroundColor3 = Color3.fromRGB(100, 50, 50)
    xb.Text = "Tutup GUI"
    xb.TextColor3 = Color3.new(1, 1, 1)
    xb.Font = Enum.Font.Gotham
    xb.TextSize = 12
    xb.Parent = fbFrame
    xb.MouseButton1Click:Connect(function() fbFrame.Visible = false end)
end

function refreshInfo()
    local r = "Punch: " .. tostring(Remotes.Punch and "OK" or "X") ..
              " Collect: " .. tostring(Remotes.Collect and "OK" or "X") ..
              "\nPlant: " .. tostring(Remotes.Plant and "OK" or "X") ..
              " Harvest: " .. tostring(Remotes.Harvest and "OK" or "X")
    local l = "Learn Punch: " .. (learned[Names.Punch] and dumpArgs(learned[Names.Punch]) or "belum") ..
              "\nLearn Plant: " .. (learned[Names.Plant] and dumpArgs(learned[Names.Plant]) or "belum")
    local s = "Seed: " .. tostring(Config.SelectedSeed)
    pcall(function()
        if USE_RAY then
            lblRemote:Set(r); lblLearn:Set(l); lblSeed:Set(s)
        elseif fbStatus then
            fbStatus.Text = r .. "\n" .. s
        end
    end)
end
refreshInfo()

-- ================= LOGIC =================
function resolveRemotes()
    local ok, err = pcall(function()
        if not worldFolder then
            for _, o in ipairs(game:GetDescendants()) do
                if o.Name == "WorldRemotes" then worldFolder = o; break end
            end
        end
        for k, name in pairs(Names) do
            Remotes[k] = worldFolder and worldFolder:FindFirstChild(name) or nil
        end
    end)
    if not ok then warn("[GrowlockHub] resolveRemotes error: " .. tostring(err)) end
    refreshInfo()
    notify("Remote", "Punch=" .. tostring(Remotes.Punch and "OK" or "X") ..
        " Collect=" .. tostring(Remotes.Collect and "OK" or "X") ..
        " Plant=" .. tostring(Remotes.Plant and "OK" or "X") ..
        " Harvest=" .. tostring(Remotes.Harvest and "OK" or "X"))
end

pcall(function()
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local args = { ... }
        local method = getnamecallmethod and getnamecallmethod() or ""
        local name = self and self.Name
        if TargetNames[name] and (method == "FireServer" or method == "InvokeServer") then
            learned[name] = args
            if not printed[name] then
                printed[name] = true
                print("[GrowlockHub] ARG " .. name .. ": " .. dumpArgs(args))
                notify("Learn " .. name, dumpArgs(args))
                refreshInfo()
            end
        end
        return oldNamecall(self, ...)
    end)
end)

local function buildArgs(name, target, extra)
    local base = learned[name]
    if not base then return nil end
    local args = {}
    for _, v in ipairs(base) do
        local t = typeof(v)
        if t == "Instance" then
            if v:IsA("BasePart") or v:IsA("Model") then table.insert(args, target)
            else table.insert(args, v) end
        elseif t == "Vector3" then table.insert(args, target.Position or target)
        elseif t == "string" then
            if name == Names.Plant and extra and v:lower():find("seed") then table.insert(args, extra)
            else table.insert(args, v) end
        else table.insert(args, v) end
    end
    return args
end

local Patterns = {
    [Names.Punch] = {
        function(t) return { t.Position } end, function(t) return { t } end,
        function(t) return { t.Position, "Hand" } end, function(t) return { t, "Hand" } end,
    },
    [Names.Collect] = {
        function(t) return { t } end, function(t) return { t.Position } end,
        function(t) return { t.Name } end,
    },
    [Names.Plant] = {
        function(t, s) return { s, t.Position } end, function(t, s) return { t.Position, s } end,
        function(t, s) return { t, s } end, function(t, s) return { s, t } end,
        function(t, s) return { s } end,
    },
    [Names.Harvest] = { function(t) return { t } end, function(t) return { t.Position } end },
}

local function send(name, target, extra)
    local remote = Remotes[name]
    if not remote then return false end
    local args = buildArgs(name, target, extra)
    if args then
        pcall(function() remote:FireServer(unpack(args)) end)
        return true
    end
    for _, fn in ipairs(Patterns[name] or {}) do
        local a = fn(target, extra)
        pcall(function() remote:FireServer(unpack(a)) end)
        wait(0.05)
    end
    return true
end

local function doPunch()
    local hrp = getHRP(); if not hrp then return end
    for _, o in ipairs(workspace:GetDescendants()) do
        if o:IsA("BasePart") and contains(o.Name, Config.TreeKeywords)
           and (hrp.Position - o.Position).Magnitude <= Config.PunchRange then
            send(Names.Punch, o); wait(Config.PunchDelay)
        end
    end
end

local function doCollect()
    local hrp = getHRP(); if not hrp then return end
    for _, o in ipairs(workspace:GetDescendants()) do
        if (o:IsA("BasePart") or o:IsA("Model")) and contains(o.Name, Config.DropKeywords) then
            local part = o:IsA("Model") and (o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart")) or o
            if part and (hrp.Position - part.Position).Magnitude <= Config.CollectRange then
                send(Names.Collect, o); wait(Config.CollectDelay)
            end
        end
    end
end

local function doPlant()
    local hrp = getHRP(); if not hrp then return end
    for _, o in ipairs(workspace:GetDescendants()) do
        if o:IsA("BasePart") and contains(o.Name, Config.SoilKeywords)
           and (hrp.Position - o.Position).Magnitude <= Config.PlantRange then
            send(Names.Plant, o, Config.SelectedSeed); wait(Config.PlantDelay)
        end
    end
end

local function doHarvest()
    local hrp = getHRP(); if not hrp then return end
    for _, o in ipairs(workspace:GetDescendants()) do
        if o:IsA("BasePart") and contains(o.Name, Config.TreeKeywords)
           and (hrp.Position - o.Position).Magnitude <= Config.HarvestRange then
            send(Names.Harvest, o); wait(Config.HarvestDelay)
        end
    end
end

genv.GrowlockAutoPunch = false
genv.GrowlockAutoCollect = false
genv.GrowlockAutoPlant = false
genv.GrowlockAutoHarvest = false

spawn(function() while true do if genv.GrowlockAutoPunch then pcall(doPunch) end wait(0.05) end end)
spawn(function() while true do if genv.GrowlockAutoCollect then pcall(doCollect) end wait(0.05) end end)
spawn(function() while true do if genv.GrowlockAutoPlant then pcall(doPlant) end wait(0.05) end end)
spawn(function() while true do if genv.GrowlockAutoHarvest then pcall(doHarvest) end wait(0.05) end end)

pcall(resolveRemotes)
print("[GrowlockHub] Siap. Rayfield=" .. tostring(USE_RAY) .. ". Punch & tanam manual 1x.")
