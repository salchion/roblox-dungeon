-- IntroClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: IntroClient)
-- 처음 접속(레벨 1 / 경험치 0 / 무기 +0 / 튜토리얼 진행 중)한 사람에게만 나오는 약 6초짜리 오프닝:
--   마을 문 위에서 필드를 따라 맨 끝의 보스까지 빠르게 날아가고 -> 보스가 눈을 뜨고 에너지를 모아 쏘면 화면이 깨지고 -> 게임 이름이 뜬 뒤 -> 스폰의 내 캐릭터 뒤(로비)로 이어진다.
--   * 화면을 누르거나 아무 키나 누르면 바로 건너뛴다. 끝나면 카메라는 원래대로 돌아온다.
--   * 오프닝이 도는 동안 player Attribute "IntroPlaying" 이 켜져 있어서 TutorialClient 가 미션 카드를 미룬다.
--   * 다른 화면(HUD)은 잠깐 꺼 두었다가 끝나면 원래 켜져 있던 것만 다시 켠다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

local function play()
	local camera = workspace.CurrentCamera
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not root or not camera then return end
	player:SetAttribute("IntroPlaying", true)
	local Config = require(ReplicatedStorage:WaitForChild("Config"))
	local F = Config.Field

	-- 오프닝 화면: 검은 막 + 위아래 검은 띠 + 제목 + 금(균열)
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
	local flash = frame({ Size = UDim2.new(1, 0, 1, 0), ZIndex = 8, BackgroundColor3 = Color3.fromRGB(255, 140, 90), BackgroundTransparency = 1 })
	local topBar = frame({ Size = UDim2.new(1, 0, 0, 0), ZIndex = 4 })
	local bottomBar = frame({ Size = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), ZIndex = 4 })
	local function text(props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.TextTransparency = 1
		l.TextStrokeTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Font = Enum.Font.GothamBlack
		l.ZIndex = 6
		for k, v in pairs(props) do l[k] = v end
		l.Parent = gui
		return l
	end
	local title = text({ Size = UDim2.new(1, 0, 0, 80), Position = UDim2.new(0.5, 0, 0.47, 0), TextSize = 66, TextColor3 = Color3.fromRGB(242, 228, 196), Text = "GEAR RUSH" })
	local subtitle = text({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0.5, 0, 0.47, 56), TextSize = 17, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(190, 175, 150), Text = "D U N G E O N   S H O O T E R" })

	-- 다른 화면 잠깐 끄기 (끝나면 원래 켜져 있던 것만 복구)
	for _, other in ipairs(playerGui:GetChildren()) do
		if other:IsA("ScreenGui") and other ~= gui and other.Enabled then
			hiddenGuis[#hiddenGuis + 1] = other
			other.Enabled = false
		end
	end

	-- 연출 전용 부품(내 화면에만 보인다): 필드 끝의 보스 모습 + 에너지 구슬 / 광선
	local props = Instance.new("Folder")
	props.Name = "IntroProps"
	props.Parent = workspace

	local finished = false
	local connection
	local function finish()
		if finished then return end
		finished = true
		if connection then connection:Disconnect() end
		pcall(function()
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
		end)
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

	-- 보스 자리: 필드 맨 끝 (최후의 군주 포탈 뒤), 마을 쪽(서쪽)을 바라본다
	local bossX = F.ZoneEnd(F.ZoneCount) + 6
	local groundY = 0
	do
		local hit = workspace:Raycast(Vector3.new(bossX, 600, 0), Vector3.new(0, -1200, 0))
		if hit then groundY = hit.Position.Y end
	end
	local B = Vector3.new(bossX, groundY, 0)
	local void, void2 = Color3.fromRGB(26, 20, 34), Color3.fromRGB(40, 30, 48)
	local function piece(name, size, offset, color, shape, rotation, material)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
		part.Material = material or Enum.Material.SmoothPlastic
		part.Color = color
		part.Size = size
		if shape then part.Shape = shape end
		part.CFrame = CFrame.new(B + offset) * (rotation or CFrame.new())
		part.Parent = props
		return part
	end
	piece("Legs", Vector3.new(50, 60, 70), Vector3.new(0, 30, 0), void)
	piece("Torso", Vector3.new(44, 64, 80), Vector3.new(0, 90, 0), void2)
	piece("ShoulderL", Vector3.new(24, 24, 26), Vector3.new(0, 112, -52), void, Enum.PartType.Ball)
	piece("ShoulderR", Vector3.new(24, 24, 26), Vector3.new(0, 112, 52), void, Enum.PartType.Ball)
	piece("Head", Vector3.new(26, 26, 26), Vector3.new(-4, 148, 0), void2, Enum.PartType.Ball)
	for i = -2, 2 do
		piece("Crown", Vector3.new(4, 24 - math.abs(i) * 4, 4), Vector3.new(-4, 168, i * 6), void, nil, CFrame.Angles(math.rad(i * 8), 0, 0))
	end
	piece("Cape", Vector3.new(6, 100, 110), Vector3.new(24, 90, 0), Color3.fromRGB(20, 14, 26))
	local eyes = {}
	for _, z in ipairs({ -5, 5 }) do
		eyes[#eyes + 1] = piece("Eye", Vector3.new(2.5, 2.5, 5), Vector3.new(-18, 151, z), Color3.fromRGB(120, 30, 40), nil, nil, Enum.Material.Neon)
	end
	piece("Halo", Vector3.new(3, 90, 90), Vector3.new(24, 150, 0), Color3.fromRGB(100, 36, 56), Enum.PartType.Cylinder, CFrame.Angles(0, 0, math.pi / 2)).Transparency = 0.55
	local face = B + Vector3.new(-20, 150, 0)

	-- 카메라 준비: 마을 동쪽 문 위에서 필드를 따라 동쪽을 본다
	local startPos = Vector3.new(110, 100, 0)
	local arrivePos = Vector3.new(bossX - 215, groundY + 165, 0)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 66
	camera.CFrame = CFrame.lookAt(startPos, startPos + Vector3.new(1000, -30, 0))
	TweenService:Create(topBar, TweenInfo.new(0.7), { Size = UDim2.new(1, 0, 0.1, 0) }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(0.7), { Size = UDim2.new(1, 0, 0.1, 0) }):Play()
	TweenService:Create(veil, TweenInfo.new(0.9), { BackgroundTransparency = 1 }):Play()
	sfx("Aug_Flame", 1.0, 0.7) -- 바람을 가르는 소리
	task.wait(0.6)
	if finished then return end

	-- 1) 마을에서 보스까지 한 번에 날아간다 (빠르게 가속했다가 보스 앞에서 멈춘다. 시야각이 넓어졌다가 좁아진다)
	TweenService:Create(camera, TweenInfo.new(3.2, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut), {
		CFrame = CFrame.lookAt(arrivePos, face + Vector3.new(0, -4, 0)),
	}):Play()
	TweenService:Create(camera, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { FieldOfView = 100 }):Play()
	task.delay(1.4, function()
		if not finished then TweenService:Create(camera, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { FieldOfView = 58 }):Play() end
	end)
	task.delay(1.5, function() if not finished then sfx("Aug_Flame", 0.9, 0.55) end end)
	task.wait(3.3)
	if finished then return end

	-- 2) 보스가 눈을 뜬다 -> 에너지를 모은다 (구슬이 커지고 화면이 떨린다)
	sfx("Lord_Voice", 0.9)
	for _, eye in ipairs(eyes) do
		TweenService:Create(eye, TweenInfo.new(0.8), { Color = Color3.fromRGB(255, 80, 70) }):Play()
	end
	task.wait(0.6)
	if finished then return end
	sfx("Lord_Charge", 1.0)
	local orb = Instance.new("Part")
	orb.Shape = Enum.PartType.Ball
	orb.Anchored, orb.CanCollide, orb.CanQuery, orb.CanTouch, orb.CastShadow = true, false, false, false, false
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(255, 110, 70)
	orb.Transparency = 0.25
	orb.Size = Vector3.new(3, 3, 3)
	orb.Position = face + Vector3.new(-30, -4, 0)
	orb.Parent = props
	TweenService:Create(orb, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(70, 70, 70), Transparency = 0.1 }):Play()
	local chargeStart = os.clock()
	local baseCFrame = CFrame.lookAt(arrivePos, face + Vector3.new(0, -4, 0))
	while os.clock() - chargeStart < 1.6 and not finished do
		local power = (os.clock() - chargeStart) / 1.6
		local jitter = 0.15 + power * 1.1
		camera.CFrame = baseCFrame * CFrame.new(math.random() * jitter - jitter / 2, math.random() * jitter - jitter / 2, -power * 8)
		RunService.RenderStepped:Wait()
	end
	if finished then return end

	-- 3) 발사: 광선이 화면으로 날아오고, 화면이 깨진다
	sfx("Lord_Blast", 1.0)
	sfx("Ult_Finale", 0.8)
	local distance = (arrivePos - orb.Position).Magnitude
	local beam = Instance.new("Part")
	beam.Anchored, beam.CanCollide, beam.CanQuery, beam.CanTouch, beam.CastShadow = true, false, false, false, false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 150, 100)
	beam.Transparency = 0.1
	beam.Size = Vector3.new(50, 50, distance)
	beam.CFrame = CFrame.lookAt((orb.Position + arrivePos) / 2, arrivePos)
	beam.Parent = props
	flash.BackgroundTransparency = 0.25
	TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	-- 금 (화면 가운데에서 사방으로 번진다)
	local angle0 = math.random() * 40
	for i = 1, 12 do
		local len = 0.25 + math.random() * 0.5
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0)
		line.Position = UDim2.new(0.5, 0, 0.5, 0)
		line.Size = UDim2.new(0, 2 + math.random() * 2, len, 0)
		line.Rotation = angle0 + i * 30 + math.random(-10, 10) + 180
		line.BackgroundColor3 = Color3.fromRGB(236, 236, 246)
		line.BackgroundTransparency = 0.05
		line.BorderSizePixel = 0
		line.ZIndex = 9
		line.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Thickness = 1
		stroke.Parent = line
	end
	sfx("Shield_Block", 1.0, 1.7)
	task.delay(0.12, function() sfx("Shield_Block", 0.9, 1.3) end)
	local blastStart = os.clock()
	while os.clock() - blastStart < 0.55 and not finished do
		local k = 1 - (os.clock() - blastStart) / 0.55
		local jitter = 3 * k
		camera.CFrame = baseCFrame * CFrame.new(math.random() * jitter - jitter / 2, math.random() * jitter - jitter / 2, -8)
		RunService.RenderStepped:Wait()
	end
	if finished then return end

	-- 4) 화면이 깨지며 어두워지고, 게임 이름이 나온다
	TweenService:Create(veil, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
	task.wait(0.4)
	if finished then return end
	sfx("Dungeon_Start", 0.9, 0.8)
	TweenService:Create(title, TweenInfo.new(0.9), { TextTransparency = 0, TextStrokeTransparency = 0.7 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(1.2), { TextTransparency = 0.1 }):Play()
	task.wait(2.3)
	if finished then return end

	-- 5) 로비로: 스폰의 내 캐릭터 뒤로 바로 이어진다 (어둠에서 밝아진다)
	local look = root.CFrame.LookVector
	camera.CFrame = CFrame.lookAt(root.Position - look * 14 + Vector3.new(0, 7, 0), root.Position + look * 30 + Vector3.new(0, 4, 0))
	camera.FieldOfView = 70
	props:ClearAllChildren()
	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("Frame") and child ~= veil and child ~= topBar and child ~= bottomBar and child ~= flash then child:Destroy() end -- 금 지우기
	end
	sfx("Reel_Stop", 0.8, 0.9)
	TweenService:Create(title, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	TweenService:Create(veil, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(topBar, TweenInfo.new(1.2), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(1.2), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	task.wait(1.3)
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
