-- IntroClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: IntroClient)
-- 처음 접속(레벨 1 / 경험치 0 / 무기 +0 / 튜토리얼 진행 중)한 사람에게만 나오는 약 6초짜리 오프닝:
--   어둠에서 밝아지며 필드 위 높은 하늘에서 저 멀리 우뚝 선 최후의 군주를 내려다보고(게임 이름이 뜬다) -> 마을 쪽으로 빠르게 줌 인 하며 스폰의 내 캐릭터 뒤로 내려앉는다.
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

local LORD_AT = Vector3.new(620, 200, 0) -- 마을 동쪽 하늘의 군주 그림자 (LobbyDecor 의 DistantLord)
local shownThisSession = false
local hiddenGuis = {} -- 오프닝 동안 잠깐 끈 화면들 (끝나거나 오류가 나면 이것만 다시 켠다)

local function isNewPlayer()
	return (player:GetAttribute("Level") or 1) <= 1 and (player:GetAttribute("XP") or 0) == 0
		and (player:GetAttribute("WeaponLevel") or 0) == 0 and player:GetAttribute("TutorialActive") == true
end

local function play()
	local camera = workspace.CurrentCamera
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not root or not camera then return end
	player:SetAttribute("IntroPlaying", true)

	-- 오프닝 화면: 검은 막 + 위아래 검은 띠 + 제목
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
	local title = text({ Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0.5, 0, 0.74, 0), TextSize = 56, TextColor3 = Color3.fromRGB(242, 228, 196), Text = "GEAR RUSH" })
	local subtitle = text({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0.5, 0, 0.74, 52), TextSize = 16, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(190, 175, 150), Text = "D U N G E O N   S H O O T E R" })

	-- 다른 화면 잠깐 끄기 (끝나면 원래 켜져 있던 것만 복구)
	for _, other in ipairs(playerGui:GetChildren()) do
		if other:IsA("ScreenGui") and other ~= gui and other.Enabled then
			hiddenGuis[#hiddenGuis + 1] = other
			other.Enabled = false
		end
	end

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

	-- 카메라: 군주 그림자를 보는 먼 시점 -> 내 캐릭터 뒤
	local look = root.CFrame.LookVector
	local startPos = Vector3.new(230, 240, -190) -- 필드 입구 위 높은 하늘: 동쪽으로 펼쳐진 필드와 그 끝의 군주가 한눈에 보인다
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 68
	camera.CFrame = CFrame.lookAt(startPos, LORD_AT)
	TweenService:Create(topBar, TweenInfo.new(0.8), { Size = UDim2.new(1, 0, 0.1, 0) }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(0.8), { Size = UDim2.new(1, 0, 0.1, 0) }):Play()
	TweenService:Create(veil, TweenInfo.new(1.0), { BackgroundTransparency = 1 }):Play()
	pcall(function()
		local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
		if SoundBank.Has("Lord_Voice") then SoundBank.Play(SoundService, "Lord_Voice", { Volume = 0.6 }) end -- 낮고 묵직한 울림 (군주의 목소리)
	end)

	-- 1) 높은 하늘에서 군주 쪽으로 천천히 다가간다 (군주가 또렷하게 커진다)
	TweenService:Create(camera, TweenInfo.new(3.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		CFrame = CFrame.lookAt(startPos + Vector3.new(110, -28, 70), LORD_AT), FieldOfView = 54,
	}):Play()
	task.delay(1.6, function()
		if finished then return end
		TweenService:Create(title, TweenInfo.new(0.9), { TextTransparency = 0, TextStrokeTransparency = 0.7 }):Play()
		TweenService:Create(subtitle, TweenInfo.new(1.2), { TextTransparency = 0.1 }):Play()
	end)
	task.wait(3.7)
	if finished then return end

	-- 2) 마을 쪽으로 빠르게 줌 인: 하늘에서 스폰의 내 캐릭터 뒤로 내려앉는다
	local finalPos = root.Position - look * 14 + Vector3.new(0, 7, 0)
	local finalLook = root.Position + look * 30 + Vector3.new(0, 4, 0)
	TweenService:Create(camera, TweenInfo.new(2.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
		CFrame = CFrame.lookAt(finalPos, finalLook), FieldOfView = 70,
	}):Play()
	TweenService:Create(title, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(1.2), { TextTransparency = 1 }):Play()
	TweenService:Create(topBar, TweenInfo.new(1.4), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(1.4), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	task.wait(2.9)
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
