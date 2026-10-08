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
		local on = player:GetAttribute("DeadeyeActive") == true
		vignette.Visible = on
		if on then
			tint.Enabled = true
			TweenService:Create(tint, TweenInfo.new(0.3), { Saturation = -0.2, Contrast = 0.06, Brightness = 0, TintColor = Color3.fromRGB(255, 205, 205) }):Play()
		else
			local tween = TweenService:Create(tint, TweenInfo.new(0.4), { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.new(1, 1, 1) })
			tween:Play()
			tween.Completed:Connect(function()
				if player:GetAttribute("DeadeyeActive") ~= true then tint.Enabled = false end
			end)
		end
	end
	player:GetAttributeChangedSignal("DeadeyeActive"):Connect(apply)
end

-- 구역별 분위기: 로비는 해 질 녘(서버가 설정), 필드 / 던전은 예전처럼 밝은 낮 (어두워서 안 보이는 일이 없게)
do
	local Lighting = game:GetService("Lighting")
	local DAY = { ClockTime = 14, Brightness = 2.2, Ambient = Color3.fromRGB(70, 70, 70), OutdoorAmbient = Color3.fromRGB(70, 70, 70), ExposureCompensation = 0 }
	local dusk = nil
	local function apply()
		local zone = player:GetAttribute("Zone")
		local grade = Lighting:FindFirstChild("LobbyGrade")
		local bloom = Lighting:FindFirstChild("LobbyBloom")
		if zone == "Lobby" then
			if dusk then
				TweenService:Create(Lighting, TweenInfo.new(0.8), dusk):Play()
			end
			if grade then grade.Enabled = true end
			if bloom then bloom.Enabled = true end
		elseif zone == "Field" or zone == "Dungeon" then
			if not dusk then
				dusk = {
					ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
					OutdoorAmbient = Lighting.OutdoorAmbient, ExposureCompensation = Lighting.ExposureCompensation,
				}
			end
			TweenService:Create(Lighting, TweenInfo.new(0.8), DAY):Play()
			if grade then grade.Enabled = false end
			if bloom then bloom.Enabled = false end
		end
	end
	player:GetAttributeChangedSignal("Zone"):Connect(apply)
	task.defer(apply)
end

-- 내 체력바: 캐릭터 발밑에만 표시
do
	local fill = { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(70, 220, 100) }
	local text = { Text = "" }
	local feet
	local lastHealth
	local function update()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
		-- 맞으면 화면 가장자리가 붉게 번쩍이고 -피해량이 뜬다 (맞고 있는지 한눈에)
		if lastHealth and humanoid.Health < lastHealth - 0.5 then
			local hurt = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 20, 20), BackgroundTransparency = 0.78, BorderSizePixel = 0, ZIndex = 45, Active = false }, gui)
			TweenService:Create(hurt, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			task.delay(0.4, function() hurt:Destroy() end)
			local lost = makeLabel({ Size = UDim2.new(0, 200, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.55, 0), Text = string.format("-%d", math.ceil(lastHealth - humanoid.Health)), Font = Enum.Font.GothamBlack, TextSize = 34, TextColor3 = Color3.fromRGB(255, 80, 80), TextStrokeTransparency = 0, ZIndex = 46 }, gui)
			TweenService:Create(lost, TweenInfo.new(0.7), { Position = UDim2.new(0.5, 0, 0.47, 0), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(0.8, function() lost:Destroy() end)
		end
		lastHealth = humanoid.Health
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
			makeLabel({ Name = "HP", Size = UDim2.fromScale(1, 1), Text = "", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.35, ZIndex = 3 }, back)
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

		lootDrops[id] = { Beam = beam, Cube = cube, Base = base, Time = 0 }
	elseif action == "Gone" then
		local drop = lootDrops[id]
		if drop then
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
