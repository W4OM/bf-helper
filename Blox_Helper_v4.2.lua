-- BloxFruits_Helper_v4.2.lua
-- exécuteur : Delta / Fluxus / Solara / Wave / Script-Ware
-- coller, exécuter — F1 = cacher/afficher le menu
--
-- fixes v4.2 :
--   * autoStats  : typeof(pts.Value) == "number" (corrige le crash "compare nil")
--   * auto-Haki  : keypress direct (InputBegan:Fire() n'existe pas)
--   * ProximityPrompt : fireproximityprompt (HoldBegin/InputHoldBegin n'existent pas)
--   * clics UI : vrais clics mousemoveabs/mouse1click + repli VirtualInputManager
--   * le script n'interagit plus avec sa propre GUI (clics + lecture de quête)
--   * autoFarm : nil-check HumanoidRootPart / cible détruite
--   * garde anti double-chargement (token + destruction ancienne GUI)
--   * toutes les boucles s'arrêtent proprement si le script est relancé

local Players                = game:GetService("Players")
local RunService             = game:GetService("RunService")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local VirtualUser            = game:GetService("VirtualUser")
local UserInputService       = game:GetService("UserInputService")
local TweenService           = game:GetService("TweenService")

local LP        = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")
local mouse     = LP:GetMouse()

-- ============================================================ ANTI DOUBLE CHARGEMENT
local TOKEN = "_BFH_v4.2_" .. os.clock() .. "_" .. math.random(1, 1e9)
_G.__BFH_TOKEN = TOKEN

local function running()
    return _G.__BFH_TOKEN == TOKEN
end

do -- détruit l'ancienne GUI (les anciennes boucles mourront via running())
    local old = PlayerGui:FindFirstChild("BFH")
    if old then old:Destroy() end
end

local function ownGui()
    return PlayerGui:FindFirstChild("BFH")
end

-- ============================================================ CONFIG
local CFG = {
    autoFarm     = false, farmRadius  = 350,  autoClick    = true,
    autoHaki     = true,  autoStats   = false, statToMax   = "Melee",
    autoChest    = false, autoBoss    = false, autoRaids   = false,
    autoQuest    = false, turnIn      = true,
    gacha        = false, gachaDelay  = 45,   autoBuyFruit = false,
    fruitWanted  = "",    autoStyles  = false,
    mobESP       = false, chestESP    = false, playerESP   = false,
    fruitESP     = false, teamCheck   = false,
    walkSpeed    = 32,    autoHakiKey = Enum.KeyCode.H,
    antiAfk      = true,  autoFruit   = false,
    _travelName  = "",
}

local STATE = {
    target     = nil, questMob  = nil, questCount = 0,
    questDone  = false, lastGacha = 0, status     = "prêt.",
    paused     = false,
}

-- ============================================================ HELPERS
local function rootOf(c)   return c and c:FindFirstChild("HumanoidRootPart") end
local function myChar()    return LP.Character end
local function myRoot()    return rootOf(myChar()) end
local function myHum()     local c = myChar() return c and c:FindFirstChild("Humanoid") end

local function isAlive(p)
    local c = p and p.Character
    local h = c and c:FindFirstChild("Humanoid")
    return h and h.Health > 0 and rootOf(c) ~= nil
end

local function dist(a, b)
    if not a or not b then return math.huge end
    return (a.Position - b.Position).Magnitude
end

local function setStatus(s) STATE.status = s end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function tpTo(pos)
    if not pos then return end -- FIX : guard position nil
    local r = myRoot()
    if not r then return end
    r.Velocity = Vector3.new(0, 0, 0)
    r.CFrame   = CFrame.new(pos + Vector3.new(0, 4, 0))
end

local function isVisible(inst) -- FIX : boutons d'ancêtres invisibles ignorés
    local p = inst
    while p and p ~= PlayerGui do
        if p:IsA("GuiObject") and not p.Visible then return false end
        p = p.Parent
    end
    return true
end

-- anti-afk
if CFG.antiAfk then
    LP.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end

-- ============================================================ CLICS RÉELS
-- FIX : gui.Activated:Fire() / MouseButton1Click:Fire() N'EXISTENT PAS
-- → on simule un vrai clic souris au centre du bouton
local function virtualClick(x, y)
    if type(mousemoveabs) == "function" and type(mouse1click) == "function" then
        if pcall(mousemoveabs, x, y) then
            task.wait(0.05)
            pcall(mouse1click)
            return true
        end
    end
    -- repli : VirtualInputManager (Delta / Fluxus / Wave)
    local ok = pcall(function()
        local VIM = game:GetService("VirtualInputManager")
        VIM:SendMouseButtonEvent(x, y, 0, true,  game, 0)
        task.wait(0.05)
        VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
    return ok
end

local function clickInstance(inst)
    local okP, pos = pcall(function() return inst.AbsolutePosition end)
    local okS, siz = pcall(function() return inst.AbsoluteSize end)
    if not okP or not okS then return false end

    local saved
    pcall(function() saved = mouse.Location end)

    local done = virtualClick(pos.X + siz.X / 2, pos.Y + siz.Y / 2)

    if saved then -- restaure la souris à sa position d'origine
        pcall(function()
            if type(mousemoveabs) == "function" then
                mousemoveabs(saved.X, saved.Y)
            end
        end)
    end
    return done
end

-- ============================================================ DIALOGUE ENGINE
local function findNPC(namePart)
    namePart = namePart:lower()
    for _, container in ipairs({ workspace, workspace:FindFirstChild("NPCs") }) do
        if container then
            for _, obj in ipairs(container:GetChildren()) do
                if (obj:IsA("Model") or obj:IsA("Folder"))
                    and obj.Name:lower():find(namePart, 1, true) then
                    return obj
                end
            end
        end
    end
    return nil
end

local function triggerNPC(npc)
    if not npc then return false end

    local prompt = npc:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        -- FIX : prompt:HoldBegin()/InputHoldBegin() n'existent pas
        if type(fireproximityprompt) == "function" then
            pcall(fireproximityprompt, prompt, 0)
        elseif type(keypress) == "function" then
            pcall(function()
                keypress(prompt.KeyboardKeyCode.Value)
                task.wait(0.12)
                keyrelease(prompt.KeyboardKeyCode.Value)
            end)
        end
        return true
    end

    local cd = npc:FindFirstChildWhichIsA("ClickDetector", true)
    if cd then
        if type(fireclickdetector) == "function" then
            pcall(fireclickdetector, cd)
        end
        return true
    end
    return false
end

local function clickButton(wantTexts, maxClicks)
    maxClicks = maxClicks or 3
    local clicked = 0
    local gui = ownGui()

    for _ = 1, maxClicks do
        local found = false
        for _, btn in ipairs(PlayerGui:GetDescendants()) do
            -- FIX : on ignore notre propre GUI (sinon on clique nos propres boutons)
            if not (gui and btn:IsDescendantOf(gui)) and btn:IsA("TextButton")
                and btn.Visible and isVisible(btn) then

                local t = (btn.Text or ""):lower()
                if t ~= "" then
                    for _, want in ipairs(wantTexts) do
                        if t:find(want:lower(), 1, true) then
                            if clickInstance(btn) then
                                clicked += 1
                                found = true
                            end
                            task.wait(0.25)
                            break
                        end
                    end
                end
            end
            if found then break end
        end
        if not found then break end
    end
    return clicked
end

local function talkAndBuy(npcName, wanted)
    local npc = findNPC(npcName)
    if not npc then return false end
    local hrp = rootOf(npc)
    local r   = myRoot()
    if hrp and r and dist(r.Position, hrp.Position) > 12 then
        tpTo(hrp.Position + Vector3.new(3, 0, 0))
        task.wait(0.3)
    end
    if not triggerNPC(npc) then return false end
    task.wait(0.5)
    clickButton(wanted, 4)
    return true
end

-- ============================================================ QUEST ENGINE
local function questGivers()
    local list = {}
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj.Name:lower():find("quest giver", 1, true) then
            local h = obj:FindFirstChild("Humanoid")
            if h and h.Health > 0 then table.insert(list, obj) end
        end
    end
    return list
end

local function readQuestUI()
    local playerGui = LP:WaitForChild("PlayerGui")
    local gui = ownGui() -- FIX : ne lit pas sa propre barre de statut ("quête 1/3")
    for _, d in ipairs(playerGui:GetDescendants()) do
        if not (gui and d:IsDescendantOf(gui)) then
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible then
                local t  = d.Text or ""
                local a, b = t:match("(%d+)/(%d+)")
                if a and b then
                    local title = t:match("^(.-)%s*%(") or t:match("[Kk]ill%s+(.+)%s+%(") or ""
                    if title == "" then
                        local p = d.Parent
                        if p then
                            for _, sib in ipairs(p:GetChildren()) do
                                if sib:IsA("TextLabel") and not (sib.Text or ""):match("%d+/%d+") then
                                    title = sib.Text or title
                                    break
                                end
                            end
                        end
                    end
                    local mob = trim(title:gsub("^%a+ ", ""):gsub("%s*%d*$", ""))
                    return tonumber(a), tonumber(b), mob
                end
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
    local g   = givers[1]
    local hrp = rootOf(g)
    if not hrp then return false end
    if dist(r.Position, hrp.Position) > 10 then
        tpTo(hrp.Position + Vector3.new(3, 0, 0))
        task.wait(0.3)
    end
    triggerNPC(g)
    task.wait(0.6)
    clickButton({ "quest", "accept", "yes", "commencer" }, 5)
    task.wait(0.4)
    local cur, need, mob = readQuestUI()
    if need > 0 then
        STATE.questCount = cur
        STATE.questDone  = cur >= need
        STATE.questMob   = (mob and mob ~= "") and mob or STATE.questMob
        return true
    end
    return false
end

local function turnInQuest()
    local r = myRoot()
    if not r then return false end
    for _, g in ipairs(questGivers()) do
        local hrp = rootOf(g)
        if hrp and dist(r.Position, hrp.Position) < 120 then
            triggerNPC(g)
            task.wait(0.5)
            clickButton({ "continue", "complete", "finish", "rendre", "next", "yes" }, 5)
            return true
        end
    end
    return false
end

-- ============================================================ CIBLES
local function questMobMatches(model)
    local want = STATE.questMob
    if not want or want == "" then return false end
    local n = model.Name:lower()
    local w = want:lower()
    return n:find(w, 1, true) or w:find(n, 1, true)
end

local function nearestMob()
    local r = myRoot()
    if not r then return nil end
    local best, bestD = nil, CFG.farmRadius
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m ~= myChar() and not Players:GetPlayerFromCharacter(m) then
            local h   = m:FindFirstChild("Humanoid")
            local hrp = rootOf(m)
            if h and h.Health > 0 and hrp then
                local d = dist(r.Position, hrp.Position)
                if questMobMatches(m) and d < bestD then
                    best, bestD = m, d
                end
            end
        end
    end
    if best then return best end
    if STATE.questMob and STATE.questMob ~= "" then return nil end
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m ~= myChar() and not Players:GetPlayerFromCharacter(m) then
            local h   = m:FindFirstChild("Humanoid")
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
    local best, bestD = nil, 180
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name:lower():find("chest", 1, true) then
            local p = obj:IsA("BasePart") and obj
                      or obj:FindFirstChildWhichIsA("BasePart")
            if p then
                local d = dist(r.Position, p.Position)
                if d < bestD then best, bestD = p, d end
            end
        end
    end
    return best
end

local function nearestFruit() -- FIX : fonction déjà écrite mais jamais utilisée
    local r = myRoot()
    if not r then return nil end
    local best, bestD = nil, 600
    for _, obj in ipairs(workspace:GetDescendants()) do
        if (obj:IsA("Tool") and obj.Name:find("Fruit", 1, true))
            or (obj:IsA("Model") and obj.Name:lower():find("fruit", 1, true)) then
            local p = obj:FindFirstChild("Handle")
                      or obj:FindFirstChildWhichIsA("BasePart")
                      or rootOf(obj)
            if p and p:IsA("BasePart") then
                local d = dist(r.Position, p.Position)
                if d < bestD then best, bestD = p, d end
            end
        end
    end
    return best
end

local BOSS_NAMES = {
    ["The Gorilla King"]=true, ["Bobby"]=true,          ["The Saw"]=true,
    ["Mob Leader"]=true,       ["Vice Admiral"]=true,   ["Warden"]=true,
    ["Chief Warden"]=true,     ["Swan"]=true,           ["Smoke Admiral"]=true,
    ["Cursed Captain"]=true,   ["Darkbeard"]=true,      ["Order"]=true,
    ["Greybeard"]=true,        ["Ice Admiral"]=true,    ["Don Swan"]=true,
    ["Tide Keeper"]=true,      ["Longma"]=true,         ["Soul Reaper"]=true,
    ["Beautiful Pirate"]=true, ["Cake Queen"]=true,     ["Saber Expert"]=true,
    ["rip_indra"]=true,        ["Captain"]=true,        ["Tyrant"]=true,
    ["Venom Champion"]=true,   ["Cake Lord"]=true,
}

-- ============================================================ BOUCLES
task.spawn(function()
    while running() and task.wait(0.18) do
        if CFG.autoFarm and not STATE.paused and isAlive(LP) then
            local t = STATE.target
            -- FIX : cible détruite / nil vérifiée avant accès
            if typeof(t) ~= "Instance" or not t.Parent
               or not t:FindFirstChild("Humanoid")
               or t.Humanoid.Health <= 0 then
                t = nearestMob()
                STATE.target = t
            end

            local r   = myRoot() -- FIX : myRoot() nil-check avant .Position
            local hrp = t and rootOf(t)
            if r and hrp then
                local d = dist(r.Position, hrp.Position)
                if d > 11 then tpTo(hrp.Position) end
                if d < 14 and CFG.autoClick and type(mouse1click) == "function" then
                    pcall(mouse1click)
                end
            end
        end
    end
end)

task.spawn(function()
    while running() and task.wait(0.8) do
        if CFG.autoHaki and not STATE.paused and isAlive(LP) then
            -- FIX : UserInputService.InputBegan:Fire() N'EXISTE PAS (RBXScriptSignal)
            if type(keypress) == "function" and type(keyrelease) == "function" then
                pcall(keypress, CFG.autoHakiKey.Value)
                task.wait(0.1)
                pcall(keyrelease, CFG.autoHakiKey.Value)
            end
        end
    end
end)

task.spawn(function()
    while running() and task.wait(1) do
        if CFG.autoStats and not STATE.paused then
            local rem      = ReplicatedStorage:FindFirstChild("Remotes")
            local addPoint = rem and (rem:FindFirstChild("AddPoint") or rem:FindFirstChild("StatAdd"))
            local pts      = LP:FindFirstChild("Data") and LP.Data:FindFirstChild("Points")
            -- FIX : typeof(...) == "number" → corrige "attempt to compare nil with number"
            if addPoint and pts and typeof(pts.Value) == "number" and pts.Value > 0 then
                pcall(function() addPoint:FireServer(CFG.statToMax, 1) end)
            end
        end
    end
end)

task.spawn(function()
    while running() and task.wait(2) do
        if not CFG.autoQuest or STATE.paused then continue end
        local cur, need, mob = readQuestUI()
        if need > 0 then
            STATE.questMob = (mob and mob ~= "") and mob or STATE.questMob
            if cur >= need then
                if CFG.turnIn then
                    setStatus("rendu de quête …")
                    turnInQuest()
                    task.wait(1)
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

task.spawn(function()
    while running() and task.wait(3) do
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

task.spawn(function()
    while running() and task.wait(1.5) do
        if STATE.paused then continue end
        if CFG.autoChest then
            local c = nearestChest()
            if c then tpTo(c.Position) setStatus("coffre …") end
        end
        if CFG.autoFruit then
            local f = nearestFruit() -- FIX : fonction enfin utilisée
            if f then tpTo(f.Position) setStatus("fruit : " .. f.Name) end
        end
    end
end)

-- ============================================================ SHOP / GACHA
local function gachaFruit()
    if os.clock() - STATE.lastGacha < CFG.gachaDelay then return end
    setStatus("gacha — Cousin …")
    local ok = talkAndBuy("cousin", { "buy", "spin", "gacha", "random", "yes" })
    if ok then STATE.lastGacha = os.clock() end
end

local function buyWantedFruit()
    if CFG.fruitWanted == "" then return end
    setStatus("vérif stock : " .. CFG.fruitWanted)
    talkAndBuy("fruit dealer",       { CFG.fruitWanted, "buy", "acheter", "yes" })
    talkAndBuy("blox fruits dealer", { CFG.fruitWanted, "buy", "acheter", "yes" })
end

local STYLES = {
    "Black Leg", "Electro", "Fishman Karate", "Dragon Claw",
    "Electric Claw", "Godhuman", "Sanguine Art", "Death Step",
    "Sharkman Karate", "Monkey King", "Overheat",
}

local function buyStyles()
    for _, s in ipairs(STYLES) do
        talkAndBuy(s:lower(), { "learn", "apprendre", "buy", s })
    end
end

task.spawn(function()
    while running() and task.wait(5) do
        if STATE.paused then continue end
        if CFG.gacha        then gachaFruit()    end
        if CFG.autoBuyFruit then buyWantedFruit() end
        if CFG.autoStyles   then buyStyles()      end
    end
end)

-- ============================================================ VOYAGE
local function findIsland(name)
    name = name:lower()
    local best, bestSize = nil, 0
    for _, container in ipairs({ workspace, workspace:FindFirstChild("Map"),
                                  workspace:FindFirstChild("Worlds") }) do
        if container then
            for _, obj in ipairs(container:GetDescendants()) do
                if (obj:IsA("Model") or obj:IsA("BasePart") or obj:IsA("Folder"))
                    and obj.Name:lower():find(name, 1, true) then
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
    if not name or name == "" then return false end
    local isl = findIsland(name)
    if not isl then setStatus("île introuvable : " .. name) return false end
    local ok, pos = pcall(function() return isl:GetPivot().Position end)
    if not ok or not pos then
        local p = rootOf(isl) or (isl:IsA("BasePart") and isl or nil)
        pos = p and p.Position or nil
    end
    if not pos then setStatus("pivot impossible") return false end
    setStatus("voyage → " .. name)
    tpTo(pos + Vector3.new(0, 20, 0))
    return true
end

-- ============================================================ ESP
local ESP_COLOR = {
    mob    = Color3.fromRGB(255, 150, 0),
    boss   = Color3.fromRGB(255, 40,  40),
    chest  = Color3.fromRGB(255, 255, 0),
    player = Color3.fromRGB(0,   170, 255),
    fruit  = Color3.fromRGB(255, 0,   255),
}

local function makeESP(part, color, text)
    if not part or not part.Parent then return end
    local hl = part:FindFirstChild("BF_ESP")
    if not hl or not hl:IsA("Highlight") then
        if hl then hl:Destroy() end
        hl = Instance.new("Highlight")
        hl.Name               = "BF_ESP"
        hl.Adornee            = part
        hl.FillTransparency   = 0.75
        hl.OutlineTransparency= 0.2
        hl.DepthMode          = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent             = part

        local sg = Instance.new("BillboardGui")
        sg.Name          = "BF_LABEL"
        sg.Adornee       = part
        sg.Size          = UDim2.new(0, 220, 0, 34)
        sg.StudsOffset   = Vector3.new(0, 3, 0)
        sg.AlwaysOnTop   = true
        local tl = Instance.new("TextLabel")
        tl.Name                  = "TXT"
        tl.Size                  = UDim2.new(1, 0, 1, 0)
        tl.BackgroundTransparency= 1
        tl.Font                  = Enum.Font.GothamBold
        tl.TextScaled            = true
        tl.TextStrokeTransparency= 0.4
        tl.Parent                = sg
        sg.Parent                = part
    end
    hl.FillColor = color
    local sg = part:FindFirstChild("BF_LABEL")
    local tl = sg and sg:FindFirstChild("TXT")
    if tl then tl.Text = text tl.TextColor3 = color end
end

local function clearESP(container)
    if not container then return end
    for _, d in ipairs(container:GetDescendants()) do
        if d.Name == "BF_ESP" or d.Name == "BF_LABEL" then d:Destroy() end
    end
end

task.spawn(function()
    while running() and task.wait(1.2) do
        if CFG.mobESP then
            for _, m in ipairs(workspace:GetChildren()) do
                if m:IsA("Model") and m ~= myChar()
                    and not Players:GetPlayerFromCharacter(m) then
                    local h   = m:FindFirstChild("Humanoid")
                    local hrp = rootOf(m)
                    if h and h.Health > 0 and hrp then
                        local boss = BOSS_NAMES[m.Name]
                        makeESP(hrp,
                            boss and ESP_COLOR.boss or ESP_COLOR.mob,
                            boss and ("★ " .. m.Name) or m.Name)
                    end
                end
            end
        end
        if CFG.playerESP then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and isAlive(plr)
                    and (not CFG.teamCheck or plr.Team ~= LP.Team) then
                    makeESP(rootOf(plr.Character), ESP_COLOR.player, plr.Name)
                end
            end
        end
    end
end)

task.spawn(function()
    while running() and task.wait(3) do
        if not CFG.chestESP and not CFG.fruitESP then continue end
        for _, obj in ipairs(workspace:GetDescendants()) do
            if CFG.chestESP and obj.Name:lower():find("chest", 1, true) then
                local p = obj:IsA("BasePart") and obj
                          or obj:FindFirstChildWhichIsA("BasePart")
                if p then makeESP(p, ESP_COLOR.chest, obj.Name) end
            end
            if CFG.fruitESP and obj:IsA("Tool") and obj.Name:find("Fruit", 1, true) then
                local p = obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart")
                if p then makeESP(p, ESP_COLOR.fruit, obj.Name) end
            end
        end
    end
end)

task.spawn(function()
    while running() and task.wait(2) do
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

-- ============================================================ VITESSE
task.spawn(function()
    while running() and task.wait(1) do
        local h = myHum()
        if h and h.WalkSpeed ~= CFG.walkSpeed then
            pcall(function() h.WalkSpeed = CFG.walkSpeed end)
        end
    end
end)

-- ============================================================ GUI
local function buildGUI()
    local gui = Instance.new("ScreenGui")
    gui.Name            = "BFH"
    gui.ResetOnSpawn    = false
    gui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    gui.Parent          = PlayerGui

    local main = Instance.new("Frame")
    main.Name               = "Window"
    main.Size               = UDim2.new(0, 740, 0, 470)
    main.Position           = UDim2.new(0.5, -370, 0.5, -235)
    main.BackgroundColor3   = Color3.fromRGB(13, 17, 23)
    main.BorderSizePixel    = 0
    main.Parent             = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", main)
    stroke.Color     = Color3.fromRGB(48, 54, 61)
    stroke.Thickness = 1

    -- drag
    do
        local drag, off
        local tb   = Instance.new("Frame")
        tb.Size                 = UDim2.new(1, 0, 0, 44)
        tb.BackgroundTransparency = 1
        tb.Active               = true
        tb.Parent               = main
        tb.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                drag = true
                off  = main.AbsolutePosition - Vector2.new(inp.Position.X, inp.Position.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if drag and off and inp.UserInputType == Enum.UserInputType.MouseMovement then
                main.Position = UDim2.new(0, inp.Position.X + off.X, 0, inp.Position.Y + off.Y)
            end
        end)
    end

    -- titre
    local title = Instance.new("TextLabel")
    title.Size               = UDim2.new(1, -140, 0, 44)
    title.BackgroundTransparency = 1
    title.Font               = Enum.Font.GothamBlack
    title.TextSize           = 18
    title.TextColor3         = Color3.fromRGB(57, 197, 207)
    title.TextXAlignment     = Enum.TextXAlignment.Left
    title.Text               = "  ◈ BLOX FRUITS HELPER v4.2"
    title.Parent             = main

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size            = UDim2.new(0, 70, 0, 26)
    closeBtn.Position        = UDim2.new(1, -84, 0, 9)
    closeBtn.BackgroundColor3= Color3.fromRGB(248, 81, 73)
    closeBtn.Font            = Enum.Font.GothamBold
    closeBtn.TextSize        = 12
    closeBtn.TextColor3      = Color3.new(1, 1, 1)
    closeBtn.Text            = "F1"
    closeBtn.Parent          = main
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
    closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)

    -- barre latérale
    local side = Instance.new("Frame")
    side.Size            = UDim2.new(0, 150, 1, -44)
    side.Position        = UDim2.new(0, 0, 0, 44)
    side.BackgroundColor3= Color3.fromRGB(22, 27, 34)
    side.BorderSizePixel = 0
    side.Parent          = main
    Instance.new("UICorner", side).CornerRadius = UDim.new(0, 10)

    local pages     = {}
    local pageHolder= Instance.new("Frame")
    pageHolder.Size                = UDim2.new(1, -170, 1, -70)
    pageHolder.Position            = UDim2.new(0, 160, 0, 52)
    pageHolder.BackgroundTransparency = 1
    pageHolder.Parent              = main

    local function newPage(name)
        local p = Instance.new("ScrollingFrame")
        p.Name                   = name
        p.Size                   = UDim2.new(1, 0, 1, 0)
        p.BackgroundTransparency = 1
        p.BorderSizePixel        = 0
        p.ScrollBarThickness     = 4
        p.ScrollBarImageColor3   = Color3.fromRGB(57, 197, 207)
        p.CanvasSize             = UDim2.new(0, 0, 0, 0)
        p.AutomaticCanvasSize    = Enum.AutomaticSize.Y
        p.Visible                = false
        p.Parent                 = pageHolder
        local layout = Instance.new("UIListLayout", p)
        layout.Padding    = UDim.new(0, 6)
        layout.SortOrder  = Enum.SortOrder.LayoutOrder
        pages[name]       = p
        return p
    end

    local function mkSection(parent, text, order)
        local s = Instance.new("TextLabel")
        s.Size               = UDim2.new(1, 0, 0, 24)
        s.BackgroundTransparency = 1
        s.Font               = Enum.Font.GothamBold
        s.TextSize           = 13
        s.TextColor3         = Color3.fromRGB(216, 222, 233)
        s.TextXAlignment     = Enum.TextXAlignment.Left
        s.Text               = "— " .. text
        s.LayoutOrder        = order
        s.Parent             = parent
    end

    local function mkToggle(parent, label, key, order)
        local row = Instance.new("Frame")
        row.Size             = UDim2.new(1, -6, 0, 34)
        row.BackgroundColor3 = Color3.fromRGB(22, 27, 34)
        row.BorderSizePixel  = 0
        row.LayoutOrder      = order
        row.Parent           = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

        local l = Instance.new("TextLabel")
        l.Size               = UDim2.new(1, -70, 1, 0)
        l.Position           = UDim2.new(0, 12, 0, 0)
        l.BackgroundTransparency = 1
        l.Font               = Enum.Font.Gotham
        l.TextSize           = 13
        l.TextColor3         = Color3.fromRGB(201, 209, 217)
        l.TextXAlignment     = Enum.TextXAlignment.Left
        l.Text               = label
        l.Parent             = row

        local sw = Instance.new("TextButton")
        sw.Size              = UDim2.new(0, 46, 0, 22)
        sw.Position          = UDim2.new(1, -56, 0.5, -11)
        sw.BackgroundColor3  = Color3.fromRGB(48, 54, 61)
        sw.Font              = Enum.Font.GothamBold
        sw.TextSize          = 11
        sw.TextColor3        = Color3.fromRGB(139, 148, 158)
        sw.Text              = "OFF"
        sw.AutoButtonColor   = false
        sw.Parent            = row
        Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)

        local function paint()
            sw.Text = CFG[key] and "ON" or "OFF"
            TweenService:Create(sw, TweenInfo.new(0.18), {
                BackgroundColor3 = CFG[key] and Color3.fromRGB(63, 185, 80)
                                   or Color3.fromRGB(48, 54, 61),
                TextColor3       = CFG[key] and Color3.new(1, 1, 1)
                                   or Color3.fromRGB(139, 148, 158),
            }):Play()
        end
        sw.MouseButton1Click:Connect(function() CFG[key] = not CFG[key] paint() end)
        paint()
        return row
    end

    local function mkSlider(parent, label, key, minV, maxV, order)
        local row = Instance.new("Frame")
        row.Size             = UDim2.new(1, -6, 0, 34)
        row.BackgroundColor3 = Color3.fromRGB(22, 27, 34)
        row.BorderSizePixel  = 0
        row.LayoutOrder      = order
        row.Parent           = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

        local l = Instance.new("TextLabel")
        l.Size               = UDim2.new(1, -140, 1, 0)
        l.Position           = UDim2.new(0, 12, 0, 0)
        l.BackgroundTransparency = 1
        l.Font               = Enum.Font.Gotham
        l.TextSize           = 13
        l.TextColor3         = Color3.fromRGB(201, 209, 217)
        l.TextXAlignment     = Enum.TextXAlignment.Left
        l.Text               = label
        l.Parent             = row

        local val = Instance.new("TextLabel")
        val.Size             = UDim2.new(0, 56, 0, 22)
        val.Position         = UDim2.new(1, -112, 0.5, -11)
        val.BackgroundColor3 = Color3.fromRGB(13, 17, 23)
        val.Font             = Enum.Font.Code
        val.TextSize         = 13
        val.TextColor3       = Color3.fromRGB(216, 222, 233)
        val.Text             = tostring(CFG[key])
        val.Parent           = row
        Instance.new("UICorner", val).CornerRadius = UDim.new(0, 6)

        local step = math.max(1, (maxV - minV) // 20)
        local function set(v)
            CFG[key]  = math.clamp(math.floor(v), minV, maxV)
            val.Text  = tostring(CFG[key])
        end
        local function mkBtn(txt, x, fn)
            local b = Instance.new("TextButton")
            b.Size            = UDim2.new(0, 26, 0, 22)
            b.Position        = UDim2.new(1, x, 0.5, -11)
            b.BackgroundColor3= Color3.fromRGB(48, 54, 61)
            b.Font            = Enum.Font.GothamBold
            b.TextSize        = 14
            b.TextColor3      = Color3.fromRGB(57, 197, 207)
            b.Text            = txt
            b.Parent          = row
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
            b.MouseButton1Click:Connect(fn)
        end
        mkBtn("−", -142, function() set(CFG[key] - step) end)
        mkBtn("+", -30,  function() set(CFG[key] + step) end)
        return row
    end

    local function mkInput(parent, label, key, order)
        local row = Instance.new("Frame")
        row.Size             = UDim2.new(1, -6, 0, 36)
        row.BackgroundColor3 = Color3.fromRGB(22, 27, 34)
        row.BorderSizePixel  = 0
        row.LayoutOrder      = order
        row.Parent           = parent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

        local l = Instance.new("TextLabel")
        l.Size               = UDim2.new(0, 140, 1, 0)
        l.Position           = UDim2.new(0, 12, 0, 0)
        l.BackgroundTransparency = 1
        l.Font               = Enum.Font.Gotham
        l.TextSize           = 13
        l.TextColor3         = Color3.fromRGB(201, 209, 217)
        l.TextXAlignment     = Enum.TextXAlignment.Left
        l.Text               = label
        l.Parent             = row

        local box = Instance.new("TextBox")
        box.Size             = UDim2.new(1, -175, 0, 24)
        box.Position         = UDim2.new(0, 160, 0.5, -12)
        box.BackgroundColor3 = Color3.fromRGB(13, 17, 23)
        box.Font             = Enum.Font.Code
        box.TextSize         = 13
        box.TextColor3       = Color3.fromRGB(57, 197, 207)
        box.PlaceholderText  = "…"
        box.Text             = tostring(CFG[key] or "")
        box.ClearTextOnFocus = false
        box.Parent           = row
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
        box.FocusLost:Connect(function() CFG[key] = box.Text end)
        return row
    end

    local function mkButton(parent, label, color, fn, order)
        local b = Instance.new("TextButton")
        b.Size            = UDim2.new(1, -6, 0, 34)
        b.BackgroundColor3= color
        b.Font            = Enum.Font.GothamBold
        b.TextSize        = 13
        b.TextColor3      = Color3.new(1, 1, 1)
        b.Text            = label
        b.LayoutOrder     = order
        b.Parent          = parent
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        b.MouseEnter:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.15),
                { BackgroundColor3 = color:Lerp(Color3.new(1,1,1), 0.15) }):Play()
        end)
        b.MouseLeave:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.15),
                { BackgroundColor3 = color }):Play()
        end)
        b.MouseButton1Click:Connect(fn)
        return b
    end

    -- ---------- pages
    local pFarm = newPage("farm")
    mkSection(pFarm, "FARM", 1)
    mkToggle(pFarm, "Auto Farm",    "autoFarm",   2)
    mkToggle(pFarm, "Auto Click",   "autoClick",  3)
    mkToggle(pFarm, "Auto Haki",    "autoHaki",   4)
    mkSlider(pFarm, "Rayon cible",  "farmRadius", 50, 800, 5)
    mkSection(pFarm, "PRIORITÉS",   6)
    mkToggle(pFarm, "Auto Boss",    "autoBoss",   7)
    mkToggle(pFarm, "Auto Coffres", "autoChest",  8)
    mkToggle(pFarm, "Auto Fruit au sol", "autoFruit", 9)

    local pQuest = newPage("quest")
    mkSection(pQuest, "QUÊTES", 1)
    mkToggle(pQuest, "Auto Quête (accept/rend)", "autoQuest", 2)
    mkToggle(pQuest, "Rendre automatiquement",   "turnIn",    3)
    mkButton(pQuest, "▶ Forcer acceptation",
        Color3.fromRGB(88, 166, 255),
        function() setStatus("acceptation …") acceptQuest() end, 4)
    mkButton(pQuest, "▶ Forcer rendu",
        Color3.fromRGB(63, 185, 80),
        function() setStatus("rendu …") turnInQuest() end, 5)

    local pTravel = newPage("travel")
    mkSection(pTravel, "VOYAGE", 1)
    mkInput(pTravel, "Nom de l'île", "_travelName", 2)
    mkButton(pTravel, "◈ VOYAGER", Color3.fromRGB(57, 197, 207),
        function() travelTo(CFG._travelName or "") end, 3)
    mkSection(pTravel, "RAPIDE", 4)
    for i, isl in ipairs({
        "Starter", "Jungle", "Pirate Village", "Marine Fortress",
        "Skylands", "Snow", "Cafe", "Mansion", "Green Zone",
        "Graveyard", "Great Tree", "Haunted Castle", "Sea 3",
    }) do
        local islandName = isl
        mkButton(pTravel, islandName, Color3.fromRGB(48, 54, 61),
            function() travelTo(islandName) end, 4 + i)
    end

    local pShop = newPage("shop")
    mkSection(pShop, "GACHA / FRUITS", 1)
    mkToggle(pShop, "Auto Gacha (Cousin)",   "gacha",        2)
    mkSlider(pShop, "Delay gacha (s)",        "gachaDelay",  15, 300, 3)
    mkToggle(pShop, "Auto Buy Fruit ciblé",   "autoBuyFruit", 4)
    mkInput(pShop,  "Fruit voulu",            "fruitWanted",  5)
    mkButton(pShop, "▶ Acheter maintenant",
        Color3.fromRGB(255, 170, 0), function() buyWantedFruit() end, 6)
    mkSection(pShop, "FIGHTING STYLES", 7)
    mkToggle(pShop, "Auto apprendre styles",  "autoStyles",   8)
    mkSection(pShop, "STATS", 9)
    mkToggle(pShop, "Auto points",            "autoStats",    10)
    for idx, stat in ipairs({ "Melee", "Defense", "Sword", "Devil Fruit", "Gun" }) do
        local statCopy = stat
        mkButton(pShop, "Max : " .. statCopy,
            CFG.statToMax == statCopy and Color3.fromRGB(63, 185, 80)
                                       or Color3.fromRGB(48, 54, 61),
            function()
                CFG.statToMax = statCopy
                for _, b in ipairs(pShop:GetChildren()) do
                    if b:IsA("TextButton") and b.Text:sub(1, 6) == "Max : " then
                        b.BackgroundColor3 = b.Text:find(statCopy, 1, true)
                            and Color3.fromRGB(63, 185, 80)
                            or  Color3.fromRGB(48, 54, 61)
                    end
                end
            end, 10 + idx)
    end

    local pESP = newPage("esp")
    mkSection(pESP, "ESP", 1)
    mkToggle(pESP, "Mob ESP (boss = rouge)", "mobESP",    2)
    mkToggle(pESP, "Chest ESP",              "chestESP",  3)
    mkToggle(pESP, "Fruit ESP",              "fruitESP",  4)
    mkToggle(pESP, "Player ESP",             "playerESP", 5)
    mkToggle(pESP, "Team Check",             "teamCheck", 6)

    local pSet = newPage("settings")
    mkSection(pSet, "MOUVEMENT", 1)
    mkSlider(pSet, "WalkSpeed", "walkSpeed", 16, 100, 2)
    mkSection(pSet, "DIVERS", 3)
    mkToggle(pSet, "Anti-AFK", "antiAfk", 4)
    mkButton(pSet, "⏸ Pause / Reprise",
        Color3.fromRGB(248, 81, 73),
        function()
            STATE.paused = not STATE.paused
            setStatus(STATE.paused and "PAUSE" or "repris")
        end, 5)
    mkButton(pSet, "✕ Nettoyer ESP",
        Color3.fromRGB(48, 54, 61),
        function()
            for _, d in ipairs(workspace:GetDescendants()) do
                if d.Name == "BF_ESP" or d.Name == "BF_LABEL" then d:Destroy() end
            end
            setStatus("ESP nettoyés")
        end, 6)

    -- ---------- onglets
    local tabs = {
        { "farm",     "FARM",     Color3.fromRGB(63, 185, 80)  },
        { "quest",    "QUÊTES",   Color3.fromRGB(88, 166, 255) },
        { "travel",   "VOYAGE",   Color3.fromRGB(57, 197, 207) },
        { "shop",     "SHOP",     Color3.fromRGB(255, 170, 0)  },
        { "esp",      "ESP",      Color3.fromRGB(255, 0, 255)  },
        { "settings", "RÉGLAGES", Color3.fromRGB(139, 148, 158)},
    }
    local current = "farm"

    for i, t in ipairs(tabs) do
        local b = Instance.new("TextButton")
        b.Size            = UDim2.new(1, -20, 0, 34)
        b.Position        = UDim2.new(0, 10, 0, 10 + (i - 1) * 40)
        b.BackgroundColor3= Color3.fromRGB(13, 17, 23)
        b.Font            = Enum.Font.GothamBold
        b.TextSize        = 12
        b.TextColor3      = Color3.fromRGB(139, 148, 158)
        b.Text            = t[2]
        b.AutoButtonColor = false
        b.Parent          = side
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)

        local dot = Instance.new("Frame")
        dot.Size            = UDim2.new(0, 6, 0, 6)
        dot.Position        = UDim2.new(0, 8, 0.5, -3)
        dot.BackgroundColor3= t[3]
        dot.Visible         = false
        dot.Parent          = b
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

        b.MouseButton1Click:Connect(function()
            current = t[1]
            for name, pg in pairs(pages) do pg.Visible = (name == current) end
            for _, other in ipairs(side:GetChildren()) do
                if other:IsA("TextButton") then
                    local on = (other.Text == t[2])
                    other.BackgroundColor3 = on and Color3.fromRGB(22, 27, 34)
                                              or Color3.fromRGB(13, 17, 23)
                    other.TextColor3       = on and Color3.fromRGB(216, 222, 233)
                                              or Color3.fromRGB(139, 148, 158)
                    for _, ch in ipairs(other:GetChildren()) do
                        if ch:IsA("Frame") then ch.Visible = on end
                    end
                end
            end
        end)

        if i == 1 then
            b.BackgroundColor3 = Color3.fromRGB(22, 27, 34)
            b.TextColor3       = Color3.fromRGB(216, 222, 233)
            dot.Visible        = true
        end
    end
    pages["farm"].Visible = true

    -- ---------- barre d'état
    local foot = Instance.new("TextLabel")
    foot.Size                = UDim2.new(1, -20, 0, 20)
    foot.Position            = UDim2.new(0, 10, 1, -26)
    foot.BackgroundTransparency = 1
    foot.Font                = Enum.Font.Code
    foot.TextSize            = 12
    foot.TextColor3          = Color3.fromRGB(139, 148, 158)
    foot.TextXAlignment      = Enum.TextXAlignment.Left
    foot.Text                = "F1 = menu"
    foot.Parent              = main

    local hb -- FIX : se déconnecte si le script est relancé
    hb = RunService.Heartbeat:Connect(function()
        if not running() or not foot.Parent then hb:Disconnect() return end
        local lvl = "?"
        pcall(function() lvl = tostring(LP.Data.Level.Value) end)
        foot.Text = string.format(
            "Niv. %s  |  %s  |  %s",
            lvl, STATE.status,
            STATE.paused and "⏸ PAUSE" or "▶ actif")
    end)

    local f1
    f1 = UserInputService.InputBegan:Connect(function(inp, gpe)
        if not running() then f1:Disconnect() return end
        if gpe then return end
        if inp.KeyCode == Enum.KeyCode.F1 then
            main.Visible = not main.Visible
        end
    end)
end

local ok, err = pcall(buildGUI)
if not ok then warn("[BFH] GUI error : " .. tostring(err)) end
print("[BFH] v4.2 chargé — F1 = menu")
