-- PlayerFX (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: PlayerFX)
-- PlayerClient 가 Roblox 스크립트 크기 한도(약 20만 자)에 가까워져서 따로 뺀 독립 연출들:
--   데드아이 붉은 틴트 / 구역별 조명 / 내 체력바 + 피격 번쩍임 / 구역 경고 배너 / 전리품 빔
-- 서버가 주는 Attribute / Remote 만 보고 동작하므로 PlayerClient 와 직접 얽히지 않는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
local create, rounded, makePanel, makeLabel, makeButton = Kit.create, Kit.rounded, Kit.makePanel, Kit.makeLabel, Kit.makeButton

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local gui = create("ScreenGui", { Name = "HUDFx", ResetOnSpawn = false, IgnoreGuiInset = true }, player:WaitForChild("PlayerGui"))

-- 데드아이 연출: 락온 + 난사 동안 화면이 붉게 물들고(채도 감소 + 붉은 색조) 가장자리가 어두워지고 시야가 좁아진다
do
	local Lighting = game:GetService("Lighting")
	local tint = Lighting:FindFirstChild("DeadeyeTint") or Instance.new("ColorCorrectionEffect")
	tint.Name = "DeadeyeTint"
	tint.Enabled = false
	tint.Parent = Lighting
	local vignette = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 40, Active = false }, gui)
	for _, edge in ipairs({
		{ Size = UDim2.new(1, 0, 0.12, 0), Position = UDim2.new(0, 0, 0, 0), Rotation = 90 },
		{ Size = UDim2.new(1, 0, 0.12, 0), Position = UDim2.new(0, 0, 0.88, 0), Rotation = 270 },
		{ Size = UDim2.new(0.09, 0, 1, 0), Position = UDim2.new(0, 0, 0, 0), Rotation = 0 },
		{ Size = UDim2.new(0.09, 0, 1, 0), Position = UDim2.new(0.91, 0, 0, 0), Rotation = 180 },
	}) do
		local frame = create("Frame", { Size = edge.Size, Position = edge.Position, BackgroundColor3 = Color3.fromRGB(200, 20, 30), BorderSizePixel = 0 }, vignette)
		create("UIGradient", { Rotation = edge.Rotation, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }) }, frame)
	end
	local function apply()
		-- 데드아이 중 화면이 붉게 물들거나 가장자리가 어두워지는 효과는 없앴다 (너무 번쩍여서): 탄과 락온 표시로만 연출한다
		vignette.Visible = false
		tint.Enabled = false
	end
	player:GetAttributeChangedSignal("DeadeyeActive"):Connect(apply)
end

-- 구역별 분위기: 로비는 해 질 녘(서버가 설정), 던전은 밝은 낮, 필드는 구역(1~8)마다 하늘 / 안개 / 빛 색이 달라진다
do
	local Lighting = game:GetService("Lighting")
	-- 눈이 편하도록: 필드 / 던전은 채도와 대비를 살짝 낮춘 부드러운 색보정을 늘 켜 두고, 전체 밝기도 약간 낮춘다
	local soft = Lighting:FindFirstChild("SoftGrade") or Instance.new("ColorCorrectionEffect")
	soft.Name = "SoftGrade"
	soft.Saturation = -0.12
	soft.Contrast = -0.04
	soft.TintColor = Color3.fromRGB(252, 249, 244)
	soft.Parent = Lighting
	local DAY = { ClockTime = 14, Brightness = 1.85, Ambient = Color3.fromRGB(70, 70, 70), OutdoorAmbient = Color3.fromRGB(70, 70, 70), ExposureCompensation = 0 }
	-- 필드 구역별 하늘: 시간대 / 밝기 / 주변광 / 안개 색 / 안개 농도
	local FIELD_THEMES = {
		{ ClockTime = 14, Brightness = 2.4, Ambient = Color3.fromRGB(90, 90, 90), OutdoorAmbient = Color3.fromRGB(112, 112, 112), Fog = Color3.fromRGB(200, 225, 255), Density = 0.22 },   -- 초원: 맑은 낮
		{ ClockTime = 11, Brightness = 1.9, Ambient = Color3.fromRGB(60, 82, 70), OutdoorAmbient = Color3.fromRGB(88, 108, 96), Fog = Color3.fromRGB(150, 205, 175), Density = 0.35 }, -- 숲: 초록 안개
		{ ClockTime = 16.5, Brightness = 2.2, Ambient = Color3.fromRGB(104, 86, 70), OutdoorAmbient = Color3.fromRGB(132, 112, 92), Fog = Color3.fromRGB(212, 182, 150), Density = 0.34 }, -- 황무지: 먼지
		{ ClockTime = 13, Brightness = 2.6, Ambient = Color3.fromRGB(132, 116, 82), OutdoorAmbient = Color3.fromRGB(162, 142, 102), Fog = Color3.fromRGB(255, 226, 172), Density = 0.4 }, -- 사막: 뜨거운 낮
		{ ClockTime = 10, Brightness = 2.3, Ambient = Color3.fromRGB(96, 106, 128), OutdoorAmbient = Color3.fromRGB(132, 148, 172), Fog = Color3.fromRGB(218, 238, 255), Density = 0.42 }, -- 설원: 차가운 흰 안개
		{ ClockTime = 18.5, Brightness = 1.6, Ambient = Color3.fromRGB(98, 52, 42), OutdoorAmbient = Color3.fromRGB(124, 62, 46), Fog = Color3.fromRGB(255, 150, 100), Density = 0.46 }, -- 화산: 붉은 노을
		{ ClockTime = 21, Brightness = 1.3, Ambient = Color3.fromRGB(58, 46, 88), OutdoorAmbient = Color3.fromRGB(84, 68, 124), Fog = Color3.fromRGB(150, 110, 230), Density = 0.46 }, -- 암흑 지대: 보랏빛 밤
		{ ClockTime = 23, Brightness = 1.1, Ambient = Color3.fromRGB(64, 32, 74), OutdoorAmbient = Color3.fromRGB(90, 42, 100), Fog = Color3.fromRGB(255, 100, 180), Density = 0.5 }, -- 심연: 분홍 어둠
	}
	-- 던전 변이 화면 분위기 (서버가 던전 시작 때 DungeonVisual 을 정한다)
	local DUNGEON_VISUALS = {
		Dark  = { Lighting = { ClockTime = 0, Brightness = 0.5, Ambient = Color3.fromRGB(26, 26, 44), OutdoorAmbient = Color3.fromRGB(34, 34, 58) }, Atmosphere = { Color = Color3.fromRGB(20, 20, 40), Density = 0.5 } },
		Fog   = { Lighting = { Brightness = 1.5, Ambient = Color3.fromRGB(110, 115, 125), OutdoorAmbient = Color3.fromRGB(140, 145, 155) }, Atmosphere = { Color = Color3.fromRGB(205, 212, 225), Density = 0.78 } },
		Blood = { Lighting = { ClockTime = 18.5, Brightness = 1.5, Ambient = Color3.fromRGB(112, 40, 40), OutdoorAmbient = Color3.fromRGB(140, 50, 46) }, Atmosphere = { Color = Color3.fromRGB(255, 70, 60), Density = 0.42 } },
		Gold  = { Lighting = { ClockTime = 16.5, Brightness = 2.6, Ambient = Color3.fromRGB(130, 112, 60), OutdoorAmbient = Color3.fromRGB(165, 140, 76) }, Atmosphere = { Color = Color3.fromRGB(255, 220, 130), Density = 0.3 } },
		Elite = { Lighting = { ClockTime = 21, Brightness = 1.3, Ambient = Color3.fromRGB(70, 44, 100), OutdoorAmbient = Color3.fromRGB(96, 62, 130) }, Atmosphere = { Color = Color3.fromRGB(170, 110, 255), Density = 0.4 } },
	}
	local dusk = nil
	local fieldIndex = 0
	-- 시간대 변화: 서버 시계를 그대로 쓰므로 서버 부담이 없고, 모두 같은 시간대를 본다 (한 바퀴 DAY_CYCLE 초)
	local DAY_CYCLE = 540
	local NIGHT_AMBIENT, NIGHT_OUTDOOR, NIGHT_FOG = Color3.fromRGB(46, 56, 96), Color3.fromRGB(64, 76, 122), Color3.fromRGB(70, 86, 140)
	local DUSK_FOG = Color3.fromRGB(255, 170, 120)
	local function nightAmount()
		local t = (workspace:GetServerTimeNow() % DAY_CYCLE) / DAY_CYCLE
		-- 0~0.5 낮, 0.5~0.6 노을, 0.6~0.9 밤, 0.9~1 새벽
		if t < 0.5 then return 0 end
		if t < 0.6 then return (t - 0.5) / 0.1 end
		if t < 0.9 then return 1 end
		return 1 - (t - 0.9) / 0.1
	end
	local lastNight = -1
	local phaseName = "낮"
	local function applyField(index)
		local theme = FIELD_THEMES[index or fieldIndex]
		if not theme then return end
		fieldIndex = index or fieldIndex
		local n = nightAmount()
		lastNight = n
		local smooth = n * n * (3 - 2 * n)
		local warm = math.sin(math.pi * smooth) * 0.35
		local clock = theme.ClockTime + (21.5 - theme.ClockTime) * smooth * 0.6
		TweenService:Create(Lighting, TweenInfo.new(1.2), {
			ClockTime = clock, Brightness = theme.Brightness * 0.86 * (1 - 0.35 * smooth),
			Ambient = theme.Ambient:Lerp(NIGHT_AMBIENT, smooth * 0.6), OutdoorAmbient = theme.OutdoorAmbient:Lerp(NIGHT_OUTDOOR, smooth * 0.6), ExposureCompensation = 0,
		}):Play()
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			local fog = theme.Fog:Lerp(NIGHT_FOG, smooth * 0.55):Lerp(DUSK_FOG, warm)
			TweenService:Create(atmosphere, TweenInfo.new(1.2), { Color = fog, Density = theme.Density }):Play()
		end
		local name = n < 0.15 and "낮" or (n > 0.85 and "밤" or "노을")
		if name ~= phaseName then
			phaseName = name
			local gui = player:FindFirstChildOfClass("PlayerGui")
			if gui and not player:GetAttribute("InDoomArena") then
				local sg = Instance.new("ScreenGui")
				sg.Name = "DayPhaseToast"
				sg.ResetOnSpawn = false
				sg.Parent = gui
				local label = Instance.new("TextLabel")
				label.AnchorPoint = Vector2.new(0.5, 0)
				label.Position = UDim2.new(0.5, 0, 0.14, 0)
				label.Size = UDim2.new(0, 260, 0, 30)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.GothamBold
				label.TextSize = 20
				label.TextColor3 = Color3.fromRGB(235, 232, 220)
				label.TextStrokeTransparency = 0.5
				label.TextTransparency = 1
				label.Text = name == "낮" and "☀ 아침이 밝았다" or (name == "밤" and "☾ 밤이 되었다 - 시야 주의" or "해가 저물어 간다")
				label.Parent = sg
				TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
				task.delay(3, function()
					TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
					task.delay(1, function() sg:Destroy() end)
				end)
			end
		end
	end
	local function apply()
		local zone = player:GetAttribute("Zone")
		local grade = Lighting:FindFirstChild("LobbyGrade")
		local bloom = Lighting:FindFirstChild("LobbyBloom")
		if zone == "Lobby" then
			if dusk then
				TweenService:Create(Lighting, TweenInfo.new(0.8), dusk.Lighting):Play()
				local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
				if atmosphere and dusk.Atmosphere then
					TweenService:Create(atmosphere, TweenInfo.new(0.8), dusk.Atmosphere):Play()
				end
			end
			fieldIndex = 0
			if grade then grade.Enabled = true end
			if bloom then bloom.Enabled = true end
		elseif zone == "Field" or zone == "Dungeon" then
			if not dusk then
				local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
				dusk = {
					Lighting = {
						ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
						OutdoorAmbient = Lighting.OutdoorAmbient, ExposureCompensation = Lighting.ExposureCompensation,
					},
					Atmosphere = atmosphere and { Color = atmosphere.Color, Density = atmosphere.Density } or nil,
				}
			end
			if zone == "Dungeon" then
				local visual = DUNGEON_VISUALS[player:GetAttribute("DungeonVisual") or ""]
				local look = DAY
				if visual then
					look = {}
					for key, value in pairs(DAY) do look[key] = value end
					for key, value in pairs(visual.Lighting) do look[key] = value end
				end
				if player:GetAttribute("DungeonTypeKey") == "Ice" then -- 얼음 성채: 눈 / 얼음이 하얗게 번쩍여 눈부시지 않게 밝기를 낮추고 푸른 어둑한 톤으로
					local dim = {}
					for key, value in pairs(look) do dim[key] = value end
					dim.Brightness = math.min(dim.Brightness or 1.85, 1.15)
					dim.ExposureCompensation = -0.45
					dim.Ambient = Color3.fromRGB(46, 58, 80)
					dim.OutdoorAmbient = Color3.fromRGB(62, 78, 104)
					look = dim
				end
				TweenService:Create(Lighting, TweenInfo.new(visual and 2 or 0.8), look):Play()
				local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
				if atmosphere and dusk and dusk.Atmosphere then
					TweenService:Create(atmosphere, TweenInfo.new(2), visual and visual.Atmosphere or dusk.Atmosphere):Play()
				end
				fieldIndex = 0
			end
			if grade then grade.Enabled = false end
			if bloom then bloom.Enabled = false end
		end
	end
	player:GetAttributeChangedSignal("Zone"):Connect(apply)
	player:GetAttributeChangedSignal("DungeonVisual"):Connect(apply)
	player:GetAttributeChangedSignal("DungeonTypeKey"):Connect(apply)
	task.defer(apply)
	-- 필드 안에서는 지금 서 있는 구역을 보고 하늘을 바꾼다
	task.spawn(function()
		while true do
			task.wait(0.5)
			if player:GetAttribute("Zone") == "Field" then
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local F = Config.Field
					local index = F.ZoneOfX(root.Position.X)
					if index ~= fieldIndex then applyField(index) end
				end
			end
		end
	end)
end

-- 화면 가장자리 연출: 체력이 낮을 때 붉게 맥박치고, 필드 이벤트(공습 / 엘리트 / 대이동)가 터질 때 번쩍인다 (소리 대신)
local LowHpFx = { Ratio = 1 }
do
	local edges = {} -- [Top / Bottom / Left / Right] = Frame
	local sides = {
		Top = { Size = UDim2.new(1, 0, 0.2, 0), Position = UDim2.new(0, 0, 0, 0), Anchor = Vector2.new(0, 0), Rotation = 90 },
		Bottom = { Size = UDim2.new(1, 0, 0.2, 0), Position = UDim2.new(0, 0, 1, 0), Anchor = Vector2.new(0, 1), Rotation = 270 },
		Left = { Size = UDim2.new(0.12, 0, 1, 0), Position = UDim2.new(0, 0, 0, 0), Anchor = Vector2.new(0, 0), Rotation = 0 },
		Right = { Size = UDim2.new(0.12, 0, 1, 0), Position = UDim2.new(1, 0, 0, 0), Anchor = Vector2.new(1, 0), Rotation = 180 },
	}
	for name, side in pairs(sides) do
		local frame = create("Frame", { Name = "Edge" .. name, Size = side.Size, Position = side.Position, AnchorPoint = side.Anchor,
			BackgroundColor3 = Color3.fromRGB(200, 28, 36), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 44, Active = false }, gui)
		create("UIGradient", { Rotation = side.Rotation, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }) }, frame)
		edges[name] = frame
	end
	local function paint(color, transparency, only) -- only: nil = 네 변 모두 / "Left" "Right" = 그쪽 변만
		for name, frame in pairs(edges) do
			frame.BackgroundColor3 = color
			frame.BackgroundTransparency = (only == nil or only == name) and transparency or 1
		end
	end
	local flashUntil, flashStart, flashColor, flashPulses, flashOnly = 0, 0, nil, 0, nil
	local edgesShown = false
	game:GetService("RunService").RenderStepped:Connect(function()
		local now = os.clock()
		if flashColor and now < flashUntil then -- 이벤트 번쩍임: 정해진 횟수만큼 맥박
			local t = (now - flashStart) / (flashUntil - flashStart)
			local wave = math.abs(math.sin(t * math.pi * flashPulses))
			edgesShown = true
			paint(flashColor, 1 - 0.78 * wave, flashOnly)
			return
		end
		flashColor = nil
		local ratio = LowHpFx.Ratio
		if ratio <= 0.3 then -- 체력이 낮을수록 더 진하고 빠르게 맥박친다
			local danger = (0.3 - ratio) / 0.3
			local pulse = 0.5 + 0.5 * math.sin(now * (3 + danger * 5))
			edgesShown = true
			paint(Color3.fromRGB(200, 28, 36), 0.9 - (0.35 + 0.35 * danger) * (0.55 + 0.45 * pulse))
		elseif edgesShown then
			edgesShown = false
			paint(Color3.fromRGB(200, 28, 36), 1)
		end
	end)
	player:GetAttributeChangedSignal("EventFxTick"):Connect(function()
		local kind = player:GetAttribute("EventFx")
		local now = os.clock()
		if kind == "Raid" then
			flashColor, flashPulses, flashOnly, flashUntil = Color3.fromRGB(220, 50, 40), 3, nil, now + 2.4
		elseif kind == "Elite" then
			flashColor, flashPulses, flashOnly, flashUntil = Color3.fromRGB(235, 180, 70), 2, nil, now + 1.8
		elseif kind == "StampedeR" or kind == "StampedeL" then
			flashColor, flashPulses, flashOnly, flashUntil = Color3.fromRGB(230, 140, 60), 3, kind == "StampedeR" and "Right" or "Left", now + 2.2
		else
			return
		end
		flashStart = now
	end)
end

-- 내 체력바: 캐릭터 발밑에만 표시
do
	local fill = { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(70, 220, 100) }
	local text = { Text = "" }
	local feet
	local lastHealth
	local lastLowSound
	local function update()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
		-- 맞으면 화면 가장자리가 붉게 번쩍이고 -피해량이 뜬다 (맞고 있는지 한눈에)
		if lastHealth and humanoid.Health < lastHealth - 0.5 then
			SoundBank.Play(game:GetService("SoundService"), "Player_Hurt", { Pitch = 0.92 + math.random() * 0.16 })
			local hurt = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 20, 20), BackgroundTransparency = 0.78, BorderSizePixel = 0, ZIndex = 45, Active = false }, gui)
			TweenService:Create(hurt, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			task.delay(0.4, function() hurt:Destroy() end)
			local lost = makeLabel({ Size = UDim2.new(0, 200, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.55, 0), Text = string.format("-%d", math.ceil(lastHealth - humanoid.Health)), Font = Enum.Font.GothamBlack, TextSize = 34, TextColor3 = Color3.fromRGB(255, 80, 80), TextStrokeTransparency = 0, ZIndex = 46 }, gui)
			TweenService:Create(lost, TweenInfo.new(0.7), { Position = UDim2.new(0.5, 0, 0.47, 0), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(0.8, function() lost:Destroy() end)
		end
		lastHealth = humanoid.Health
		LowHpFx.Ratio = humanoid.Health > 0 and ratio or 1 -- 체력이 낮으면 화면 가장자리가 붉게 맥박친다 (심장 소리 대신 화면 연출)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		fill.BackgroundColor3 = ratio > 0.5 and Color3.fromRGB(70, 220, 100) or ratio > 0.25 and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(255, 70, 70)
		text.Text = string.format("%d / %d", math.ceil(humanoid.Health), math.ceil(humanoid.MaxHealth))
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and (not feet or feet.Parent ~= root) then
			if feet then feet:Destroy() end
			feet = Instance.new("BillboardGui")
			feet.Size = UDim2.fromOffset(140, 16)
			feet.StudsOffset = Vector3.new(0, -3.7, 0)
			feet.AlwaysOnTop = true
			feet.Parent = root
			-- 왼쪽 HUD 패널과 같은 어두운 남색 + 둥근 모서리, 채움은 그라데이션으로 부드럽게
			local back = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(16, 18, 30), BackgroundTransparency = 0.25, BorderSizePixel = 0, ClipsDescendants = true }, feet)
			create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, back)
			create("UIStroke", { Color = Color3.fromRGB(120, 130, 190), Thickness = 1.2, Transparency = 0.35 }, back)
			local inner = create("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(70, 220, 100), BorderSizePixel = 0 }, back)
			create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, inner)
			create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)) }, inner)
			makeLabel({ Name = "HP", Size = UDim2.fromScale(1, 1), Text = "", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.35, ZIndex = 3 }, back)
		end
		local f = feet and feet:FindFirstChild("Fill", true)
		if f then
			f.Size = UDim2.fromScale(ratio, 1)
			f.BackgroundColor3 = fill.BackgroundColor3
			feet:FindFirstChild("HP", true).Text = text.Text
		end
	end
	RunService.Heartbeat:Connect(update)
end

-- NEAR MISS: 아슬아슬하게 피했을 때 시야가 순간 좁아지며(줌) 화면이 청록으로 번쩍이고 큰 글자가 튀어나온다
-- (Roblox 는 게임 전체를 느리게 만들 수 없어서, 슬로모션 대신 줌 + 색 번쩍임으로 "시간이 멈칫"하는 느낌을 낸다)
do
	local Lighting = game:GetService("Lighting")
	local pulse = Lighting:FindFirstChild("NearMissPulse") or Instance.new("ColorCorrectionEffect")
	pulse.Name = "NearMissPulse"
	pulse.Enabled = false
	pulse.Parent = Lighting
	Remotes.Banner.OnClientEvent:Connect(function(action, info)
		if action ~= "NearMiss" then return end
		pulse.Enabled = true
		pulse.Saturation, pulse.Contrast, pulse.TintColor = -0.55, 0.25, Color3.fromRGB(190, 255, 255)
		TweenService:Create(pulse, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) }):Play()
		task.delay(0.5, function() pulse.Enabled = false end)
		local fov = camera.FieldOfView
		camera.FieldOfView = fov - 9
		TweenService:Create(camera, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { FieldOfView = fov }):Play()
		local streak = info and info.Streak or 1
		if info and info.First then -- 처음 한 번: NEAR MISS 가 뭔지 설명 카드
			local card = makePanel({
				Size = UDim2.new(0, 380, 0, 168), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -96), -- 화면 가운데를 가리지 않게 왼쪽 아래
				BackgroundColor3 = Color3.fromRGB(14, 24, 36), BackgroundTransparency = 0.03, ZIndex = 58,
			}, gui)
			create("UIStroke", { Color = Color3.fromRGB(120, 255, 255), Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
			makeLabel({ Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 0, 8), Text = "⚡ NEAR MISS 란?", TextSize = 22, Font = Enum.Font.GothamBlack,
				TextColor3 = Color3.fromRGB(120, 255, 255), ZIndex = 59 }, card)
			makeLabel({ Size = UDim2.new(1, -28, 0, 116), Position = UDim2.new(0, 14, 0, 42), TextSize = 15, Font = Enum.Font.GothamBold, TextWrapped = true, RichText = true,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 59,
				Text = "적의 탄이나 공격을 <font color='#78ffff'>대시(Q)로 아슬아슬하게 스치며 피하면</font> 발동해요!\n<font color='#ffe16e'>데드아이 게이지가 차오르고, 연속으로 성공할수록 공격력이 쌓여요! (머리 위 막대가 붉어져요)</font>\n8초 안에 연속으로 성공하면 계속 쌓여요. (심연 도전에서는 점수도 올라요)" }, card)
			task.delay(8, function()
				if card.Parent then
					TweenService:Create(card, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
					task.wait(0.4)
					card:Destroy()
				end
			end)
		end
		local text = makeLabel({
			Size = UDim2.new(0, 520, 0, 70), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.3, 0),
			Text = streak > 1 and string.format("⚡ NEAR MISS!  x%d", streak) or "⚡ NEAR MISS!", TextSize = 46, Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.fromRGB(120, 255, 255), TextStrokeTransparency = 0, ZIndex = 60,
		}, gui)
		local sub = makeLabel({
			Size = UDim2.new(0, 520, 0, 28), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.3, 46),
			Text = "데드아이 게이지 +  ·  공격력이 점점 올라가요!", TextSize = 18, Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(255, 240, 160), TextStrokeTransparency = 0, ZIndex = 60,
		}, gui)
		text.Size = UDim2.new(0, 340, 0, 46)
		TweenService:Create(text, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 520, 0, 70) }):Play()
		task.delay(0.9, function()
			TweenService:Create(text, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.new(0.5, 0, 0.26, 0) }):Play()
			TweenService:Create(sub, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(0.4)
			text:Destroy()
			sub:Destroy()
		end)
	end)
end

-- 구역 경고 배너: 새 구역에 들어서면 붉은 번쩍임 + 큰 글자가 쾅 하고 내려앉는다 (난이도가 얼마나 뛰는지 숫자로)
do
	Remotes.Banner.OnClientEvent:Connect(function(action, info)
		if action ~= "Zone" then return end
		local old = gui:FindFirstChild("ZoneBanner")
		if old then old:Destroy() end
		local root = create("Frame", { Name = "ZoneBanner", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 55, Active = false }, gui)
		local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(220, 30, 40), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 55 }, root)
		TweenService:Create(flash, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
		local band = create("Frame", { Size = UDim2.new(1, 0, 0, 150), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.3, 0), BackgroundColor3 = Color3.fromRGB(10, 6, 14), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 56 }, root)
		TweenService:Create(band, TweenInfo.new(0.25), { BackgroundTransparency = 0.25 }):Play()
		local title = makeLabel({
			Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 0, 10), Text = string.format("⚠ 구역 %d · %s ⚠", info.Zone, info.Name),
			Font = Enum.Font.GothamBlack, TextSize = 120, TextColor3 = Color3.fromRGB(255, 90, 80), TextStrokeTransparency = 0, ZIndex = 57, TextTransparency = 1,
		}, band)
		TweenService:Create(title, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 50, TextTransparency = 0 }):Play()
		local stars = {}
		for i = 1, 8 do table.insert(stars, i <= info.Stars and "★" or "☆") end
		makeLabel({
			Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 80), Text = "위험도 " .. table.concat(stars), TextSize = 20, Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(255, 200, 90), ZIndex = 57,
		}, band)
		makeLabel({
			Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 110), RichText = true, TextSize = 18, ZIndex = 57,
			Text = string.format("몬스터 체력 <font color='#ff8c7a'><b>x%.1f</b></font> · 공격력 <font color='#ff8c7a'><b>x%.1f</b></font>   |   보상 <font color='#8cff9c'><b>x%.1f</b></font>   (Lv.%d~)", info.HealthMult, info.DamageMult, info.RewardMult, info.Level),
		}, band)
		task.delay(3.2, function()
			if not root.Parent then return end
			TweenService:Create(band, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			for _, child in ipairs(band:GetChildren()) do
				if child:IsA("TextLabel") then TweenService:Create(child, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play() end
			end
			game:GetService("Debris"):AddItem(root, 0.6)
		end)
	end)
end


------------------------------------------------------------
-- 전리품 빔 (개인 전리품): 내가 잡은 몬스터가 떨어뜨린 아이템만 내 화면에 보인다.
-- 가까이 가면 자동으로 주워지고, 등급이 높을수록 빔이 굵고 화려하다.
------------------------------------------------------------
local lootFolder = Instance.new("Folder")
lootFolder.Name = "LootBeams"
lootFolder.Parent = workspace

local lootDrops = {}   -- [id] = { Beam, Cube, Base, Time }

Remotes.Loot.OnClientEvent:Connect(function(action, id, position, rarity, itemName)
	if action == "Drop" then
		local color = Config.Gear.RarityColors[rarity]
		local width = 0.5 + rarity * 0.35
		if rarity >= 3 then SoundBank.Play(game:GetService("SoundService"), "Rare_Drop", { Pitch = 0.9 + 0.05 * rarity }) end -- 희귀 이상 장비

		local beam = create("Part", {
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			Material = Enum.Material.Neon, Color = color, Transparency = 0.4,
			Size = Vector3.new(width, 60, width), Position = position + Vector3.new(0, 30, 0),
		}, lootFolder)

		local base = position + Vector3.new(0, 3, 0)
		local cube = create("Part", {
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			Material = Enum.Material.Neon, Color = color,
			Size = Vector3.new(1.4 + rarity * 0.2, 1.4 + rarity * 0.2, 1.4 + rarity * 0.2), Position = base,
		}, lootFolder)

		local gui = create("BillboardGui", { Size = UDim2.new(0, 220, 0, 30), StudsOffset = Vector3.new(0, 3, 0), AlwaysOnTop = true, MaxDistance = 150 }, cube)
		makeLabel({
			Size = UDim2.new(1, 0, 1, 0), Text = string.format("[%s] %s", Config.Gear.RarityNames[rarity], itemName),
			Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = color, TextStrokeTransparency = 0,
		}, gui)

		lootDrops[id] = { Beam = beam, Cube = cube, Base = base, Time = 0, Rarity = rarity }
	elseif action == "Gone" then
		local drop = lootDrops[id]
		if drop then
			SoundBank.Play(game:GetService("SoundService"), "Pickup", { Pitch = 0.85 + 0.1 * (drop.Rarity or 1) })
			drop.Beam:Destroy()
			drop.Cube:Destroy()
			lootDrops[id] = nil
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	for _, drop in pairs(lootDrops) do
		drop.Time += dt
		drop.Cube.CFrame = CFrame.new(drop.Base + Vector3.new(0, math.sin(drop.Time * 3) * 0.5, 0)) * CFrame.Angles(drop.Time * 2, drop.Time * 3, 0)
	end
end)


-- 연속 처치 이정표: 10 / 25 / 50 / 100 / 200 연속 처치 때 큰 글자가 쾅! 하고 뜬다 (박진감)
do
	local milestones = { [10] = "🔥 10 연속 처치!", [25] = "⚡ 25 연속 처치!!", [50] = "💥 50 연속 처치!!!", [100] = "👑 100 연속 처치!!!!", [200] = "🌋 200 연속 — 전설!" }
	local lastCombo = 0
	player:GetAttributeChangedSignal("Combo"):Connect(function()
		local combo = player:GetAttribute("Combo") or 0
		if combo > lastCombo and milestones[combo] then
			local label = makeLabel({
				Size = UDim2.new(1, 0, 0, 90), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.32, 0),
				Text = milestones[combo], Font = Enum.Font.GothamBlack, TextSize = 28, TextColor3 = Color3.fromRGB(255, 220, 90),
				TextStrokeTransparency = 0, ZIndex = 60,
			}, gui)
			TweenService:Create(label, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 62 }):Play()
			task.delay(0.9, function()
				TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.new(0.5, 0, 0.26, 0) }):Play()
			end)
			task.delay(1.5, function() label:Destroy() end)
		end
		lastCombo = combo
	end)
end

-- 사운드 테스트 창 (Studio 전용, K 키): 항목별 소리를 들어 보고, 후보 소리 ID 를 항목에 걸어 미리 들어 본다.
-- 마음에 드는 조합은 [출력으로 내보내기] 로 AudioIds 에 붙여 넣을 줄을 만든다.
if game:GetService("RunService"):IsStudio() then
	local panel = makePanel({ Size = UDim2.new(0, 560, 0, 520), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Visible = false, ZIndex = 80, BackgroundTransparency = 0.05 }, gui)
	makeLabel({ Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 8), Text = "🔊 사운드 테스트 (Studio 전용 · K 키로 열고 닫기)", Font = Enum.Font.GothamBlack, TextSize = 18, ZIndex = 81, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	local idBox = create("TextBox", { Size = UDim2.new(1, -150, 0, 32), Position = UDim2.new(0, 10, 0, 44), PlaceholderText = "후보 소리 ID(숫자) 붙여넣기", Text = "", ClearTextOnFocus = false,
		BackgroundColor3 = Color3.fromRGB(40, 42, 62), TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamMedium, TextSize = 15, BorderSizePixel = 0, ZIndex = 81 }, panel)
	rounded(idBox, 6)
	local function playRaw(id)
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://" .. id
		sound.Volume = 0.6
		sound.Parent = game:GetService("SoundService")
		sound:Play()
		game:GetService("Debris"):AddItem(sound, 6)
	end
	makeButton({ Size = UDim2.new(0, 130, 0, 32), Position = UDim2.new(1, -140, 0, 44), Text = "▶ 이 ID 그대로", TextSize = 14, ZIndex = 81 }, panel, function()
		local id = tonumber(idBox.Text)
		if id then playRaw(id) end
	end)
	local list = create("ScrollingFrame", { Size = UDim2.new(1, -20, 1, -130), Position = UDim2.new(0, 10, 0, 84), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0), ZIndex = 81 }, panel)
	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local chosen = {} -- 항목 -> 내가 걸어 본 ID
	for order, key in ipairs(SoundBank.Order) do
		local row = create("Frame", { Size = UDim2.new(1, -8, 0, 34), BackgroundColor3 = Color3.fromRGB(34, 36, 54), BorderSizePixel = 0, LayoutOrder = order, ZIndex = 81 }, list)
		rounded(row, 6)
		makeLabel({ Size = UDim2.new(1, -250, 1, 0), Position = UDim2.new(0, 8, 0, 0), Text = string.format("%s  <font color='#9aa0c8'>%s</font>", key, SoundBank.Descriptions[key] or ""), RichText = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 82 }, row)
		makeButton({ Size = UDim2.new(0, 70, 0, 26), Position = UDim2.new(1, -240, 0.5, -13), Text = "▶ 지금", TextSize = 13, ZIndex = 82, BackgroundColor3 = Color3.fromRGB(70, 110, 220) }, row, function()
			SoundBank.Play(game:GetService("SoundService"), key)
		end)
		makeButton({ Size = UDim2.new(0, 160, 0, 26), Position = UDim2.new(1, -162, 0.5, -13), Text = "▶ 내 ID 걸어서", TextSize = 13, ZIndex = 82, BackgroundColor3 = Color3.fromRGB(60, 150, 100) }, row, function()
			local id = tonumber(idBox.Text)
			if id then
				chosen[key] = id
				Config.Audio.Bank[key] = id -- 이번 플레이 동안만 이 항목의 소리를 내 ID 로 바꿔서 들어 본다
				SoundBank.Play(game:GetService("SoundService"), key)
			end
		end)
	end
	makeButton({ Size = UDim2.new(1, -20, 0, 34), Position = UDim2.new(0, 10, 1, -44), Text = "📋 고른 조합을 출력창으로 내보내기 (AudioIds 에 붙여넣기)", TextSize = 14, ZIndex = 81, BackgroundColor3 = Color3.fromRGB(190, 110, 40) }, panel, function()
		local parts = {}
		for key, id in pairs(chosen) do
			table.insert(parts, string.format("%s = %d", key, id))
		end
		table.sort(parts)
		print("[사운드] AudioIds 의 return { ... } 안에 이 줄을 추가하세요:\n\tBank = { " .. table.concat(parts, ", ") .. " },")
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.K then
			panel.Visible = not panel.Visible
		end
	end)
end

-- 구역 분위기 입자: 필드에서는 플레이어 주변에 구역마다 다른 것이 떠다닌다 (꽃가루 / 반딧불 / 먼지 / 모래바람 / 눈 / 불씨 / 보랏빛 가루 / 분홍 포자)
do
	local THEMES = {
		{ Color = Color3.fromRGB(255, 240, 150), Rate = 14, Size = 0.5, Speed = 2, Life = 7, Drift = true, Height = 18 },   -- 초원: 꽃가루
		{ Color = Color3.fromRGB(150, 255, 150), Rate = 16, Size = 0.5, Speed = 1.5, Life = 8, Drift = true, Height = 8, Glow = true }, -- 숲: 반딧불
		{ Color = Color3.fromRGB(190, 165, 130), Rate = 20, Size = 1.2, Speed = 6, Life = 6, Drift = true, Height = 6 },      -- 황무지: 먼지
		{ Color = Color3.fromRGB(240, 215, 160), Rate = 34, Size = 1.1, Speed = 14, Life = 5, Drift = true, Height = 4 },     -- 사막: 모래바람
		{ Color = Color3.fromRGB(255, 255, 255), Rate = 70, Size = 0.55, Speed = 6, Life = 7, Height = 38, Fall = true },      -- 설원: 눈
		{ Color = Color3.fromRGB(255, 150, 60), Rate = 36, Size = 0.6, Speed = 7, Life = 5, Height = -2, Rise = true, Glow = true }, -- 화산: 불씨
		{ Color = Color3.fromRGB(190, 130, 255), Rate = 22, Size = 0.6, Speed = 2.5, Life = 7, Drift = true, Height = 8, Glow = true }, -- 암흑 지대: 보랏빛 가루
		{ Color = Color3.fromRGB(255, 90, 170), Rate = 26, Size = 0.7, Speed = 3, Life = 7, Height = -2, Rise = true, Glow = true },  -- 심연: 분홍 포자
	}
	local holder = create("Part", { Name = "AmbienceEmitter", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(90, 1, 90) }, workspace)
	local emitters = {}
	for index, theme in ipairs(THEMES) do
		local e = Instance.new("ParticleEmitter")
		e.Enabled = false
		e.Rate = theme.Rate
		e.Lifetime = NumberRange.new(theme.Life * 0.7, theme.Life)
		e.Speed = NumberRange.new(theme.Speed * 0.5, theme.Speed)
		e.SpreadAngle = Vector2.new(theme.Fall and 8 or 40, theme.Fall and 8 or 40)
		e.EmissionDirection = theme.Rise and Enum.NormalId.Top or (theme.Fall and Enum.NormalId.Bottom or Enum.NormalId.Front)
		e.LightEmission = theme.Glow and 1 or 0.2
		e.Color = ColorSequence.new(theme.Color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, theme.Size), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(1, 1) })
		e.Rotation = NumberRange.new(0, 360)
		e.Parent = holder
		emitters[index] = e
	end
	local active = 0
	RunService.Heartbeat:Connect(function()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local index = 0
		if root and player:GetAttribute("Zone") == "Field" then
			local F = Config.Field
			index = F.ZoneOfX(root.Position.X)
		end
		if index ~= active then
			if emitters[active] then emitters[active].Enabled = false end
			if emitters[index] then emitters[index].Enabled = true end
			active = index
		end
		if root and THEMES[index] then
			holder.Position = root.Position + Vector3.new(0, THEMES[index].Height, 0)
		end
	end)
end

-- 필드 입구 큰 간판("사냥 필드 입구"): 멀리서는 방향을 알려 주지만, 문 가까이 오거나 필드에 들어오면 화면을 가리지 않게 숨긴다
task.spawn(function()
	local sign
	while true do
		task.wait(0.25)
		if not sign or not sign.Parent then
			local holder = workspace:FindFirstChild("FieldGateSign", true)
			sign = holder and holder:FindFirstChildOfClass("BillboardGui")
		end
		if sign and sign.Parent then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local anchor = sign.Parent
			if root and anchor:IsA("BasePart") then
				local flat = Vector3.new(root.Position.X - anchor.Position.X, 0, root.Position.Z - anchor.Position.Z).Magnitude
				sign.Enabled = player:GetAttribute("Zone") == "Lobby" and flat > 90
			end
		end
	end
end)

-- 무기 진화 연출: 무기가 다음 단계(새 무기)로 바뀌는 순간 화면이 어두워지고 → 빛줄기가 퍼지며 → 이전 무기가 부서지고 → 새 무기 이름이 쾅 하고 박힌다.
-- (강화창의 "진화!" 글자는 그대로 두고 그 위에 겹쳐 연출한다. 아무 곳이나 누르면 닫힌다)
do
	local evolveGui = create("ScreenGui", { Name = "EvolveFx", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 100 }, player:WaitForChild("PlayerGui"))
	local shownTier = nil
	local playing = false

	local function shake(strength)
		player:SetAttribute("ShakeStrength", strength)
		player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
	end

	local function play(oldName, newName, newIndex)
		if playing then return end
		playing = true
		local skipped = false
		local root = create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 1 }, evolveGui)
		root.Activated:Connect(function() skipped = true end)
		local function pause(seconds)
			local untilTime = os.clock() + seconds
			while not skipped and root.Parent and os.clock() < untilTime do task.wait() end
		end
		TweenService:Create(root, TweenInfo.new(0.35), { BackgroundTransparency = 0.25 }):Play()

		-- 중앙 빛 + 회전하는 빛줄기
		local center = create("Frame", { Size = UDim2.new(0, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.46, 0), BackgroundTransparency = 1, ZIndex = 2 }, root)
		local glow = create("Frame", { Size = UDim2.new(0, 60, 0, 60), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(255, 225, 120), BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 2 }, center)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)
		local rays = {}
		for i = 0, 4 do -- 가운데를 지나는 5줄 = 10갈래 빛줄기 (각 줄은 자기 중심을 기준으로 회전해서 한 점에서 퍼진다)
			local ray = create("Frame", {
				Size = UDim2.new(0, 14, 0, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(255, 235, 150),
				BackgroundTransparency = 0.35, BorderSizePixel = 0, Rotation = i * 36, ZIndex = 2,
			}, center)
			table.insert(rays, ray)
		end
		local spin = 0
		local spinning = true
		task.spawn(function()
			while spinning and root.Parent do
				spin += 0.8
				center.Rotation = spin
				task.wait()
			end
		end)
		SoundBank.Play(workspace, "Enh_Evolve")
		TweenService:Create(glow, TweenInfo.new(1.1, Enum.EasingStyle.Quad), { Size = UDim2.new(0, 360, 0, 360), BackgroundTransparency = 0.6 }):Play()
		for _, ray in ipairs(rays) do
			TweenService:Create(ray, TweenInfo.new(1.1, Enum.EasingStyle.Quad), { Size = UDim2.new(0, 14, 0, 1040) }):Play()
		end
		shake(0.35)

		-- 이전 무기 이름이 흔들리다가 부서진다
		local oldLabel = makeLabel({
			Size = UDim2.new(0, 520, 0, 50), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.46, 0),
			Text = oldName, Font = Enum.Font.GothamBlack, TextSize = 34, TextColor3 = Color3.fromRGB(210, 210, 225), TextStrokeTransparency = 0.3, ZIndex = 5,
		}, root)
		for i = 1, 12 do
			if skipped then break end
			oldLabel.Position = UDim2.new(0.5, math.random(-8, 8), 0.46, math.random(-6, 6))
			task.wait(0.07)
		end
		-- 폭발: 번쩍 + 파편
		local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 20 }, root)
		TweenService:Create(flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
		SoundBank.Play(workspace, "Enh_Success", { Pitch = 1.6 })
		shake(1)
		oldLabel:Destroy()
		for i = 1, 22 do
			local angle = math.rad(i * (360 / 22) + math.random(-8, 8))
			local distance = math.random(180, 420)
			local spark = create("Frame", {
				Size = UDim2.new(0, math.random(8, 16), 0, math.random(8, 16)), AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.46, 0), BackgroundColor3 = Color3.fromRGB(255, math.random(190, 240), math.random(70, 130)), BorderSizePixel = 0, ZIndex = 6, Rotation = math.random(0, 90),
			}, root)
			TweenService:Create(spark, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, math.cos(angle) * distance, 0.46, math.sin(angle) * distance), BackgroundTransparency = 1,
			}):Play()
		end

		-- 새 무기 이름이 쾅 하고 박힌다
		local title = makeLabel({
			Size = UDim2.new(0, 560, 0, 30), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.34, 0),
			Text = "✨ 무기 진화! ✨", Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = Color3.fromRGB(255, 225, 100), TextStrokeTransparency = 0.2, ZIndex = 7, TextTransparency = 1,
		}, root)
		local name = makeLabel({
			Size = UDim2.new(0, 640, 0, 80), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.46, 0),
			Text = newName, Font = Enum.Font.GothamBlack, TextSize = 54, TextColor3 = Color3.fromRGB(255, 245, 190), TextStrokeTransparency = 0, ZIndex = 7,
		}, root)
		local nameScale = create("UIScale", { Scale = 3 }, name)
		TweenService:Create(nameScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(title, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
		local sub = makeLabel({
			Size = UDim2.new(0, 560, 0, 26), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.56, 0),
			Text = string.format("%d번째 무기  ·  무기가 더 강해졌어요!", newIndex), Font = Enum.Font.GothamBold, TextSize = 16,
			TextColor3 = Color3.fromRGB(215, 215, 235), TextStrokeTransparency = 0.4, ZIndex = 7, TextTransparency = 1,
		}, root)
		task.delay(0.5, function() if sub.Parent then TweenService:Create(sub, TweenInfo.new(0.4), { TextTransparency = 0 }):Play() end end)
		task.delay(0.3, function() shake(0.6) end)
		pause(2.6)
		spinning = false
		TweenService:Create(root, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		for _, child in ipairs(root:GetDescendants()) do
			if child:IsA("TextLabel") then TweenService:Create(child, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play() end
		end
		task.wait(0.45)
		root:Destroy()
		playing = false
	end

	local function tierIndexNow()
		return Config.GetWeaponTierIndex(player:GetAttribute("WeaponLevel") or 0)
	end
	task.defer(function()
		while player.Parent and player:GetAttribute("WeaponLevel") == nil do task.wait(0.5) end
		shownTier = tierIndexNow()
		player:GetAttributeChangedSignal("WeaponLevel"):Connect(function()
			local now = tierIndexNow()
			local before = shownTier
			shownTier = now
			if before and now > before and Config.Weapon.Tiers[now] and Config.Weapon.Tiers[before] then
				task.delay(0.6, function() play(Config.Weapon.Tiers[before].Name, Config.Weapon.Tiers[now].Name, now) end)
			end
		end)
	end)
end

-- 대시 감지: 대시(속도 약 135)를 쓰면 서버에 알려 준다. 첫 위기 안내(대시 한 줄)를 이미 대시를 쓰는 사람에게는 안 띄우려는 용도.
do
	local lastReport = 0
	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local velocity = root.AssemblyLinearVelocity
		if Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 85 and os.clock() - lastReport > 3 then
			lastReport = os.clock()
			Remotes.Tutorial:FireServer("Dashed")
		end
	end)
end

-- 전투력 변화 표시: 강화 / 장비 교체 / 훈련 등으로 전투력이 바뀌면 "⚡ 전투력 +131 ▲  (1077 → 1208)" 이 잠깐 떠오른다.
-- (마을에서만. 짧은 시간에 여러 번 바뀌면 한 번에 합쳐서 보여 준다)
do
	local last = nil
	local from = nil
	local token = 0
	local joinedAt = os.clock()
	local function show(fromPower, toPower)
		local diff = toPower - fromPower
		if diff == 0 then return end
		local up = diff > 0
		local color = up and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(255, 130, 120)
		local holder = create("Frame", { Size = UDim2.new(0, 300, 0, 74), AnchorPoint = Vector2.new(0, 1), Position = gui.Parent:GetAttribute("UiCompact") and UDim2.new(0.5, -150, 0.4, 0) or UDim2.new(0, 14, 1, -(((player:GetAttribute("Zone") == "Dungeon") and 210 or 112) + 232)), BackgroundTransparency = 1, ZIndex = 60 }, gui)
		local main = makeLabel({
			Size = UDim2.new(1, 0, 0, 44), Text = string.format("⚡ 전투력 %s%d %s", up and "+" or "", diff, up and "▲" or "▼"), TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBlack, TextSize = 28, TextColor3 = color, TextStrokeTransparency = 0.2, ZIndex = 61, TextTransparency = 1,
		}, holder)
		local sub = makeLabel({
			Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 44), Text = string.format("%d  →  %d", fromPower, toPower),
			Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3, ZIndex = 61, TextTransparency = 1,
		}, holder)
		local scale = create("UIScale", { Scale = 0.6 }, holder)
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(main, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
		TweenService:Create(sub, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
		TweenService:Create(holder, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = holder.Position - UDim2.new(0, 0, 0, 36) }):Play()
		task.delay(1.3, function()
			TweenService:Create(main, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			TweenService:Create(sub, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(0.45)
			holder:Destroy()
		end)
		if up then SoundBank.Play(workspace, "Enh_Success", { Pitch = 1.25 }) end
	end
	player:GetAttributeChangedSignal("Power"):Connect(function()
		local power = player:GetAttribute("Power") or 0
		if last == nil or os.clock() - joinedAt < 4 then
			last = power
			return
		end
		if player:GetAttribute("Zone") ~= "Lobby" then
			last = power
			return
		end
		from = from or last
		last = power
		token += 1
		local mine = token
		task.delay(0.35, function() -- 연속으로 바뀌면 마지막 값만 한 번에
			if token ~= mine then return end
			local startPower = from
			from = nil
			if startPower and startPower ~= last then show(startPower, last) end
		end)
	end)
end
