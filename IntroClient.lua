-- IntroClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: IntroClient)
-- 처음 접속(레벨 1 / 경험치 0 / 무기 +0 / 튜토리얼 진행 중)한 사람에게만 나오는 약 15초짜리 오프닝:
--   마을 문 위에서 필드를 따라 맨 끝의 보스까지 빠르게 날아가고 -> 보스가 눈을 뜨고 에너지를 모아 쏘면 화면이 와장창 깨지고 -> 카메라가 뒤로 빠지며 하늘로 솟구쳐 게임 이름이 뜨고 -> 스폰으로 확 떨어지며 내 캐릭터가 나타난다.
--   * 화면을 누르거나 아무 키나 누르면 바로 건너뛴다. 끝나면 카메라는 원래대로 돌아온다.
--   * 오프닝이 도는 동안 player Attribute "IntroPlaying" 이 켜져 있어서 TutorialClient 가 미션 카드를 미룬다.
--   * 다른 화면(HUD)은 잠깐 꺼 두었다가 끝나면 원래 켜져 있던 것만 다시 켠다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INTRO_SOUND_ID = 132046898251409 -- 오프닝 음악 (로블록스 오디오 에셋 ID). 0 으로 바꾸면 이 음악은 끈다
local shownThisSession = false
local hiddenGuis = {} -- 오프닝 동안 잠깐 끈 화면들 (끝나거나 오류가 나면 이것만 다시 켠다)

local function isNewPlayer()
	return (player:GetAttribute("Level") or 1) <= 1 and (player:GetAttribute("XP") or 0) == 0
		and (player:GetAttribute("WeaponLevel") or 0) == 0 and player:GetAttribute("TutorialActive") == true
end

local function sfx(key, volume, pitch)
	pcall(function()
		local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
		if SoundBank.Has(key) then SoundBank.Play(SoundService, key, { Volume = volume or 1, Pitch = pitch }) end
	end)
end

-- 최후의 군주 모습 (Server/DoomScene.lua 의 buildDoomLord 와 같은 생김새를 연출용으로 옮긴 것: 내 화면에만 잠깐 만든다)
local function buildLord(parent, baseCF, S)
	local eyes = {}
	local function add(size, rel, color, material, transparency, shape)
		local part = Instance.new("Part")
		part.Size = size * S
		part.Color = color
		part.Material = material or Enum.Material.Metal
		part.Transparency = transparency or 0
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
		if shape then part.Shape = shape end
		part.CFrame = baseCF * (CFrame.new(rel.Position * S) * (rel - rel.Position))
		part.Parent = parent
		return part
	end
	local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
	local dark, steel, red = rgb(26, 12, 22), rgb(60, 52, 70), rgb(255, 50, 60)
	add(Vector3.new(12, 20, 7), CFrame.new(0, 0, 0), dark)
	add(Vector3.new(8, 6, 5), CFrame.new(0, -12, 0), dark)
	add(Vector3.new(4, 7, 3), CFrame.new(0, -18, 0), steel)
	local core = add(Vector3.new(5, 5, 5), CFrame.new(0, 4, -4.2) * CFrame.Angles(math.rad(45), math.rad(45), 0), red, Enum.Material.Neon)
	add(Vector3.new(11, 1, 1), CFrame.new(0, 9, -3.8), steel)
	add(Vector3.new(11, 1, 1), CFrame.new(0, -3, -3.8), steel)
	add(Vector3.new(6.5, 6.5, 6.5), CFrame.new(0, 14, 0), rgb(18, 8, 16))
	for _, side in ipairs({ -1, 1 }) do
		eyes[#eyes + 1] = add(Vector3.new(3, 0.9, 0.6), CFrame.new(side * 1.7, 14.6, -3.3) * CFrame.Angles(0, 0, math.rad(side * 18)), rgb(255, 230, 90), Enum.Material.Neon)
		add(Vector3.new(1.4, 13, 1.4), CFrame.new(side * 4.2, 21, 0) * CFrame.Angles(0, 0, math.rad(side * -28)), rgb(230, 220, 205), Enum.Material.SmoothPlastic)
		add(Vector3.new(1.2, 7, 1.2), CFrame.new(side * 9, 27, 0) * CFrame.Angles(0, 0, math.rad(side * -58)), rgb(230, 220, 205), Enum.Material.SmoothPlastic)
		add(Vector3.new(8, 4, 8), CFrame.new(side * 9.5, 9, 0), steel)
		for k = 0, 2 do
			add(Vector3.new(1.4, 8 - k * 1.5, 1.4), CFrame.new(side * (7.5 + k * 2.2), 13 + k * 0.8, 0) * CFrame.Angles(0, 0, math.rad(side * (-15 - k * 14))), red, Enum.Material.Neon)
		end
		add(Vector3.new(4, 16, 4), CFrame.new(side * 12, -1, 0), dark)
		add(Vector3.new(7.5, 7.5, 7.5), CFrame.new(side * 12, -11, -1), steel)
		add(Vector3.new(8, 0.8, 8), CFrame.new(side * 12, -8, -1), red, Enum.Material.Neon)
		for k = 0, 3 do
			add(Vector3.new(1, 22 - k * 3, 5), CFrame.new(side * (8 + k * 3.4), 6 + k * 0.5, 7) * CFrame.Angles(math.rad(-10), math.rad(side * -12), math.rad(side * (-22 - k * 14))), rgb(90, 20, 40), Enum.Material.Metal)
			add(Vector3.new(0.4, 20 - k * 3, 1.2), CFrame.new(side * (8 + k * 3.4), 6 + k * 0.5, 4.6) * CFrame.Angles(math.rad(-10), math.rad(side * -12), math.rad(side * (-22 - k * 14))), red, Enum.Material.Neon, 0.15)
		end
	end
	local gold, cloak = rgb(150, 116, 60), rgb(70, 14, 26)
	add(Vector3.new(8, 1.2, 8), CFrame.new(0, 17.6, 0), gold, Enum.Material.Metal)
	for k = 0, 6 do
		local a = k / 7 * math.pi * 2
		add(Vector3.new(0.8, 3.2 + (k % 2) * 1.6, 0.8), CFrame.new(math.cos(a) * 3.4, 19.2 + (k % 2) * 0.8, math.sin(a) * 3.4) * CFrame.Angles(math.sin(a) * 0.25, 0, -math.cos(a) * 0.25), gold, Enum.Material.Metal)
	end
	for k = -1, 1 do
		add(Vector3.new(5.5, 26 - math.abs(k) * 4, 0.5), CFrame.new(k * 5, -4 - math.abs(k) * 2, 5.6) * CFrame.Angles(math.rad(12), 0, math.rad(k * 8)), cloak, Enum.Material.Fabric)
	end
	for k = -1, 1 do
		add(Vector3.new(3.6, 6, 0.8), CFrame.new(k * 3.6, -14, -3) * CFrame.Angles(math.rad(-10), 0, math.rad(k * -6)), steel, Enum.Material.Metal)
	end
	for k = 0, 2 do
		add(Vector3.new(10 - k * 1.5, 0.8, 1), CFrame.new(0, 6 - k * 2.4, -3.9), rgb(40, 34, 48), Enum.Material.Metal)
	end
	for _, side in ipairs({ -1, 1 }) do
		add(Vector3.new(3, 11, 3), CFrame.new(side * 10.5, -6, -2.5) * CFrame.Angles(math.rad(-25), 0, math.rad(side * 20)), dark)
		add(Vector3.new(5, 5, 5), CFrame.new(side * 13, -12, -6), steel)
		add(Vector3.new(1, 6, 1), CFrame.new(side * 13, -16, -6.5) * CFrame.Angles(0, 0, math.rad(side * 10)), gold, Enum.Material.Metal)
	end
	add(Vector3.new(0.7, 30, 30), CFrame.new(0, 15, 8) * CFrame.Angles(0, math.rad(90), 0), red, Enum.Material.Neon, 0.25, Enum.PartType.Cylinder)
	add(Vector3.new(0.5, 38, 38), CFrame.new(0, 15, 9) * CFrame.Angles(0, math.rad(90), 0), rgb(255, 150, 60), Enum.Material.Neon, 0.5, Enum.PartType.Cylinder)
	for k = 1, 4 do -- 몸 주변에 떠 있는 칼날 (연출에서는 가만히)
		local angle = k * math.pi / 2
		add(Vector3.new(1.2, 8, 2.4), CFrame.new(math.cos(angle) * 16, 4, math.sin(angle) * 8) * CFrame.Angles(0, -angle, math.rad(20)), red, Enum.Material.Neon, 0.1)
	end
	return eyes, core
end

local function play()
	local camera = workspace.CurrentCamera
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not root or not camera then return end
	player:SetAttribute("IntroPlaying", true)
	local Config = require(ReplicatedStorage:WaitForChild("Config"))
	local F = Config.Field

	-- 오프닝 화면: 검은 막 + 위아래 검은 띠 + 제목 + 유리 (금 / 조각)
	local gui = Instance.new("ScreenGui")
	gui.Name = "IntroGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.Parent = playerGui
	local function frame(props)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		for k, v in pairs(props) do f[k] = v end
		f.Parent = gui
		return f
	end
	local veil = frame({ Size = UDim2.new(1, 0, 1, 0), ZIndex = 5 })
	local flash = frame({ Size = UDim2.new(1, 0, 1, 0), ZIndex = 12, BackgroundColor3 = Color3.fromRGB(255, 140, 90), BackgroundTransparency = 1 })
	local topBar = frame({ Size = UDim2.new(1, 0, 0, 0), ZIndex = 4 })
	local bottomBar = frame({ Size = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), ZIndex = 4 })
	local glass = Instance.new("Folder") -- 유리 조각들을 담아 두는 곳 (금 + 조각 한 번에 치우기 좋게)
	glass.Name = "Glass"
	glass.Parent = gui
	local function text(props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.TextTransparency = 1
		l.TextStrokeTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Font = Enum.Font.GothamBlack
		l.ZIndex = 11
		for k, v in pairs(props) do l[k] = v end
		l.Parent = gui
		return l
	end
	local title = text({ Size = UDim2.new(1, 0, 0, 80), Position = UDim2.new(0.5, 0, 0.47, 0), TextSize = 66, TextColor3 = Color3.fromRGB(242, 228, 196), Text = "GEAR RUSH" })
	local subtitle = text({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0.5, 0, 0.47, 56), TextSize = 17, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(190, 175, 150), Text = "D U N G E O N   S H O O T E R" })

	-- 날아가는 동안 보이는 "여정" 표시: 지나가는 구역 이름 + 아래 검은 띠 속 진행 막대 (끝에는 ☠). 이걸 다 뚫고 가야 보스가 있다는 걸 보여 준다
	local zoneLabel = text({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0.5, 0, 0.84, 0), TextSize = 22, TextColor3 = Color3.fromRGB(236, 226, 200), Text = "" })
	local barBack = frame({ Size = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.955, 0), BackgroundColor3 = Color3.fromRGB(70, 66, 78), BackgroundTransparency = 1, ZIndex = 6 })
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BorderSizePixel = 0
	barFill.BackgroundColor3 = Color3.fromRGB(226, 176, 96)
	barFill.BackgroundTransparency = 1
	barFill.ZIndex = 7
	barFill.Parent = barBack
	local ticks = {}
	for index = 1, F.ZoneCount - 1 do -- 구역 경계 눈금
		local tick = Instance.new("Frame")
		tick.Size = UDim2.new(0, 2, 0, 10)
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.new((F.ZoneEnd(index) - F.StartX) / F.TotalLength(), 0, 0.5, 0)
		tick.BorderSizePixel = 0
		tick.BackgroundColor3 = Color3.fromRGB(150, 144, 160)
		tick.BackgroundTransparency = 1
		tick.ZIndex = 7
		tick.Parent = barBack
		ticks[#ticks + 1] = tick
	end
	local skull = text({ Size = UDim2.new(0, 40, 0, 26), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.75, 12, 0.955, 0), TextSize = 22, TextColor3 = Color3.fromRGB(230, 90, 90), Text = "☠" })
	local lordLabel = text({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0.5, 0, 0.84, 0), TextSize = 26, TextColor3 = Color3.fromRGB(235, 90, 90), Text = "☠  THE FINAL LORD  ☠" })

	-- 다른 화면 잠깐 끄기 (끝나면 원래 켜져 있던 것만 복구)
	for _, other in ipairs(playerGui:GetChildren()) do
		if other:IsA("ScreenGui") and other ~= gui and other.Enabled then
			hiddenGuis[#hiddenGuis + 1] = other
			other.Enabled = false
		end
	end

	-- 내 캐릭터는 마지막에 하늘에서 떨어지며 "나타난다": 그때까지 내 화면에서만 투명하게 (머리 위 이름표도 잠깐 끈다)
	local bodyParts, billboards = {}, {}
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") then
			bodyParts[#bodyParts + 1] = item
		elseif item:IsA("BillboardGui") and item.Enabled then
			billboards[#billboards + 1] = item
			item.Enabled = false
		end
	end
	local function setBodyAlpha(alpha) -- 0 = 보임, 1 = 안 보임
		for _, item in ipairs(bodyParts) do
			if item.Parent then item.LocalTransparencyModifier = alpha end
		end
	end
	setBodyAlpha(1)

	-- 연출 전용 부품(내 화면에만 보인다): 보스 / 에너지 구슬 / 광선 / 착지 빛
	local props = Instance.new("Folder")
	props.Name = "IntroProps"
	props.Parent = workspace

	-- 오프닝 음악: 불러와지면 재생하고, 건너뛰거나 끝나면 부드럽게 줄인다 (못 불러오면 조용히 넘어간다)
	local music
	if INTRO_SOUND_ID ~= 0 then
		music = Instance.new("Sound")
		music.Name = "IntroMusic"
		music.SoundId = "rbxassetid://" .. INTRO_SOUND_ID
		music.Volume = 0.7
		music.Parent = SoundService
	end

	-- 날아가는 동안만 안개를 걷고 노출을 조금 올려서 아래 지형이 더 보이게 한다 (끝나면 원래대로)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local saved = {
		Exposure = Lighting.ExposureCompensation,
		Density = atmosphere and atmosphere.Density, Haze = atmosphere and atmosphere.Haze,
	}
	TweenService:Create(Lighting, TweenInfo.new(0.8), { ExposureCompensation = saved.Exposure + 0.45 }):Play()
	if atmosphere then TweenService:Create(atmosphere, TweenInfo.new(0.8), { Density = 0.05, Haze = 0 }):Play() end

	local finished = false
	local connection
	local function finish()
		if finished then return end
		finished = true
		if connection then connection:Disconnect() end
		pcall(function()
			TweenService:Create(Lighting, TweenInfo.new(1.0), { ExposureCompensation = saved.Exposure }):Play()
			if atmosphere and saved.Density then TweenService:Create(atmosphere, TweenInfo.new(1.0), { Density = saved.Density, Haze = saved.Haze }):Play() end
		end)
		if music then
			local fading = music
			music = nil
			TweenService:Create(fading, TweenInfo.new(0.7), { Volume = 0 }):Play()
			task.delay(0.8, function() fading:Destroy() end)
		end
		pcall(function()
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
		end)
		setBodyAlpha(0)
		for _, board in ipairs(billboards) do
			if board.Parent then board.Enabled = true end
		end
		for _, other in ipairs(hiddenGuis) do
			if other.Parent then other.Enabled = true end
		end
		table.clear(hiddenGuis)
		player:SetAttribute("IntroPlaying", nil)
		props:Destroy()
		TweenService:Create(veil, TweenInfo.new(0.01), { BackgroundTransparency = 1 }):Play()
		task.delay(0.1, function() gui:Destroy() end)
	end

	-- 건너뛰기 (시작하고 0.7초 뒤부터)
	local startedAt = os.clock()
	connection = UserInputService.InputBegan:Connect(function(input)
		if os.clock() - startedAt < 0.7 then return end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Keyboard then
			finish()
		end
	end)

	-- 보스 자리: 필드 맨 끝 (최후의 군주 포탈 뒤), 마을 쪽(서쪽)을 바라본다. 실제 보스와 같은 모습
	local S = 2.4
	local bossX = F.ZoneEnd(F.ZoneCount) + 6
	local groundY = 0
	do
		local hit = workspace:Raycast(Vector3.new(bossX, 600, 0), Vector3.new(0, -1200, 0))
		if hit then groundY = hit.Position.Y end
	end
	local bodyPos = Vector3.new(bossX, groundY + 21.5 * S + 2, 0)
	local bossCF = CFrame.lookAt(bodyPos, bodyPos + Vector3.new(-1, 0, 0)) -- 몸 앞쪽(-Z)이 서쪽(마을)을 본다
	local eyes = buildLord(props, bossCF, S)
	for _, eye in ipairs(eyes) do eye.Transparency = 1 end -- 눈은 감고 있다가 뜬다
	local face = bodyPos + Vector3.new(0, 14 * S, 0)

	-- 카메라 준비: 마을 동쪽 문 위에서 필드를 따라 동쪽을 본다
	local startPos = Vector3.new(110, 70, 0)
	local arrivePos = Vector3.new(bossX - 250, groundY + 120, 0)
	local arriveLook = face + Vector3.new(0, -8, 0)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 66
	camera.CFrame = CFrame.lookAt(startPos, startPos + Vector3.new(1000, -70, 0))
	TweenService:Create(topBar, TweenInfo.new(0.7), { Size = UDim2.new(1, 0, 0.1, 0) }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(0.7), { Size = UDim2.new(1, 0, 0.1, 0) }):Play()
	TweenService:Create(veil, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
	if music then
		local loading = music
		task.spawn(function()
			local waited = os.clock()
			while not loading.IsLoaded and os.clock() - waited < 3 do task.wait(0.1) end
			if not finished and loading.Parent and loading.IsLoaded then loading:Play() end
		end)
	end
	sfx("Aug_Flame", 1.0, 0.7) -- 바람을 가르는 소리
	task.wait(0.6)
	if finished then return end

	-- 1) 마을에서 보스까지 한 번에 날아간다 (빠르게 가속했다가 보스 앞에서 멈춘다. 시야각이 넓어졌다가 좁아진다)
	local FLY_TIME = 8.0 -- 필드가 잘 보이도록 천천히 (예전 3.2초는 너무 빨라서 지나가는 필드가 흐릿했다)
	TweenService:Create(camera, TweenInfo.new(FLY_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = CFrame.lookAt(arrivePos, arriveLook) }):Play()
	TweenService:Create(camera, TweenInfo.new(2.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { FieldOfView = 82 }):Play()
	task.delay(FLY_TIME - 2.4, function()
		if not finished then TweenService:Create(camera, TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { FieldOfView = 58 }):Play() end
	end)
	task.delay(2.5, function() if not finished then sfx("Aug_Flame", 0.8, 0.6) end end)
	task.delay(5.2, function() if not finished then sfx("Aug_Flame", 0.7, 0.5) end end)
	-- 날아가는 동안: 진행 막대가 차오르고, 구역을 지날 때마다 구역 이름이 뜬다
	TweenService:Create(barBack, TweenInfo.new(0.6), { BackgroundTransparency = 0.2 }):Play()
	TweenService:Create(barFill, TweenInfo.new(0.6), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(skull, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
	for _, tick in ipairs(ticks) do TweenService:Create(tick, TweenInfo.new(0.6), { BackgroundTransparency = 0.2 }):Play() end
	local flyStart = os.clock()
	local lastZone = 0
	while os.clock() - flyStart < FLY_TIME + 0.1 and not finished do
		local x = camera.CFrame.Position.X
		barFill.Size = UDim2.new(math.clamp((x - F.StartX) / F.TotalLength() + 0.02, 0, 1), 0, 1, 0)
		local zone = x < F.StartX and 0 or F.ZoneOfX(x)
		if zone ~= lastZone and zone >= 1 then
			lastZone = zone
			zoneLabel.Text = string.format("ZONE %d  ·  %s   %s", zone, F.ZoneNames[zone] or "", string.rep("☠", zone))
			zoneLabel.TextTransparency = 0.6
			TweenService:Create(zoneLabel, TweenInfo.new(0.25), { TextTransparency = 0, TextStrokeTransparency = 0.6 }):Play()
			task.delay(0.8, function()
				if not finished and lastZone == zone then
					TweenService:Create(zoneLabel, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
				end
			end)
		end
		RunService.RenderStepped:Wait()
	end
	if finished then return end
	TweenService:Create(zoneLabel, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	-- 2) 보스가 눈을 뜬다 -> 에너지를 모은다 (구슬이 커지고 화면이 떨린다)
	sfx("Lord_Voice", 0.9)
	TweenService:Create(lordLabel, TweenInfo.new(0.6), { TextTransparency = 0, TextStrokeTransparency = 0.5 }):Play()
	for _, eye in ipairs(eyes) do
		TweenService:Create(eye, TweenInfo.new(0.7), { Transparency = 0 }):Play()
	end
	task.wait(0.7)
	if finished then return end
	sfx("Lord_Charge", 1.0)
	local orb = Instance.new("Part")
	orb.Shape = Enum.PartType.Ball
	orb.Anchored, orb.CanCollide, orb.CanQuery, orb.CanTouch, orb.CastShadow = true, false, false, false, false
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(255, 110, 70)
	orb.Transparency = 0.25
	orb.Size = Vector3.new(3, 3, 3)
	orb.Position = face + Vector3.new(-34, -6, 0)
	orb.Parent = props
	TweenService:Create(orb, TweenInfo.new(1.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(80, 80, 80), Transparency = 0.1 }):Play()
	local chargeStart = os.clock()
	local baseCFrame = CFrame.lookAt(arrivePos, arriveLook)
	while os.clock() - chargeStart < 1.7 and not finished do
		local power = (os.clock() - chargeStart) / 1.7
		local jitter = 0.15 + power * 1.2
		camera.CFrame = baseCFrame * CFrame.new(math.random() * jitter - jitter / 2, math.random() * jitter - jitter / 2, -power * 10)
		RunService.RenderStepped:Wait()
	end
	if finished then return end

	-- 3) 발사: 광선이 화면으로 날아오고, 화면이 깨진다 (유리 판 + 금 -> 와장창 조각으로 흩어진다)
	for _, item in ipairs({ lordLabel, skull }) do TweenService:Create(item, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play() end
	for _, item in ipairs({ barBack, barFill }) do TweenService:Create(item, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play() end
	for _, tick in ipairs(ticks) do TweenService:Create(tick, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play() end
	sfx("Lord_Blast", 1.0)
	sfx("Ult_Finale", 0.8)
	local distance = (arrivePos - orb.Position).Magnitude
	local beam = Instance.new("Part")
	beam.Anchored, beam.CanCollide, beam.CanQuery, beam.CanTouch, beam.CastShadow = true, false, false, false, false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 150, 100)
	beam.Transparency = 0.1
	beam.Size = Vector3.new(60, 60, distance)
	beam.CFrame = CFrame.lookAt((orb.Position + arrivePos) / 2, arrivePos)
	beam.Parent = props
	flash.BackgroundTransparency = 0.25
	TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	local cols, rows = 12, 7
	local tiles = {}
	for cx = 0, cols - 1 do
		for cy = 0, rows - 1 do
			local tile = Instance.new("Frame")
			tile.BorderSizePixel = 0
			tile.AnchorPoint = Vector2.new(0.5, 0.5)
			local w, h = 1 / cols, 1 / rows
			tile.Size = UDim2.new(w * (1.05 + math.random() * 0.12), 0, h * (1.05 + math.random() * 0.12), 0)
			tile.Position = UDim2.new((cx + 0.5) * w, 0, (cy + 0.5) * h, 0)
			tile.Rotation = math.random(-4, 4)
			tile.BackgroundColor3 = Color3.fromRGB(205, 222, 240)
			tile.BackgroundTransparency = 0.84 + math.random() * 0.06
			tile.ZIndex = 9
			tile.Parent = glass
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(240, 246, 255)
			stroke.Thickness = 1.3
			stroke.Transparency = 0.35
			stroke.Parent = tile
			tiles[#tiles + 1] = { Frame = tile, Stroke = stroke, X = (cx + 0.5) * w, Y = (cy + 0.5) * h }
		end
	end
	local angle0 = math.random() * 40
	for i = 1, 14 do -- 금: 가운데에서 사방으로
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0)
		line.Position = UDim2.new(0.5, 0, 0.5, 0)
		line.Size = UDim2.new(0, 2 + math.random() * 2, 0.3 + math.random() * 0.55, 0)
		line.Rotation = angle0 + i * 25.7 + math.random(-8, 8) + 180
		line.BackgroundColor3 = Color3.fromRGB(240, 240, 250)
		line.BackgroundTransparency = 0.05
		line.BorderSizePixel = 0
		line.ZIndex = 10
		line.Parent = glass
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 1
		stroke.Parent = line
	end
	sfx("Shield_Block", 1.0, 1.7)
	task.delay(0.12, function() sfx("Shield_Block", 0.9, 1.3) end)
	local blastStart = os.clock()
	while os.clock() - blastStart < 0.5 and not finished do
		local k = 1 - (os.clock() - blastStart) / 0.5
		local jitter = 3 * k
		camera.CFrame = baseCFrame * CFrame.new(math.random() * jitter - jitter / 2, math.random() * jitter - jitter / 2, -10)
		RunService.RenderStepped:Wait()
	end
	if finished then return end

	-- 4) 와장창: 유리가 사방으로 터져 아래로 쏟아진다 + 카메라가 뒤로 쑥 빠지며 하늘로 솟구친다
	sfx("Shield_Block", 1.0, 2.0)
	sfx("Boom", 0.9, 1.1)
	sfx("Shield_Block", 0.9, 1.5)
	for _, tile in ipairs(tiles) do
		local dx, dy = tile.X - 0.5, tile.Y - 0.5
		local push = 1.4 + math.random() * 1.6
		local delay = math.random() * 0.22
		local duration = 1.0 + math.random() * 0.6
		task.delay(delay, function()
			if finished then return end
			local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(tile.Frame, info, {
				Position = UDim2.new(0.5 + dx * push * 2, 0, 0.5 + dy * push * 2 + 1.1 + math.random() * 0.6, 0),
				Rotation = tile.Frame.Rotation + math.random(-260, 260),
				BackgroundTransparency = 1,
			}):Play()
			TweenService:Create(tile.Stroke, info, { Transparency = 1 }):Play()
		end)
	end
	for _, item in ipairs(glass:GetChildren()) do -- 금은 먼저 사라진다
		if item:IsA("Frame") and item.ZIndex == 10 then
			TweenService:Create(item, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			local stroke = item:FindFirstChildOfClass("UIStroke")
			if stroke then TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play() end
		end
	end
	local spawnPos = root.Position
	local look = root.CFrame.LookVector
	local skyPos = spawnPos + Vector3.new(210, 600, 0)
	local skyLook = CFrame.lookAt(skyPos, spawnPos)
	sfx("Aug_Flame", 1.0, 0.5)
	TweenService:Create(camera, TweenInfo.new(2.1, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut), { CFrame = skyLook }):Play()
	TweenService:Create(camera, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { FieldOfView = 110 }):Play()
	task.delay(1.0, function()
		if not finished then TweenService:Create(camera, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { FieldOfView = 72 }):Play() end
	end)
	task.delay(0.9, function() if not finished then props:ClearAllChildren() end end) -- 보스는 멀어진 뒤에 치운다
	task.wait(1.4)
	if finished then return end
	sfx("Dungeon_Start", 0.9, 0.8)
	TweenService:Create(title, TweenInfo.new(0.8), { TextTransparency = 0, TextStrokeTransparency = 0.6 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(1.1), { TextTransparency = 0.1 }):Play()
	task.wait(0.7)
	if finished then return end

	-- 5) 하늘 높은 곳에서 잠깐 멈췄다가 -> 마을 스폰으로 확 떨어지며 캐릭터가 나타난다
	local homePose = CFrame.lookAt(spawnPos - look * 14 + Vector3.new(0, 7, 0), spawnPos + look * 30 + Vector3.new(0, 4, 0))
	TweenService:Create(camera, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = CFrame.lookAt(skyPos - Vector3.new(30, 60, 0), spawnPos) }):Play() -- 정점에서 살짝 다가온다
	task.wait(1.2)
	if finished then return end
	local pillar = Instance.new("Part") -- 하늘에서 스폰까지 내려꽂히는 부드러운 빛줄기
	pillar.Anchored, pillar.CanCollide, pillar.CanQuery, pillar.CanTouch, pillar.CastShadow = true, false, false, false, false
	pillar.Material = Enum.Material.Neon
	pillar.Color = Color3.fromRGB(150, 215, 255)
	pillar.Transparency = 0.55
	pillar.Size = Vector3.new(5, 700, 5)
	pillar.Position = spawnPos + Vector3.new(0, 330, 0)
	pillar.Parent = props
	sfx("Aug_Flame", 1.0, 0.45)
	TweenService:Create(title, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
	TweenService:Create(camera, TweenInfo.new(0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = homePose, FieldOfView = 70 }):Play()
	task.wait(0.95)
	if finished then return end

	-- 착지: 충격 고리 + 빛줄기가 사라지며 캐릭터가 나타난다
	sfx("Boom", 0.8, 0.9)
	sfx("LevelUp", 0.6, 0.8)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(150, 215, 255)
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.4, 4, 4)
	ring.CFrame = CFrame.new(spawnPos - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = props
	TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.4, 60, 60), Transparency = 1 }):Play()
	TweenService:Create(pillar, TweenInfo.new(0.7), { Transparency = 1, Size = Vector3.new(0.5, 700, 0.5) }):Play()
	TweenService:Create(topBar, TweenInfo.new(0.9), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(0.9), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	local landStart = os.clock()
	while os.clock() - landStart < 0.8 and not finished do
		local k = (os.clock() - landStart) / 0.8
		setBodyAlpha(math.max(0, 1 - k * 1.6)) -- 몸이 서서히 나타난다
		local jitter = 1.6 * (1 - k)
		camera.CFrame = homePose * CFrame.new(math.random() * jitter - jitter / 2, math.random() * jitter - jitter / 2, 0)
		RunService.RenderStepped:Wait()
	end
	setBodyAlpha(0)
	sfx("Reel_Stop", 0.8, 0.9)
	task.wait(0.4)
	finish()
end

task.spawn(function()
	local waited = os.clock()
	while player:GetAttribute("Zone") ~= "Lobby" and os.clock() - waited < 25 do task.wait(0.25) end
	if player:GetAttribute("Zone") ~= "Lobby" then return end
	-- 서버가 레벨 / 튜토리얼 값을 채울 때까지 잠깐 기다린다 (최대 5초)
	waited = os.clock()
	while (player:GetAttribute("Level") == nil or player:GetAttribute("TutorialActive") == nil) and os.clock() - waited < 5 do task.wait(0.25) end
	if shownThisSession or not isNewPlayer() then return end
	shownThisSession = true
	local ok, err = pcall(play)
	if not ok then
		warn("[오프닝] 오류: " .. tostring(err))
		pcall(function()
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
			workspace.CurrentCamera.FieldOfView = 70
		end)
		player:SetAttribute("IntroPlaying", nil)
		local leftover = playerGui:FindFirstChild("IntroGui")
		if leftover then leftover:Destroy() end
		for _, other in ipairs(hiddenGuis) do
			if other.Parent then other.Enabled = true end
		end
		table.clear(hiddenGuis)
	end
end)
