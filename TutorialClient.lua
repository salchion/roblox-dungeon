-- TutorialClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: TutorialClient)
-- 튜토리얼 미션 표시: 상단 목표 바 + 목표 위치의 빛기둥/거리 표지 (처음 1~5분 가이드).
-- 미션 진행은 서버(TutorialService)가 관리하고, 여기서는 받아서 보여주기만 한다.
-- (PlayerClient 가 지역 변수 한도에 가까워서 별도 스크립트로 분리했다)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function create(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function rounded(instance, radius)
	create("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, instance)
end

local function label(props, parent)
	local base = {
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextColor3 = Color3.new(1, 1, 1),
		TextSize = 15, TextStrokeTransparency = 0.5,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	return create("TextLabel", base, parent)
end

local objective = create("Frame", {
	Size = UDim2.new(0, 540, 0, 70), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
	BackgroundColor3 = Color3.fromRGB(20, 20, 30), BackgroundTransparency = 0.2, BorderSizePixel = 0, Visible = false,
}, gui)
rounded(objective)
local stroke = create("UIStroke", { Color = Color3.fromRGB(255, 210, 90), Thickness = 2 }, objective)
local titleLabel = label({
	Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 10, 0, 6), TextSize = 17, Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left, RichText = true,
}, objective)
local barBack = create("Frame", {
	Size = UDim2.new(1, -20, 0, 14), Position = UDim2.new(0, 10, 0, 40), BackgroundColor3 = Color3.fromRGB(45, 45, 65), BorderSizePixel = 0,
}, objective)
rounded(barBack)
local barFill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 210, 90), BorderSizePixel = 0 }, barBack)
rounded(barFill)
local barText = label({ Size = UDim2.new(1, 0, 1, 0), TextSize = 11, Font = Enum.Font.GothamBold }, barBack)

local waypoint = nil    -- 던전 안에서 다음 방을 가리키는 빛기둥 (하늘색)
local waypointLabel = nil
local current = nil     -- 지금 미션 정보
local beacon = nil      -- 목표 위치의 빛기둥 Part
local beaconLabel = nil

local function clearBeacon()
	if beacon then
		beacon:Destroy()
		beacon = nil
		beaconLabel = nil
	end
end

local function placeBeacon(position, name)
	clearBeacon()
	if not position then return end
	beacon = Instance.new("Part")
	beacon.Name = "TutorialBeacon"
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CanTouch = false
	beacon.Material = Enum.Material.Neon
	beacon.Color = Color3.fromRGB(255, 220, 90)
	beacon.Transparency = 0.55
	beacon.Size = Vector3.new(3, 140, 3)
	beacon.Position = position + Vector3.new(0, 60, 0)
	beacon.Parent = workspace

	local billboard = create("BillboardGui", {
		Size = UDim2.new(0, 220, 0, 50), StudsOffset = Vector3.new(0, -50, 0), AlwaysOnTop = true, MaxDistance = 100000,
	}, beacon)
	beaconLabel = label({
		Size = UDim2.new(1, 0, 1, 0), TextSize = 20, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0,
		TextColor3 = Color3.fromRGB(255, 230, 120), Text = "▼ " .. (name or "목표"),
	}, billboard)
end

local function refresh()
	if not current then
		objective.Visible = false
		return
	end
	titleLabel.Text = string.format("<font color='#ffd966'>미션 %d/%d</font>  %s", current.Index, current.Total, current.Text)
	local ratio = math.clamp(current.Progress / current.Goal, 0, 1)
	TweenService:Create(barFill, TweenInfo.new(0.25), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
	barText.Text = string.format("%d / %d", current.Progress, current.Goal)
	objective.Visible = true
end

local function clearWaypoint()
	if waypoint then
		waypoint:Destroy()
		waypoint = nil
		waypointLabel = nil
	end
end

local function placeWaypoint(position, name)
	clearWaypoint()
	waypoint = Instance.new("Part")
	waypoint.Name = "RoomWaypoint"
	waypoint.Anchored = true
	waypoint.CanCollide = false
	waypoint.CanQuery = false
	waypoint.CanTouch = false
	waypoint.Material = Enum.Material.Neon
	waypoint.Color = Color3.fromRGB(110, 210, 255)
	waypoint.Transparency = 0.5
	waypoint.Size = Vector3.new(3, 160, 3)
	waypoint.Position = position + Vector3.new(0, 70, 0)
	waypoint.Parent = workspace
	local billboard = create("BillboardGui", {
		Size = UDim2.new(0, 240, 0, 50), StudsOffset = Vector3.new(0, -60, 0), AlwaysOnTop = true, MaxDistance = 100000,
	}, waypoint)
	waypointLabel = label({
		Size = UDim2.new(1, 0, 1, 0), TextSize = 20, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0,
		TextColor3 = Color3.fromRGB(150, 225, 255), Text = "▼ " .. (name or "다음 방"),
	}, billboard)
end

Remotes.Tutorial.OnClientEvent:Connect(function(action, data)
	if action == "Waypoint" then
		placeWaypoint(data.Pos, data.Name)
		return
	elseif action == "WaypointClear" then
		clearWaypoint()
		return
	end
	if action == "Step" then
		local newStep = current == nil or current.Index ~= data.Index
		current = data
		if newStep then
			placeBeacon(data.Target, data.TargetName)
			stroke.Color = Color3.fromRGB(120, 255, 150)
			TweenService:Create(stroke, TweenInfo.new(0.8), { Color = Color3.fromRGB(255, 210, 90) }):Play()
		end
		refresh()
	else
		current = nil
		clearBeacon()
		refresh()
	end
end)

RunService.RenderStepped:Connect(function()
	if waypoint and waypointLabel then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local flat = Vector3.new(root.Position.X - waypoint.Position.X, 0, root.Position.Z - waypoint.Position.Z).Magnitude
			waypointLabel.Text = string.format("▼ 다음 방  %dm", math.floor(flat + 0.5))
			waypoint.Transparency = flat < 30 and 0.85 or 0.5
		end
	end
	-- 던전 안에서는 던전 UI 와 겹치지 않게 숨긴다
	objective.Visible = current ~= nil and player:GetAttribute("Zone") ~= "Dungeon"
	if beacon and beaconLabel and current then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local flat = Vector3.new(root.Position.X - beacon.Position.X, 0, root.Position.Z - beacon.Position.Z).Magnitude
			beaconLabel.Text = string.format("▼ %s  %dm", current.TargetName or "목표", math.floor(flat + 0.5))
			beacon.Transparency = flat < 40 and 0.85 or 0.55 -- 가까워지면 얇게 (시야 방해 방지)
		end
	end
end)
