-- Hopper Server Finder - Final (Personalizable, draggable GUI + floating bubble)
-- Escanea servidores públicos server-by-server buscando Brainrots individuales >= mínimo elegido.
-- Usa: copiar/pegar en executor o cargar con loadstring(game:HttpGet("RAW_URL"))()

-- Seguridad básica
if not (game and game.GetService) then return end
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
if not player then error("Este script debe ejecutarse en un LocalScript o en un entorno con LocalPlayer.") end
local playerGui = player:WaitForChild("PlayerGui")

-- Config por defecto (puedes cambiar desde GUI)
local PLACE_ID = game.PlaceId
local DEFAULT_MIN = 50 * 1e6 -- 50M por defecto
local MIN_GENERATION = DEFAULT_MIN
local SCAN_WAIT = 4 -- segundos después de teleport antes de escanear
local MAX_SERVERS_TO_TRY = 200 -- máximo servidores a pedir
local teleportRetryCount = 3
local teleportRetryDelay = 1.2
local throttleHttpSeconds = 1.0
local lastHttp = 0

-- Helpers
local function addCorner(parent, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = parent end
local function clamp(v, a, b) if v < a then return a end; if v > b then return b end; return v end
local function formatNumber(n) n = tonumber(n) or 0; if n>=1e9 then return string.format("$%.1fB", n/1e9) elseif n>=1e6 then return string.format("$%.1fM", n/1e6) elseif n>=1e3 then return string.format("$%.1fK", n/1e3) else return "$"..tostring(math.floor(n)) end end

-- Draggable helper (works with touch and mouse)
local function makeDraggable(frame, dragHandle)
    dragHandle = dragHandle or frame
    local dragging = false
    local dragStart = nil
    local startPos = nil

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                clamp(startPos.X.Scale,0,1),
                startPos.X.Offset + delta.X,
                clamp(startPos.Y.Scale,0,1),
                startPos.Y.Offset + delta.Y
            )
        end
    end)

    dragHandle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- Safe HTTP GET + JSON decode with throttling
local function safeHttpGet(url)
    local now = tick()
    if now - lastHttp < throttleHttpSeconds then task.wait(throttleHttpSeconds - (now - lastHttp)) end
    lastHttp = tick()
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if not ok then return nil, "httpfail" end
    local decodeOk, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not decodeOk then return nil, "decodefail" end
    return data, nil
end

-- Notification small helper (simple, non-blocking)
local function showNotification(text, color)
    local screen = playerGui:FindFirstChild("HopperFinderGui") or playerGui
    local notif = Instance.new("Frame")
    notif.Size = UDim2.new(0, 380, 0, 72)
    notif.Position = UDim2.new(1, -400, 0, 24)
    notif.BackgroundColor3 = color or Color3.fromRGB(50,200,100)
    notif.BorderSizePixel = 0
    notif.ZIndex = 9999
    notif.Parent = screen
    addCorner(notif, 10)

    local lab = Instance.new("TextLabel")
    lab.Size = UDim2.new(1, -20, 1, -20)
    lab.Position = UDim2.new(0, 10, 0, 10)
    lab.BackgroundTransparency = 1
    lab.Font = Enum.Font.GothamBold
    lab.TextSize = 14
    lab.TextColor3 = Color3.fromRGB(255,255,255)
    lab.TextWrapped = true
    lab.Text = tostring(text)
    lab.Parent = notif

    task.spawn(function()
        task.wait(3.6)
        if notif and notif.Parent then notif:Destroy() end
    end)
end

-- Remove existing GUI if any
local existing = playerGui:FindFirstChild("HopperFinderGui")
if existing then existing:Destroy() end

-- Create main ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HopperFinderGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Main window (unique style inspired by your image)
local main = Instance.new("Frame")
main.Name = "MainWindow"
main.Size = UDim2.new(0, 520, 0, 620)
main.Position = UDim2.new(0.5, -260, 0.5, -310)
main.BackgroundColor3 = Color3.fromRGB(26, 34, 47)
main.BorderSizePixel = 0
main.Parent = screenGui
addCorner(main, 14)

-- Top bar
local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 56)
topBar.Position = UDim2.new(0, 0, 0, 0)
topBar.BackgroundColor3 = Color3.fromRGB(36, 45, 62)
topBar.BorderSizePixel = 0
topBar.Parent = main
addCorner(topBar, 14)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -140, 1, 0)
title.Position = UDim2.new(0, 16, 0, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(240,240,240)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "🤖 HOPPER FINDER - Server Scanner"
title.Parent = topBar

-- Buttons: minimize and close
local btnMin = Instance.new("TextButton")
btnMin.Size = UDim2.new(0, 38, 0, 38)
btnMin.Position = UDim2.new(1, -96, 0, 9)
btnMin.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
btnMin.Text = "—"
btnMin.Font = Enum.Font.GothamBold
btnMin.TextSize = 20
btnMin.TextColor3 = Color3.fromRGB(0,0,0)
btnMin.Parent = topBar
addCorner(btnMin, 10)

local btnClose = Instance.new("TextButton")
btnClose.Size = UDim2.new(0, 38, 0, 38)
btnClose.Position = UDim2.new(1, -44, 0, 9)
btnClose.BackgroundColor3 = Color3.fromRGB(220,50,50)
btnClose.Text = "✕"
btnClose.Font = Enum.Font.GothamBold
btnClose.TextSize = 18
btnClose.TextColor3 = Color3.fromRGB(255,255,255)
btnClose.Parent = topBar
addCorner(btnClose, 10)

-- Status panel
local statusPanel = Instance.new("Frame")
statusPanel.Size = UDim2.new(1, -32, 0, 110)
statusPanel.Position = UDim2.new(0, 16, 0, 64)
statusPanel.BackgroundColor3 = Color3.fromRGB(29, 38, 55)
statusPanel.Parent = main
addCorner(statusPanel, 10)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 1, -20)
statusLabel.Position = UDim2.new(0, 10, 0, 10)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 13
statusLabel.TextColor3 = Color3.fromRGB(205,205,205)
statusLabel.TextWrapped = true
statusLabel.Text = "✅ GUI listo. Selecciona mínimo y presiona INICIAR EXPLORACIÓN."
statusLabel.Parent = statusPanel

-- Filters panel
local filterPanel = Instance.new("Frame")
filterPanel.Size = UDim2.new(1, -32, 0, 92)
filterPanel.Position = UDim2.new(0, 16, 0, 184)
filterPanel.BackgroundColor3 = Color3.fromRGB(29, 38, 55)
filterPanel.Parent = main
addCorner(filterPanel, 10)

local flabel = Instance.new("TextLabel")
flabel.Size = UDim2.new(1, -20, 0, 24)
flabel.Position = UDim2.new(0, 10, 0, 6)
flabel.BackgroundTransparency = 1
flabel.Font = Enum.Font.GothamBold
flabel.Text = "⚙️ FILTROS"
flabel.TextSize = 14
flabel.TextColor3 = Color3.fromRGB(255,255,255)
flabel.Parent = filterPanel

-- range label (shows current minimum)
local rangeLabel = Instance.new("TextLabel")
rangeLabel.Size = UDim2.new(1, -20, 0, 20)
rangeLabel.Position = UDim2.new(0, 10, 0, 64)
rangeLabel.BackgroundTransparency = 1
rangeLabel.Font = Enum.Font.Gotham
rangeLabel.TextSize = 12
rangeLabel.TextColor3 = Color3.fromRGB(200,200,200)
rangeLabel.TextXAlignment = Enum.TextXAlignment.Left
rangeLabel.Parent = filterPanel

-- Minimum buttons (personalizable)
local mins = {["10M"]=10*1e6, ["20M"]=20*1e6, ["50M"]=50*1e6, ["100M"]=100*1e6}
local chosenKey = "50M"
local minButtons = {}
local function updateRangeLabel()
    rangeLabel.Text = "🔎 Mínimo seleccionado: "..chosenKey.." ("..formatNumber(MIN_GENERATION).."/s)"
end

local x = 10
for key,val in pairs(mins) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 78, 0, 28)
    b.Position = UDim2.new(0, x, 0, 36)
    b.Text = key
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Parent = filterPanel
    addCorner(b, 8)
    b.BackgroundColor3 = (key == chosenKey) and Color3.fromRGB(50,200,100) or Color3.fromRGB(95,95,95)
    b.MouseButton1Click:Connect(function()
        MIN_GENERATION = val
        chosenKey = key
        for kk,btn in pairs(minButtons) do btn.BackgroundColor3 = (kk==key) and Color3.fromRGB(50,200,100) or Color3.fromRGB(95,95,95) end
        updateRangeLabel()
    end)
    minButtons[key] = b
    x = x + 86
end
MIN_GENERATION = mins[chosenKey] or DEFAULT_MIN
updateRangeLabel()

-- Control buttons: scan, explore, stop
scanBtn = Instance.new("TextButton")
scanBtn.Size = UDim2.new(1, -32, 0, 46)
scanBtn.Position = UDim2.new(0, 16, 0, 288)
scanBtn.BackgroundColor3 = Color3.fromRGB(50,150,250)
scanBtn.Font = Enum.Font.GothamBold
scanBtn.TextSize = 15
scanBtn.TextColor3 = Color3.fromRGB(255,255,255)
scanBtn.Text = "🔍 ESCANEAR SERVIDOR ACTUAL"
scanBtn.Parent = main
addCorner(scanBtn, 10)

exploreBtn = Instance.new("TextButton")
exploreBtn.Size = UDim2.new(1, -32, 0, 46)
exploreBtn.Position = UDim2.new(0, 16, 0, 344)
exploreBtn.BackgroundColor3 = Color3.fromRGB(50,200,100)
exploreBtn.Font = Enum.Font.GothamBold
exploreBtn.TextSize = 15
exploreBtn.TextColor3 = Color3.fromRGB(255,255,255)
exploreBtn.Text = "🚀 INICIAR EXPLORACIÓN (server-by-server)"
exploreBtn.Parent = main
addCorner(exploreBtn, 10)

stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(1, -32, 0, 46)
stopBtn.Position = UDim2.new(0, 16, 0, 344)
stopBtn.BackgroundColor3 = Color3.fromRGB(220,50,50)
stopBtn.Font = Enum.Font.GothamBold
stopBtn.TextSize = 15
stopBtn.TextColor3 = Color3.fromRGB(255,255,255)
stopBtn.Text = "⏹ DETENER EXPLORACIÓN"
stopBtn.Visible = false
stopBtn.Parent = main
addCorner(stopBtn, 10)

-- Results list
results = Instance.new("ScrollingFrame")
results.Size = UDim2.new(1, -32, 0, 210)
results.Position = UDim2.new(0, 16, 0, 404)
results.BackgroundColor3 = Color3.fromRGB(29, 38, 55)
results.Parent = main
results.ScrollBarThickness = 6
addCorner(results, 10)
results.CanvasSize = UDim2.new(0,0,0,0)

foundServers = {} -- local to this instance (will not persist across teleports automatically)

local function clearResultsUI()
    for _,c in ipairs(results:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextLabel") or c:IsA("TextButton") then pcall(function() c:Destroy() end) end
    end
    results.CanvasSize = UDim2.new(0,0,0,0)
    foundServers = {}
end

local function addResultToUI(entry)
    table.insert(foundServers, entry)
    local idx = #foundServers - 1
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -12, 0, 70)
    frame.Position = UDim2.new(0, 6, 0, idx * 75)
    frame.BackgroundColor3 = Color3.fromRGB(40, 50, 70)
    frame.Parent = results
    addCorner(frame, 8)

    local nameL = Instance.new("TextLabel")
    nameL.Size = UDim2.new(1, -220, 0, 22)
    nameL.Position = UDim2.new(0, 10, 0, 8)
    nameL.BackgroundTransparency = 1
    nameL.Font = Enum.Font.GothamBold
    nameL.TextSize = 13
    nameL.TextColor3 = Color3.fromRGB(255,255,255)
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.Text = entry.name or "Brainrot SECRET"
    nameL.Parent = frame

    local genL = Instance.new("TextLabel")
    genL.Size = UDim2.new(1, -220, 0, 18)
    genL.Position = UDim2.new(0, 10, 0, 30)
    genL.BackgroundTransparency = 1
    genL.Font = Enum.Font.Gotham
    genL.TextSize = 12
    genL.TextColor3 = Color3.fromRGB(110,255,120)
    genL.Text = "💰 "..formatNumber(entry.generation) .. "/s"
    genL.Parent = frame

    local playersL = Instance.new("TextLabel")
    playersL.Size = UDim2.new(1, -220, 0, 16)
    playersL.Position = UDim2.new(0, 10, 0, 50)
    playersL.BackgroundTransparency = 1
    playersL.Font = Enum.Font.Gotham
    playersL.TextSize = 11
    playersL.TextColor3 = Color3.fromRGB(150,180,255)
    playersL.Text = "👥 " .. (entry.players or "0/??")
    playersL.Parent = frame

    local joinBtn = Instance.new("TextButton")
    joinBtn.Size = UDim2.new(0, 92, 0, 50)
    joinBtn.Position = UDim2.new(1, -106, 0, 10)
    joinBtn.BackgroundColor3 = Color3.fromRGB(50,150,250)
    joinBtn.Font = Enum.Font.GothamBold
    joinBtn.TextSize = 14
    joinBtn.Text = "ENTRAR"
    joinBtn.Parent = frame
    addCorner(joinBtn, 8)

    joinBtn.MouseButton1Click:Connect(function()
        joinBtn.Text = "⏳"
        joinBtn.BackgroundColor3 = Color3.fromRGB(100,100,100)
        local tries = 0; local success = false
        while tries < teleportRetryCount and not success do
            tries = tries + 1
            local ok,err = pcall(function() TeleportService:TeleportToPlaceInstance(PLACE_ID, tostring(entry.serverId), player) end)
            if ok then success = true; break end
            task.wait(teleportRetryDelay)
        end
        if not success then
            joinBtn.Text = "ENTRAR"; joinBtn.BackgroundColor3 = Color3.fromRGB(50,150,250)
            showNotification("❌ Falló el teleport a ese servidor", Color3.fromRGB(220,50,50))
        end
    end)

    results.CanvasSize = UDim2.new(0,0,0,#foundServers*75)
end

-- Scan current server for brainrots (robust patterns)
local function scanCurrentServerForBrainrots()
    statusLabel.Text = "🔍 Escaneando este servidor por Brainrots..."
    local found = {}
    for _,obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BillboardGui") then
            local hasSecret = false
            local genText = nil
            local nameText = nil
            for _,c in ipairs(obj:GetDescendants()) do
                if c:IsA("TextLabel") and type(c.Text) == "string" then
                    local txt = c.Text
                    local U = txt:upper()
                    if U:find("SECRET") then hasSecret = true end
                    -- match patterns like "$4M/s" or "4M/s" or "4M / s"
                    local m = txt:match("(%$?[%d%.]+%s*[KMBkmb]?%s*/%s*s)")
                    if not m then m = txt:match("(%$?[%d%.]+[KMBkmb]+/s)") end
                    if m then genText = m end
                    if (not txt:find("%$")) and (not U:find("SECRET")) and (not txt:find("/s")) and txt:len()>2 and txt:len()<40 then nameText = txt end
                end
            end
            if hasSecret and genText then
                local digits = genText:match("([%d%.]+)")
                local generation = 0
                if digits then
                    local num = tonumber(digits)
                    if genText:upper():find("B") then generation = num * 1e9
                    elseif genText:upper():find("M") then generation = num * 1e6
                    elseif genText:upper():find("K") then generation = num * 1e3 end
                end
                if generation >= MIN_GENERATION then
                    local playersCount = #Players:GetPlayers()
                    table.insert(found, {
                        serverId = tostring(game.JobId or "local"),
                        generation = generation,
                        genText = genText,
                        name = nameText or "Brainrot SECRET",
                        players = tostring(playersCount) .. "/" .. tostring(Players.MaxPlayers or 16)
                    })
                end
            end
        end
    end
    return found
end

-- Fetch servers pages from Roblox API (paginated)
local function fetchServersPage(cursor)
    local url = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Desc&limit=100"):format(tostring(PLACE_ID))
    if cursor and cursor ~= "" then url = url .. "&cursor=" .. tostring(cursor) end
    local data,err = safeHttpGet(url)
    if not data then return nil, err end
    return data, nil
end

local function getServersList(limit)
    limit = limit or MAX_SERVERS_TO_TRY
    local servers = {}
    local cursor = nil
    local total = 0
    repeat
        local data,err = fetchServersPage(cursor)
        if not data then break end
        if type(data.data) == "table" then
            for _,s in ipairs(data.data) do
                if s and s.id and tostring(s.id) ~= tostring(game.JobId) then
                    if (s.playing or 0) >= 1 then
                        table.insert(servers, s)
                        total = total + 1
                        if total >= limit then break end
                    end
                end
            end
        end
        cursor = data.nextPageCursor
        if not cursor or cursor == "" then break end
    until total >= limit
    return servers
end

-- Main exploration: server-by-server teleport until find brainrot in a server
local function startServerByServerExplore()
    if _G.HopperExploring then return end
    _G.HopperExploring = true
    exploreBtn.Visible = false; stopBtn.Visible = true
    statusLabel.Text = "🌐 Obteniendo lista de servidores..."
    task.wait(0.5)
    local servers = getServersList(MAX_SERVERS_TO_TRY)
    if not servers or #servers == 0 then statusLabel.Text = "❌ No se obtuvieron servidores."; _G.HopperExploring = false; exploreBtn.Visible = true; stopBtn.Visible = false; showNotification("❌ No se obtuvieron servidores públicos", Color3.fromRGB(200,100,50)); return end
    statusLabel.Text = "🔁 Teleportando secuencialmente buscando >= "..formatNumber(MIN_GENERATION).."/s"
    -- shuffle order
    local order = {}
    for i=1,#servers do order[i] = servers[i] end
    for i=#order,2,-1 do local j = math.random(1,i); order[i],order[j] = order[j],order[i] end

    -- scan current server first
    local localFound = scanCurrentServerForBrainrots()
    if #localFound > 0 then
        for _,v in ipairs(localFound) do addResultToUI(v) end
        statusLabel.Text = "🎉 Encontrado en este servidor! Revisa la lista."
        showNotification("🎉 Encontrado en este servidor: "..formatNumber(localFound[1].generation).."/s", Color3.fromRGB(50,200,100))
        _G.HopperExploring = false; exploreBtn.Visible = true; stopBtn.Visible = false
        return
    end

    for idx,s in ipairs(order) do
        if not _G.HopperExploring then break end
        statusLabel.Text = ("🔁 Teleportando a servidor %d/%d (id: %s)"):format(idx, #order, tostring(s.id))
        local ok = false
        for attempt=1,teleportRetryCount do
            local success,err = pcall(function() TeleportService:TeleportToPlaceInstance(PLACE_ID, tostring(s.id), player) end)
            if success then ok = true; break end
            task.wait(teleportRetryDelay)
        end
        if not ok then
            task.wait(0.2)
            continue
        end
        -- If teleport succeeded, script execution will jump to the new server; post-teleport logic below handles scanning.
        return
    end

    _G.HopperExploring = false; exploreBtn.Visible = true; stopBtn.Visible = false
    statusLabel.Text = "🔍 Exploración finalizada (no se encontraron resultados o no se pudo teleportar)."
    showNotification("🔍 Exploración finalizada.", Color3.fromRGB(200,200,80))
end

-- Post-teleport: if global flag is set, wait SCAN_WAIT and scan this server
if _G.HopperExploring then
    statusLabel.Text = "⏳ Exploración: cargando servidor... esperando "..tostring(SCAN_WAIT).."s"
    task.wait(SCAN_WAIT)
    local f = scanCurrentServerForBrainrots()
    if f and #f > 0 then
        for _,v in ipairs(f) do addResultToUI(v) end
        statusLabel.Text = "🎉 ¡Brainrot detectado en este servidor!"
        showNotification("🎉 ¡Brainrot detectado: "..formatNumber(f[1].generation).."/s!", Color3.fromRGB(50,200,100))
        _G.HopperExploring = false
        exploreBtn.Visible = true; stopBtn.Visible = false
    else
        statusLabel.Text = "🔎 No se detectó en este servidor. Presiona INICIAR EXPLORACIÓN para continuar."
        _G.HopperExploring = false
        exploreBtn.Visible = true; stopBtn.Visible = false
    end
end

-- UI interactions
btnClose.MouseButton1Click:Connect(function()
    if screenGui and screenGui.Parent then screenGui:Destroy() end
    _G.HopperExploring = false
end)

btnMin.MouseButton1Click:Connect(function()
    main.Visible = false
    -- show bubble (create if not exists)
    local bubble = screenGui:FindFirstChild("HopperBubble")
    if bubble then bubble.Visible = true; return end
    local bubbleFrame = Instance.new("Frame")
    bubbleFrame.Name = "HopperBubble"
    bubbleFrame.Size = UDim2.new(0, 68, 0, 68)
    bubbleFrame.Position = UDim2.new(1, -110, 0.7, -34)
    bubbleFrame.BackgroundColor3 = Color3.fromRGB(50,150,240)
    bubbleFrame.ZIndex = 9999
    bubbleFrame.Parent = screenGui
    addCorner(bubbleFrame, 34)

    local bubbleBtn = Instance.new("TextButton")
    bubbleBtn.Size = UDim2.new(1,0,1,0)
    bubbleBtn.BackgroundTransparency = 1
    bubbleBtn.Font = Enum.Font.GothamBold
    bubbleBtn.Text = "🤖"
    bubbleBtn.TextScaled = true
    bubbleBtn.TextColor3 = Color3.fromRGB(255,255,255)
    bubbleBtn.Parent = bubbleFrame

    makeDraggable(bubbleFrame, bubbleFrame)

    bubbleBtn.MouseButton1Click:Connect(function()
        bubbleFrame.Visible = false
        main.Visible = true
    end)
end)

scanBtn.MouseButton1Click:Connect(function()
    scanBtn.Text = "⏳ ESCANEANDO..."
    scanBtn.BackgroundColor3 = Color3.fromRGB(100,100,100)
    task.spawn(function()
        clearResultsUI()
        local found = scanCurrentServerForBrainrots()
        if found and #found > 0 then
            for _,v in ipairs(found) do addResultToUI(v) end
            statusLabel.Text = "🎉 Encontrado " .. tostring(#found) .. " brainrot(s) en este servidor."
            showNotification("🎉 Encontrado: "..formatNumber(found[1].generation).."/s", Color3.fromRGB(50,200,100))
        else
            statusLabel.Text = "🔎 No se detectaron brainrots en este servidor."
            showNotification("🔎 No se detectaron brainrots en este servidor.", Color3.fromRGB(200,200,80))
        end
        scanBtn.Text = "🔍 ESCANEAR SERVIDOR ACTUAL"
        scanBtn.BackgroundColor3 = Color3.fromRGB(50,150,250)
    end)
end)

exploreBtn.MouseButton1Click:Connect(function()
    exploreBtn.Visible = false; stopBtn.Visible = true
    task.spawn(startServerByServerExplore)
end)

stopBtn.MouseButton1Click:Connect(function()
    _G.HopperExploring = false
    exploreBtn.Visible = true; stopBtn.Visible = false
    statusLabel.Text = "⏸ Exploración detenida por usuario."
end)

-- Make main window draggable by topBar
makeDraggable(main, topBar)

-- Initial state
statusLabel.Text = "✅ Listo. Selecciona mínimo y usa ESCANEAR o INICIAR EXPLORACIÓN."
