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
gui.DisplayOrder = 60 -- 강화창 / 메뉴 같은 창 위에 떠서 미션 안내가 가려지지 않게
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

-- 새 미션이 시작되면 화면 중앙에 큼직한 카드로 먼저 보여준다 (상단 바는 눈에 잘 안 띄어서)
local lastPopupIndex = 0
local activeCard = nil
local activeWhere = nil -- 새 미션 카드 안의 "목표가 어느 쪽에 있는지" 줄 (매 프레임 갱신)
local function popupMission()
	if activeCard then activeCard:Destroy() end -- 이전 카드가 남아 글자가 겹치지 않게
	local card = create("Frame", {
		Size = UDim2.new(0, 520, 0, 150), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.22, 0),
		BackgroundColor3 = Color3.fromRGB(16, 18, 30), BackgroundTransparency = 0.02, BorderSizePixel = 0, ZIndex = 30,
	}, gui)
	activeCard = card
	rounded(card, 18)
	local cardStroke = create("UIStroke", { Color = Color3.fromRGB(255, 225, 110), Thickness = 4 }, card)
	label({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 10), TextSize = 26, Font = Enum.Font.GothamBlack, RichText = true, ZIndex = 31,
		Text = string.format("<font color='#ffd966'>🎯 미션 %d/%d</font>", current.Index, current.Total) }, card)
	label({ Size = UDim2.new(1, -40, 0, 56), Position = UDim2.new(0, 20, 0, 50), TextSize = 22, Font = Enum.Font.GothamBold, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 31,
		Text = current.Text }, card)
	activeWhere = label({ Size = UDim2.new(1, -40, 0, 26), Position = UDim2.new(0, 20, 1, -34), TextSize = 20, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(130, 255, 160), ZIndex = 31,
		Text = current.TargetName and ("📍 " .. current.TargetName) or "" }, card)
	card.Size = UDim2.new(0, 400, 0, 110)
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 520, 0, 150) }):Play()
	TweenService:Create(cardStroke, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 8 }):Play()
	task.delay(4.5, function()
		TweenService:Create(card, TweenInfo.new(0.4), { Position = UDim2.new(0.5, 0, 0, 45), Size = UDim2.new(0, 300, 0, 60), BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		card:Destroy()
		if activeCard == card then activeCard = nil end
	end)
end

local function refresh()
	if current and current.Index ~= lastPopupIndex then
		lastPopupIndex = current.Index
		popupMission()
	end
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
	waypoint.Size = Vector3.new(1.4, 70, 1.4)
	waypoint.Transparency = 0.6
	waypoint.Position = position + Vector3.new(0, 35, 0)
	waypoint.Parent = workspace
	local billboard = create("BillboardGui", {
		Size = UDim2.new(0, 240, 0, 50), StudsOffset = Vector3.new(0, -26, 0), AlwaysOnTop = true, MaxDistance = 100000,
	}, waypoint)
	waypointLabel = label({
		Size = UDim2.new(1, 0, 1, 0), TextSize = 20, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0,
		TextColor3 = Color3.fromRGB(150, 225, 255), Text = "▼ " .. (name or "다음 방"),
	}, billboard)
end

-- 영화 같은 연출 (최후의 군주): 위아래 검은 띠 + 색 바랜 화면 + 줌 -> 하얀 섬광 -> 암전 + 자막 -> (마을에서) 서서히 밝아짐
local Lighting = game:GetService("Lighting")
local cinema = {}
do
	local function bar(position)
		local frame = create("Frame", { Size = UDim2.new(1, 0, 0, 0), Position = position, AnchorPoint = Vector2.new(0, position.Y.Scale), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 90 }, gui)
		return frame
	end
	cinema.Top = bar(UDim2.new(0, 0, 0, 0))
	cinema.Bottom = bar(UDim2.new(0, 0, 1, 0))
	cinema.Flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 95 }, gui)
	cinema.Black = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 96 }, gui)
	cinema.Text = label({ Size = UDim2.new(1, 0, 0, 80), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), TextSize = 44, Font = Enum.Font.GothamBlack,
		TextTransparency = 1, TextStrokeTransparency = 1, ZIndex = 97, Text = "…………" }, gui)
	cinema.Color = Instance.new("ColorCorrectionEffect")
	cinema.Color.Enabled = false
	cinema.Color.Parent = Lighting
end
local function cinemaPlay(phase)
	local camera = workspace.CurrentCamera
	if phase == "Start" then
		TweenService:Create(cinema.Top, TweenInfo.new(0.8), { Size = UDim2.new(1, 0, 0.13, 0) }):Play()
		TweenService:Create(cinema.Bottom, TweenInfo.new(0.8), { Size = UDim2.new(1, 0, 0.13, 0) }):Play()
		cinema.Color.Enabled = true
		TweenService:Create(cinema.Color, TweenInfo.new(2.2), { Saturation = -0.75, Contrast = 0.35, Brightness = -0.08, TintColor = Color3.fromRGB(255, 200, 200) }):Play()
		if camera then TweenService:Create(camera, TweenInfo.new(2.6, Enum.EasingStyle.Quad), { FieldOfView = 48 }):Play() end
	elseif phase == "Blast" then
		cinema.Flash.BackgroundTransparency = 0
		TweenService:Create(cinema.Flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
		if camera then TweenService:Create(camera, TweenInfo.new(0.35), { FieldOfView = 32 }):Play() end
		TweenService:Create(cinema.Color, TweenInfo.new(0.3), { Saturation = -1, Contrast = 0.6 }):Play()
	elseif phase == "Black" then
		TweenService:Create(cinema.Black, TweenInfo.new(0.5), { BackgroundTransparency = 0 }):Play()
		TweenService:Create(cinema.Text, TweenInfo.new(0.6), { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()
	elseif phase == "End" then
		cinema.Black.BackgroundTransparency = 0
		TweenService:Create(cinema.Black, TweenInfo.new(1.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(cinema.Text, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(cinema.Top, TweenInfo.new(0.8), { Size = UDim2.new(1, 0, 0, 0) }):Play()
		TweenService:Create(cinema.Bottom, TweenInfo.new(0.8), { Size = UDim2.new(1, 0, 0, 0) }):Play()
		TweenService:Create(cinema.Color, TweenInfo.new(0.8), { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
		if camera then camera.FieldOfView = 70 end
		task.delay(1, function() cinema.Color.Enabled = false end)
	end
end

-- 스포트라이트 튜토리얼: 화면 전체를 어둡게 하고 눌러야 할 버튼만 밝게 뚫어서 거기로만 유도한다 (다른 곳은 눌러도 반응 없음)
--   "메뉴를 열어라" 미션: 메뉴 버튼 -> (메뉴가 열리면) 성장 탭 -> 훈련 시작 버튼 순서로 하나씩 가리킨다
local highlightToken = 0
local spot = {}
do
	local function dim(name)
		-- 클릭을 막지 않는다 (위치가 조금 어긋나도 게임 조작이 막히지 않게): 눈으로만 유도
		return create("Frame", { Name = name, Active = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
			BorderSizePixel = 0, ZIndex = 80, Visible = false }, gui)
	end
	spot.Top, spot.Bottom, spot.Left, spot.Right = dim("SpotTop"), dim("SpotBottom"), dim("SpotLeft"), dim("SpotRight")
	spot.Ring = create("Frame", { Name = "SpotRing", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 81, Visible = false }, gui)
	create("UICorner", { CornerRadius = UDim.new(0, 12) }, spot.Ring)
	local ringStroke = create("UIStroke", { Color = Color3.fromRGB(255, 225, 80), Thickness = 4 }, spot.Ring)
	TweenService:Create(ringStroke, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 10 }):Play()
	spot.Arrow = label({ Name = "SpotArrow", Size = UDim2.new(0, 260, 0, 40), BackgroundColor3 = Color3.fromRGB(255, 225, 80), BackgroundTransparency = 0,
		TextSize = 20, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(40, 28, 0), TextStrokeTransparency = 1, ZIndex = 82, Visible = false, Text = "" }, gui)
	create("UICorner", { CornerRadius = UDim.new(0, 10) }, spot.Arrow)
end
local function spotHide()
	for key, part in pairs(spot) do
		if key ~= "Corr" then part.Visible = false end
	end
end
local function spotShow(target, text)
	local scale = (gui:FindFirstChildOfClass("UIScale") and gui:FindFirstChildOfClass("UIScale").Scale) or 1
	local pad = 8
	-- 화면 좌표가 UI 마다 조금씩 어긋나는 경우(상단 바 / 스케일)를 위해 실제로 놓인 고리 위치를 보고 보정한다
	spot.Corr = spot.Corr or Vector2.zero
	if spot.Ring.Visible then
		local error = (target.AbsolutePosition - Vector2.new(pad, pad)) - spot.Ring.AbsolutePosition
		if error.Magnitude > 1 and error.Magnitude < 400 then
			spot.Corr += error / scale
		end
	end
	local position = target.AbsolutePosition / scale - Vector2.new(pad, pad) + spot.Corr
	local size = target.AbsoluteSize / scale + Vector2.new(pad * 2, pad * 2)
	local x0, y0, x1, y1 = position.X, position.Y, position.X + size.X, position.Y + size.Y
	spot.Top.Position, spot.Top.Size = UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, y0)
	spot.Bottom.Position, spot.Bottom.Size = UDim2.new(0, 0, 0, y1), UDim2.new(1, 0, 1, -y1)
	spot.Left.Position, spot.Left.Size = UDim2.new(0, 0, 0, y0), UDim2.new(0, x0, 0, y1 - y0)
	spot.Right.Position, spot.Right.Size = UDim2.new(0, x1, 0, y0), UDim2.new(1, -x1, 0, y1 - y0)
	spot.Ring.Position, spot.Ring.Size = UDim2.new(0, x0, 0, y0), UDim2.new(0, size.X, 0, size.Y)
	-- 말풍선: 대상 오른쪽 (화면 오른쪽 끝이면 아래쪽)
	local viewport = workspace.CurrentCamera.ViewportSize / scale
	if x1 + 280 < viewport.X then
		spot.Arrow.Position = UDim2.new(0, x1 + 12, 0, y0 + (y1 - y0) / 2 - 20)
		spot.Arrow.Text = "◀ " .. text
	else
		spot.Arrow.Position = UDim2.new(0, math.max(8, x0 - 40), 0, y1 + 12)
		spot.Arrow.Text = "▲ " .. text
	end
	for key, part in pairs(spot) do
		if key ~= "Corr" then part.Visible = true end
	end
end
local function runHighlight(kind)
	highlightToken += 1
	local token = highlightToken
	spotHide()
	if kind ~= "Menu" then return end
	task.spawn(function()
		while token == highlightToken do
			local hud = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("HUD")
			local target, text
			if hud then
				local menuButton, growthTab, trainButton
				for _, descendant in ipairs(hud:GetDescendants()) do
					if descendant:IsA("TextButton") and descendant.Visible then
						if descendant.Text == "📋 메뉴 (I)" then menuButton = descendant end
						if descendant.Text == "성장" and descendant.Parent and descendant.Parent.Visible then growthTab = descendant end
						if descendant.Text == "훈련 시작" and not trainButton then trainButton = descendant end
					end
				end
				if growthTab then
					if growthTab.BackgroundColor3.B < 0.8 then
						target, text = growthTab, "성장 탭을 눌러요!"
					elseif trainButton then
						target, text = trainButton, "훈련 시작을 눌러요!"
					end
				elseif menuButton then
					target, text = menuButton, "메뉴를 열어요! (I)"
				end
			end
			if target and target.AbsoluteSize.X > 0 then
				spotShow(target, text)
			else
				spotHide()
			end
			task.wait(0.1)
		end
		spotHide()
	end)
end

-- 키 안내 카드: 키 모양 큰 글자 + 설명 (잠깐 떠 있다가 사라진다)
local activePrompt = nil
local function showPrompt(data)
	if activePrompt then activePrompt:Destroy() end
	local card = create("Frame", { Size = UDim2.new(0, 460, 0, 110), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, data.Top and 0.2 or 0.66, 0),
		BackgroundColor3 = Color3.fromRGB(16, 18, 30), BackgroundTransparency = 0.05, BorderSizePixel = 0, ZIndex = 70 }, gui)
	activePrompt = card
	rounded(card, 16)
	local cardStroke = create("UIStroke", { Color = Color3.fromRGB(255, 225, 110), Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	TweenService:Create(cardStroke, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 8 }):Play()
	local keycap = create("Frame", { Size = UDim2.new(0, 78, 0, 78), Position = UDim2.new(0, 16, 0.5, -39), BackgroundColor3 = Color3.fromRGB(245, 245, 250), BorderSizePixel = 0, ZIndex = 71 }, card)
	rounded(keycap, 12)
	label({ Size = UDim2.new(1, 0, 1, 0), Text = data.Key or "?", TextSize = 52, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(30, 34, 50), TextStrokeTransparency = 1, ZIndex = 72 }, keycap)
	label({ Size = UDim2.new(1, -120, 0, 34), Position = UDim2.new(0, 108, 0, 12), Text = data.Title or "", TextSize = 24, Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 225, 110), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 71 }, card)
	label({ Size = UDim2.new(1, -120, 0, 52), Position = UDim2.new(0, 108, 0, 46), Text = data.Text or "", TextSize = 17, Font = Enum.Font.GothamBold, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 71 }, card)
	task.delay(data.Duration or 7, function()
		if card.Parent then
			TweenService:Create(card, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			task.wait(0.4)
			card:Destroy()
		end
		if activePrompt == card then activePrompt = nil end
	end)
end

Remotes.Tutorial.OnClientEvent:Connect(function(action, data)
	if action == "Prompt" then
		showPrompt(data)
		return
	elseif action == "PromptHide" then
		if activePrompt then
			activePrompt:Destroy()
			activePrompt = nil
		end
		return
	end
	if action == "Step" then
		runHighlight(data.Highlight)
	elseif action ~= "Cinema" and action ~= "Waypoint" and action ~= "WaypointClear" then
		runHighlight(nil)
	end
	if action == "Cinema" then
		cinemaPlay(data)
		return
	end
	if action == "Prompt" or action == "PromptHide" then return end -- 키 안내 카드는 위쪽 핸들러가 처리한다 (미션 표시는 건드리지 않는다)
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

-- 시점 둘러보기 미션: 카메라가 좌우로 돈 각도를 모아서 30도(= 10%)마다 서버에 알린다
local lastYaw, lookAccum = nil, 0
RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not (current and current.Look ~= false and current.Index == 1 and camera) then
		lastYaw, lookAccum = nil, 0
		return
	end
	local look = camera.CFrame.LookVector
	local yaw = math.atan2(look.X, look.Z)
	if lastYaw then
		local delta = math.abs(math.atan2(math.sin(yaw - lastYaw), math.cos(yaw - lastYaw)))
		lookAccum += math.deg(delta)
		while lookAccum >= 30 do
			lookAccum -= 30
			Remotes.Tutorial:FireServer("Look")
		end
	end
	lastYaw = yaw
end)

RunService.RenderStepped:Connect(function()
	if waypoint and waypointLabel then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local flat = Vector3.new(root.Position.X - waypoint.Position.X, 0, root.Position.Z - waypoint.Position.Z).Magnitude
			waypointLabel.Text = string.format("▼ 다음 방  %dm", math.floor(flat + 0.5))
			waypoint.Transparency = flat < 30 and 0.92 or 0.6
		end
	end
	-- 던전 안에서는 던전 UI 와 겹치지 않게 숨긴다
	objective.Visible = current ~= nil and player:GetAttribute("Zone") ~= "Dungeon"
	if beacon and beaconLabel and current then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local flat = Vector3.new(root.Position.X - beacon.Position.X, 0, root.Position.Z - beacon.Position.Z).Magnitude
			beaconLabel.Text = string.format("▼ %s  %dm", current.TargetName or "목표", math.floor(flat + 0.5))
			-- 메뉴 / 강화창이 화면을 가려도 상단 바에서 방향과 거리를 알 수 있게 한다 (북쪽 = -Z, 동쪽 = +X)
			local dx, dz = beacon.Position.X - root.Position.X, beacon.Position.Z - root.Position.Z
			local compass = { "동", "남동", "남", "남서", "서", "북서", "북", "북동" }
			local index = math.floor((math.atan2(dz, dx) / (math.pi / 4)) % 8 + 0.5) % 8 + 1
			local where = compass[index] .. "쪽"
			local camera = workspace.CurrentCamera
			local meters = math.floor(flat + 0.5)
			if camera then -- 보는 방향 기준으로 "앞 / 뒤 / 왼쪽 / 오른쪽" (가까울수록 "바로 ~에 있어요!")
				local rel = camera.CFrame:VectorToObjectSpace(Vector3.new(dx, 0, dz))
				local angle = math.deg(math.atan2(rel.X, -rel.Z))
				local side = math.abs(angle) <= 45 and "앞" or math.abs(angle) >= 135 and "뒤" or angle > 0 and "오른쪽" or "왼쪽"
				if flat < 45 then
					where = "바로 " .. side .. "에 있어요!"
				else
					where = side .. "쪽 (" .. where .. ")"
				end
			end
			local line = string.format("📍 %s  %s  %dm", current.TargetName or "목표", where, meters)
			barText.Text = string.format("%d / %d     %s", current.Progress, current.Goal, line)
			if activeWhere and activeWhere.Parent then activeWhere.Text = line end
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
