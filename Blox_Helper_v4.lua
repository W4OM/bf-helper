-- BloxFruits_Helper_v5.lua
-- exécuteur : Delta / Fluxus / Wave / Script-Ware / Solara
-- F2 par défaut = ouvrir/fermer le menu — configs sauvegardées automatiquement

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser       = game:GetService("VirtualUser")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LP    = Players.LocalPlayer
local mouse = LP:GetMouse()

-- ============================================================ CONFIG + SAVE
local SAVE_FILE = "BFH_v5_config.json"

local DEFAULTS = {
    autoFarm    = false, farmRadius = 350, autoClick  = true,
    autoHaki    = true,  autoStats  = false, statToMax = "Melee",
    autoChest   = false, autoBoss   = false,
    autoQuest   = false, turnIn     = true,
    gacha       = false, gachaDelay = 45,   autoBuyFruit = false,
    fruitWanted = "",    autoStyles = false,
    mobESP      = false, chestESP   = false, playerESP = false,
    fruitESP    = false, teamCheck  = false,
    walkSpeed   = 32,    antiAfk    = true,
    intro       = true,
    guiKeyName  = "RightShift",
    hakiKeyName = "H",
    _travelName = "",
}

local CFG = table.clone(DEFAULTS)

local function saveCFG()
    pcall(function()
        writefile(SAVE_FILE, HttpService:JSONEncode(CFG))
    end)
end

local function loadCFG()
    pcall(function()
        if readfile and isfile and isfile(SAVE_FILE) then
            local data = HttpService:JSONDecode(readfile(SAVE_FILE))
            for k, v in pairs(data) do
                if DEFAULTS[k] ~= nil then CFG[k] = v end
            end
        end
    end)
end
loadCFG()

local STATE = {
    target = nil, questMob = nil, questCount = 0,
    lastGacha = 0, status = "prêt.", paused = false,
    guiOpen = true,
}

local function setStatus(s) STATE.status = s end

-- ============================================================ HELPERS
local function rootOf(c) return c and c:FindFirstChild("HumanoidRootPart") end
local function myChar()  return LP.Character end
local function myRoot()  return rootOf(myChar()) end
local function myHum()   local c = myChar() return c and c:FindFirstChild("Humanoid") end
local function isAlive(p)
    local c = p and p.Character
    local h = c and c:FindFirstChild("Humanoid")
    return h and h.Health > 0 and rootOf(c) ~= nil
end
local function dist(a, b)
    if not a or not b then return math.huge end
    return (a.Position - b.Position).Magnitude
end
local function tpTo(pos)
    local r = myRoot()
    if not r then return end
    r.Velocity = Vector3.new(0, 0, 0)
    r.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
end

if CFG.antiAfk then
    LP.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end

-- ============================================================ SIGNALS
-- FIX v4 : :Fire() sur les signaux Roblox ne fait rien côté client.
-- On passe par firesignal / fireproximityprompt des exécuteurs.
local function fireSignal(sig, ...)
    if firesignal then
        pcall(function() firesignal(sig, ...) end)
        return true
    end
    return false
end

local function clickGuiButton(btn)
    if not btn then return end
    fireSignal(btn.MouseButton1Click)
    fireSignal(btn.Activated)
    pcall(function() btn.MouseButton1Click:Fire() end)
end

local function firePrompt(prompt)
    if not prompt then return false end
    if fireproximityprompt then
        pcall(function() fireproximityprompt(prompt, true) end)
        return true
    end
    fireSignal(prompt.Triggered, LP)
    pcall(function() fireclickdetector(prompt.Parent:FindFirstChildWhichIsA("ClickDetector", true)) end)
    return true
end

-- ============================================================ DIALOGUE ENGINE
local function findNPC(namePart)
    namePart = namePart:lower()
    local roots = {workspace}
    local npcs = workspace:FindFirstChild("NPCs")
    if npcs then table.insert(roots, npcs) end
    for _, container in ipairs(roots) do
        for _, obj in ipairs(container:GetChildren()) do
            if (obj:IsA("Model") or obj:IsA("Folder"))
               and obj.Name:lower():find(namePart) then
                local h = obj:FindFirstChild("Humanoid")
                if not h or h.Health > 0 then return obj end
            end
        end
    end
    return nil
end

local function clickWanted(wantTexts, maxClicks)
    maxClicks = maxClicks or 3
    local clicked = 0
    local playerGui = LP:WaitForChild("PlayerGui")
    for _ = 1, maxClicks do
        local done = false
        for _, gui in ipairs(playerGui:GetDescendants()) do
            if gui:IsA("TextButton") and gui.Visible then
                local t = (gui.Text or ""):lower()
                if t ~= "" then
                    for _, want in ipairs(wantTexts) do
                        if t:find(want:lower()) then
                            clickGuiButton(gui)
                            clicked = clicked + 1
                            done = true
                            task.wait(0.3)
                            break
                        end
                    end
                end
            end
            if done then break end
        end
        if not done then break end
    end
    return clicked
end

local function talkTo(npcName, wanted)
    local npc = findNPC(npcName)
    if not npc then return false end
    local hrp = rootOf(npc)
    local r = myRoot()
    if hrp and r and dist(r.Position, hrp.Position) > 12 then
        tpTo(hrp.Position + Vector3.new(3, 0, 0))
        task.wait(0.35)
    end
    local prompt = npc:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        firePrompt(prompt)
    else
        pcall(function()
            fireclickdetector(npc:FindFirstChildWhichIsA("ClickDetector", true))
        end)
    end
    task.wait(0.55)
    if wanted then clickWanted(wanted, 4) end
    return true
end

-- ============================================================ QUEST ENGINE
local function questGivers()
    local list = {}
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj.Name:lower():find("quest giver") then
            local h = obj:FindFirstChild("Humanoid")
            if h and h.Health > 0 then table.insert(list, obj) end
        end
    end
    return list
end

local function readQuestUI()
    local playerGui = LP:WaitForChild("PlayerGui")
    for _, d in ipairs(playerGui:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible then
            local t = d.Text or ""
            local a, b = t:match("(%d+)/(%d+)")
            if a and b then
                local title = t:match("^(.-)%s*%(") or t:match("[Kk]ill%s+(.+)%s+%(") or ""
                if title == "" and d.Parent then
                    for _, sib in ipairs(d.Parent:GetChildren()) do
                        if sib:IsA("TextLabel") and not (sib.Text or ""):match("%d+/%d+") then
                            title = sib.Text or ""
                            break
                        end
                    end
                end
                local mob = title:gsub("^%a+ ", ""):gsub("%s*%d*$", "")
                return tonumber(a), tonumber(b), mob
            end
        end
    end
    return 0, 0, nil
end

local function acceptQuest()
    local givers = questGivers()
    if #givers == 0 then return false end
    local r = myRoot()
    if not r then return false end
    table.sort(givers, function(x, y)
        local hx, hy = rootOf(x), rootOf(y)
        if not hx then return false end
        if not hy then return true end
        return dist(r.Position, hx.Position) < dist(r.Position, hy.Position)
    end)
    local g = givers[1]
    local hrp = rootOf(g)
    if not hrp then return false end
    if dist(r.Position, hrp.Position) > 10 then
        tpTo(hrp.Position + Vector3.new(3, 0, 0))
        task.wait(0.35)
    end
    local prompt = g:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then firePrompt(prompt) end
    task.wait(0.6)
    clickWanted({"quest", "accept", "yes", "commencer"}, 5)
    task.wait(0.4)
    local cur, need, mob = readQuestUI()
    if need > 0 then
        STATE.questCount = cur
        STATE.questMob = (mob and mob ~= "") and mob or STATE.questMob
        return true
    end
    return false
end

local function turnInQuest()
    for _, g in ipairs(questGivers()) do
        local hrp = rootOf(g)
        local r = myRoot()
        if hrp and r and dist(r.Position, hrp.Position) < 150 then
            local prompt = g:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt then firePrompt(prompt) end
            task.wait(0.5)
            clickWanted({"continue", "complete", "finish", "rendre", "next", "yes"}, 5)
            return true
        end
    end
    return false
end

-- ============================================================ CIBLES
local function questMobMatches(model)
    local want = STATE.questMob
    if not want or want == "" then return false end
    local n, w = model.Name:lower(), want:lower()
    return n:find(w) or w:find(n)
end

local function nearestMob()
    local r = myRoot()
    if not r then return nil end
    local best, bestD = nil, CFG.farmRadius
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m ~= myChar() and not Players:GetPlayerFromCharacter(m) then
            local h = m:FindFirstChild("Humanoid")
            local hrp = rootOf(m)
            if h and h.Health > 0 and hrp and questMobMatches(m) then
                local d = dist(r.Position, hrp.Position)
                if d < bestD then best, bestD = m, d end
            end
        end
    end
    if best then return best end
    if STATE.questMob and STATE.questMob ~= "" then return nil end
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m ~= myChar() and not Players:GetPlayerFromCharacter(m) then
            local h = m:FindFirstChild("Humanoid")
            local hrp = rootOf(m)
            if h and h.Health > 0 and hrp then
                local d = dist(r.Position, hrp.Position)
                if d < bestD then best, bestD = m, d end
            end
        end
    end
    return best
end

local function nearestChest()
    local r = myRoot()
    if not r then return nil end
    local best, bestD = nil, 200
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name:lower():find("chest") then
            local p = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart")
            if p then
                local dd = dist(r.Position, p.Position)
                if dd < bestD then best, bestD = p, dd end
            end
        end
    end
    return best
end

local BOSS_NAMES = {
    ["The Gorilla King"]=true, ["Bobby"]=true, ["The Saw"]=true,
    ["Mob Leader"]=true, ["Vice Admiral"]=true, ["Warden"]=true,
    ["Chief Warden"]=true, ["Swan"]=true, ["Smoke Admiral"]=true,
    ["Cursed Captain"]=true, ["Darkbeard"]=true, ["Order"]=true,
    ["Greybeard"]=true, ["Ice Admiral"]=true, ["Don Swan"]=true,
    ["Tide Keeper"]=true, ["Longma"]=true, ["Soul Reaper"]=true,
    ["Beautiful Pirate"]=true, ["Cake Queen"]=true, ["Saber Expert"]=true,
    ["rip_indra"]=true, ["Captain"]=true, ["Tyrant"]=true,
    ["Venom Champion"]=true, ["Cake Lord"]=true,
}

-- ============================================================ BOUCLES
spawn(function()
    while task.wait(0.18) do
        if CFG.autoFarm and not STATE.paused and isAlive(LP) then
            if not STATE.target or not STATE.target:FindFirstChild("Humanoid")
               or STATE.target.Humanoid.Health <= 0 then
                STATE.target = nearestMob()
            end
            local t = STATE.target
            if t and rootOf(t) then
                local d = dist(myRoot().Position, rootOf(t).Position)
                if d > 11 then tpTo(rootOf(t).Position) end
                if d < 14 and CFG.autoClick then pcall(mouse1click) end
            end
        end
    end
end)

spawn(function()
    while task.wait(0.8) do
        if CFG.autoHaki and not STATE.paused and isAlive(LP) then
            local key = Enum.KeyCode[CFG.hakiKeyName] or Enum.KeyCode.H
            pcall(function() keypress(key.Value) end)
            task.wait(0.1)
            pcall(function() keyrelease(key.Value) end)
        end
    end
end)

spawn(function()
    while task.wait(1) do
        if CFG.autoStats and not STATE.paused then
            local rem = ReplicatedStorage:FindFirstChild("Remotes")
            local addPoint = rem and (rem:FindFirstChild("AddPoint")
                              or rem:FindFirstChild("StatAdd"))
            local pts = LP:FindFirstChild("Data") and LP.Data:FindFirstChild("Points")
            if addPoint and pts and pts.Value > 0 then
                pcall(function() addPoint:FireServer(CFG.statToMax, 1) end)
            end
        end
    end
end)

spawn(function()
    while task.wait(2) do
        if not CFG.autoQuest or STATE.paused then continue end
        local cur, need, mob = readQuestUI()
        if need > 0 then
            STATE.questMob = (mob and mob ~= "") and mob or STATE.questMob
            if cur >= need then
                if CFG.turnIn then
                    setStatus("rendu de quête …")
                    turnInQuest()
                    task.wait(1.2)
                    STATE.questMob = nil
                end
            else
                setStatus(string.format("quête %d/%d — %s", cur, need, STATE.questMob or "?"))
            end
        else
            setStatus("recherche de quête …")
            acceptQuest()
            task.wait(1.5)
        end
    end
end)

spawn(function()
    while task.wait(3) do
        if not CFG.autoBoss or STATE.paused then continue end
        for name in pairs(BOSS_NAMES) do
            local b = workspace:FindFirstChild(name)
            if b and rootOf(b) then
                STATE.target = b
                tpTo(rootOf(b).Position)
                setStatus("boss : " .. name)
                break
            end
        end
    end
end)

spawn(function()
    while task.wait(1.5) do
        if CFG.autoChest and not STATE.paused then
            local c = nearestChest()
            if c then tpTo(c.Position) end
        end
    end
end)

-- ============================================================ SHOP / GACHA
local function gachaFruit()
    if os.clock() - STATE.lastGacha < CFG.gachaDelay then return end
    setStatus("gacha — Cousin …")
    if talkTo("cousin", {"buy", "spin", "random", "gacha", "yes"}) then
        STATE.lastGacha = os.clock()
        saveCFG()
    end
end

local function buyWantedFruit()
    if CFG.fruitWanted == "" then return end
    setStatus("stock : " .. CFG.fruitWanted)
    talkTo("fruit dealer", {CFG.fruitWanted, "buy", "acheter", "yes"})
    talkTo("blox fruits dealer", {CFG.fruitWanted, "buy", "acheter", "yes"})
end

local STYLES = {
    "Black Leg", "Electro", "Fishman Karate", "Dragon Claw",
    "Electric Claw", "Godhuman", "Sanguine Art", "Death Step",
    "Sharkman Karate", "Monkey King",
}

spawn(function()
    while task.wait(5) do
        if STATE.paused then continue end
        if CFG.gacha then gachaFruit() end
        if CFG.autoBuyFruit then buyWantedFruit() end
        if CFG.autoStyles then
            for _, s in ipairs(STYLES) do
                talkTo(s:lower(), {"learn", "apprendre", "buy", s})
            end
        end
    end
end)

-- ============================================================ VOYAGE
local function findIsland(name)
    name = name:lower()
    if name == "" then return nil end
    local best, bestSize = nil, 0
    for _, container in ipairs({workspace, workspace:FindFirstChild("Map"),
                                workspace:FindFirstChild("Worlds")}) do
        if container then
            for _, obj in ipairs(container:GetDescendants()) do
                if (obj:IsA("Model") or obj:IsA("Folder") or obj:IsA("BasePart"))
                   and obj.Name:lower():find(name) then
                    local ok, size = pcall(function() return obj:GetExtentsSize() end)
                    if ok and size and size.Magnitude > bestSize then
                        best, bestSize = obj, size.Magnitude
                    end
                end
            end
        end
    end
    return best
end

local function travelTo(name)
    local isl = findIsland(name)
    if not isl then setStatus("île introuvable : " .. tostring(name)) return false end
    local ok, pos = pcall(function() return isl:GetPivot().Position end)
    if not ok or not pos then
        local p = rootOf(isl) or (isl:IsA("BasePart") and isl)
        pos = p and p.Position or nil
    end
    if not pos then setStatus("pivot impossible") return false end
    setStatus("voyage → " .. name)
    tpTo(pos + Vector3.new(0, 20, 0))
    return true
end

-- ============================================================ ESP
local ESPC = {
    mob    = Color3.fromRGB(255, 150, 0),
    boss   = Color3.fromRGB(255, 40, 40),
    chest  = Color3.fromRGB(255, 255, 0),
    player = Color3.fromRGB(0, 170, 255),
    fruit  = Color3.fromRGB(255, 0, 255),
}

local function makeESP(part, color, text)
    if not part then return end
    local hl = part:FindFirstChild("BF_ESP")
    if not hl then
        hl = Instance.new("Highlight")
        hl.Name = "BF_ESP"
        hl.Adornee = part
        hl.FillTransparency = 0.75
        hl.OutlineTransparency = 0.2
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = part
        local sg = Instance.new("BillboardGui")
        sg.Name = "BF_LABEL"
        sg.Adornee = part
        sg.Size = UDim2.new(0, 220, 0, 34)
        sg.StudsOffset = Vector3.new(0, 3, 0)
        sg.AlwaysOnTop = true
        local tl = Instance.new("TextLabel")
        tl.Name = "TXT"
        tl.Size = UDim2.new(1, 0, 1, 0)
        tl.BackgroundTransparency = 1
        tl.Font = Enum.Font.GothamBold
        tl.TextScaled = true
        tl.TextStrokeTransparency = 0.4
        tl.Parent = sg
        sg.Parent = part
    end
    hl.FillColor = color
    local sg = part:FindFirstChild("BF_LABEL")
    local tl = sg and sg:FindFirstChild("TXT")
    if tl then tl.Text = text tl.TextColor3 = color end
end

local function clearESP(container)
    for _, d in ipairs(container:GetDescendants()) do
        if d.Name == "BF_ESP" or d.Name == "BF_LABEL" then d:Destroy() end
    end
end

spawn(function()
    while task.wait(1.2) do
        if CFG.mobESP then
            for _, m in ipairs(workspace:GetChildren()) do
                if m:IsA("Model") and m ~= myChar()
                   and not Players:GetPlayerFromCharacter(m) then
                    local h = m:FindFirstChild("Humanoid")
                    local hrp = rootOf(m)
                    if h and h.Health > 0 and hrp then
                        local boss = BOSS_NAMES[m.Name]
                        makeESP(hrp, boss and ESPC.boss or ESPC.mob,
                                boss and ("★ " .. m.Name) or m.Name)
                    end
                end
            end
        end
        if CFG.chestESP then
            for _, d in ipairs(workspace:GetDescendants()) do
                if d.Name:lower():find("chest") then
                    local p = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart")
                    if p then makeESP(p, ESPC.chest, d.Name) end
                end
            end
        end
        if CFG.fruitESP then
            for _, d in ipairs(workspace:GetDescendants()) do
                if d:IsA("Tool") and d.Name:find("Fruit") then
                    local p = d:FindFirstChild("Handle") or d:FindFirstChildWhichIsA("BasePart")
                    if p then makeESP(p, ESPC.fruit, d.Name) end
                end
            end
        end
        if CFG.playerESP then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and isAlive(plr)
                   and (not CFG.teamCheck or plr.Team ~= LP.Team) then
                    makeESP(rootOf(plr.Character), ESPC.player, plr.Name)
                end
            end
        end
    end
end)

spawn(function()
    while task.wait(2) do
        if not CFG.mobESP then
            for _, m in ipairs(workspace:GetChildren()) do
                if m:IsA("Model") and not Players:GetPlayerFromCharacter(m) then
                    clearESP(m)
                end
            end
        end
        if not CFG.playerESP then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr.Character then clearESP(plr.Character) end
            end
        end
    end
end)

spawn(function()
    while task.wait(1) do
        local h = myHum()
        if h and h.WalkSpeed ~= CFG.walkSpeed then
            h.WalkSpeed = CFG.walkSpeed
        end
    end
end)

-- ============================================================ GUI v5
local ACCENT    = Color3.fromRGB(57, 197, 207)
local ACCENT2   = Color3.fromRGB(88, 166, 255)
local GREEN     = Color3.fromRGB(63, 185, 80)
local ORANGE    = Color3.fromRGB(255, 170, 0)
local RED       = Color3.fromRGB(248, 81, 73)
local PINK      = Color3.fromRGB(255, 0, 255)
local BGW       = Color3.fromRGB(13, 17, 23)
local BG2       = Color3.fromRGB(22, 27, 34)
local BG3       = Color3.fromRGB(30, 36, 44)
local FG        = Color3.fromRGB(201, 209, 217)
local MUTED     = Color3.fromRGB(139, 148, 158)
local STROKE    = Color3.fromRGB(48, 54, 61)

local function buildGUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "BFH"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = LP:WaitForChild("PlayerGui")

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 750, 0, 480)
    main.Position = UDim2.new(0.5, -375, 0.5, -240)
    main.BackgroundColor3 = BGW
    main.BorderSizePixel = 0
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
    local mStroke = Instance.new("UIStroke", main)
    mStroke.Color = STROKE
    mStroke.Thickness = 1

    -- drag
    do
        local drag, off
        local tb = Instance.new("Frame")
        tb.Size = UDim2.new(1, 0, 0, 46)
        tb.BackgroundTransparency = 1
        tb.Parent = main
        tb.Active = true
        tb.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                drag = true
                off = main.AbsolutePosition - Vector2.new(inp.Position.X, inp.Position.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if drag and inp.UserInputType == Enum.UserInputType.MouseMovement then
                main.Position = UDim2.new(0, inp.Position.X + off.X, 0, inp.Position.Y + off.Y)
            end
        end)
    end

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -200, 0, 46)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 18
    title.TextColor3 = ACCENT
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "  ◈ BLOX FRUITS HELPER"
    title.Parent = main

    local ver = Instance.new("TextLabel")
    ver.Size = UDim2.new(0, 34, 0, 18)
    ver.Position = UDim2.new(0, 232, 0, 15)
    ver.BackgroundColor3 = BG3
    ver.Font = Enum.Font.GothamBold
    ver.TextSize = 10
    ver.TextColor3 = MUTED
    ver.Text = "v5"
    ver.Parent = main
    Instance.new("UICorner", ver).CornerRadius = UDim.new(1, 0)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 74, 0, 26)
    closeBtn.Position = UDim2.new(1, -88, 0, 10)
    closeBtn.BackgroundColor3 = BG3
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 11
    closeBtn.TextColor3 = RED
    closeBtn.Text = "FERMER"
    closeBtn.AutoButtonColor = false
    closeBtn.Parent = main
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 7)
    closeBtn.MouseButton1Click:Connect(function() main.Visible = false STATE.guiOpen = false end)

    -- sidebar
    local side = Instance.new("Frame")
    side.Size = UDim2.new(0, 156, 1, -56)
    side.Position = UDim2.new(0, 8, 0, 50)
    side.BackgroundColor3 = BG2
    side.BorderSizePixel = 0
    side.Parent = main
    Instance.new("UICorner", side).CornerRadius = UDim.new(0, 10)

    local pageHolder = Instance.new("Frame")
    pageHolder.Size = UDim2.new(1, -180, 1, -76)
    pageHolder.Position = UDim2.new(0, 174, 0, 54)
    pageHolder.BackgroundTransparency = 1
    pageHolder.Parent = main

    local pages = {}
    local function newPage(name)
        local p = Instance.new("ScrollingFrame")
        p.Name = name
        p.Size = UDim2.new(1, 0, 1, 0)
        p.BackgroundTransparency = 1
        p.BorderSizePixel = 0
        p.ScrollBarThickness = 3
        p.ScrollBarImageColor3 = ACCENT
        p.CanvasSize = UDim2.new(0, 0, 0, 0)
        p.AutomaticCanvasSize = Enum.AutomaticSize.Y
        p.Visible = false
        p.Parent = pageHolder
        local lay = Instance.new("UIListLayout", p)
        lay.Padding = UDim.new(0, 6)
        lay.SortOrder = Enum.SortOrder.LayoutOrder
        pages[name] = p
        return p
    end

    local function mkSection(parent, text, order)
        local s = Instance.new("TextLabel")
        s.Size = UDim2.new(1, 0, 0, 26)
        s.BackgroundTransparency = 1
        s.Font = Enum.Font.GothamBold
        s.TextSize = 11
        s.TextColor3 = MUTED
        s.TextXAlignment = Enum.TextXAlignment.Left
        s.Text = "—  " .. string.upper(text)
        s.LayoutOrder = order
        s.Parent = parent
    end

    local function mkToggle(parent, label, key, order)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 34)
        row.BackgroundColor3 = BG2
        row.BorderSizePixel = 0
        row.LayoutOrder = order
        row.Parent = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -70, 1, 0)
        l.Position = UDim2.new(0, 12, 0, 0)
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.Gotham
        l.TextSize = 13
        l.TextColor3 = FG
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = label
        l.Parent = row
        local sw = Instance.new("TextButton")
        sw.Size = UDim2.new(0, 46, 0, 22)
        sw.Position = UDim2.new(1, -56, 0.5, -11)
        sw.BackgroundColor3 = BG3
        sw.Font = Enum.Font.GothamBold
        sw.TextSize = 11
        sw.TextColor3 = MUTED
        sw.Text = "OFF"
        sw.AutoButtonColor = false
        sw.Parent = row
        Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)
        local function paint()
            sw.Text = CFG[key] and "ON" or "OFF"
            TweenService:Create(sw, TweenInfo.new(0.16), {
                BackgroundColor3 = CFG[key] and GREEN or BG3,
                TextColor3 = CFG[key] and Color3.new(1, 1, 1) or MUTED,
            }):Play()
        end
        sw.MouseButton1Click:Connect(function()
            CFG[key] = not CFG[key]
            paint()
            saveCFG()
        end)
        paint()
        return row
    end

    local function mkSlider(parent, label, key, minV, maxV, order)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 34)
        row.BackgroundColor3 = BG2
        row.BorderSizePixel = 0
        row.LayoutOrder = order
        row.Parent = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, -150, 1, 0)
        l.Position = UDim2.new(0, 12, 0, 0)
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.Gotham
        l.TextSize = 13
        l.TextColor3 = FG
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = label
        l.Parent = row
        local val = Instance.new("TextLabel")
        val.Size = UDim2.new(0, 54, 0, 22)
        val.Position = UDim2.new(1, -110, 0.5, -11)
        val.BackgroundColor3 = BGW
        val.Font = Enum.Font.Code
        val.TextSize = 13
        val.TextColor3 = ACCENT
        val.Text = tostring(CFG[key])
        val.Parent = row
        Instance.new("UICorner", val).CornerRadius = UDim.new(0, 6)
        local function set(v)
            CFG[key] = math.clamp(math.floor(v), minV, maxV)
            val.Text = tostring(CFG[key])
            saveCFG()
        end
        local step = math.max(1, math.floor((maxV - minV) / 20))
        local function mkBtn(txt, x)
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(0, 24, 0, 22)
            b.Position = UDim2.new(1, x, 0.5, -11)
            b.BackgroundColor3 = BG3
            b.Font = Enum.Font.GothamBold
            b.TextSize = 14
            b.TextColor3 = ACCENT
            b.Text = txt
            b.AutoButtonColor = false
            b.Parent = row
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
            return b
        end
        local minus, plus = mkBtn("−", -140), mkBtn("+", -28)
        minus.MouseButton1Click:Connect(function() set(CFG[key] - step) end)
        plus.MouseButton1Click:Connect(function() set(CFG[key] + step) end)
        return row
    end

    local function mkInput(parent, label, key, order)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 36)
        row.BackgroundColor3 = BG2
        row.BorderSizePixel = 0
        row.LayoutOrder = order
        row.Parent = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(0, 130, 1, 0)
        l.Position = UDim2.new(0, 12, 0, 0)
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.Gotham
        l.TextSize = 13
        l.TextColor3 = FG
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = label
        l.Parent = row
        local box = Instance.new("TextBox")
        box.Size = UDim2.new(1, -165, 0, 24)
        box.Position = UDim2.new(0, 150, 0.5, -12)
        box.BackgroundColor3 = BGW
        box.Font = Enum.Font.Code
        box.TextSize = 13
        box.TextColor3 = ACCENT
        box.PlaceholderText = "…"
        box.PlaceholderColor3 = MUTED
        box.Text = tostring(CFG[key] or "")
        box.ClearTextOnFocus = false
        box.Parent = row
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
        box.FocusLost:Connect(function()
            CFG[key] = box.Text
            saveCFG()
        end)
        return row
    end

    local function mkButton(parent, label, color, fn, order)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -4, 0, 32)
        b.BackgroundColor3 = color
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Text = label
        b.LayoutOrder = order
        b.AutoButtonColor = false
        b.Parent = parent
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        local base = color
        b.MouseEnter:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.12),
                {BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.14)}):Play()
        end)
        b.MouseLeave:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = base}):Play()
        end)
        b.MouseButton1Click:Connect(fn)
        return b
    end

    -- ================= pages
    local pFarm = newPage("farm")
    mkSection(pFarm, "FARM", 1)
    mkToggle(pFarm, "Auto Farm", "autoFarm", 2)
    mkToggle(pFarm, "Auto Click", "autoClick", 3)
    mkToggle(pFarm, "Auto Haki", "autoHaki", 4)
    mkSlider(pFarm, "Rayon de cible", "farmRadius", 50, 800, 5)
    mkSection(pFarm, "PRIORITÉS", 6)
    mkToggle(pFarm, "Auto Boss", "autoBoss", 7)
    mkToggle(pFarm, "Auto Coffres", "autoChest", 8)

    local pQuest = newPage("quest")
    mkSection(pQuest, "QUÊTES AUTO", 1)
    mkToggle(pQuest, "Auto Quête", "autoQuest", 2)
    mkToggle(pQuest, "Rendre automatiquement", "turnIn", 3)
    mkButton(pQuest, "▶ Forcer l'acceptation", ACCENT2, function()
        setStatus("acceptation …") acceptQuest()
    end, 4)
    mkButton(pQuest, "▶ Forcer le rendu", GREEN, function()
        setStatus("rendu …") turnInQuest()
    end, 5)

    local pTravel = newPage("travel")
    mkSection(pTravel, "VOYAGE", 1)
    mkInput(pTravel, "Nom de l'île", "_travelName", 2)
    mkButton(pTravel, "◈ VOYAGER", ACCENT, function()
        travelTo(CFG._travelName or "")
    end, 3)
    mkSection(pTravel, "RAPIDE", 4)
    for i, isl in ipairs({"Starter", "Jungle", "Pirate Village", "Marine Fortress",
                          "Skylands", "Snow", "Cafe", "Mansion", "Green Zone",
                          "Graveyard", "Great Tree", "Haunted Castle"}) do
        mkButton(pTravel, isl, BG3, function() travelTo(isl) end, 4 + i)
    end

    local pShop = newPage("shop")
    mkSection(pShop, "GACHA / FRUITS", 1)
    mkToggle(pShop, "Auto Gacha (Cousin)", "gacha", 2)
    mkSlider(pShop, "Delay gacha (s)", "gachaDelay", 15, 300, 3)
    mkToggle(pShop, "Auto Buy Fruit ciblé", "autoBuyFruit", 4)
    mkInput(pShop, "Fruit voulu", "fruitWanted", 5)
    mkButton(pShop, "▶ Acheter maintenant", ORANGE, function()
        buyWantedFruit()
    end, 6)
    mkSection(pShop, "FIGHTING STYLES", 7)
    mkToggle(pShop, "Auto apprendre les styles", "autoStyles", 8)
    mkSection(pShop, "STATS", 9)
    mkToggle(pShop, "Auto dépenser les points", "autoStats", 10)
    for i, stat in ipairs({"Melee", "Defense", "Sword", "Devil Fruit", "Gun"}) do
        mkButton(pShop, "Max : " .. stat,
                 CFG.statToMax == stat and GREEN or BG3,
                 function()
                     CFG.statToMax = stat
                     saveCFG()
                     for _, b in ipairs(pShop:GetChildren()) do
                         if b:IsA("TextButton") and tostring(b.Text):find("Max : ") then
                             b.BackgroundColor3 = tostring(b.Text):find(stat, 1, true)
                                 and GREEN or BG3
                         end
                     end
                 end, 10 + i)
    end

    local pESP = newPage("esp")
    mkSection(pESP, "ESP", 1)
    mkToggle(pESP, "Mob ESP (boss en rouge)", "mobESP", 2)
    mkToggle(pESP, "Chest ESP", "chestESP", 3)
    mkToggle(pESP, "Fruit ESP", "fruitESP", 4)
    mkToggle(pESP, "Player ESP", "playerESP", 5)
    mkToggle(pESP, "Team Check", "teamCheck", 6)

    local pSet = newPage("settings")
    mkSection(pSet, "MENU", 1)
    mkToggle(pSet, "Animation d'accueil", "intro", 2)
    local keyRow = mkButton(pSet, "Touche du menu : " .. CFG.guiKeyName, ACCENT2, function() end, 3)
    keyRow.Text = "Touche du menu : " .. CFG.guiKeyName .. "  (cliquer pour lier)"
    local binding = false
    keyRow.MouseButton1Click:Connect(function()
        binding = true
        keyRow.Text = "… appuie sur une touche"
        keyRow.BackgroundColor3 = ORANGE
    end)
    UserInputService.InputBegan:Connect(function(inp, gpe)
        if binding and inp.UserInputType == Enum.UserInputType.Keyboard then
            CFG.guiKeyName = inp.KeyCode.Name
            binding = false
            keyRow.Text = "Touche du menu : " .. CFG.guiKeyName .. "  (cliquer pour lier)"
            keyRow.BackgroundColor3 = ACCENT2
            saveCFG()
        end
    end)
    mkSection(pSet, "MOUVEMENT", 4)
    mkSlider(pSet, "WalkSpeed", "walkSpeed", 16, 100, 5)
    mkSection(pSet, "DIVERS", 6)
    mkToggle(pSet, "Anti-AFK", "antiAfk", 7)
    mkButton(pSet, "⏸ Pause / Reprise", RED, function()
        STATE.paused = not STATE.paused
        setStatus(STATE.paused and "PAUSE" or "repris")
    end, 8)
    mkButton(pSet, "✕ Nettoyer les ESP", BG3, function()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d.Name == "BF_ESP" or d.Name == "BF_LABEL" then d:Destroy() end
        end
        setStatus("ESP nettoyés")
    end, 9)
    mkButton(pSet, "↺ Reset config", BG3, function()
        for k, v in pairs(DEFAULTS) do CFG[k] = v end
        saveCFG()
        setStatus("config réinitialisée — relance le script")
    end, 10)

    -- ================= onglets
    local tabs = {
        {"farm",     "FARM",     GREEN,  "◈"},
        {"quest",    "QUÊTES",   ACCENT2, "◆"},
        {"travel",   "VOYAGE",   ACCENT, "➤"},
        {"shop",     "SHOP",     ORANGE, "⛁"},
        {"esp",      "ESP",      PINK,   "◉"},
        {"settings", "RÉGLAGES", MUTED,  "⚙"},
    }
    local function selectTab(id)
        for name, pg in pairs(pages) do
            pg.Visible = (name == id)
            if name == id then
                pg.CanvasPosition = Vector2.new(0, 0)
                pg.BackgroundTransparency = 1
                TweenService:Create(pg, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
            end
        end
        for _, other in ipairs(side:GetChildren()) do
            if other:IsA("TextButton") then
                local on = other:GetAttribute("tabId") == id
                TweenService:Create(other, TweenInfo.new(0.15), {
                    BackgroundColor3 = on and BG3 or BG2,
                    TextColor3 = on and FG or MUTED,
                }):Play()
                local dot = other:FindFirstChild("Dot")
                if dot then dot.Visible = on end
            end
        end
    end
    for i, t in ipairs(tabs) do
        local b = Instance.new("TextButton")
        b.Name = "tab_" .. t[1]
        b.Size = UDim2.new(1, -16, 0, 34)
        b.Position = UDim2.new(0, 8, 0, 10 + (i - 1) * 40)
        b.BackgroundColor3 = BG2
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.TextColor3 = MUTED
        b.Text = "  " .. t[4] .. "  " .. t[2]
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.AutoButtonColor = false
        b:SetAttribute("tabId", t[1])
        b.Parent = side
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        local dot = Instance.new("Frame")
        dot.Name = "Dot"
        dot.Size = UDim2.new(0, 5, 0, 5)
        dot.Position = UDim2.new(0, 6, 0.5, -2.5)
        dot.BackgroundColor3 = t[3]
        dot.Visible = false
        dot.Parent = b
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
        b.MouseButton1Click:Connect(function() selectTab(t[1]) end)
    end
    selectTab("farm")

    -- ================= foot
    local foot = Instance.new("TextLabel")
    foot.Size = UDim2.new(1, -20, 0, 18)
    foot.Position = UDim2.new(0, 10, 1, -24)
    foot.BackgroundTransparency = 1
    foot.Font = Enum.Font.Code
    foot.TextSize = 11
    foot.TextColor3 = MUTED
    foot.TextXAlignment = Enum.TextXAlignment.Left
    foot.Text = ""
    foot.Parent = main
    RunService.Heartbeat:Connect(function()
        local lvl = "?"
        pcall(function() lvl = LP.Data.Level.Value end)
        foot.Text = string.format("Niv. %s  │  %s  │  %s  │  %s",
            tostring(lvl), STATE.status,
            STATE.paused and "⏸ PAUSE" or "▶ actif",
            tostring(CFG.guiKeyName))
    end)

    -- ================= touche globale
    UserInputService.InputBegan:Connect(function(inp, gpe)
        if gpe then return end
        if inp.KeyCode.Name == CFG.guiKeyName then
            STATE.guiOpen = not STATE.guiOpen
            main.Visible = STATE.guiOpen
            if STATE.guiOpen then
                main.Size = UDim2.new(0, 730, 0, 460)
                main.Position = UDim2.new(0.5, -365, 0.5, -230)
                TweenService:Create(main, TweenInfo.new(0.18, Enum.EasingStyle.Quad),
                    {Size = UDim2.new(0, 750, 0, 480),
                     Position = UDim2.new(0.5, -375, 0.5, -240)}):Play()
            end
        end
    end)

    -- ================= INTRO (≤ 5 s, désactivable)
    if CFG.intro then
        local intro = Instance.new("Frame")
        intro.Name = "Intro"
        intro.Size = UDim2.new(1, 0, 1, 0)
        intro.BackgroundColor3 = BGW
        intro.BorderSizePixel = 0
        intro.ZIndex = 50
        intro.Parent = main
        Instance.new("UICorner", intro).CornerRadius = UDim.new(0, 12)

        local it = Instance.new("TextLabel")
        it.Size = UDim2.new(1, 0, 0, 40)
        it.Position = UDim2.new(0, 0, 0.36, 0)
        it.BackgroundTransparency = 1
        it.Font = Enum.Font.GothamBlack
        it.TextSize = 26
        it.TextColor3 = ACCENT
        it.Text = ""
        it.ZIndex = 51
        it.Parent = intro

        local is = Instance.new("TextLabel")
        is.Size = UDim2.new(1, 0, 0, 18)
        is.Position = UDim2.new(0, 0, 0.36, 44)
        is.BackgroundTransparency = 1
        is.Font = Enum.Font.Code
        is.TextSize = 12
        is.TextColor3 = MUTED
        is.Text = ""
        is.ZIndex = 51
        is.Parent = intro

        local track = Instance.new("Frame")
        track.Size = UDim2.new(0, 220, 0, 4)
        track.Position = UDim2.new(0.5, -110, 0.36, 76)
        track.BackgroundColor3 = BG3
        track.BorderSizePixel = 0
        track.ZIndex = 51
        track.Parent = intro
        Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = ACCENT
        fill.BorderSizePixel = 0
        fill.ZIndex = 52
        fill.Parent = track
        Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

        -- contenu de l'intro
        local full = "◈ BLOX FRUITS HELPER"
        local sub  = "v5 · chargement du menu …"
        local chars = 0
        while chars < #full do
            chars = chars + 1
            it.Text = string.sub(full, 1, chars)
            task.wait(0.045)
        end
        local c2 = 0
        while c2 < #sub do
            c2 = c2 + 1
            is.Text = string.sub(sub, 1, c2)
            task.wait(0.02)
        end
        TweenService:Create(fill, TweenInfo.new(1.1, Enum.EasingStyle.Quad),
            {Size = UDim2.new(1, 0, 1, 0)}):Play()
        task.wait(1.3)
        -- fondu de sortie
        for _, obj in ipairs(intro:GetDescendants()) do
            if obj:IsA("TextLabel") then
                TweenService:Create(obj, TweenInfo.new(0.35),
                    {TextTransparency = 1}):Play()
            end
        end
        TweenService:Create(intro, TweenInfo.new(0.35), {BackgroundTransparency = 1}):Play()
        task.wait(0.4)
        intro:Destroy()
    end

    -- autosave périodique
    spawn(function()
        while task.wait(30) do saveCFG() end
    end)
end

local ok, err = pcall(buildGUI)
if not ok then warn("[BFH] GUI error: " .. tostring(err)) end
print("[BFH] v5 chargé — touche : " .. CFG.guiKeyName)
