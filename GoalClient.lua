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
panel.Position = UDim2.new(0, 16, 0, 282)
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
golden.Size = UDim2.new(0, 420, 0, 30)
golden.AnchorPoint = Vector2.new(0.5, 0)
golden.Position = UDim2.new(0.5, 0, 0, 88)
golden.BackgroundColor3 = Color3.fromRGB(70, 50, 10)
golden.BackgroundTransparency = 0.25
golden.BorderSizePixel = 0
golden.Font = Enum.Font.GothamBlack
golden.TextSize = 16
golden.TextColor3 = Color3.fromRGB(255, 220, 90)
golden.Visible = false
golden.Parent = gui
addCorner(golden, 8)

local function comma(n)
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- 지금 보여줄 목표 후보를 모두 만들고 (달성 비율이 가장 높은 것) 하나를 고른다
local function pickGoal()
	local candidates = {}
	local gold = player:GetAttribute("Gold") or 0
	local typeKey = player:GetAttribute("WeaponType") or "Pistol"
	local level = player:GetAttribute("WeaponLevel") or 0

	-- 무기 진화
	if level < Config.Weapon.MaxLevel then
		local nextTier
		for _, tier in ipairs(Config.Weapon.Tiers) do
			if tier.MinLevel > level then
				nextTier = tier
				break
			end
		end
		if nextTier then
			local cost = 0
			for l = level, nextTier.MinLevel - 1 do
				cost += Config.GetEnhanceCost(l)
			end
			table.insert(candidates, {
				Text = string.format("🔫 다음 진화 <font color='#ffd966'>%s</font> (+%d)\n강화 비용 %s G · 보유 %s G", nextTier.Names[typeKey], nextTier.MinLevel, comma(cost), comma(gold)),
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

	-- 지금 바로 쓸 수 있는 것
	if (player:GetAttribute("Keys") or 0) >= 1 then
		table.insert(candidates, { Text = string.format("🗝 던전 열쇠 %d개!\n북쪽 게이트에서 던전에 도전하세요", player:GetAttribute("Keys")), Ratio = 0.95, Priority = 3 })
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

	local now = os.clock()
	if now - last >= 0.5 then
		last = now
		local goal = pickGoal()
		if goal then
			titleLabel.Text = goal.Text
			barFill.Size = UDim2.new(goal.Ratio, 0, 1, 0)
			barFill.BackgroundColor3 = goal.Ratio >= 1 and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(110, 210, 255)
		end

		local left = (workspace:GetAttribute("GoldenUntil") or 0) - os.time()
		golden.Visible = left > 0 and zone ~= "Dungeon"
		if left > 0 then
			golden.Text = string.format("🌟 골든 타임! 경험치 x%d · 골드 x%.1f  (%d:%02d)", Config.Golden.XpMult, Config.Golden.GoldMult, math.floor(left / 60), left % 60)
		end
	end
end)
