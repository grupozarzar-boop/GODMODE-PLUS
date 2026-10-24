local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local CONFIG = {
    PanelName = "RaulsRivalsMovementPanel",
    PanelTitle = "RAULS RIVALS MODDED",

    MaxTargetDistance = 300,
    TargetOffsetY = 10,
    FixedTeleportRate = 144,
    TargetTeleportRate = 144,

    PanelWidth = 280,
    PanelHeight = 280,
    PanelMarginLeft = 15,
    PanelMarginTop = 15,

    Colors = {
        Background = Color3.fromRGB(20, 20, 24),
        Header = Color3.fromRGB(30, 30, 36),
        Text = Color3.fromRGB(255, 255, 255),
        Muted = Color3.fromRGB(170, 170, 170),
        Blue = Color3.fromRGB(45, 95, 180),
        Green = Color3.fromRGB(50, 150, 80),
        GreenActive = Color3.fromRGB(45, 160, 85),
        Red = Color3.fromRGB(180, 60, 60),
        Grey = Color3.fromRGB(80, 80, 85),
        Success = Color3.fromRGB(100, 255, 130),
        Error = Color3.fromRGB(255, 100, 100),
    },
}

local State = {
    SavedCFrame = nil,
    FixedTeleportEnabled = false,
    ClickSystemEnabled = false,
    MouseHeld = false,

    FixedAccumulator = 0,
    TargetAccumulator = 0,

    Character = nil,
    CharacterGeneration = 0,
    Destroyed = false,

    Connections = {},
    CharacterConnections = {},
    AllowedTargets = {},
}

local function disconnectConnection(connection)
    if connection and connection.Connected then
        connection:Disconnect()
    end
end

local function addConnection(connection)
    table.insert(State.Connections, connection)
    return connection
end

local function clearCharacterConnections()
    for _, connection in ipairs(State.CharacterConnections) do
        disconnectConnection(connection)
    end
    table.clear(State.CharacterConnections)
end

local function addCharacterConnection(connection)
    table.insert(State.CharacterConnections, connection)
    return connection
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getHumanoid(character)
    if not character then
        return nil
    end
    return character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(character)
    if not character then
        return nil
    end
    return character:FindFirstChild("HumanoidRootPart")
end

local function getLivingCharacterParts(character)
    local humanoid = getHumanoid(character)
    local root = getRoot(character)

    if not humanoid or humanoid.Health <= 0 or not root then
        return nil, nil
    end

    return humanoid, root
end

local TEAM_FIELD_NAMES = { "Team", "TeamName", "TeamId", "Faction", "Side", "Squad" }

local function normalizeTeamValue(value)
    if value == nil then
        return nil
    end
    if typeof(value) == "Instance" then
        if value:IsA("Team") then
            return "team:" .. value.Name:lower()
        end
        if value:IsA("ValueBase") then
            value = value.Value
        else
            return nil
        end
    end
    if typeof(value) == "BrickColor" then
        return "color:" .. value.Name:lower()
    end
    if typeof(value) == "Color3" then
        return string.format("color3:%.3f,%.3f,%.3f", value.R, value.G, value.B)
    end
    if typeof(value) == "string" then
        local cleaned = value:lower():gsub("%s+", "")
        if cleaned == "" or cleaned == "neutral" or cleaned == "none" then
            return nil
        end
        return "value:" .. cleaned
    end
    if typeof(value) == "number" then
        return "value:" .. tostring(value)
    end
    return nil
end

local function getTeamSignature(player, character)
    if not player then
        return nil
    end

    if player.Team ~= nil then
        return "team:" .. player.Team.Name:lower()
    end
    if player.Neutral == false then
        local nativeColor = normalizeTeamValue(player.TeamColor)
        if nativeColor then
            return nativeColor
        end
    end

    local containers = { player, character }
    for _, container in ipairs(containers) do
        if container then
            for _, fieldName in ipairs(TEAM_FIELD_NAMES) do
                local attr = container:GetAttribute(fieldName)
                local normalizedAttr = normalizeTeamValue(attr)
                if normalizedAttr then
                    return normalizedAttr
                end

                local child = container:FindFirstChild(fieldName)
                local normalizedChild = normalizeTeamValue(child)
                if normalizedChild then
                    return normalizedChild
                end
            end
        end
    end

    return nil
end

local function isTargetDamageable(character, targetPlayer)
    if not character or not targetPlayer then
        return false
    end

    local humanoid = getHumanoid(character)
    if not humanoid or humanoid.Health <= 0 or not getRoot(character) then
        return false
    end

    if character:FindFirstChildOfClass("ForceField") then
        return false
    end

    if character:GetAttribute("Invulnerable") == true
        or humanoid:GetAttribute("Invulnerable") == true
        or character:GetAttribute("CanTakeDamage") == false
        or humanoid:GetAttribute("CanTakeDamage") == false then
        return false
    end

    local myTeam = getTeamSignature(LocalPlayer, getCharacter())
    local targetTeam = getTeamSignature(targetPlayer, character)
    if myTeam ~= nil and targetTeam ~= nil and myTeam == targetTeam then
        return false
    end

    if character:GetAttribute("IsSpawnProtected") == true
        or character:GetAttribute("SpawnProtected") == true
        or humanoid:GetAttribute("SpawnProtected") == true then
        return false
    end

    return true
end

local function getClosestValidPlayer()
    local myCharacter = getCharacter()
    local _, myRoot = getLivingCharacterParts(myCharacter)
    if not myRoot then
        return nil, nil, nil
    end

    local closestPlayer = nil
    local closestCharacter = nil
    local closestRoot = nil
    local closestDistance = CONFIG.MaxTargetDistance

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and State.AllowedTargets[player.UserId] == true then
            local character = player.Character
            local _, targetRoot = getLivingCharacterParts(character)

            if targetRoot and isTargetDamageable(character, player) then
                local distance = (targetRoot.Position - myRoot.Position).Magnitude

                if distance <= closestDistance then
                    closestDistance = distance
                    closestPlayer = player
                    closestCharacter = character
                    closestRoot = targetRoot
                end
            end
        end
    end

    return closestPlayer, closestCharacter, closestRoot
end

local existingGui = PlayerGui:FindFirstChild(CONFIG.PanelName)
if existingGui then
    existingGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = CONFIG.PanelName
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 20
gui.Parent = PlayerGui

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(CONFIG.PanelWidth, CONFIG.PanelHeight)
main.Position = UDim2.new(0, CONFIG.PanelMarginLeft, 0, CONFIG.PanelMarginTop)
main.BackgroundColor3 = CONFIG.Colors.Background
main.BorderSizePixel = 0
main.Parent = gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 10)
mainCorner.Parent = main

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = CONFIG.Colors.Header
mainStroke.Thickness = 1
mainStroke.Parent = main

local function createLabel(name, text, size, position)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Size = size
    label.Position = position
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = CONFIG.Colors.Text
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextWrapped = true
    label.Parent = main
    return label
end

local function createButton(name, text, size, position, background)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Size = size
    button.Position = position
    button.BackgroundColor3 = background
    button.BorderSizePixel = 0
    button.Text = text
    button.TextColor3 = CONFIG.Colors.Text
    button.TextSize = 14
    button.Font = Enum.Font.GothamBold
    button.AutoButtonColor = true
    button.Active = true
    button.Parent = main

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 7)
    corner.Parent = button

    return button
end

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 42)
title.Position = UDim2.new(0, 0, 0, 0)
title.BackgroundColor3 = CONFIG.Colors.Header
title.BorderSizePixel = 0
title.Text = CONFIG.PanelTitle
title.TextColor3 = CONFIG.Colors.Text
title.TextSize = 17
title.Font = Enum.Font.GothamBold
title.Active = true
title.Parent = main

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 10)
titleCorner.Parent = title

local saveButton = createButton(
    "SavePosition",
    "FIJAR POSICIÓN XYZ",
    UDim2.new(1, -30, 0, 42),
    UDim2.new(0, 15, 0, 70),
    CONFIG.Colors.Blue
)

local teleportButton = createButton(
    "TeleportButton",
    "TELEPORT 144/s : OFF",
    UDim2.new(1, -30, 0, 42),
    UDim2.new(0, 15, 0, 120),
    CONFIG.Colors.Green
)

local clickButton = createButton(
    "ClickSystemButton",
    "J : SISTEMA CLIC OFF",
    UDim2.new(1, -30, 0, 35),
    UDim2.new(0, 15, 0, 169),
    CONFIG.Colors.Grey
)
clickButton.TextSize = 13

local status = createLabel(
    "Status",
    "POSICIÓN: NO FIJADA",
    UDim2.new(1, -20, 0, 25),
    UDim2.new(0, 10, 0, 207)
)
status.Font = Enum.Font.GothamBold
status.TextColor3 = CONFIG.Colors.Error

local listButton = createButton(
    "PlayerListToggle",
    "Lista  v",
    UDim2.new(1, -30, 0, 34),
    UDim2.new(0, 15, 0, 236),
    CONFIG.Colors.Grey
)

local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "PlayerList"
listFrame.Position = UDim2.new(0, 15, 0, 278)
listFrame.Size = UDim2.new(1, -30, 0, 190)
listFrame.BackgroundColor3 = CONFIG.Colors.Header
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 5
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.Visible = false
listFrame.Parent = main

local listCorner = Instance.new("UICorner")
listCorner.CornerRadius = UDim.new(0, 10)
listCorner.Parent = listFrame

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 6)
listPadding.PaddingBottom = UDim.new(0, 6)
listPadding.PaddingLeft = UDim.new(0, 6)
listPadding.PaddingRight = UDim.new(0, 6)
listPadding.Parent = listFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.SortOrder = Enum.SortOrder.Name
listLayout.Parent = listFrame

local playerRows = {}

local function updatePlayerRow(player)
    local entry = playerRows[player]
    if not entry then
        return
    end
    local allowed = State.AllowedTargets[player.UserId] == true
    entry.State.Text = allowed and "✓" or "X"
    entry.State.TextColor3 = allowed and CONFIG.Colors.Success or CONFIG.Colors.Error
    entry.State.BackgroundColor3 = allowed and Color3.fromRGB(35, 80, 48) or Color3.fromRGB(85, 38, 38)
end

local function addPlayerRow(player)
    if player == LocalPlayer or playerRows[player] then
        return
    end
    if State.AllowedTargets[player.UserId] == nil then
        State.AllowedTargets[player.UserId] = false
    end

    local row = Instance.new("Frame")
    row.Name = string.format("Player_%d", player.UserId)
    row.Size = UDim2.new(1, -2, 0, 48)
    row.BackgroundColor3 = CONFIG.Colors.Background
    row.BorderSizePixel = 0
    row.Parent = listFrame

    local rowCorner = Instance.new("UICorner")
    rowCorner.CornerRadius = UDim.new(0, 7)
    rowCorner.Parent = row

    local displayName = Instance.new("TextLabel")
    displayName.Name = "DisplayName"
    displayName.Position = UDim2.new(0, 9, 0, 5)
    displayName.Size = UDim2.new(1, -58, 0, 21)
    displayName.BackgroundTransparency = 1
    displayName.Text = player.DisplayName
    displayName.TextColor3 = CONFIG.Colors.Text
    displayName.TextSize = 13
    displayName.Font = Enum.Font.GothamSemibold
    displayName.TextXAlignment = Enum.TextXAlignment.Left
    displayName.TextTruncate = Enum.TextTruncate.AtEnd
    displayName.Parent = row

    local username = Instance.new("TextLabel")
    username.Name = "Username"
    username.Position = UDim2.new(0, 9, 0, 25)
    username.Size = UDim2.new(1, -58, 0, 16)
    username.BackgroundTransparency = 1
    username.Text = "@" .. player.Name
    username.TextColor3 = CONFIG.Colors.Muted
    username.TextSize = 10
    username.Font = Enum.Font.Gotham
    username.TextXAlignment = Enum.TextXAlignment.Left
    username.TextTruncate = Enum.TextTruncate.AtEnd
    username.Parent = row

    local stateButton = Instance.new("TextButton")
    stateButton.Name = "AllowedToggle"
    stateButton.AnchorPoint = Vector2.new(1, 0.5)
    stateButton.Position = UDim2.new(1, -7, 0.5, 0)
    stateButton.Size = UDim2.fromOffset(32, 32)
    stateButton.BackgroundColor3 = CONFIG.Colors.Red
    stateButton.BorderSizePixel = 0
    stateButton.Text = "X"
    stateButton.TextColor3 = CONFIG.Colors.Error
    stateButton.TextSize = 19
    stateButton.Font = Enum.Font.GothamBold
    stateButton.Parent = row

    local stateCorner = Instance.new("UICorner")
    stateCorner.CornerRadius = UDim.new(1, 0)
    stateCorner.Parent = stateButton

    playerRows[player] = {Frame = row, State = stateButton}
    stateButton.Activated:Connect(function()
        State.AllowedTargets[player.UserId] = not (State.AllowedTargets[player.UserId] == true)
        updatePlayerRow(player)
    end)
    updatePlayerRow(player)
end

local function removePlayerRow(player)
    local entry = playerRows[player]
    if entry then
        entry.Frame:Destroy()
        playerRows[player] = nil
    end
    State.AllowedTargets[player.UserId] = nil
end

local function setListExpanded(expanded)
    listFrame.Visible = expanded
    listButton.Text = expanded and "Lista  ^" or "Lista  v"
    main.Size = UDim2.fromOffset(CONFIG.PanelWidth, expanded and 485 or CONFIG.PanelHeight)
end

listButton.Activated:Connect(function()
    setListExpanded(not listFrame.Visible)
end)

for _, player in ipairs(Players:GetPlayers()) do
    addPlayerRow(player)
end
addConnection(Players.PlayerAdded:Connect(addPlayerRow))
addConnection(Players.PlayerRemoving:Connect(removePlayerRow))

local function setStatus(message, color)
    if State.Destroyed or not status.Parent then
        return
    end
    status.Text = message
    status.TextColor3 = color or CONFIG.Colors.Muted
end

local function updateFixedButton()
    if State.FixedTeleportEnabled then
        teleportButton.Text = "TELEPORT 144/s : ON"
        teleportButton.BackgroundColor3 = CONFIG.Colors.Red
    else
        teleportButton.Text = "TELEPORT 144/s : OFF"
        teleportButton.BackgroundColor3 = CONFIG.Colors.Green
    end
end

local function updateClickButton()
    if State.ClickSystemEnabled then
        clickButton.Text = "J : SISTEMA CLIC ON"
        clickButton.BackgroundColor3 = CONFIG.Colors.GreenActive
    else
        clickButton.Text = "J : SISTEMA CLIC OFF"
        clickButton.BackgroundColor3 = CONFIG.Colors.Grey
    end
end

local function saveCurrentPosition()
    local character = getCharacter()
    local _, root = getLivingCharacterParts(character)

    if not root then
        setStatus("PERSONAJE NO DISPONIBLE", CONFIG.Colors.Error)
        return
    end

    State.SavedCFrame = root.CFrame
    setStatus("POSICIÓN XYZ: FIJADA ✓", CONFIG.Colors.Success)

    local previousText = saveButton.Text
    saveButton.Text = "POSICIÓN FIJADA ✓"

    task.delay(1.2, function()
        if not State.Destroyed and saveButton.Parent then
            saveButton.Text = previousText
        end
    end)
end

saveButton.Activated:Connect(saveCurrentPosition)

local function toggleFixedTeleport()
    State.FixedTeleportEnabled = not State.FixedTeleportEnabled
    State.FixedAccumulator = 0

    if State.FixedTeleportEnabled then
        if not State.SavedCFrame then
            State.FixedTeleportEnabled = false
            updateFixedButton()
            setStatus("GUARDA XYZ PRIMERO", CONFIG.Colors.Error)
            return
        end

        State.MouseHeld = false
        updateFixedButton()
        setStatus("TELEPORT FIJO ACTIVADO", CONFIG.Colors.Success)
    else
        updateFixedButton()
        setStatus(State.SavedCFrame and "POSICIÓN: FIJADA ✓" or "POSICIÓN: NO FIJADA",
            State.SavedCFrame and CONFIG.Colors.Success or CONFIG.Colors.Error)
    end
end

teleportButton.Activated:Connect(toggleFixedTeleport)

local function toggleClickSystem()
    State.ClickSystemEnabled = not State.ClickSystemEnabled

    if not State.ClickSystemEnabled then
        State.MouseHeld = false
        State.TargetAccumulator = 0
        updateClickButton()
        setStatus("SISTEMA J DESACTIVADO", CONFIG.Colors.Muted)
        return
    end

    State.FixedTeleportEnabled = false
    State.FixedAccumulator = 0
    updateFixedButton()
    updateClickButton()
    setStatus("SISTEMA J ACTIVO: MANTÉN CLIC IZQUIERDO", CONFIG.Colors.Success)
end

clickButton.Activated:Connect(toggleClickSystem)

addConnection(UserInputService.InputBegan:Connect(function(input, processed)
    if State.Destroyed then
        return
    end

    if input.KeyCode == Enum.KeyCode.LeftControl then
        main.Visible = not main.Visible
        return
    end

    if processed then
        return
    end

    if input.KeyCode == Enum.KeyCode.J then
        toggleClickSystem()
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if not State.ClickSystemEnabled then
            State.MouseHeld = false
            State.TargetAccumulator = 0
            return
        end

        State.MouseHeld = true
        State.TargetAccumulator = 0
    end
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
    if State.Destroyed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        return
    end

    local wasFollowing = State.MouseHeld and State.ClickSystemEnabled
    State.MouseHeld = false
    State.TargetAccumulator = 0

    if wasFollowing and State.SavedCFrame then
        local character = getCharacter()
        local _, root = getLivingCharacterParts(character)
        if root then
            root.CFrame = State.SavedCFrame
        end
    end
end))

local dragging = false
local dragStart = nil
local startPosition = nil
local activeDragInput = nil

local function isPointerInput(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

title.InputBegan:Connect(function(input)
    if not isPointerInput(input) then
        return
    end

    dragging = true
    dragStart = input.Position
    startPosition = main.Position
    activeDragInput = input
end)

addConnection(UserInputService.InputChanged:Connect(function(input)
    if State.Destroyed or not dragging or not dragStart or not startPosition then
        return
    end

    local isMouseMove = input.UserInputType == Enum.UserInputType.MouseMovement
    local isMatchingTouch = input.UserInputType == Enum.UserInputType.Touch
        and activeDragInput == input

    if not isMouseMove and not isMatchingTouch then
        return
    end

    local delta = input.Position - dragStart
    main.Position = UDim2.new(
        startPosition.X.Scale,
        startPosition.X.Offset + delta.X,
        startPosition.Y.Scale,
        startPosition.Y.Offset + delta.Y
    )
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
    if isPointerInput(input) then
        dragging = false
        dragStart = nil
        startPosition = nil
        activeDragInput = nil
    end
end))

local function teleportToSavedPosition(root)
    if not State.SavedCFrame then
        State.FixedTeleportEnabled = false
        updateFixedButton()
        setStatus("GUARDA XYZ PRIMERO", CONFIG.Colors.Error)
        return false
    end

    root.CFrame = State.SavedCFrame
    return true
end

local function teleportAboveTarget(root, targetRoot)
    local destination = targetRoot.Position + Vector3.new(0, CONFIG.TargetOffsetY, 0)
    root.CFrame = CFrame.lookAt(destination, targetRoot.Position)
end

addConnection(RunService.Heartbeat:Connect(function(deltaTime)
    if State.Destroyed then
        return
    end

    local character = getCharacter()
    local humanoid, root = getLivingCharacterParts(character)

    if not humanoid or not root then
        return
    end

    if State.ClickSystemEnabled and State.MouseHeld then
        State.TargetAccumulator += deltaTime
        local interval = 1 / CONFIG.TargetTeleportRate
        local iterations = 0

        while State.TargetAccumulator >= interval and iterations < 4 do
            State.TargetAccumulator -= interval
            iterations += 1

            local _, _, targetRoot = getClosestValidPlayer()
            if targetRoot and targetRoot.Parent then
                teleportAboveTarget(root, targetRoot)
                setStatus("SIGUIENDO OBJETIVO VÁLIDO", CONFIG.Colors.Success)
            else
                setStatus("SIN OBJETIVOS VÁLIDOS", CONFIG.Colors.Error)
            end
        end

        if iterations == 4 and State.TargetAccumulator >= interval then
            State.TargetAccumulator = 0
        end
        return
    end

    if State.FixedTeleportEnabled then
        State.FixedAccumulator += deltaTime
        local interval = 1 / CONFIG.FixedTeleportRate
        local iterations = 0

        while State.FixedAccumulator >= interval and iterations < 4 do
            State.FixedAccumulator -= interval
            iterations += 1

            if not teleportToSavedPosition(root) then
                break
            end
        end

        if iterations == 4 and State.FixedAccumulator >= interval then
            State.FixedAccumulator = 0
        end
    else
        State.FixedAccumulator = 0
    end
end))

local function onCharacterAdded(character)
    State.CharacterGeneration += 1
    local generation = State.CharacterGeneration
    State.Character = character
    State.FixedAccumulator = 0
    State.TargetAccumulator = 0
    State.MouseHeld = false

    clearCharacterConnections()

    task.spawn(function()
        local humanoid = character:WaitForChild("Humanoid", 10)
        local root = character:WaitForChild("HumanoidRootPart", 10)

        if State.Destroyed or generation ~= State.CharacterGeneration then
            return
        end

        if not humanoid or not root then
            setStatus("ESPERANDO PERSONAJE VÁLIDO", CONFIG.Colors.Error)
            return
        end

        if State.FixedTeleportEnabled then
            setStatus("TP XYZ: REANUDANDO", CONFIG.Colors.Success)
        elseif State.ClickSystemEnabled then
            setStatus("SISTEMA J ACTIVO: MANTÉN CLIC IZQUIERDO", CONFIG.Colors.Success)
        end

        addCharacterConnection(humanoid.Died:Connect(function()
            State.MouseHeld = false
            State.FixedAccumulator = 0
            State.TargetAccumulator = 0
        end))
    end)
end

addConnection(LocalPlayer.CharacterAdded:Connect(onCharacterAdded))

if LocalPlayer.Character then
    onCharacterAdded(LocalPlayer.Character)
end

local function destroyModule()
    if State.Destroyed then
        return
    end

    State.Destroyed = true
    State.FixedTeleportEnabled = false
    State.ClickSystemEnabled = false
    State.MouseHeld = false

    clearCharacterConnections()

    for _, connection in ipairs(State.Connections) do
        disconnectConnection(connection)
    end
    table.clear(State.Connections)

    if gui and gui.Parent then
        gui:Destroy()
    end
end

script.Destroying:Connect(destroyModule)

updateFixedButton()
updateClickButton()
if State.SavedCFrame then
    setStatus("POSICIÓN: FIJADA ✓", CONFIG.Colors.Success)
else
    setStatus("POSICIÓN: NO FIJADA", CONFIG.Colors.Error)
end

print("[ORION TP] Module initialized successfully.")
