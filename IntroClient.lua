-- IntroClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: IntroClient)
-- 처음 접속(레벨 1 / 경험치 0 / 무기 +0 / 튜토리얼 진행 중)한 사람에게만 나오는 약 15초짜리 오프닝:
--   마을 문 위에서 필드를 따라 맨 끝의 보스까지 빠르게 날아가고 -> 보스가 눈을 뜨고 에너지를 모아 쏘면 화면이 와장창 깨지고 -> 카메라가 뒤로 빠지며 하늘로 솟구쳐 게임 이름이 뜨고 -> 스폰으로 확 떨어지며 내 캐릭터가 나타난다.
--   * 처음 한 번은 건너뛸 수 없다(끝까지 봐야 한다). 한 번 끝까지 본 뒤에는 화면을 누르거나 아무 키나 누르면 바로 건너뛴다. 끝나면 카메라는 원래대로 돌아온다.
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
	local red = rgb(255, 50, 60)
	local look = require(ReplicatedStorage:WaitForChild("LordLook")).Build(add) -- 모양은 결투의 군주와 같은 모듈 (LordLook)
	for k = 1, 4 do -- 몸 주변에 떠 있는 칼날 (연출에서는 가만히)
		local angle = k * math.pi / 2
		add(Vector3.new(1.2, 8, 2.4), CFrame.new(math.cos(angle) * 16, 4, math.sin(angle) * 8) * CFrame.Angles(0, -angle, math.rad(20)), red, Enum.Material.Neon, 0.1)
	end
	local eyes, core = look.Eyes, look.Core
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

	-- 오프닝 동안 다른 화면이 다시 켜지는 것(예: 무기 바 1~0)을 막는다: 매 프레임 확인해서 꺼 둔다 (끝나면 원래 켜져 있던 것만 복구)
	local guardConnection = RunService.Heartbeat:Connect(function()
		for _, other in ipairs(playerGui:GetChildren()) do
			if other:IsA("ScreenGui") and other ~= gui and other.Enabled then
				hiddenGuis[#hiddenGuis + 1] = other
				other.Enabled = false
			end
		end
	end)

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

	local introRemote -- 서버와 주고받는 통신 (필드 불러오기 / 카메라 위치 알림)
	local finished = false
	local connection
	local endWall -- 오프닝 동안 투명하게 만드는 필드 끝 벽 (끝나면 되돌린다)
	local function finish()
		if finished then return end
		finished = true
		if connection then connection:Disconnect() end
		guardConnection:Disconnect()
		if introRemote then pcall(function() introRemote:FireServer("End") end) end -- 불러오기 기준점을 다시 내 캐릭터로
		pcall(function() require(ReplicatedStorage:WaitForChild("Remotes")).Tutorial:FireServer("IntroSeen") end) -- 끝까지 봤다: 다음부터는 건너뛸 수 있다
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
		if endWall and endWall.Parent then endWall.Transparency = 0 end
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

	-- (건너뛰기 없음: 로딩 화면처럼 처음부터 끝까지 그냥 보여 준다. 오프닝 길이는 이전보다 약 10% 줄였다)
	local startedAt = os.clock()
	-- 오프닝 동안만 필드 끝 벽을 투명하게 (군주 뒤를 가려 보였다). 끝나면 되돌린다
	pcall(function()
		local fieldFolder = workspace:FindFirstChild("Field")
		endWall = fieldFolder and fieldFolder:FindFirstChild("CanyonEnd", true)
		if endWall then endWall.Transparency = 1 end
	end)

	-- 보스 자리: 필드 맨 끝 (최후의 군주 포탈 뒤), 마을 쪽(서쪽)을 바라본다. 실제 보스와 같은 모습
	local S = 3.8 -- 보스 크기 (이전 2.4: 왕관 / 뿔 / 날개 장식이 작아서 안 보였다)
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
	-- 어두운 보스의 장식(왕관 / 뿔 / 어깨 가시 / 날개)이 보이도록 연출용 조명 두 개 (내 화면에만, 끝나면 같이 사라진다)
	local function lightAt(offset, color, range, brightness)
		local holder = Instance.new("Part")
		holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow = true, false, false, false, false
		holder.Transparency = 1
		holder.Size = Vector3.new(1, 1, 1)
		holder.Position = bodyPos + offset
		holder.Parent = props
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = brightness
		light.Shadows = false
		light.Parent = holder
	end
	lightAt(Vector3.new(-120, 40, 0), Color3.fromRGB(190, 200, 235), 240, 2.4) -- 앞쪽 차가운 빛: 윤곽과 장식이 드러난다
	lightAt(Vector3.new(-30, 10, 0), Color3.fromRGB(255, 120, 100), 160, 2.2) -- 가슴 앞 붉은 빛: 코어에서 번지는 느낌

	-- 카메라 준비: 마을 동쪽 문 위에서 필드를 따라 동쪽을 본다
	local FLY_HEIGHT = 260 -- 날아가는 높이: 낮으면 벽 / 절벽에 가려 바닥의 필드가 안 보인다. 높이 떠서 아래를 내려다본다
	local TILT = Vector3.new(600, -300, 0) -- 아래로 약 27도 기울여 바라본다
	local startPos = Vector3.new(110, FLY_HEIGHT, 0)
	local arrivePos = Vector3.new(bossX - 320, groundY + 150, 0)
	local arriveLook = face + Vector3.new(0, -8, 0)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 70
	camera.CFrame = CFrame.lookAt(startPos, startPos + TILT)
	-- 필드 미리 불러오기: 이 게임은 멀리 있는 지형을 아껴서 불러오기 때문에(StreamingEnabled), 날아가기 전에 서버에 필드를 미리 보내 달라고 한다. 검은 화면에서 잠깐 기다린다 (최대 9초)
	do
		-- 로딩 화면: 게임 이름 + 진행 막대 + 팁 (검은 화면으로 멈춘 것처럼 보이지 않게)
		local page = Instance.new("Frame")
		page.Name = "LoadingPage"
		page.Size = UDim2.new(1, 0, 1, 0)
		page.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
		page.BorderSizePixel = 0
		page.ZIndex = 13
		page.Parent = gui
		local function pageText(props)
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			l.Font = Enum.Font.GothamBold
			l.ZIndex = 14
			for k, v in pairs(props) do l[k] = v end
			l.Parent = page
			return l
		end
		pageText({ Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0.5, 0, 0.36, 0), TextSize = 56, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(226, 208, 168), Text = "GEAR RUSH" })
		pageText({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0.5, 0, 0.36, 50), TextSize = 15, TextColor3 = Color3.fromRGB(150, 138, 118), Text = "D U N G E O N   S H O O T E R" })
		local barBackLoad = Instance.new("Frame")
		barBackLoad.Size = UDim2.new(0, 360, 0, 6)
		barBackLoad.AnchorPoint = Vector2.new(0.5, 0.5)
		barBackLoad.Position = UDim2.new(0.5, 0, 0.58, 0)
		barBackLoad.BackgroundColor3 = Color3.fromRGB(46, 44, 58)
		barBackLoad.BorderSizePixel = 0
		barBackLoad.ZIndex = 14
		barBackLoad.Parent = page
		local barFillLoad = Instance.new("Frame")
		barFillLoad.Size = UDim2.new(0.04, 0, 1, 0)
		barFillLoad.BackgroundColor3 = Color3.fromRGB(226, 176, 96)
		barFillLoad.BorderSizePixel = 0
		barFillLoad.ZIndex = 15
		barFillLoad.Parent = barBackLoad
		for _, bar in ipairs({ barBackLoad, barFillLoad }) do
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 3)
			corner.Parent = bar
		end
		local status = pageText({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0.5, 0, 0.58, 24), TextSize = 13, TextColor3 = Color3.fromRGB(160, 156, 172), Text = "Preparing the field..." })
		local tips = {
			"Tip · Defeat each zone's Lord to open the next zone.",
			"Tip · Press Q to dash. Narrowly dodging enemy shots gives a bonus.",
			"Tip · Set effects stack: mix gear from different zones to build your style.",
			"Tip · Mythic gear can carry a Unique effect. Dungeons are the best place to find them.",
		}
		local tipLabel = pageText({ Size = UDim2.new(1, -60, 0, 20), Position = UDim2.new(0.5, 0, 0.82, 0), TextSize = 13, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(190, 182, 160), Text = tips[math.random(#tips)] })

		local pageStart = os.clock()
		local ready = false
		local remote
		pcall(function() remote = require(ReplicatedStorage:WaitForChild("Remotes")).Intro end)
		introRemote = remote
		local listener
		if remote then
			listener = remote.OnClientEvent:Connect(function(action, done, total)
				if action == "Ready" then
					ready = true
				elseif action == "Progress" and total then
					TweenService:Create(barFillLoad, TweenInfo.new(0.25), { Size = UDim2.new(math.clamp(done / total, 0.04, 1), 0, 1, 0) }):Play()
					status.Text = string.format("Preparing the field...  %d / %d", done, total)
				end
			end)
			remote:FireServer("Stream")
			local waited = os.clock()
			local lastTip = waited
			while not ready and os.clock() - waited < 9 and not finished do
				if os.clock() - lastTip > 2.5 then
					lastTip = os.clock()
					tipLabel.Text = tips[math.random(#tips)]
				end
				task.wait(0.1)
			end
			listener:Disconnect()
		end
		local stillNeeded = 1.5 - (os.clock() - pageStart) -- 로딩이 빨리 끝나도 로딩 화면은 최소 1.5초는 보여 준다 (첫 화면이 번쩍 지나가지 않게)
		if stillNeeded > 0 and not finished then
			TweenService:Create(barFillLoad, TweenInfo.new(stillNeeded, Enum.EasingStyle.Sine), { Size = UDim2.new(0.92, 0, 1, 0) }):Play()
			task.wait(stillNeeded)
		end
		-- (진단) 필드 바닥이 실제로 내 화면에 불러와졌는지 Output 에 한 줄 남긴다
		pcall(function()
			local fieldFolder = workspace:FindFirstChild("Field")
			local found = 0
			if fieldFolder then
				for _, item in ipairs(fieldFolder:GetChildren()) do
					if string.sub(item.Name, 1, 6) == "Ground" then found += 1 end
				end
			end
			print(string.format("[오프닝 진단] Ready=%s · Field 폴더 %s · 불러온 바닥 조각 %d개", tostring(ready), fieldFolder and "있음" or "없음", found))
		end)
		TweenService:Create(barFillLoad, TweenInfo.new(0.2), { Size = UDim2.new(1, 0, 1, 0) }):Play()
		status.Text = "Ready"
		task.wait(0.35)
		for _, item in ipairs(page:GetDescendants()) do -- 로딩 화면이 부드럽게 사라진다
			if item:IsA("TextLabel") then TweenService:Create(item, TweenInfo.new(0.5), { TextTransparency = 1 }):Play() end
			if item:IsA("Frame") then TweenService:Create(item, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play() end
		end
		TweenService:Create(page, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		task.delay(0.6, function() page:Destroy() end)
		if finished then return end
	end
	-- 카메라가 날아가는 동안 서버에 카메라 위치(x)를 계속 알려서, 서버가 그 둘레의 지형을 불러 준다 (캐릭터는 스폰에 있어서 그냥은 멀리 있는 필드가 안 불러와진다)
	if introRemote then
		task.spawn(function()
			local lastX = camera.CFrame.Position.X
			local lastAt = os.clock()
			while not finished do
				task.wait(0.2)
				local now = os.clock()
				local x = camera.CFrame.Position.X
				local velocity = (x - lastX) / math.max(now - lastAt, 0.05)
				lastX, lastAt = x, now
				introRemote:FireServer("Focus", x + math.clamp(velocity * 0.8, -700, 700)) -- 가는 방향 앞쪽을 미리 불러 준다
			end
		end)
	end
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
	-- 로딩 화면처럼: 위쪽 검은 띠에 "Loading the world..." + 돌아가는 팁 (건너뛸 수 없으니 그냥 보게)
	do
		local caption = Instance.new("TextLabel")
		caption.BackgroundTransparency = 1
		caption.AnchorPoint = Vector2.new(0.5, 0.5)
		caption.Size = UDim2.new(1, -40, 0, 22)
		caption.Position = UDim2.new(0.5, 0, 0.05, 0) -- 위쪽 검은 띠 가운데 (아래 띠에는 진행 막대 / 구역 이름이 있어서 겹쳤다)
		caption.Font = Enum.Font.GothamMedium
		caption.TextSize = 13
		caption.TextColor3 = Color3.fromRGB(190, 182, 160)
		caption.ZIndex = 20
		caption.Parent = gui
		local captionTips = {
			"Defeat each zone's Lord to open the next zone.",
			"Press Q to dash. Narrowly dodging enemy shots gives a bonus.",
			"Set effects stack: mix gear from different zones to build your style.",
			"Mythic gear can carry a Unique effect. Dungeons are the best place to find them.",
		}
		task.spawn(function()
			local index = math.random(#captionTips)
			while not finished and caption.Parent do
				caption.Text = "Loading the world...  ·  " .. captionTips[index]
				index = index % #captionTips + 1
				task.wait(3.5)
			end
		end)
	end
	sfx("Aug_Flame", 1.0, 0.7) -- 바람을 가르는 소리
	task.wait(0.6)
	if finished then return end

	-- 1) 마을에서 보스까지 한 번에 날아간다 (빠르게 가속했다가 보스 앞에서 멈춘다. 시야각이 넓어졌다가 좁아진다)
	-- 먼저 높은 하늘에서 아래를 내려다보며 일정한 속도로 날아가고(필드가 한눈에 보인다), 끝에서 보스 앞으로 내려오며 속도를 줄인다
	local FLY_TIME = 7.2 -- (예전 9.0: 20% 줄임)
	local DESCEND_TIME = 1.84 -- (예전 2.3: 20% 줄임)
	local midPos = Vector3.new(bossX - 650, FLY_HEIGHT, 0)
	TweenService:Create(camera, TweenInfo.new(FLY_TIME, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(midPos, midPos + TILT) }):Play()
	TweenService:Create(camera, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { FieldOfView = 84 }):Play()
	local descending = false
	task.delay(3.5, function() if not finished then sfx("Aug_Flame", 0.8, 0.6) end end)
	task.delay(7.0, function() if not finished then sfx("Aug_Flame", 0.7, 0.5) end end)
	-- 날아가는 동안: 진행 막대가 차오르고, 구역을 지날 때마다 구역 이름이 뜬다
	TweenService:Create(barBack, TweenInfo.new(0.6), { BackgroundTransparency = 0.2 }):Play()
	TweenService:Create(barFill, TweenInfo.new(0.6), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(skull, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
	for _, tick in ipairs(ticks) do TweenService:Create(tick, TweenInfo.new(0.6), { BackgroundTransparency = 0.2 }):Play() end
	local flyStart = os.clock()
	local lastProbe = 0
	local lastZone = 0
	while os.clock() - flyStart < FLY_TIME + DESCEND_TIME + 0.05 and not finished do
		if not descending and os.clock() - flyStart >= FLY_TIME then
			descending = true
			TweenService:Create(camera, TweenInfo.new(DESCEND_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.lookAt(arrivePos, arriveLook), FieldOfView = 58 }):Play()
		end
		local x = camera.CFrame.Position.X
		if os.clock() - (lastProbe or 0) > 1.5 then -- (진단) 지금 카메라 아래에 지면이 있는지
			lastProbe = os.clock()
			local probe = workspace:Raycast(camera.CFrame.Position, Vector3.new(0, -1500, 0))
			print(string.format("[오프닝 진단] 카메라 x=%.0f y=%.0f · 아래 지면 %s", x, camera.CFrame.Position.Y, probe and string.format("있음(y=%.0f, %s)", probe.Position.Y, probe.Instance.Name) or "없음"))
		end
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
	orb.Position = face + Vector3.new(-54, -8, 0)
	orb.Parent = props
	TweenService:Create(orb, TweenInfo.new(1.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(120, 120, 120), Transparency = 0.1 }):Play()
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
	beam.Size = Vector3.new(90, 90, distance)
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
	TweenService:Create(camera, TweenInfo.new(3.6, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut), { CFrame = skyLook }):Play()
	TweenService:Create(camera, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { FieldOfView = 105 }):Play()
	task.delay(1.6, function()
		if not finished then TweenService:Create(camera, TweenInfo.new(1.9, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { FieldOfView = 72 }):Play() end
	end)
	task.delay(1.4, function() if not finished then props:ClearAllChildren() end end) -- 보스는 멀어진 뒤에 치운다
	task.wait(1.9)
	if finished then return end
	sfx("Dungeon_Start", 0.9, 0.8)
	TweenService:Create(title, TweenInfo.new(0.8), { TextTransparency = 0, TextStrokeTransparency = 0.6 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(1.1), { TextTransparency = 0.1 }):Play()
	task.wait(1.0)
	if finished then return end

	-- 5) 하늘 높은 곳에서 제목을 보여 주다가 -> 내 캐릭터가 하늘에서 "슝" 내려와 아이언맨처럼 착지한다
	--    (진짜 캐릭터는 스폰에 숨겨 두고, 내 화면에만 보이는 분신이 떨어진다. 착지가 끝나면 분신을 지우고 진짜 캐릭터가 나타난다)
	local homePose = CFrame.lookAt(spawnPos - look * 14 + Vector3.new(0, 7, 0), spawnPos + look * 30 + Vector3.new(0, 4, 0))
	local right = root.CFrame.RightVector
	local function pitched(position, degrees) -- 몸을 앞으로 기울인다 (머리가 바라보는 쪽으로)
		return CFrame.new(position) * CFrame.fromAxisAngle(right, -math.rad(degrees)) * (root.CFrame - root.CFrame.Position)
	end
	local double
	do
		character.Archivable = true
		double = character:Clone()
		for _, item in ipairs(double:GetDescendants()) do
			if item:IsA("Script") or item:IsA("LocalScript") or item:IsA("BillboardGui") or item:IsA("ForceField") or item:IsA("Sound") then
				item:Destroy()
			elseif item:IsA("BasePart") then
				item.Anchored, item.CanCollide, item.CanQuery, item.CanTouch = true, false, false, false
				item.LocalTransparencyModifier = 0
			end
		end
		local humanoid = double:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
		double.Parent = props
	end
	local FALL_HEIGHT = 520
	double:PivotTo(pitched(spawnPos + Vector3.new(0, FALL_HEIGHT, 0), 25))
	local streak = Instance.new("Part") -- 떨어지는 몸 뒤로 길게 남는 빛줄기
	streak.Anchored, streak.CanCollide, streak.CanQuery, streak.CanTouch, streak.CastShadow = true, false, false, false, false
	streak.Material = Enum.Material.Neon
	streak.Color = Color3.fromRGB(150, 215, 255)
	streak.Transparency = 0.45
	streak.Size = Vector3.new(3.5, 110, 3.5)
	streak.Position = spawnPos + Vector3.new(0, FALL_HEIGHT + 60, 0)
	streak.Parent = props

	TweenService:Create(camera, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = CFrame.lookAt(skyPos - Vector3.new(40, 60, 0), spawnPos + Vector3.new(0, FALL_HEIGHT * 0.5, 0)) }):Play() -- 하늘 정점에서 떨어질 자리를 향해 자세를 잡는다
	task.delay(0.7, function()
		if finished then return end
		TweenService:Create(title, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(subtitle, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
	end)
	sfx("Aug_Flame", 0.8, 0.4)
	task.wait(1.2)
	if finished then return end

	-- 낙하: 점점 빨라지며 "슝" (카메라는 떨어지는 몸을 쫓아 내려온다). 브릿지: 시작하는 순간 화면이 살짝 어두워졌다 밝아진다
	TweenService:Create(veil, TweenInfo.new(0.3, Enum.EasingStyle.Sine), { BackgroundTransparency = 0.55 }):Play()
	task.delay(0.35, function()
		if not finished then TweenService:Create(veil, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 }):Play() end
	end)
	sfx("Aug_Flame", 1.0, 0.3)
	local camFrom = camera.CFrame.Position
	local camLand = spawnPos - look * 26 + Vector3.new(0, 11, 0)
	local fovStart = camera.FieldOfView
	local fallTime = 1.7
	local fallStart = os.clock()
	while not finished do
		local t = math.clamp((os.clock() - fallStart) / fallTime, 0, 1)
		local fall = t * t -- 중력처럼 가속
		local charPos = spawnPos + Vector3.new(0, FALL_HEIGHT * (1 - fall), 0)
		local tilt = 25 * (1 - t) + 35 * t -- 기울기는 땅에 닿을 때 앞으로 숙인 자세로
		double:PivotTo(pitched(charPos, tilt))
		streak.Position = charPos + Vector3.new(0, 62, 0)
		local f = t * t * (3 - 2 * t)
		camera.CFrame = CFrame.lookAt(camFrom:Lerp(camLand, f), charPos + Vector3.new(0, 2, 0))
		camera.FieldOfView = fovStart + (82 - fovStart) * math.sin(math.pi * t) -- 떨어질 때 시야가 넓어졌다가 돌아온다
		if t >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	if finished then return end

	-- 착지: 쾅! 숙인 자세로 땅을 짚고 충격이 퍼진다 (흙먼지 조각 + 충격 고리 + 번쩍 + 화면 흔들림)
	sfx("Boom", 1.0, 0.7)
	sfx("Aug_MeteorHit", 0.9, 1.0)
	sfx("Ult_Finale", 0.6, 0.9)
	TweenService:Create(streak, TweenInfo.new(0.5), { Transparency = 1 }):Play()
	flash.BackgroundColor3 = Color3.fromRGB(190, 225, 255)
	flash.BackgroundTransparency = 0.45
	TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(160, 220, 255)
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.4, 4, 4)
	ring.CFrame = CFrame.new(spawnPos - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = props
	TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.4, 70, 70), Transparency = 1 }):Play()
	local scar = Instance.new("Part") -- 땅에 남는 어두운 균열 자국
	scar.Shape = Enum.PartType.Cylinder
	scar.Anchored, scar.CanCollide, scar.CanQuery, scar.CanTouch, scar.CastShadow = true, false, false, false, false
	scar.Material = Enum.Material.Slate
	scar.Color = Color3.fromRGB(34, 32, 40)
	scar.Transparency = 0.25
	scar.Size = Vector3.new(0.2, 16, 16)
	scar.CFrame = CFrame.new(spawnPos - Vector3.new(0, 2.7, 0)) * CFrame.Angles(0, 0, math.rad(90))
	scar.Parent = props
	TweenService:Create(scar, TweenInfo.new(2.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	for i = 1, 14 do -- 튀어 오르는 돌 조각
		local angle = i / 14 * math.pi * 2 + math.random() * 0.4
		local chunk = Instance.new("Part")
		chunk.Anchored, chunk.CanCollide, chunk.CanQuery, chunk.CanTouch, chunk.CastShadow = true, false, false, false, false
		chunk.Material = Enum.Material.Slate
		chunk.Color = Color3.fromRGB(110 + math.random(-15, 15), 104, 100)
		local size = 0.5 + math.random() * 0.9
		chunk.Size = Vector3.new(size, size, size)
		local base = spawnPos - Vector3.new(0, 2.5, 0) + Vector3.new(math.cos(angle) * 2, 0, math.sin(angle) * 2)
		chunk.CFrame = CFrame.new(base) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		chunk.Parent = props
		local up = base + Vector3.new(math.cos(angle) * (6 + math.random() * 7), 4 + math.random() * 6, math.sin(angle) * (6 + math.random() * 7))
		local down = up + Vector3.new(math.cos(angle) * 4, -(5 + math.random() * 3), math.sin(angle) * 4)
		TweenService:Create(chunk, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = up }):Play()
		task.delay(0.35, function()
			if not chunk.Parent then return end
			local fade = TweenService:Create(chunk, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = down, Transparency = 1 })
			fade:Play()
		end)
	end
	TweenService:Create(topBar, TweenInfo.new(1.2), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(1.2), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	-- 숙인 자세(앞으로 기울이고 낮게)로 잠깐 버틴다 -> 천천히 일어선다. 카메라는 흔들리며 캐릭터 뒤로 자리 잡는다
	local crouchPos = spawnPos - Vector3.new(0, 1.3, 0)
	double:PivotTo(pitched(crouchPos, 38))
	local holdStart = os.clock()
	while os.clock() - holdStart < 0.55 and not finished do
		local k = (os.clock() - holdStart) / 0.55
		local jitter = 2.2 * (1 - k)
		camera.CFrame = CFrame.lookAt(camLand:Lerp(homePose.Position, k * 0.5), crouchPos + Vector3.new(0, 2, 0)) * CFrame.new(math.random() * jitter - jitter / 2, math.random() * jitter - jitter / 2, 0)
		RunService.RenderStepped:Wait()
	end
	local riseStart = os.clock()
	local riseTime = 0.9
	while os.clock() - riseStart < riseTime and not finished do
		local k = (os.clock() - riseStart) / riseTime
		local eased = k * k * (3 - 2 * k)
		double:PivotTo(pitched(crouchPos:Lerp(spawnPos, eased), 38 * (1 - eased)))
		camera.CFrame = CFrame.lookAt(camLand:Lerp(homePose.Position, 0.5 + 0.5 * eased), spawnPos:Lerp(spawnPos + look * 30 + Vector3.new(0, 4, 0), eased) + Vector3.new(0, 2, 0))
		camera.FieldOfView = 70
		RunService.RenderStepped:Wait()
	end
	setBodyAlpha(0) -- 분신 대신 진짜 캐릭터가 나타난다 (같은 자세 / 같은 자리)
	double:Destroy()
	camera.CFrame = homePose
	camera.FieldOfView = 70
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
	if shownThisSession then return end -- (접속할 때마다 한 번: 새 유저만이 아니라 모두에게 보여 준다)
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
