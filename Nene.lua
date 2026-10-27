--// GalaXoR | Murder Mystery 2 // v4
local genv = (getgenv and getgenv()) or _G
if genv.GalaXoR_Unload then pcall(genv.GalaXoR_Unload) end

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local UIS             = game:GetService("UserInputService")
local TweenService    = game:GetService("TweenService")
local Lighting        = game:GetService("Lighting")
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser     = game:GetService("VirtualUser")
local CoreGui         = game:GetService("CoreGui")
local RepStorage      = game:GetService("ReplicatedStorage")

local LP          = Players.LocalPlayer
local GuiParent   = (gethui and gethui()) or CoreGui
local CONFIG_FILE = "GalaXoR_mm2.json"

--// state
local conns      = {}
local function track(c) table.insert(conns, c) return c end
local rmbHeld    = false
local menuOpen   = false
local lockedMouse = false
local shootTimer = 0
local tpTarget   = nil
local flinging   = false
local world      = { coins = {}, gun = nil, items = {} }
local timers     = { aura = 0, grab = 0, farm = 0, hb = 0, fling = 0, esp = 0, scan = 0 }
local hitboxOrig = {}
local knifeOrig  = {}
local origLight  = {
    Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
    Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
}
local st = { speed = false, fly = false, noclip = false, fullbright = false }

--// config
local CFG = {
    -- combat
    Aimbot = false, AimHold = true, AimPart = "Head", AimFov = 160, AimSmooth = 30,
    AutoShoot = false,
    KillAura = false, KillAll = false, AutoKill = false, AuraRange = 18,
    KnifeReach = false, KnifeSize = 8,
    Hitbox = false, HitboxSize = 9,
    FlingMurderer = false, AutoGrab = false,
    -- visuals
    ESP = true, EspBox = true, EspName = true, EspRole = true, EspDist = true,
    EspGun = true, EspCoin = true, EspItem = false, Chams = false,
    EspHue = 275, EspSat = 90, EspVal = 100,
    Fullbright = false,
    -- movement
    Speed = false, WalkSpeed = 40, Fly = false, FlySpeed = 80,
    Noclip = false, InfJump = false, Godmode = false, AntiFling = false,
    -- farm / teleport
    AutoFarmCoins = false, Underground = false, ClickTP = false,
    -- misc
    AntiAFK = true,
    -- menu look
    MenuHue = 0, MenuSat = 85, MenuVal = 100, MenuSize = 85, MenuOpacity = 0,
}

--// colors
local C = {
    bg    = Color3.fromRGB(14, 13, 17),
    panel = Color3.fromRGB(21, 19, 25),
    row   = Color3.fromRGB(28, 26, 33),
    rowH  = Color3.fromRGB(38, 35, 44),
    off   = Color3.fromRGB(58, 55, 66),
    text  = Color3.fromRGB(240, 238, 244),
    dim   = Color3.fromRGB(128, 124, 138),
}
local function hsv(h, s, v)
    return Color3.fromHSV((h % 360) / 360, math.clamp(s / 100, 0, 1), math.clamp(v / 100, 0, 1))
end
local function menuColor() return hsv(CFG.MenuHue, CFG.MenuSat, CFG.MenuVal) end
local function espColor()  return hsv(CFG.EspHue, CFG.EspSat, CFG.EspVal) end

--// paint registry: every accent-bound thing re-paints on change
local refreshers = {}
local function bind(fn)
    table.insert(refreshers, fn)
    local ok, err = pcall(fn)
    if not ok then warn("[GalaXoR] " .. tostring(err)) end
end
local function refreshAll()
    for _, f in ipairs(refreshers) do
        local ok, err = pcall(f)
        if not ok then warn("[GalaXoR] " .. tostring(err)) end
    end
end

--// instance helpers
local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function round(o, r)
    new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
    return o
end
local function stroke(o, th, col)
    return new("UIStroke", { Thickness = th or 1, Color = col or C.dim, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end
local orders = setmetatable({}, { __mode = "k" })
local function nextOrder(page)
    orders[page] = (orders[page] or 0) + 1
    return orders[page]
end

--// root gui
local gui = new("ScreenGui", {
    Name = "GalaXoR_UI", ResetOnSpawn = false, DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
gui.Parent = GuiParent

--// toast
local toastHolder = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20),
    Size = UDim2.fromOffset(300, 200), BackgroundTransparency = 1, ZIndex = 50,
}, gui)
new("UIListLayout", {
    VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, toastHolder)
local toastN = 0
local function toast(msg)
    toastN += 1
    local t = round(new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.panel, BorderSizePixel = 0, ZIndex = 51,
        Text = tostring(msg), Font = Enum.Font.GothamMedium, TextSize = 12,
        TextColor3 = C.text, LayoutOrder = toastN,
    }, toastHolder), 7)
    stroke(t, 1, menuColor())
    task.delay(2.4, function() if t then pcall(function() t:Destroy() end) end end)
end

--// draggable: tap vs drag aware
local function makeDraggable(handle, target, onTap)
    local dragging, moved, startMouse, startPos = false, false, nil, nil
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            startMouse, startPos = i.Position, target.Position
        end
    end)
    track(UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startMouse
            if d.Magnitude > 6 then moved = true end
            if moved then
                target.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y
                )
            end
        end
    end))
    track(UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            if dragging and not moved and onTap then onTap() end
            dragging = false
        end
    end))
end

--// floating square icon
local icon = round(new("Frame", {
    Name = "Icon", Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0, 12, 0.4, 0),
    BackgroundColor3 = C.bg, BorderSizePixel = 0, Active = true, ZIndex = 5,
}, gui), 8)
local iconStroke = stroke(icon, 2, menuColor())
bind(function() iconStroke.Color = menuColor() end)
new("TextLabel", {
    BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "G",
    Font = Enum.Font.GothamBlack, TextSize = 20, TextColor3 = menuColor(), ZIndex = 6,
}, icon)

--// main window
local TAB_NAMES = { "Combat", "Visuals", "Move", "Teleport", "Misc", "Config" }
local glass = {}
local main = round(new("Frame", {
    Name = "Main", Size = UDim2.fromOffset(440, 320), Position = UDim2.new(0.5, -220, 0.5, -160),
    BackgroundColor3 = C.bg, BorderSizePixel = 0, Visible = false, Active = true,
    ClipsDescendants = true, BackgroundTransparency = 0,
}, gui), 10)
local mainScale = new("UIScale", { Scale = 1 }, main)
local mainStroke = stroke(main, 1.5, menuColor())
bind(function() mainStroke.Color = menuColor() end)
table.insert(glass, main)

local function baseScale() return CFG.MenuSize / 100 end

local top = round(new("Frame", {
    Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = C.panel, BorderSizePixel = 0, Active = true, ZIndex = 2,
}, main), 10)
new("Frame", {
    Position = UDim2.new(0, 0, 1, -10), Size = UDim2.new(1, 0, 0, 10),
    BackgroundColor3 = C.panel, BorderSizePixel = 0, ZIndex = 2,
}, top)
table.insert(glass, top)
local title = new("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(200, 38),
    Text = "GalaXoR", Font = Enum.Font.GothamBlack, TextSize = 17, TextColor3 = menuColor(),
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
}, top)
bind(function() title.TextColor3 = menuColor() end)
local closeBtn = new("TextButton", {
    BackgroundTransparency = 1, Position = UDim2.new(1, -36, 0, 3), Size = UDim2.fromOffset(32, 32),
    Text = "×", Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = C.dim, ZIndex = 3, AutoButtonColor = false,
}, top)

local content = new("Frame", {
    Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 1, -84),
    BackgroundTransparency = 1, ClipsDescendants = true,
}, main)

local tabBar = new("Frame", {
    Position = UDim2.new(0, 0, 1, -46), Size = UDim2.new(1, 0, 0, 46),
    BackgroundColor3 = C.panel, BorderSizePixel = 0, ZIndex = 2,
}, main)
table.insert(glass, tabBar)

local tabButtons, pages = {}, {}
local function selectTab(name)
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, t in pairs(tabButtons) do
        local on = (n == name)
        t.lbl.TextColor3 = on and menuColor() or C.dim
        t.bar.Visible = on
    end
end

local function makePage(name, index)
    local btn = new("TextButton", {
        Position = UDim2.new((index - 1) / #TAB_NAMES, 0, 0, 0),
        Size = UDim2.new(1 / #TAB_NAMES, 0, 1, 0),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 3,
    }, tabBar)
    local bar = new("Frame", {
        Size = UDim2.new(0.6, 0, 0, 2), Position = UDim2.new(0.2, 0, 0, 0),
        BackgroundColor3 = menuColor(), BorderSizePixel = 0, Visible = false, ZIndex = 4,
    }, btn)
    bind(function() bar.BackgroundColor3 = menuColor() end)
    local lbl = new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = name,
        Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.dim, ZIndex = 4,
    }, btn)
    tabButtons[name] = { btn = btn, bar = bar, lbl = lbl }
    btn.MouseButton1Click:Connect(function() selectTab(name) end)

    local page = new("ScrollingFrame", {
        Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 1, -12),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
        ScrollBarImageColor3 = menuColor(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(0, 0, 0, 0), Visible = false,
    }, content)
    bind(function() page.ScrollBarImageColor3 = menuColor() end)
    new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, page)
    new("UIPadding", { PaddingRight = UDim.new(0, 4) }, page)
    pages[name] = page
    return page
end

--// component builders
local function sectionTitle(page, text)
    new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, -4, 0, 16),
        Text = string.upper(text), Font = Enum.Font.GothamBold, TextSize = 10,
        TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = nextOrder(page),
    }, page)
end

local function row(page, h)
    return new("TextButton", {
        Size = UDim2.new(1, -4, 0, h), BackgroundColor3 = C.row, BorderSizePixel = 0,
        Text = "", AutoButtonColor = false, LayoutOrder = nextOrder(page),
    }, page)
end

local function toggle(page, text, key, cb)
    local r = round(row(page, 36), 8)
    new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -70, 1, 0),
        Text = text, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }, r)
    local pill = round(new("Frame", {
        Size = UDim2.fromOffset(38, 20), Position = UDim2.new(1, -50, 0.5, -10),
        BackgroundColor3 = C.off, BorderSizePixel = 0,
    }, r), 10)
    local knob = round(new("Frame", {
        Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(2, 2),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, pill), 8)
    local function render(instant)
        local on = CFG[key] == true
        local info = TweenInfo.new(instant and 0 or 0.18, Enum.EasingStyle.Quart)
        TweenService:Create(pill, info, { BackgroundColor3 = on and menuColor() or C.off }):Play()
        TweenService:Create(knob, info, {
            Position = on and UDim2.new(1, -18, 0, 2) or UDim2.fromOffset(2, 2),
        }):Play()
    end
    bind(function() render(true) end)
    r.MouseButton1Click:Connect(function()
        CFG[key] = not CFG[key]
        render(false)
        if cb then
            local ok, err = pcall(cb, CFG[key])
            if not ok then toast("error: " .. tostring(err)) end
        end
    end)
    return r
end

local function slider(page, text, key, min, max, step, opts)
    opts = opts or {}
    local r = round(row(page, 50), 8)
    new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -100, 0, 18),
        Text = text, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, r)
    local val = new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(1, -90, 0, 6), Size = UDim2.fromOffset(78, 18),
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right,
    }, r)
    local bar = round(new("Frame", {
        Position = UDim2.fromOffset(12, 33), Size = UDim2.new(1, -24, 0, 6),
        BackgroundColor3 = C.off, BorderSizePixel = 0,
    }, r), 3)
    local fill = round(new("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, bar), 3)
    if opts.hue then
        new("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, hsv(0, 100, 100)), ColorSequenceKeypoint.new(0.17, hsv(60, 100, 100)),
                ColorSequenceKeypoint.new(0.33, hsv(120, 100, 100)), ColorSequenceKeypoint.new(0.5, hsv(180, 100, 100)),
                ColorSequenceKeypoint.new(0.67, hsv(240, 100, 100)), ColorSequenceKeypoint.new(0.83, hsv(300, 100, 100)),
                ColorSequenceKeypoint.new(1, hsv(360, 100, 100)),
            }),
        }, bar)
        fill.BackgroundTransparency = 1
    end
    round(new("Frame", {
        Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0, ZIndex = 3,
    }, fill), 7)

    local function render()
        local p = (CFG[key] - min) / (max - min)
        fill.Size = UDim2.new(math.clamp(p, 0, 1), 0, 1, 0)
        if not opts.hue then fill.BackgroundColor3 = opts.color and opts.color() or menuColor() end
        val.Text = string.format("%g", CFG[key])
    end
    bind(render)

    local dragging = false
    local function setFrom(x)
        local w = math.max(bar.AbsoluteSize.X, 1)
        local p = math.clamp((x - bar.AbsolutePosition.X) / w, 0, 1)
        local v = math.clamp(min + math.floor((max - min) * p / step + 0.5) * step, min, max)
        if CFG[key] ~= v then
            CFG[key] = v
            render()
            if opts.cb then
                local ok, err = pcall(opts.cb, v)
                if not ok then toast("error: " .. tostring(err)) end
            end
            if opts.recolor then refreshAll() end
        end
    end

    local hit = new("TextButton", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 24), Size = UDim2.new(1, -24, 0, 24),
        Text = "", AutoButtonColor = false, ZIndex = 4,
    }, r)
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFrom(i.Position.X)
        end
    end)
    track(UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    track(UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            setFrom(i.Position.X)
        end
    end))
    return r
end

local function cycle(page, label, key, options, cb)
    local b = round(row(page, 36), 8)
    new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -150, 1, 0),
        Text = label, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, b)
    local val = new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(1, -150, 0, 0), Size = UDim2.fromOffset(138, 36),
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = menuColor(), TextXAlignment = Enum.TextXAlignment.Right,
    }, b)
    local function render() val.Text = tostring(CFG[key]) end
    render()
    bind(function() val.TextColor3 = menuColor() end)
    b.MouseButton1Click:Connect(function()
        local idx = 1
        for i, v in ipairs(options) do
            if v == CFG[key] then idx = i break end
        end
        CFG[key] = options[idx % #options + 1]
        render()
        if cb then pcall(cb, CFG[key]) end
    end)
    return b
end

local function button(page, text, cb)
    local b = round(row(page, 34), 8)
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = C.text
    b.MouseEnter:Connect(function() b.BackgroundColor3 = C.rowH end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = C.row end)
    b.MouseButton1Click:Connect(function()
        if cb then
            local ok, err = pcall(cb)
            if not ok then toast("error: " .. tostring(err)) end
        end
    end)
    return b
end

--// helpers
local function getHRP(c) return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum(c) return c and c:FindFirstChildOfClass("Humanoid") end
local function alive(c)
    local h = getHum(c)
    return h ~= nil and h.Health > 0
end
local function ownHRP() return getHRP(LP.Character) end

local function hasTool(p, name)
    local c = p.Character
    if c and c:FindFirstChild(name) then return true end
    local bp = p:FindFirstChildOfClass("Backpack")
    return bp ~= nil and bp:FindFirstChild(name) ~= nil
end

local function roleOf(p)
    if hasTool(p, "Knife") then return "Murderer" end
    if hasTool(p, "Gun") then return "Sheriff" end
    return "Innocent"
end

local function roleColor(role)
    if role == "Murderer" then return Color3.fromRGB(255, 72, 84) end
    if role == "Sheriff" then return Color3.fromRGB(80, 160, 255) end
    return espColor()
end

local function findRole(role)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and alive(p.Character) and roleOf(p) == role then return p end
    end
    return nil
end

local function randomPlayer()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and alive(p.Character) then table.insert(list, p) end
    end
    if #list == 0 then return nil end
    return list[math.random(#list)]
end

local canTouch = typeof(firetouchinterest) == "function"
local function touch(a, b)
    if not canTouch or not a or not b then return end
    pcall(firetouchinterest, a, b, 0)
    pcall(firetouchinterest, a, b, 1)
end

local function visibleFrom(part, from)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {}
    if LP.Character then table.insert(ignore, LP.Character) end
    if part.Parent then table.insert(ignore, part.Parent) end
    params.FilterDescendantsInstances = ignore
    return workspace:Raycast(from, part.Position - from, params) == nil
end

local function setCenterLock(on)
    if on == lockedMouse then return end
    lockedMouse = on
    pcall(function()
        UIS.MouseBehavior = on and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
    end)
end

--// teleport
local function tpTo(pos)
    local root = ownHRP()
    if not root then return end
    root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
end
local function tpBehind(part)
    local root = ownHRP()
    if root and part then root.CFrame = part.CFrame * CFrame.new(0, 0, 3) end
end
local function tpToRole(role)
    local p = findRole(role)
    if not p then return toast(role .. " не найден") end
    tpBehind(getHRP(p.Character))
end

--// world scan
local function getCoins()
    local out = {}
    local cont = workspace:FindFirstChild("CoinContainer", true)
    if cont then
        for _, c in ipairs(cont:GetChildren()) do
            local part = c:IsA("BasePart") and c or c:FindFirstChildWhichIsA("BasePart", true)
            if part then table.insert(out, part) end
        end
    end
    return out
end
local function getGunDrop()
    local g = workspace:FindFirstChild("GunDrop", true)
    if not g then return nil end
    if g:IsA("BasePart") then return g end
    return g:FindFirstChildWhichIsA("BasePart", true)
end
local function scanWorld()
    world.coins = getCoins()
    world.gun = getGunDrop()
    world.items = {}
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Tool") then
            local h = child:FindFirstChild("Handle") or child:FindFirstChildWhichIsA("BasePart")
            if h then table.insert(world.items, h) end
        end
    end
end
local function nearestCoin(pos)
    local best, bd = nil, math.huge
    for _, part in ipairs(world.coins) do
        if part.Parent then
            local d = (part.Position - pos).Magnitude
            if d < bd then best, bd = part, d end
        end
    end
    return best
end

--// combat
local function equipKnife()
    local c, h = LP.Character, getHum(LP.Character)
    if not c or not h or c:FindFirstChild("Knife") then return end
    local bp = LP:FindFirstChildOfClass("Backpack")
    local k = bp and bp:FindFirstChild("Knife")
    if k and k:IsA("Tool") then pcall(function() h:EquipTool(k) end) end
end

local function doKill(range, root)
    local c = LP.Character
    local knife = c and c:FindFirstChild("Knife")
    local handle = knife and knife:FindFirstChild("Handle")
    if not handle or not root then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and alive(p.Character) then
            local th = getHRP(p.Character)
            if th and (th.Position - root.Position).Magnitude <= range then touch(handle, th) end
        end
    end
end

local function restoreKnife()
    for handle, size in pairs(knifeOrig) do
        if handle.Parent then pcall(function() handle.Size = size end) end
        knifeOrig[handle] = nil
    end
end
local function restoreHitbox()
    for part, size in pairs(hitboxOrig) do
        if part.Parent then pcall(function() part.Size = size end) end
        hitboxOrig[part] = nil
    end
end

local function aimTarget(cam)
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local best, bestD = nil, CFG.AimFov
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and alive(p.Character) then
            local part = p.Character:FindFirstChild(CFG.AimPart) or getHRP(p.Character)
            if part then
                local sp, on = cam:WorldToViewportPoint(part.Position)
                if on and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if d < bestD and visibleFrom(part, cam.CFrame.Position) then
                        best, bestD = part, d
                    end
                end
            end
        end
    end
    return best
end

local function autoShootTarget(cam)
    if not CFG.AutoShoot then return nil end
    local c = LP.Character
    if not c or not c:FindFirstChild("Gun") then return nil end
    local m = findRole("Murderer")
    local mc = m and m.Character
    local mh = mc and (mc:FindFirstChild("Head") or getHRP(mc))
    if mh and alive(mc) and visibleFrom(mh, cam.CFrame.Position) then return mh end
    return nil
end

--// camera step: bound after camera update so our CFrame sticks
local function camStep()
    local cam = workspace.CurrentCamera
    if not cam then return end

    if CFG.Aimbot and (not CFG.AimHold or rmbHeld) then
        local part = aimTarget(cam)
        if part then
            local goal = CFrame.lookAt(cam.CFrame.Position, part.Position)
            cam.CFrame = cam.CFrame:Lerp(goal, math.clamp(CFG.AimSmooth / 100, 0.02, 1))
        end
    end

    local shootPart = autoShootTarget(cam)
    if shootPart then
        cam.CFrame = CFrame.lookAt(cam.CFrame.Position, shootPart.Position)
        setCenterLock(not menuOpen)
        local now = os.clock()
        if now - shootTimer > 0.35 and typeof(mouse1click) == "function" then
            shootTimer = now
            pcall(mouse1click)
        end
    else
        setCenterLock(false)
    end
end

--// ESP: Highlight on character, billboard over head
local espStore = { players = {}, world = {} }
local function destroyEntry(e)
    if not e then return end
    pcall(function() e.hl:Destroy() end)
    if e.bb then pcall(function() e.bb:Destroy() end) end
end
local function getEntry(store, key, adornee, labelParent)
    local e = store[key]
    if e and e.adornee == adornee and e.hl.Parent then return e end
    if e then destroyEntry(e) end
    local hl = new("Highlight", {
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Adornee = adornee, Parent = gui,
    })
    local bb, lbl
    if labelParent then
        bb = new("BillboardGui", {
            AlwaysOnTop = true, Size = UDim2.fromOffset(240, 22),
            StudsOffset = Vector3.new(0, 2.6, 0), Adornee = labelParent, Parent = labelParent,
        })
        lbl = new("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold,
            TextSize = 13, TextStrokeTransparency = 0.3, TextColor3 = C.text, Text = "",
        }, bb)
    end
    e = { hl = hl, bb = bb, lbl = lbl, adornee = adornee }
    store[key] = e
    return e
end

local function updatePlayers(myRoot)
    local store = espStore.players
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local c = p.Character
            local head = c and c:FindFirstChild("Head")
            local root = getHRP(c)
            if CFG.ESP and head and root and alive(c) then
                local role = roleOf(p)
                local col = (CFG.EspRole and role ~= "Innocent") and roleColor(role) or espColor()
                local e = getEntry(store, p, c, head)
                local parts = {}
                if CFG.EspName then table.insert(parts, p.Name) end
                if CFG.EspRole then table.insert(parts, "[" .. role .. "]") end
                if CFG.EspDist and myRoot then
                    table.insert(parts, math.floor((root.Position - myRoot.Position).Magnitude) .. "m")
                end
                e.lbl.Text = table.concat(parts, "  ")
                e.lbl.TextColor3 = col
                e.bb.Enabled = #parts > 0
                e.hl.Enabled = CFG.EspBox or CFG.Chams
                e.hl.FillColor = col
                e.hl.OutlineColor = col
                e.hl.OutlineTransparency = CFG.EspBox and 0 or 1
                e.hl.FillTransparency = CFG.Chams and 0.45 or 1
            elseif store[p] then
                store[p].hl.Enabled = false
                if store[p].bb then store[p].bb.Enabled = false end
            end
        end
    end
end

local function updateWorld(myRoot)
    local s = espStore.world
    local active = {}
    local gold = Color3.fromRGB(255, 200, 60)

    if CFG.ESP and CFG.EspGun and world.gun and world.gun.Parent then
        local e = getEntry(s, "gun", world.gun, world.gun)
        local d = myRoot and math.floor((world.gun.Position - myRoot.Position).Magnitude) or 0
        e.lbl.Text = "GUN DROP  " .. d .. "m"
        e.lbl.TextColor3 = gold
        e.bb.Enabled = true
        e.hl.Enabled = true
        e.hl.FillColor = gold
        e.hl.OutlineColor = gold
        e.hl.FillTransparency = 0.5
        e.hl.OutlineTransparency = 0
        active["gun"] = true
    end

    if CFG.ESP and CFG.EspCoin and myRoot then
        local list = {}
        for _, part in ipairs(world.coins) do
            if part.Parent then table.insert(list, { part, (part.Position - myRoot.Position).Magnitude }) end
        end
        table.sort(list, function(a, b) return a[2] < b[2] end)
        for i = 1, math.min(#list, 60) do
            local part = list[i][1]
            local e = getEntry(s, part, part, nil)
            e.hl.Enabled = true
            e.hl.FillColor = Color3.fromRGB(255, 215, 60)
            e.hl.OutlineColor = Color3.fromRGB(255, 215, 60)
            e.hl.FillTransparency = 0.35
            e.hl.OutlineTransparency = 1
            active[part] = true
        end
    end

    if CFG.ESP and CFG.EspItem then
        for _, item in ipairs(world.items) do
            if item.Parent then
                local e = getEntry(s, item, item, item)
                e.lbl.Text = item.Parent.Name
                e.lbl.TextColor3 = Color3.fromRGB(180, 220, 255)
                e.bb.Enabled = true
                e.hl.Enabled = true
                e.hl.FillColor = Color3.fromRGB(180, 220, 255)
                e.hl.OutlineColor = Color3.fromRGB(180, 220, 255)
                e.hl.FillTransparency = 0.5
                e.hl.OutlineTransparency = 0
                active[item] = true
            end
        end
    end

    for key, e in pairs(s) do
        if not active[key] then
            destroyEntry(e)
            s[key] = nil
        end
    end
end

--// misc
local function fpsBoost()
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    pcall(function() Lighting.GlobalShadows = false end)
    local n = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam")
            or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
            pcall(function() d.Enabled = false end)
            n += 1
        elseif d:IsA("Decal") or d:IsA("Texture") then
            pcall(function() d.Transparency = 1 end)
            n += 1
        end
    end
    toast("boost: " .. n .. " объектов")
end

local function say(msg)
    local ok = pcall(function()
        local ev = RepStorage:FindFirstChild("DefaultChatSystemChatEvents")
        local req = ev and ev:FindFirstChild("SayMessageRequest")
        if not req then error("no legacy chat") end
        req:FireServer(msg, "All")
    end)
    if not ok then
        local ok2 = pcall(function()
            local ch = game:GetService("TextChatService").TextChannels:FindFirstChild("RBXGeneral")
            ch:SendAsync(msg)
        end)
        if not ok2 then toast("чат не найден") end
    end
end

local function getRequest()
    return (request or http_request or (syn and syn.request) or (http and http.request))
end

local function serverHop()
    local req = getRequest()
    if not req then return toast("нет request() в экзекуторе") end
    local ok, res = pcall(req, {
        Url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId),
        Method = "GET",
    })
    if not ok or not res or not res.Body then return toast("не получил список серверов") end
    local ok2, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
    if not ok2 or type(data) ~= "table" or type(data.data) ~= "table" then
        return toast("битый список серверов")
    end
    local candidates = {}
    for _, s in ipairs(data.data) do
        if s.id ~= game.JobId and s.playing and s.maxPlayers and s.playing < s.maxPlayers then
            table.insert(candidates, s.id)
        end
    end
    if #candidates == 0 then return toast("свободных серверов нет") end
    pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, candidates[math.random(#candidates)], LP)
end

local function rejoin()
    pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
end

--// main heartbeat (dt-based)
track(RunService.Heartbeat:Connect(function(dt)
    local now = os.clock()
    local c = LP.Character
    local hum = getHum(c)
    local root = getHRP(c)

    -- fullbright
    if CFG.Fullbright then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        st.fullbright = true
    elseif st.fullbright then
        Lighting.Brightness = origLight.Brightness
        Lighting.ClockTime = origLight.ClockTime
        Lighting.Ambient = origLight.Ambient
        Lighting.OutdoorAmbient = origLight.OutdoorAmbient
        st.fullbright = false
    end

    if hum and root and hum.Health > 0 then
        -- speed
        if CFG.Speed then
            hum.WalkSpeed = CFG.WalkSpeed
            st.speed = true
        elseif st.speed then
            hum.WalkSpeed = 16
            st.speed = false
        end

        -- fly: CFrame stepping, works with touch (MoveDirection) and keyboard
        if CFG.Fly then
            hum.PlatformStand = true
            st.fly = true
            local move = hum.MoveDirection
            local up = 0
            if UIS:IsKeyDown(Enum.KeyCode.Space) then up = 1 end
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then up = -1 end
            local dir = Vector3.new(move.X, up, move.Z)
            if dir.Magnitude > 1 then dir = dir.Unit end
            root.AssemblyLinearVelocity = Vector3.zero
            root.CFrame = root.CFrame + dir * CFG.FlySpeed * dt
        elseif st.fly then
            hum.PlatformStand = false
            st.fly = false
        end

        -- noclip (also forced while underground farming)
        local noclipWanted = CFG.Noclip or (CFG.AutoFarmCoins and CFG.Underground)
        if noclipWanted then
            for _, part in ipairs(c:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
            st.noclip = true
        elseif st.noclip then
            for _, part in ipairs(c:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = (part.Name ~= "HumanoidRootPart") end
            end
            st.noclip = false
        end

        -- godmode (client refill)
        if CFG.Godmode and hum.Health < hum.MaxHealth then hum.Health = hum.MaxHealth end

        -- anti-fling
        if CFG.AntiFling and root.AssemblyLinearVelocity.Magnitude > 220 then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end

        -- auto farm coins
        if CFG.AutoFarmCoins and now - timers.farm > 0.12 then
            timers.farm = now
            local coin = nearestCoin(root.Position)
            if coin then
                local off = CFG.Underground and Vector3.new(0, -9, 0) or Vector3.zero
                root.CFrame = CFrame.new(coin.Position + off)
                root.AssemblyLinearVelocity = Vector3.zero
                touch(root, coin)
            end
        end

        -- kill aura / kill all / auto kill
        if (CFG.KillAura or CFG.KillAll or CFG.AutoKill) and now - timers.aura > 0.06 then
            timers.aura = now
            if CFG.AutoKill then equipKnife() end
            doKill(CFG.KillAll and 1e9 or CFG.AuraRange, root)
        end

        -- knife reach
        if CFG.KnifeReach then
            local knife = c:FindFirstChild("Knife")
            local handle = knife and knife:FindFirstChild("Handle")
            if handle then
                if not knifeOrig[handle] then knifeOrig[handle] = handle.Size end
                handle.Size = Vector3.new(CFG.KnifeSize, CFG.KnifeSize, CFG.KnifeSize)
            end
        elseif next(knifeOrig) then
            restoreKnife()
        end

        -- hitbox expander
        if not CFG.Hitbox then
            if next(hitboxOrig) then restoreHitbox() end
        elseif now - timers.hb > 0.25 then
            timers.hb = now
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP and p.Character then
                    local th = getHRP(p.Character)
                    if th then
                        if not hitboxOrig[th] then hitboxOrig[th] = th.Size end
                        th.Size = Vector3.new(CFG.HitboxSize, CFG.HitboxSize, CFG.HitboxSize)
                    end
                end
            end
        end

        -- fling murderer: spin own root next to them (needs their replication through us)
        if CFG.FlingMurderer then
            local m = findRole("Murderer")
            local mh = m and getHRP(m.Character)
            if mh and (mh.Position - root.Position).Magnitude < 7 then
                flinging = true
                root.CFrame = CFrame.lookAt(root.Position, mh.Position)
                root.AssemblyAngularVelocity = Vector3.new(0, 400, 0)
                root.AssemblyLinearVelocity = (mh.Position - root.Position).Unit * 60
            elseif flinging then
                flinging = false
                root.AssemblyAngularVelocity = Vector3.zero
            end
        elseif flinging then
            flinging = false
            root.AssemblyAngularVelocity = Vector3.zero
        end

        -- auto grab gun
        if CFG.AutoGrab and now - timers.grab > 0.6 then
            timers.grab = now
            local gun = world.gun
            if gun and gun.Parent and not c:FindFirstChild("Gun") and not hasTool(LP, "Gun") then
                root.CFrame = gun.CFrame + Vector3.new(0, 3, 0)
                touch(root, gun)
            end
        end
    end

    if now - timers.scan > 1 then
        timers.scan = now
        scanWorld()
    end
    if now - timers.esp > 0.12 then
        timers.esp = now
        updatePlayers(root)
        updateWorld(root)
    end
end))

--// camera bound after default camera priority
pcall(function()
    RunService:BindToRenderStep("GalaXoRCam", Enum.RenderPriority.Camera.Value + 1, camStep)
end)

--// anti-afk
track(LP.Idled:Connect(function()
    if CFG.AntiAFK then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end))

--// infinite jump
track(UIS.JumpRequest:Connect(function()
    if CFG.InfJump and LP.Character then
        local h = getHum(LP.Character)
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end))

--// menu open / close with animation
local function setMenu(open)
    if open == menuOpen then return end
    menuOpen = open
    local target = baseScale()
    if open then
        main.Visible = true
        mainScale.Scale = target * 0.8
        main.BackgroundTransparency = 1
        TweenService:Create(mainScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
        TweenService:Create(main, TweenInfo.new(0.2), { BackgroundTransparency = CFG.MenuOpacity / 100 }):Play()
    else
        local t = TweenService:Create(mainScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = target * 0.8 })
        TweenService:Create(main, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
        t:Play()
        t.Completed:Connect(function()
            if not menuOpen then main.Visible = false end
        end)
    end
end
local function toggleMenu() setMenu(not menuOpen) end

track(UIS.InputBegan:Connect(function(i, gp)
    if i.UserInputType == Enum.UserInputType.MouseButton2 then rmbHeld = true end
    if gp then return end
    if i.KeyCode == Enum.KeyCode.RightShift or i.KeyCode == Enum.KeyCode.Insert then
        toggleMenu()
    end
    if CFG.ClickTP and i.UserInputType == Enum.UserInputType.MouseButton1 and UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
        local ok, hit = pcall(function() return LP:GetMouse().Hit end)
        if ok and hit then tpTo(hit.Position) end
    end
end))
track(UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton2 then rmbHeld = false end
end))

makeDraggable(icon, icon, toggleMenu)
makeDraggable(top, main, nil)
track(closeBtn.MouseButton1Click:Connect(function() setMenu(false) end))

--// config
local function saveConfig()
    if not writefile then return toast("writefile нет в экзекуторе") end
    local data = {}
    for k, v in pairs(CFG) do
        if type(v) ~= "table" then data[k] = v end
    end
    local ok, err = pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(data)) end)
    toast(ok and "config сохранён" or ("save error: " .. tostring(err)))
end

local function loadConfig()
    if not (readfile and isfile and isfile(CONFIG_FILE)) then return toast("конфига нет") end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CONFIG_FILE)) end)
    if not ok or type(data) ~= "table" then return toast("конфиг битый") end
    for k, v in pairs(data) do
        if CFG[k] ~= nil and type(CFG[k]) == type(v) then CFG[k] = v end
    end
    main.Size = UDim2.fromOffset(440, 320)
    mainScale.Scale = baseScale()
    refreshAll()
    toast("config загружен")
end

--// unload
local function unload()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    pcall(function() RunService:UnbindFromRenderStep("GalaXoRCam") end)
    setCenterLock(false)
    for _, e in pairs(espStore.players) do destroyEntry(e) end
    for _, e in pairs(espStore.world) do destroyEntry(e) end
    restoreKnife()
    restoreHitbox()
    Lighting.Brightness = origLight.Brightness
    Lighting.ClockTime = origLight.ClockTime
    Lighting.Ambient = origLight.Ambient
    Lighting.OutdoorAmbient = origLight.OutdoorAmbient
    local h = getHum(LP.Character)
    if h then pcall(function() h.WalkSpeed = 16 h.PlatformStand = false end) end
    pcall(function() gui:Destroy() end)
    genv.GalaXoR_Unload = nil
end
genv.GalaXoR_Unload = unload

--// pages
local function buildPages()
    local combat = makePage("Combat", 1)
    sectionTitle(combat, "Aim")
    toggle(combat, "Aimbot", "Aimbot")
    toggle(combat, "Only while holding RMB", "AimHold")
    cycle(combat, "Aim bone", "AimPart", { "Head", "Torso", "HumanoidRootPart" })
    slider(combat, "FOV radius", "AimFov", 20, 500, 5)
    slider(combat, "Smoothing %", "AimSmooth", 5, 100, 5)
    toggle(combat, "Auto Shoot", "AutoShoot")
    sectionTitle(combat, "Melee")
    toggle(combat, "Kill Aura", "KillAura")
    slider(combat, "Aura range", "AuraRange", 5, 60, 1)
    toggle(combat, "Kill All (as Murderer)", "KillAll")
    toggle(combat, "Auto Kill", "AutoKill")
    toggle(combat, "Knife Reach", "KnifeReach")
    slider(combat, "Knife size", "KnifeSize", 2, 25, 1)
    toggle(combat, "Hitbox Expander", "Hitbox")
    slider(combat, "Hitbox size", "HitboxSize", 2, 25, 1)
    toggle(combat, "Fling Murderer", "FlingMurderer")
    sectionTitle(combat, "Pickup")
    toggle(combat, "Auto Grab Gun", "AutoGrab")

    local visuals = makePage("Visuals", 2)
    sectionTitle(visuals, "ESP")
    toggle(visuals, "ESP Master", "ESP")
    toggle(visuals, "Box", "EspBox")
    toggle(visuals, "Name", "EspName")
    toggle(visuals, "Role", "EspRole")
    toggle(visuals, "Distance", "EspDist")
    toggle(visuals, "Gun drop", "EspGun")
    toggle(visuals, "Coins", "EspCoin")
    toggle(visuals, "Dropped items", "EspItem")
    toggle(visuals, "Chams", "Chams")
    sectionTitle(visuals, "ESP color")
    slider(visuals, "Hue", "EspHue", 0, 360, 1, { hue = true })
    slider(visuals, "Saturation", "EspSat", 0, 100, 1, { color = espColor })
    slider(visuals, "Brightness", "EspVal", 10, 100, 1, { color = espColor })
    sectionTitle(visuals, "World")
    toggle(visuals, "Fullbright", "Fullbright")

    local move = makePage("Move", 3)
    sectionTitle(move, "Speed & fly")
    toggle(move, "Speed Hack", "Speed")
    slider(move, "Walk speed", "WalkSpeed", 16, 200, 1)
    toggle(move, "Fly", "Fly")
    slider(move, "Fly speed", "FlySpeed", 20, 250, 5)
    sectionTitle(move, "Physics")
    toggle(move, "Noclip", "Noclip")
    toggle(move, "Infinite Jump", "InfJump")
    toggle(move, "Godmode", "Godmode")
    toggle(move, "Anti-Fling", "AntiFling")

    local tp = makePage("Teleport", 4)
    sectionTitle(tp, "Roles")
    button(tp, "Murderer", function() tpToRole("Murderer") end)
    button(tp, "Sheriff", function() tpToRole("Sheriff") end)
    button(tp, "Random player", function()
        local p = randomPlayer()
        if not p then return toast("нет живых игроков") end
        tpBehind(getHRP(p.Character))
    end)
    sectionTitle(tp, "Player")
    local targetBtn
    targetBtn = button(tp, "Target: none", function()
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP then table.insert(list, p) end
        end
        if #list == 0 then
            tpTarget = nil
        else
            local idx = 0
            for i, p in ipairs(list) do
                if p == tpTarget then idx = i end
            end
            tpTarget = list[idx % #list + 1]
        end
        targetBtn.Text = "Target: " .. (tpTarget and tpTarget.Name or "none")
    end)
    button(tp, "Teleport to target", function()
        if not tpTarget then return toast("сначала выбери цель") end
        local th = getHRP(tpTarget.Character)
        if not th then return toast("цель без персонажа") end
        tpBehind(th)
    end)
    sectionTitle(tp, "Coins & click")
    button(tp, "Nearest coin", function()
        local root = ownHRP()
        local coin = root and nearestCoin(root.Position)
        if not coin then return toast("монет не найдено") end
        tpTo(coin.Position)
    end)
    toggle(tp, "Ctrl + Click teleport", "ClickTP")
    sectionTitle(tp, "Farm")
    toggle(tp, "Auto Farm Coins", "AutoFarmCoins")
    toggle(tp, "Underground farm", "Underground")

    local misc = makePage("Misc", 5)
    sectionTitle(misc, "Utility")
    toggle(misc, "Anti-AFK", "AntiAFK")
    button(misc, "FPS Booster", fpsBoost)
    button(misc, "Server Hop", serverHop)
    button(misc, "Rejoin", rejoin)
    sectionTitle(misc, "Emotes")
    for _, e in ipairs({ "dance", "dance2", "wave", "point", "laugh", "cheer" }) do
        button(misc, "/e " .. e, function() say("/e " .. e) end)
    end

    local cfg = makePage("Config", 6)
    sectionTitle(cfg, "Menu color")
    slider(cfg, "Hue", "MenuHue", 0, 360, 1, { hue = true, cb = refreshAll })
    slider(cfg, "Saturation", "MenuSat", 0, 100, 1, { recolor = true })
    slider(cfg, "Brightness", "MenuVal", 20, 100, 1, { recolor = true })
    sectionTitle(cfg, "Menu look")
    slider(cfg, "Size %", "MenuSize", 60, 130, 5, {
        cb = function(v)
            if menuOpen then mainScale.Scale = v / 100 end
        end,
    })
    slider(cfg, "Opacity %", "MenuOpacity", 0, 70, 1, {
        cb = function(v)
            if menuOpen then
                for _, f in ipairs(glass) do f.BackgroundTransparency = v / 100 end
            end
        end,
    })
    sectionTitle(cfg, "Config file")
    button(cfg, "Save config", saveConfig)
    button(cfg, "Load config", loadConfig)
    sectionTitle(cfg, "Session")
    button(cfg, "Unload GalaXoR", unload)
end

buildPages()
selectTab("Combat")
refreshAll()
mainScale.Scale = baseScale()
toast("GalaXoR loaded")
