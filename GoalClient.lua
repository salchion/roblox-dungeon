-- GoalClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: GoalClient)
-- "다음 목표" 패널: 지금 가장 가까운(또는 바로 할 수 있는) 목표를 항상 한 줄로 보여준다.
--   -> 세션을 끝낼 때도 "하나만 더 하면…" 하는 미완 목표가 남도록 (재방문 동기)
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

-- 작은 화면(MobileLayoutClient 가 PlayerGui 의 Ui* 속성으로 알려 준다)에서는 미션 카드들이 왼쪽 열이 아니라 위쪽 가운데(세로 화면은 왼쪽 버튼 줄 아래)에 쌓인다.
local pg = gui.Parent
local function compact() return pg:GetAttribute("UiCompact") == true end
local function lay(dy) -- dy = 미션 쌓기 맨 위에서 아래로 내려온 거리
	if compact() then
		local y = (pg:GetAttribute("UiMissionY") or 8) + dy
		if pg:GetAttribute("UiNarrow") then return UDim2.new(0, 12, 0, y) end
		return UDim2.new(0.5, -130, 0, y)
	end
	return UDim2.new(0, 16, 0, 288 + dy)
end

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 260, 0, 66)
panel.Position = lay(0)
panel.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
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

local panelH, goalStart = 66, os.clock()
local function comma(n)
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- 오늘의 퀘스트 패널: 튜토리얼에서 최종 군주에게 쓰러져 마을로 돌아온 뒤에야 나타난다 (QuestHud). 던전 / 강화 퀘스트가 항상 들어 있다.
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local TweenService = game:GetService("TweenService")
local questPanel = Instance.new("TextButton") -- 누르면 완료된 퀘스트 보상을 한꺼번에 받는다
questPanel.Text = ""
questPanel.AutoButtonColor = false
questPanel.Size = UDim2.new(0, 260, 0, 30)
questPanel.Position = UDim2.new(0, -300, 0, 288)
questPanel.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
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
local refreshQuests -- 아래에서 정의
local function claimable()
	local count = 0
	for _, quest in ipairs(dailyList or {}) do
		if not quest.Claimed and quest.Progress >= quest.Goal then count += 1 end
	end
	return count
end
questPanel.Activated:Connect(function()
	for _, quest in ipairs(dailyList or {}) do
		if not quest.Claimed and quest.Progress >= quest.Goal then
			quest.Claimed = true -- 서버 응답이 오기 전에 다시 눌러도 중복으로 보내지 않게
			Remotes.Quest:FireServer("Claim", quest.Id)
			task.wait(0.15)
		end
	end
	refreshQuests()
end)
local questShown = false
local beaconDone = false
local beacon, beaconStart = nil, 0

Remotes.Quest.OnClientEvent:Connect(function(action, data)
	if action == "State" then dailyList = data.Daily end
end)

task.defer(function() Remotes.Quest:FireServer("Request") end) -- 퀘스트 상태를 한 번 더 요청 (스크립트 시작 순서 때문에 놓칠 수 있다)

function refreshQuests()
	if not dailyList then return end
	local lines = { "<font color='#ffd966'><b>📋 오늘의 퀘스트</b></font>" }
	for _, quest in ipairs(dailyList) do
		local done = quest.Progress >= quest.Goal
		if quest.Claimed then
			table.insert(lines, string.format("<font color='#7a7f95'>✔ %s</font>", quest.Desc))
		elseif done then
			table.insert(lines, string.format("<font color='#78ff8c'>✅ %s — 눌러서 받기!</font>", quest.Desc))
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

-- 방치 수입 표시: 휴식 구역에서 방치 중일 때 초당 골드와 배율 (BM 배율이 올라가면 눈에 보인다)
local idleLabel = Instance.new("TextLabel")
idleLabel.Size = UDim2.new(0, 420, 0, 66)
idleLabel.AnchorPoint = Vector2.new(0.5, 0)
idleLabel.Position = UDim2.new(0.5, 0, 0, 128)
local idleW = 420
idleLabel.BackgroundColor3 = Color3.fromRGB(26, 30, 48)
idleLabel.BackgroundTransparency = 0.15
idleLabel.BorderSizePixel = 0
idleLabel.Font = Enum.Font.GothamBold
idleLabel.TextSize = 14
idleLabel.TextColor3 = Color3.fromRGB(255, 225, 120)
idleLabel.RichText = true
idleLabel.Visible = false
idleLabel.Parent = gui
addCorner(idleLabel, 8)
local function commas(n)
	local text = tostring(math.floor(n or 0))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
-- 방치 게이지: 방치로 골드를 받을 때마다 막대가 차오르고, 가득 찰 때까지 남은 시간을 보여 준다 (가득 차도 계속 받는다)
local idleBarBack = Instance.new("Frame")
idleBarBack.Size = UDim2.new(1, -24, 0, 8)
idleBarBack.Position = UDim2.new(0, 12, 1, -14)
idleBarBack.BackgroundColor3 = Color3.fromRGB(12, 14, 24)
idleBarBack.BorderSizePixel = 0
idleBarBack.Parent = idleLabel
addCorner(idleBarBack, 4)
local idleBarFill = Instance.new("Frame")
idleBarFill.Size = UDim2.new(0, 0, 1, 0)
idleBarFill.BackgroundColor3 = Color3.fromRGB(120, 215, 255)
idleBarFill.BorderSizePixel = 0
idleBarFill.Parent = idleBarBack
addCorner(idleBarFill, 4)
local function commas(n)
	local text = tostring(math.floor(n or 0))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function timeLeft(seconds)
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 3600 then return string.format("%d시간 %d분", seconds // 3600, (seconds % 3600) // 60) end
	return string.format("%d분 %d초", seconds // 60, seconds % 60)
end
RunService.Heartbeat:Connect(function()
	local active = player:GetAttribute("IdleActive") == true and player:GetAttribute("Zone") == "Lobby" and player:GetAttribute("IdleCapHours") ~= nil
	idleLabel.Visible = active -- 휴식 구역에 서 있을 때만
	if not active then return end
	local capSeconds = (player:GetAttribute("IdleCapHours") or 2) * 3600
	local seconds = player:GetAttribute("IdleSeconds") or 0
	local ratio = math.clamp(seconds / capSeconds, 0, 1)
	idleLabel.Size = UDim2.new(0, 420, 0, 66)
	idleBarFill.Size = UDim2.new(ratio, 0, 1, 0)
	idleBarFill.BackgroundColor3 = ratio >= 1 and Color3.fromRGB(255, 220, 110) or Color3.fromRGB(120, 215, 255)
	local mult = player:GetAttribute("IdleMultTotal") or 1
	local left = ratio >= 1 and "<font color='#ffe16e'>가득 참! (계속 받는 중)</font>" or string.format("가득 차려면 <font color='#8fffb0'>%s</font>", timeLeft(capSeconds - seconds))
	idleLabel.Text = string.format("💤 방치 수입  +%s G/초   <font color='#9ad7ff'>x%.2f</font>  ·  받은 <font color='#ffe16e'>%s G</font>\n%s  ·  가득 차면 +%s G", tostring(player:GetAttribute("IdleRate") or 0), mult, commas(player:GetAttribute("IdleEarned")), left, commas(player:GetAttribute("IdleFullGold")))
	idleLabel.TextYAlignment = Enum.TextYAlignment.Top
end)

-- 처음 던전을 마치고 돌아오면 한 번: "다음 목표(전투력)"와 "무엇으로 강해지는가" 한 장 (서버가 Growth 이벤트로 보낸다)
local guide = Instance.new("Frame")
guide.Size = UDim2.new(0, 420, 0, 320)
guide.AnchorPoint = Vector2.new(0.5, 0.5)
guide.Position = UDim2.new(0.5, 0, 0.5, 0)
guide.BackgroundColor3 = Color3.fromRGB(20, 22, 36)
guide.BackgroundTransparency = 0.06
guide.BorderSizePixel = 0
guide.Visible = false
guide.ZIndex = 50
guide.Parent = gui
addCorner(guide, 14)
local guideStroke = Instance.new("UIStroke")
guideStroke.Color = Color3.fromRGB(255, 205, 90)
guideStroke.Thickness = 3
guideStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
guideStroke.Parent = guide
local guideScale = Instance.new("UIScale")
guideScale.Parent = guide
local guideText = Instance.new("TextLabel")
guideText.Size = UDim2.new(1, -28, 1, -64)
guideText.Position = UDim2.new(0, 14, 0, 10)
guideText.BackgroundTransparency = 1
guideText.Font = Enum.Font.GothamBold
guideText.TextSize = 14
guideText.TextColor3 = Color3.new(1, 1, 1)
guideText.TextXAlignment = Enum.TextXAlignment.Left
guideText.TextYAlignment = Enum.TextYAlignment.Top
guideText.RichText = true
guideText.ZIndex = 51
guideText.Parent = guide
local guideClose = Instance.new("TextButton")
guideClose.Size = UDim2.new(1, -28, 0, 40)
guideClose.Position = UDim2.new(0, 14, 1, -50)
guideClose.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
guideClose.BorderSizePixel = 0
guideClose.Font = Enum.Font.GothamBlack
guideClose.TextSize = 18
guideClose.TextColor3 = Color3.new(1, 1, 1)
guideClose.Text = "좋아요, 강해지러 가자!"
guideClose.ZIndex = 51
guideClose.Parent = guide
addCorner(guideClose, 8)
guideClose.Activated:Connect(function() guide.Visible = false end)
Remotes.Tutorial.OnClientEvent:Connect(function(action, data)
	if action ~= "Growth" then return end
	local lines = { "<font size='20' color='#ffd966'><b>💪 더 강해지는 법</b></font>" }
	local gap = data.Need - data.Power
	if gap > 0 then
		table.insert(lines, string.format("<font color='#9ad7ff'>🎯 목표: 구역 %d 군주 격파</font>  <font size='12' color='#c9c0e0'>(권장 전투력 %s · 내 전투력 %s)</font>", data.Zone, comma(data.Need), comma(data.Power)))
	else
		table.insert(lines, string.format("<font color='#78ff8c'>🎯 구역 %d 군주에 도전할 준비 완료!</font>  <font size='12' color='#c9c0e0'>(권장 %s · 내 %s)</font>", data.Zone, comma(data.Need), comma(data.Power)))
	end
	table.insert(lines, "")
	for _, source in ipairs(data.Sources) do
		table.insert(lines, string.format("%s <b>%s</b> — %s\n      <font size='12' color='#ffd966'>%s</font>", source.Icon, source.Name, source.Desc, source.Status))
	end
	guideText.Text = table.concat(lines, "\n")
	guide.Visible = true
	guideScale.Scale = 0.6
	TweenService:Create(guideScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(45, function() guide.Visible = false end)
end)

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
			local freeLeft = player:GetAttribute("TutorialFree") == true and level < 3
			table.insert(candidates, {
				Text = freeLeft and string.format("🔫 다음 무기 <font color='#ffd966'>%s</font>\n✨ 지금은 강화가 무료예요! (%d번 남음)", nextTier.Name, 3 - level) or string.format("🔫 다음 무기 <font color='#ffd966'>%s</font> (%d/%d)\n강화 비용 %s G · 보유 %s G", nextTier.Name, nextTier.Index, Config.Weapon.WeaponCount, comma(cost), comma(gold)),
				Ratio = freeLeft and 1 or math.min(1, gold / cost), Priority = 1,
			})
		end
	end

	-- 레벨업 / 돌파
	local charLevel = player:GetAttribute("Level") or 1
	if charLevel < Config.Level.Max then
		if player:GetAttribute("GateBlocked") then
			table.insert(candidates, { Text = "🚧 레벨이 막혔어요!\n메뉴(B) → 성장에서 돌파를 진행하세요", Ratio = 1, Priority = 0 })
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
		table.insert(candidates, { Text = "🌟 최고 레벨 달성!\n환생하면 영구 공격력 + 골드 획득량이 늘어요 (메뉴 I → 캐릭터 > 정보)", Ratio = 0.99, Priority = 2 })
	end
	if (player:GetAttribute("DungeonFree") or 0) >= 1 or (player:GetAttribute("Keys") or 0) + (player:GetAttribute("KeysNormal") or 0) + (player:GetAttribute("KeysHard") or 0) >= 1 then
		table.insert(candidates, { Text = string.format("🎟 오늘 무료 입장 %d회 · 🗝 열쇠 %d개!\n북쪽 게이트에서 던전에 도전하세요", player:GetAttribute("DungeonFree") or 0, (player:GetAttribute("Keys") or 0) + (player:GetAttribute("KeysNormal") or 0) + (player:GetAttribute("KeysHard") or 0)), Ratio = 0.95, Priority = 3 })
	end
	if (player:GetAttribute("ClearedZone") or 0) >= Config.Field.ZoneCount - 1 and not player:GetAttribute("HintDone_FieldClear") and not player:GetAttribute("TutorialActive") then
		table.insert(candidates, { Text = "👑 마지막 8구역의 군주를 쓰러뜨려요!\n필드를 정복하면 끝없는 심연이 열려요", Ratio = 0.95, Priority = 3 })
	end
	if player:GetAttribute("HintDone_FieldClear") and not player:GetAttribute("TutorialActive") then
		table.insert(candidates, { Text = string.format("🌀 필드 정복! 이제 심연이에요\n마을 포털에서 심연 깊이 %d 에 도전하세요 (깊을수록 보상 x배)", player:GetAttribute("RiftUnlocked") or 1), Ratio = 0.98, Priority = 3 })
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
	panel.Position = lay(0)
	-- 마을이거나 20초가 지나면 작게: 제목 한 줄 + 목표 한 줄 (진행 막대는 숨김)
	local smallCard = zone == "Lobby" or os.clock() - goalStart > 20
	local wantH = smallCard and 46 or 66
	if panelH ~= wantH then
		panelH = wantH
		panel.Size = UDim2.new(0, 260, 0, wantH)
		barBack.Visible = not smallCard
		titleLabel.Size = UDim2.new(1, -16, 0, smallCard and 36 or 34)
	end
	if zone == "Dungeon" then beaconDone = true end

	local questOn = player:GetAttribute("QuestHud") == true and zone ~= "Dungeon" and dailyList ~= nil
	questPanel.Visible = questOn
	if questOn then
		local targetDy = panel.Visible and (panelH + 10) or (player:GetAttribute("TutorialCardUp") and (player:GetAttribute("TutorialCardH") or 116) + 8 or 0)
		if not questShown then -- 처음 나타날 때: 왼쪽에서 튕겨 들어온다 (작은 화면은 바로 제자리)
			questShown = true
			refreshQuests()
			if compact() then
				questPanel.Position = lay(targetDy)
			else
				questPanel.Position = UDim2.new(0, -300, 0, 288 + targetDy)
				TweenService:Create(questPanel, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = lay(targetDy) }):Play()
			end
		elseif compact() or questPanel.Position.X.Offset > 0 then
			questPanel.Position = lay(targetDy)
		end
	end
	-- 방치 수입 줄은 쌓인 미션 카드들 바로 아래로 (작은 화면에서만)
	if compact() then
		local cardUp = player:GetAttribute("TutorialCardUp")
		local tutH = player:GetAttribute("TutorialCardH") or 116
		local bottom = (panel.Visible and panelH) or (cardUp and tutH) or 0
		if questOn then bottom = (panel.Visible and (panelH + 10) or (cardUp and (tutH + 8) or 0)) + 30 end
		idleLabel.Position = UDim2.new(0.5, 0, 0, (pg:GetAttribute("UiMissionY") or 8) + bottom + 6)
	else
		idleLabel.Position = UDim2.new(0.5, 0, 0, 128)
	end
	updateBeacon(questOn and zone == "Lobby")

	local now = os.clock()
	if now - last >= 0.5 then
		last = now
		if questPanel.Visible then
			refreshQuests()
			questStroke.Thickness = claimable() > 0 and 4 or 2
		end
		local goal = pickGoal()
		if goal then
			titleLabel.Text = goal.Text
			barFill.Size = UDim2.new(goal.Ratio, 0, 1, 0)
			barFill.BackgroundColor3 = goal.Ratio >= 1 and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(110, 210, 255)
		end

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
