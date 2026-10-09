-- GoalClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: GoalClient)
-- "다음 목표" 패널: 지금 가장 가까운(또는 바로 할 수 있는) 목표를 항상 한 줄로 보여준다.
--   -> 세션을 끝낼 때도 "하나만 더 하면…" 하는 미완 목표가 남도록 (재방문 동기)
-- + 골든 타임(주기적 2배 이벤트) 남은 시간 표시
-- 모든 값은 서버가 설정한 플레이어 Attribute 에서 읽는다 (서버 호출 없음).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "GoalHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 260, 0, 66)
panel.Position = UDim2.new(0, 16, 0, 326)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.2
panel.BorderSizePixel = 0
panel.Parent = gui
addCorner(panel, 8)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -16, 0, 34)
titleLabel.Position = UDim2.new(0, 8, 0, 4)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 13
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextYAlignment = Enum.TextYAlignment.Top
titleLabel.TextWrapped = true
titleLabel.RichText = true
titleLabel.Parent = panel

local barBack = Instance.new("Frame")
barBack.Size = UDim2.new(1, -16, 0, 10)
barBack.Position = UDim2.new(0, 8, 1, -18)
barBack.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
barBack.BorderSizePixel = 0
barBack.Parent = panel
addCorner(barBack, 5)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(110, 210, 255)
barFill.BorderSizePixel = 0
barFill.Parent = barBack
addCorner(barFill, 5)

-- 골든 타임 배너 (화면 위쪽 가운데)
local golden = Instance.new("TextLabel")
golden.Size = UDim2.new(0, 480, 0, 34)
golden.AnchorPoint = Vector2.new(0.5, 0)
golden.Position = UDim2.new(0.5, 0, 0, 88)
golden.BackgroundColor3 = Color3.fromRGB(70, 50, 10)
golden.BackgroundTransparency = 0.08
golden.BorderSizePixel = 0
golden.Font = Enum.Font.GothamBlack
golden.TextSize = 18
golden.TextColor3 = Color3.fromRGB(255, 220, 90)
golden.Visible = false
golden.Parent = gui
addCorner(golden, 8)
local goldenStroke = Instance.new("UIStroke")
goldenStroke.Thickness = 2
goldenStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- 기본값은 글자 테두리라서 글씨가 뭉개졌다: 상자 테두리로만 쓴다
goldenStroke.Color = Color3.fromRGB(255, 200, 70)
goldenStroke.Parent = golden

local function comma(n)
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- 오늘의 퀘스트 패널: 튜토리얼에서 최종 군주에게 쓰러져 마을로 돌아온 뒤에야 나타난다 (QuestHud). 던전 / 강화 퀘스트가 항상 들어 있다.
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local TweenService = game:GetService("TweenService")
local questPanel = Instance.new("Frame")
questPanel.Size = UDim2.new(0, 260, 0, 30)
questPanel.Position = UDim2.new(0, -300, 0, 326)
questPanel.BackgroundColor3 = Color3.fromRGB(20, 22, 34)
questPanel.BackgroundTransparency = 0.12
questPanel.BorderSizePixel = 0
questPanel.Visible = false
questPanel.Parent = gui
addCorner(questPanel, 8)
local questStroke = Instance.new("UIStroke")
questStroke.Color = Color3.fromRGB(255, 205, 90)
questStroke.Thickness = 2
questStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
questStroke.Parent = questPanel
local questLabel = Instance.new("TextLabel")
questLabel.Size = UDim2.new(1, -16, 1, -8)
questLabel.Position = UDim2.new(0, 8, 0, 4)
questLabel.BackgroundTransparency = 1
questLabel.Font = Enum.Font.GothamBold
questLabel.TextSize = 13
questLabel.TextColor3 = Color3.new(1, 1, 1)
questLabel.TextXAlignment = Enum.TextXAlignment.Left
questLabel.TextYAlignment = Enum.TextYAlignment.Top
questLabel.RichText = true
questLabel.Parent = questPanel
local dailyList = nil
local questShown = false
local beaconDone = false
local beacon, beaconStart = nil, 0

Remotes.Quest.OnClientEvent:Connect(function(action, data)
	if action == "State" then dailyList = data.Daily end
end)

task.defer(function() Remotes.Quest:FireServer("Request") end) -- 퀘스트 상태를 한 번 더 요청 (스크립트 시작 순서 때문에 놓칠 수 있다)

local function refreshQuests()
	if not dailyList then return end
	local lines = { "<font color='#ffd966'><b>📋 오늘의 퀘스트</b></font>" }
	for _, quest in ipairs(dailyList) do
		local done = quest.Progress >= quest.Goal
		if quest.Claimed then
			table.insert(lines, string.format("<font color='#7a7f95'>✔ %s</font>", quest.Desc))
		elseif done then
			table.insert(lines, string.format("<font color='#78ff8c'>✅ %s — 메뉴(I)에서 받기!</font>", quest.Desc))
		else
			table.insert(lines, string.format("• %s <font color='#ffd966'>%d/%d</font>", quest.Desc, quest.Progress, quest.Goal))
		end
	end
	questLabel.Text = table.concat(lines, "\n")
	questPanel.Size = UDim2.new(0, 260, 0, 12 + 18 * #lines)
end

-- 던전 게이트에 은은한 빛기둥: 설명 없이 시선이 그쪽으로 가게 한다 (처음 던전에 들어가면 사라진다)
local function updateBeacon(active)
	if not active or beaconDone then
		if beacon then beacon:Destroy() beacon = nil end
		return
	end
	if not beacon then
		local gate = workspace:FindFirstChild("DungeonGate1", true)
		if not gate then return end
		beacon = Instance.new("Part")
		beacon.Name = "GateBeacon"
		beacon.Shape = Enum.PartType.Cylinder
		beacon.Size = Vector3.new(260, 7, 7)
		beacon.CFrame = CFrame.new(gate.Position + Vector3.new(0, 125, 0)) * CFrame.Angles(0, 0, math.rad(90))
		beacon.Anchored = true
		beacon.CanCollide = false
		beacon.CanQuery = false
		beacon.CastShadow = false
		beacon.Material = Enum.Material.Neon
		beacon.Color = Color3.fromRGB(255, 190, 80)
		beacon.Parent = workspace
		beaconStart = os.clock()
	end
	beacon.Transparency = 0.6 + 0.2 * math.sin((os.clock() - beaconStart) * 3)
	if os.clock() - beaconStart > 240 then beaconDone = true end
end

-- 지금 보여줄 목표 후보를 모두 만들고 (달성 비율이 가장 높은 것) 하나를 고른다
local function pickGoal()
	local candidates = {}
	local gold = player:GetAttribute("Gold") or 0
	local level = player:GetAttribute("WeaponLevel") or 0

	-- 무기 진화
	if level < Config.Weapon.MaxLevel then
		local nextTier = Config.Weapon.Tiers[Config.GetWeaponTierIndex(level) + 1]
		if nextTier then
			local cost = 0
			for l = level, nextTier.MinLevel - 1 do
				cost += Config.GetEnhanceCost(l)
			end
			table.insert(candidates, {
				Text = string.format("🔫 다음 무기 <font color='#ffd966'>%s</font> (%d/%d)\n강화 비용 %s G · 보유 %s G", nextTier.Name, nextTier.Index, Config.Weapon.WeaponCount, comma(cost), comma(gold)),
				Ratio = math.min(1, gold / cost), Priority = 1,
			})
		end
	end

	-- 레벨업 / 돌파
	local charLevel = player:GetAttribute("Level") or 1
	if charLevel < Config.Level.Max then
		if player:GetAttribute("GateBlocked") then
			table.insert(candidates, { Text = "🚧 레벨이 막혔어요!\n메뉴(I) → 성장 탭에서 돌파를 진행하세요", Ratio = 1, Priority = 0 })
		else
			local xp, needed = player:GetAttribute("XP") or 0, math.max(1, player:GetAttribute("XPNeeded") or 1)
			table.insert(candidates, {
				Text = string.format("⭐ 다음 레벨 Lv.%d\n경험치 %d / %d", charLevel + 1, xp, needed), Ratio = math.min(1, xp / needed), Priority = 2,
			})
		end
	end

	-- 다음 구역 관문
	local cleared = player:GetAttribute("ClearedZone") or 0
	local needed = Config.Field.Gate.KillsNeeded[cleared + 1]
	if needed then
		local kills = player:GetAttribute("GateKills") or 0
		local gold = Config.Field.Gate.RewardGold * (cleared + 1)
		table.insert(candidates, {
			Text = string.format("🚪 구역 %d 관문 열기\n구역 %d 몬스터 처치 %d / %d · 보상 %s G + 티켓", cleared + 2, cleared + 1, kills, needed, comma(gold)),
			Ratio = math.min(0.9, kills / needed), Priority = 1,
		})
	end

	-- 지금 바로 쓸 수 있는 것
	if (player:GetAttribute("Level") or 1) >= Config.Level.Max and (player:GetAttribute("Prestige") or 0) < Config.Prestige.Max then
		table.insert(candidates, { Text = "🌟 최고 레벨 달성!\n환생하면 영구 공격력 + 골드 획득량이 늘어요 (메뉴 I → 정보)", Ratio = 0.99, Priority = 2 })
	end
	if (player:GetAttribute("DungeonFree") or 0) >= 1 or (player:GetAttribute("Keys") or 0) + (player:GetAttribute("KeysNormal") or 0) + (player:GetAttribute("KeysHard") or 0) >= 1 then
		table.insert(candidates, { Text = string.format("🎟 오늘 무료 입장 %d회 · 🗝 열쇠 %d개!\n북쪽 게이트에서 던전에 도전하세요", player:GetAttribute("DungeonFree") or 0, (player:GetAttribute("Keys") or 0) + (player:GetAttribute("KeysNormal") or 0) + (player:GetAttribute("KeysHard") or 0)), Ratio = 0.95, Priority = 3 })
	end
	if (player:GetAttribute("Tickets") or 0) >= 1 then
		table.insert(candidates, { Text = string.format("🎫 티켓 %d장!\n뽑기 머신에서 장비를 뽑아보세요", player:GetAttribute("Tickets")), Ratio = 0.97, Priority = 4 })
	end

	table.sort(candidates, function(a, b)
		if a.Ratio ~= b.Ratio then return a.Ratio > b.Ratio end
		return a.Priority < b.Priority
	end)
	return candidates[1]
end

local last = 0
RunService.RenderStepped:Connect(function()
	local zone = player:GetAttribute("Zone")
	-- 튜토리얼 중에는 미션 바가 목표를 안내하므로 숨김. 던전 안에서도 숨김
	panel.Visible = not player:GetAttribute("TutorialActive") and zone ~= "Dungeon"
	if zone == "Dungeon" then beaconDone = true end

	local questOn = player:GetAttribute("QuestHud") == true and zone ~= "Dungeon" and dailyList ~= nil
	questPanel.Visible = questOn
	if questOn then
		local targetY = panel.Visible and 402 or 326
		if not questShown then -- 처음 나타날 때: 왼쪽에서 튕겨 들어온다
			questShown = true
			refreshQuests()
			questPanel.Position = UDim2.new(0, -300, 0, targetY)
			TweenService:Create(questPanel, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, 16, 0, targetY) }):Play()
		elseif questPanel.Position.X.Offset > 0 then
			questPanel.Position = UDim2.new(0, 16, 0, targetY)
		end
	end
	updateBeacon(questOn and zone == "Lobby")

	local now = os.clock()
	if now - last >= 0.5 then
		last = now
		if questPanel.Visible then refreshQuests() end
		local goal = pickGoal()
		if goal then
			titleLabel.Text = goal.Text
			barFill.Size = UDim2.new(goal.Ratio, 0, 1, 0)
			barFill.BackgroundColor3 = goal.Ratio >= 1 and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(110, 210, 255)
		end

		local left = (workspace:GetAttribute("GoldenUntil") or 0) - os.time()
		-- 관문 봉인막: 내 진행도에 맞춰 열려 보이게 / 닫혀 보이게 (내 화면에서만)
		local clearedNow = player:GetAttribute("ClearedZone") or 0
		for _, seal in ipairs(game:GetService("CollectionService"):GetTagged("ZoneSeal")) do
			local sealZone = seal:GetAttribute("SealZone") or 0
			local open = clearedNow >= sealZone - 1
			seal.Transparency = open and 1 or 0.45
			local sealGui = seal:FindFirstChild("SealGui")
			local sealText = sealGui and sealGui:FindFirstChild("Text")
			if sealGui then
				sealGui.Enabled = not open
			end
			if sealText and not open then
				local need = Config.Field.Gate.KillsNeeded[sealZone - 1] or 0
				if sealZone - 1 == clearedNow + 1 then
					local zoneSet = Config.Sets[Config.Sets.ZoneKeys[sealZone]]
					sealText.Text = string.format("🔒 구역 %d · %s 봉인\n구역 %d 몬스터 %d / %d 처치 · 군주 %s\n열면 %s %s 세트 획득 가능!", sealZone, Config.Field.ZoneNames[sealZone], sealZone - 1, player:GetAttribute("GateKills") or 0, need, player:GetAttribute("GateBossDone") and "✔ 격파" or "👑 미격파", zoneSet.Icon, zoneSet.Name)
				else
					sealText.Text = string.format("🔒 구역 %d · %s 봉인\n먼저 이전 관문을 여세요", sealZone, Config.Field.ZoneNames[sealZone])
				end
			end
		end

		local untilNext = (workspace:GetAttribute("GoldenNext") or 0) - os.time()
		golden.Visible = (left > 0 or untilNext > 0) and zone ~= "Dungeon"
		if left > 0 then
			golden.BackgroundColor3 = Color3.fromRGB(110, 78, 10)
			golden.TextColor3 = Color3.fromRGB(255, 236, 130)
			goldenStroke.Color = Color3.fromRGB(255, 210, 80)
			golden.Text = string.format("🌟 골든 타임! 경험치 x%d · 골드 x%.1f  (%d:%02d)", Config.Golden.XpMult, Config.Golden.GoldMult, math.floor(left / 60), left % 60)
		elseif untilNext > 0 then -- 평소에는 작게 "다음 골든 타임까지"를 보여줘서 기다릴 이유를 만든다
			golden.BackgroundColor3 = Color3.fromRGB(34, 36, 56)
			golden.TextColor3 = Color3.fromRGB(225, 228, 245)
			goldenStroke.Color = Color3.fromRGB(110, 120, 170)
			golden.Text = string.format("⏳ 다음 골든 타임까지 %d:%02d  (경험치 x%d · 골드 x%.1f)", math.floor(untilNext / 60), untilNext % 60, Config.Golden.XpMult, Config.Golden.GoldMult)
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
