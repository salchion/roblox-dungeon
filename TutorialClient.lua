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
	beacon.Transparency = 0.35
	beacon.Size = Vector3.new(6, 200, 6)
	beacon.Position = position + Vector3.new(0, 90, 0)
	beacon.Parent = workspace

	local billboard = create("BillboardGui", {
		Size = UDim2.new(0, 220, 0, 50), StudsOffset = Vector3.new(0, -85, 0), AlwaysOnTop = true, MaxDistance = 100000,
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
			beacon.Transparency = flat < 40 and 0.85 or 0.35 -- 가까워지면 투명하게 (시야 방해 방지)
		end
	end
end)

-- 화면이 작을 때(Studio에서 창이 끼어 있을 때 등) UI 전체를 자동으로 줄여서 잘리지 않게 한다
do
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(viewport.X / 1100, viewport.Y / 720), 0.55, 1)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

-- 화면 가장자리 화살표: 목표가 화면 밖에 있으면 그쪽을 가리키는 화살표 + 이름 + 거리를 보여준다
-- (빛기둥이 멀리 있어서 안 보일 때도 어디로 가야 하는지 알 수 있게)
do
	local camera = workspace.CurrentCamera
	local function makeArrow(color)
		local frame = create("Frame", {
			Size = UDim2.new(0, 120, 0, 70), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false, ZIndex = 50,
		}, gui)
		local arrow = label({
			Size = UDim2.new(0, 56, 0, 56), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
			Text = "➤", TextSize = 54, Font = Enum.Font.GothamBlack, TextColor3 = color, TextStrokeTransparency = 0, ZIndex = 50,
		}, frame)
		local text = label({
			Size = UDim2.new(1, 0, 0, 20), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52),
			Text = "", TextSize = 16, Font = Enum.Font.GothamBold, TextColor3 = color, TextStrokeTransparency = 0, ZIndex = 50,
		}, frame)
		return frame, arrow, text
	end
	local goalFrame, goalArrow, goalText = makeArrow(Color3.fromRGB(255, 225, 90))
	local wayFrame, wayArrow, wayText = makeArrow(Color3.fromRGB(130, 220, 255))

	local function point(frame, arrow, text, worldPosition, name)
		local viewport = camera.ViewportSize
		local uiScale = gui:FindFirstChildOfClass("UIScale")
		local k = uiScale and uiScale.Scale or 1 -- UI 자동 축소(UIScale) 때문에 화면 픽셀 좌표를 나눠서 맞춘다
		local screen, onScreen = camera:WorldToViewportPoint(worldPosition)
		local center = viewport / 2
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local distance = root and math.floor((root.Position - worldPosition).Magnitude + 0.5) or 0
		text.Text = string.format("%s  %dm", name or "목표", distance)
		-- 카메라 뒤쪽이면 방향이 뒤집히므로 보정
		local direction = Vector2.new(screen.X, screen.Y) - center
		if screen.Z < 0 then
			direction = -direction
		end
		if onScreen and screen.Z > 0 and math.abs(direction.X) < viewport.X * 0.42 and math.abs(direction.Y) < viewport.Y * 0.38 then
			-- 화면 안에 보이면 목표 바로 위에 아래쪽 화살표
			frame.Position = UDim2.fromOffset(screen.X / k, math.max(60, screen.Y - 90) / k)
			arrow.Rotation = 90
		else
			if direction.Magnitude < 1 then
				direction = Vector2.new(0, -1)
			end
			local unit = direction.Unit
			local margin = 80
			local scaleX = (viewport.X / 2 - margin) / math.max(math.abs(unit.X), 0.001)
			local scaleY = (viewport.Y / 2 - margin) / math.max(math.abs(unit.Y), 0.001)
			local edge = center + unit * math.min(scaleX, scaleY)
			frame.Position = UDim2.fromOffset(edge.X / k, edge.Y / k)
			arrow.Rotation = math.deg(math.atan2(unit.Y, unit.X))
		end
		frame.Visible = true
	end

	RunService.RenderStepped:Connect(function()
		local inDungeon = player:GetAttribute("Zone") == "Dungeon"
		if current and current.Target and not inDungeon then
			point(goalFrame, goalArrow, goalText, current.Target, current.TargetName)
		else
			goalFrame.Visible = false
		end
		if waypoint then
			point(wayFrame, wayArrow, wayText, waypoint.Position - Vector3.new(0, 70, 0), "다음 구역")
		else
			wayFrame.Visible = false
		end
	end)
end
