--[[
  GROWLOCK HUB - Rayfield (dengan fallback GUI)
  - Target block dipilih berdasarkan sisi relatif avatar:
    Depan / Belakang / Kiri / Kanan / Atas / Bawah
  - Item diambil dari GetInventory dan dipilih lewat dropdown.
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
        if ok and lib and type(lib.CreateWindow) == "function" then Rayfield = lib; break end
    end
end
local USE_RAY = Rayfield ~= nil
if not USE_RAY then warn("[GrowlockHub] Rayfield gagal dimuat. Pakai GUI fallback.") end

-- ================= DASAR =================
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local getgenv = getgenv or function() return _G end
local genv = getgenv()

local refreshInfo, resolveRemotes, refreshInventory
local Remotes, learned, printed = {}, {}, {}
local worldFolder

local Config = {
    Direction = "Depan",
    SelectedItem = "Apple Seed",

    PunchDelay = 0.10, CollectDelay = 0.15, PlantDelay = 0.30, HarvestDelay = 0.20,
    SearchRange = 12,
    TargetTolerance = 5,

    TreeKeywords = {"tree", "block", "crop", "plant", "bush", "ore", "log", "wood", "tile"},
    DropKeywords = {"drop", "item", "fruit", "apple", "seed", "loot", "drops"},
    SoilKeywords = {"soil", "tile", "grass", "plot", "farm", "ground", "dirt"},
}
local Names = {
    Punch = "PunchPlayer", Collect = "TakeDrop", Plant = "PlaceSeed",
    Harvest = "HarvestProvider", Inventory = "GetInventory",
}
local TargetNames = {
    [Names.Punch] = true, [Names.Collect] = true,
    [Names.Plant] = true, [Names.Harvest] = true,
}
local DIRECTIONS = {"Depan", "Belakang", "Kiri", "Kanan", "Atas", "Bawah"}

-- ================= UTIL =================
local function notify(title, content)
    if USE_RAY then pcall(function()
        Rayfield:Notify({ Title = title, Content = content, Duration = 4 })
    end) end
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

-- ================= TARGET BERDASAR SISI =================
local function getDirectionVector()
    local hrp = getHRP()
    if not hrp then return nil, nil end
    local cf = hrp.CFrame
    local map = {
        Depan     = cf.LookVector,
        Belakang  = -cf.LookVector,
        Kiri      = -cf.RightVector,
        Kanan     = cf.RightVector,
        Atas      = cf.UpVector,
        Bawah     = -cf.UpVector,
    }
    return map[Config.Direction] or cf.LookVector, hrp.Position
end

local function getTarget(keywords)
    local dir, origin = getDirectionVector()
    if not dir then return nil end

    -- 1) raycast ke arah yang dipilih
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    local res = workspace:Raycast(origin, dir * Config.SearchRange, params)
    if res and res.Instance and contains(res.Instance.Name, keywords) then
        return res.Instance
    end

    -- 2) fallback: objek terdekat ke titik di arah tersebut
    local point = origin + dir * 4
    local best, bestDist = nil, math.huge
    for _, o in ipairs(workspace:GetDescendants()) do
        if (o:IsA("BasePart") or o:IsA("Model")) and contains(o.Name, keywords) then
            local part = o:IsA("Model") and (o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart")) or o
            if part then
                local d = (part.Position - point).Magnitude
                if d < bestDist and d <= Config.TargetTolerance then
                    best, bestDist = o, d
                end
            end
        end
    end
    return best
end

-- ================= INVENTORI =================
local function parseInventory(res)
    local set = {}
    local function add(n)
        if type(n) == "string" and n ~= "" then set[n] = true end
    end
    if type(res) == "string" then
        add(res)
    elseif type(res) == "table" then
        for k, v in pairs(res) do
            if type(v) == "string" then
                add(v)
            elseif type(v) == "table" then
                add(v.Name or v.name or v.ItemName or v.itemName or v.Item or v.item)
                add(v.Id or v.id)
                if type(v.Items) == "table" then
                    for _, x in ipairs(v.Items) do
                        if type(x) == "string" then add(x)
                        elseif type(x) == "table" then add(x.Name or x.name or x.ItemName or x.itemName) end
                    end
                end
            elseif type(v) == "number" then
                add(k) -- key = nama item, value = jumlah
            end
        end
    end
    local list = {}
    for n in pairs(set) do table.insert(list, n) end
    table.sort(list)
    return list
end

function refreshInventory()
    local remote = Remotes.Inventory
    if not remote then
        notify("Inventori", "Remote GetInventory tidak ditemukan.")
        return {}
    end
    local ok, res = pcall(function() return remote:InvokeServer() end)
    if not ok then
        notify("Inventori", "Gagal invoke GetInventory.")
        return {}
    end
    pcall(function() print("[GrowlockHub] Inventory raw: " .. fmt(res)) end)
    local list = parseInventory(res)
    notify("Inventori", #list .. " item ditemukan.")
    return list
end

-- ================= UI =================
local MainTab, SetTab, InfoTab
local lblRemote, lblItem, lblArah
local invDropdown, dirDropdown, fbStatus, fbFrame

if USE_RAY then
    local W = Rayfield:CreateWindow({
        Name = "Growlock Hub", KeySystem = false,
        ConfigurationSaving = { Enabled = false },
    })
    MainTab = W:CreateTab("Main")
    SetTab  = W:CreateTab("Pengaturan")
    InfoTab = W:CreateTab("Info")

    MainTab:CreateSection("Arah Block (relatif avatar)")
    dirDropdown = MainTab:CreateDropdown({
        Name = "Sisi yang ditarget",
        Options = DIRECTIONS,
        CurrentOption = Config.Direction,
        Flag = "GL_Dir",
        Callback = function(o) Config.Direction = o; refreshInfo() end,
    })

    MainTab:CreateSection("Auto Farm")
    MainTab:CreateToggle({ Name = "Auto Punch", CurrentValue = false, Flag = "GL_Punch",
        Callback = function(v) genv.GrowlockAutoPunch = v end })
    MainTab:CreateToggle({ Name = "Auto Collect", CurrentValue = false, Flag = "GL_Collect",
        Callback = function(v) genv.GrowlockAutoCollect = v end })
    MainTab:CreateToggle({ Name = "Auto Plant", CurrentValue = false, Flag = "GL_Plant",
        Callback = function(v) genv.GrowlockAutoPlant = v end })
    MainTab:CreateToggle({ Name = "Auto Harvest", CurrentValue = false, Flag = "GL_Harvest",
        Callback = function(v) genv.GrowlockAutoHarvest = v end })

    MainTab:CreateSection("Item dari Inventori")
    invDropdown = MainTab:CreateDropdown({
        Name = "Pilih item / seed",
        Options = { Config.SelectedItem },
        CurrentOption = Config.SelectedItem,
        Flag = "GL_Item",
        Callback = function(o) Config.SelectedItem = o; refreshInfo() end,
    })
    MainTab:CreateButton({ Name = "Refresh Inventori", Callback = function()
        local list = refreshInventory()
        if #list > 0 and invDropdown.Refresh then
            pcall(function() invDropdown:Refresh(list, Config.SelectedItem) end)
        end
    end })
    MainTab:CreateInput({ Name = "Item custom (ketik)", PlaceholderText = "Nama item...",
        RemoveTextAfterFocusLost = false, Flag = "GL_ItemCustom",
        Callback = function(t) if t and t ~= "" then Config.SelectedItem = t; refreshInfo() end end })

    MainTab:CreateSection("Misc")
    MainTab:CreateButton({ Name = "Refresh Remote", Callback = function() resolveRemotes() end })
    MainTab:CreateButton({ Name = "Hapus UI", Callback = function() Rayfield:Destroy() end })

    SetTab:CreateSection("Delay")
    SetTab:CreateSlider({ Name = "Punch Delay", Range = {0.02, 1}, Increment = 0.02,
        CurrentValue = Config.PunchDelay, Flag = "GL_PD", Callback = function(v) Config.PunchDelay = v end })
    SetTab:CreateSlider({ Name = "Collect Delay", Range = {0.02, 1}, Increment = 0.02,
        CurrentValue = Config.CollectDelay, Flag = "GL_CD", Callback = function(v) Config.CollectDelay = v end })
    SetTab:CreateSlider({ Name = "Plant Delay", Range = {0.05, 2}, Increment = 0.05,
        CurrentValue = Config.PlantDelay, Flag = "GL_LD", Callback = function(v) Config.PlantDelay = v end })
    SetTab:CreateSection("Jarak")
    SetTab:CreateSlider({ Name = "Search Range", Range = {3, 30}, Increment = 1,
        CurrentValue = Config.SearchRange, Flag = "GL_SR", Callback = function(v) Config.SearchRange = v end })
    SetTab:CreateSlider({ Name = "Toleransi Target", Range = {1, 15}, Increment = 1,
        CurrentValue = Config.TargetTolerance, Flag = "GL_TT", Callback = function(v) Config.TargetTolerance = v end })

    InfoTab:CreateSection("Status")
    lblRemote = InfoTab:CreateLabel("-")
    lblItem   = InfoTab:CreateLabel("-")
    lblArah   = InfoTab:CreateLabel("-")
    InfoTab:CreateSection("Cara pakai")
    InfoTab:CreateLabel("1. Pilih sisi blok (Depan/Kiri/...).")
    InfoTab:CreateLabel("2. Refresh Inventori, lalu klik item.")
    InfoTab:CreateLabel("3. Nyalakan toggle auto farm.")
    InfoTab:CreateLabel("4. PUKUL & TANAM manual 1x untuk learn argumen.")
    InfoTab:CreateLabel("5. Kirim baris [GrowlockHub] ARG ke pembuat script.")
else
    local sg = Instance.new("ScreenGui")
    sg.Name = "GrowlockHubFallback"
    sg.ResetOnSpawn = false
    sg.Parent = LocalPlayer:WaitForChild("PlayerGui")

    fbFrame = Instance.new("Frame")
    fbFrame.Size = UDim2.new(0, 300, 0, 410)
    fbFrame.Position = UDim2.new(0.05, 0, 0.22, 0)
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
    fbStatus.Size = UDim2.new(1, -10, 0, 44)
    fbStatus.Position = UDim2.new(0, 5, 0, 38)
    fbStatus.BackgroundTransparency = 1
    fbStatus.TextColor3 = Color3.fromRGB(200, 200, 200)
    fbStatus.Font = Enum.Font.Gotham
    fbStatus.TextSize = 11
    fbStatus.TextWrapped = true
    fbStatus.Parent = fbFrame

    local function fbInput(label, y, text, cb)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -10, 0, 18); l.Position = UDim2.new(0, 6, 0, y)
        l.BackgroundTransparency = 1; l.TextColor3 = Color3.fromRGB(180, 220, 180)
        l.Font = Enum.Font.Gotham; l.TextSize = 11; l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = label; l.Parent = fbFrame
        local b = Instance.new("TextBox")
        b.Size = UDim2.new(1, -20, 0, 28); b.Position = UDim2.new(0, 10, 0, y + 20)
        b.BackgroundColor3 = Color3.fromRGB(50, 50, 65); b.Text = text
        b.TextColor3 = Color3.new(1, 1, 1); b.Font = Enum.Font.Gotham; b.TextSize = 12
        b.Parent = fbFrame
        b.FocusLost:Connect(function() if b.Text ~= "" then cb(b.Text) end end)
    end

    fbInput("Sisi (Depan/Belakang/Kiri/Kanan/Atas/Bawah)", 84, Config.Direction,
        function(t) Config.Direction = t; refreshInfo() end)
    fbInput("Item / seed", 140, Config.SelectedItem,
        function(t) Config.SelectedItem = t; refreshInfo() end)

    local function fbToggle(name, y, key)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -20, 0, 30); b.Position = UDim2.new(0, 10, 0, y)
        b.BackgroundColor3 = Color3.fromRGB(55, 55, 70); b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.Gotham; b.TextSize = 12; b.Text = name .. " : OFF"; b.Parent = fbFrame
        local s = false
        b.MouseButton1Click:Connect(function()
            s = not s
            b.Text = name .. " : " .. (s and "ON" or "OFF")
            b.BackgroundColor3 = s and Color3.fromRGB(40, 160, 80) or Color3.fromRGB(55, 55, 70)
            genv[key] = s
        end)
    end
    fbToggle("Auto Punch", 196, "GrowlockAutoPunch")
    fbToggle("Auto Collect", 232, "GrowlockAutoCollect")
    fbToggle("Auto Plant", 268, "GrowlockAutoPlant")
    fbToggle("Auto Harvest", 304, "GrowlockAutoHarvest")

    local rb = Instance.new("TextButton")
    rb.Size = UDim2.new(1, -20, 0, 28); rb.Position = UDim2.new(0, 10, 0, 340)
    rb.BackgroundColor3 = Color3.fromRGB(120, 80, 40); rb.Text = "Refresh Remote + Inventori"
    rb.TextColor3 = Color3.new(1, 1, 1); rb.Font = Enum.Font.Gotham; rb.TextSize = 11
    rb.Parent = fbFrame
    rb.MouseButton1Click:Connect(function() resolveRemotes(); refreshInventory() end)

    local xb = Instance.new("TextButton")
    xb.Size = UDim2.new(1, -20, 0, 26); xb.Position = UDim2.new(0, 10, 0, 374)
    xb.BackgroundColor3 = Color3.fromRGB(100, 50, 50); xb.Text = "Tutup GUI"
    xb.TextColor3 = Color3.new(1, 1, 1); xb.Font = Enum.Font.Gotham; xb.TextSize = 11
    xb.Parent = fbFrame
    xb.MouseButton1Click:Connect(function() fbFrame.Visible = false end)
end

function refreshInfo()
    pcall(function()
        local r = "Punch: " .. tostring(Remotes.Punch and "OK" or "X") ..
                  " Collect: " .. tostring(Remotes.Collect and "OK" or "X") ..
                  "\nPlant: " .. tostring(Remotes.Plant and "OK" or "X") ..
                  " Harvest: " .. tostring(Remotes.Harvest and "OK" or "X")
        local i = "Item: " .. tostring(Config.SelectedItem)
        local a = "Sisi: " .. tostring(Config.Direction)
        if USE_RAY then
            lblRemote:Set(r); lblItem:Set(i); lblArah:Set(a)
        elseif fbStatus then
            fbStatus.Text = a .. "\n" .. i
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
    local t = getTarget(Config.TreeKeywords)
    if t then send(Names.Punch, t); wait(Config.PunchDelay) end
end

local function doCollect()
    local t = getTarget(Config.DropKeywords)
    if t then send(Names.Collect, t); wait(Config.CollectDelay) end
end

local function doPlant()
    local t = getTarget(Config.SoilKeywords)
    if t then send(Names.Plant, t, Config.SelectedItem); wait(Config.PlantDelay) end
end

local function doHarvest()
    local t = getTarget(Config.TreeKeywords)
    if t then send(Names.Harvest, t); wait(Config.HarvestDelay) end
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
pcall(refreshInventory)
print("[GrowlockHub] Siap. Sisi=" .. Config.Direction .. " Item=" .. Config.SelectedItem)
