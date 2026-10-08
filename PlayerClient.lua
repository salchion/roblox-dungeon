-- PlayerClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript)
-- 3인칭 시점. 마우스(또는 터치) 방향으로 공격하고, 상황에 따라 UI가 바뀐다.
--   로비   : 파티 패널(초대/수락/추방/나가기), 무기 강화창, 게이트 안내
--   던전   : 웨이브 정보, 보스 체력바, 스탯 분배 패널(숫자키 1/2/3), 결과 화면
-- UI 구역은 서버가 설정하는 플레이어 Attribute "Zone"("Lobby" / "Dungeon")으로 전환된다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- 무기는 서버가 장착해주므로 기본 툴바(숫자키 1/2/3 충돌)는 끈다
task.spawn(function()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
			break
		end
		task.wait(0.5)
	end
end)

------------------------------------------------------------
-- UI 헬퍼
------------------------------------------------------------
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

local function makePanel(props, parent)
	local base = {
		BackgroundColor3 = Color3.fromRGB(20, 20, 30),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local frame = create("Frame", base, parent)
	rounded(frame)
	return frame
end

local function makeLabel(props, parent)
	local base = {
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextWrapped = true,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	return create("TextLabel", base, parent)
end

local function makeButton(props, parent, onClick)
	local base = {
		BackgroundColor3 = Color3.fromRGB(70, 110, 220),
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		AutoButtonColor = true,
		BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local button = create("TextButton", base, parent)
	rounded(button, 6)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

local function clearChildren(container)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local GREEN = Color3.fromRGB(60, 170, 90)
local RED = Color3.fromRGB(200, 70, 70)
local GRAY = Color3.fromRGB(70, 70, 85)

local gui = create("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = true }, player:WaitForChild("PlayerGui"))

------------------------------------------------------------
-- 공통: 상단 좌측 정보, 알림
------------------------------------------------------------
local infoPanel = makePanel({ Size = UDim2.new(0, 240, 0, 176), Position = UDim2.new(0, 16, 0, 60) }, gui) -- (Roblox 상단 버튼과 겹치지 않게 아래로)
local infoLabel = makeLabel({
	Size = UDim2.new(1, -20, 1, -16),
	Position = UDim2.new(0, 10, 0, 8),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	RichText = true,
}, infoPanel)

-- 경험치 막대 (정보 패널 맨 아래)
local xpBack = create("Frame", {
	Size = UDim2.new(1, -20, 0, 7), Position = UDim2.new(0, 10, 1, -14),
	BackgroundColor3 = Color3.fromRGB(45, 45, 60), BorderSizePixel = 0,
}, infoPanel)
rounded(xpBack, 4)
local xpFill = create("Frame", {
	Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(110, 200, 255), BorderSizePixel = 0,
}, xpBack)
rounded(xpFill, 4)

local toastLabel = makeLabel({
	Size = UDim2.new(0, 460, 0, 40),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 110),
	BackgroundColor3 = Color3.fromRGB(20, 20, 30),
	BackgroundTransparency = 0.25,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	Visible = false,
}, gui)
rounded(toastLabel)

local toastToken = 0
local function toast(text)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.Visible = true
	task.delay(3.5, function()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

Remotes.Notify.OnClientEvent:Connect(toast)

local function currentZone()
	return player:GetAttribute("Zone") or "Lobby"
end

local function weaponText(level)
	local tier = Config.GetWeaponTier(level)
	return Config.FormatWeapon(level), tier.Color
end

------------------------------------------------------------
-- 로비: 무기 강화창
------------------------------------------------------------
local enhancePanel = makePanel({
	Size = UDim2.new(0, 400, 0, 480),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Visible = false,
}, gui)

makeLabel({
	Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8),
	Text = "🔨 무기 강화", Font = Enum.Font.GothamBlack, TextSize = 24,
}, enhancePanel)

local enhanceWeapon = makeLabel({
	Size = UDim2.new(1, -24, 0, 36), Position = UDim2.new(0, 12, 0, 50),
	Font = Enum.Font.GothamBlack, TextSize = 26,
}, enhancePanel)

-- 3D 미리보기: 지금 총 / 다음 진화 총 (WeaponPreviews 모델을 복제해서 보여준다)
local function makePreview(parent, position, caption)
	local frame = Instance.new("ViewportFrame")
	frame.Size = UDim2.new(0, 170, 0, 100)
	frame.Position = position
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BorderSizePixel = 0
	frame.Ambient = Color3.fromRGB(170, 170, 180)
	frame.LightColor = Color3.new(1, 1, 1)
	frame.Parent = parent
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = frame
	frame.CurrentCamera = cam
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(200, 200, 215)
	label.Text = caption
	label.Parent = frame
	local shown
	return function(typeKey, tierIndex)
		if shown then
			shown:Destroy()
			shown = nil
		end
		local previews = ReplicatedStorage:FindFirstChild("WeaponPreviews")
		local source = previews and previews:FindFirstChild("W" .. tierIndex)
		if not source then return end
		shown = source:Clone()
		shown.Parent = frame
		local cf, size = shown:GetBoundingBox()
		local d = math.max(size.X, size.Y, size.Z) * 1.6
		cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(d, d * 0.25, d * 0.15), cf.Position)
	end
end
local previewNow = makePreview(enhancePanel, UDim2.new(0, 14, 0, 90), "지금")
local previewNext = makePreview(enhancePanel, UDim2.new(1, -184, 0, 90), "다음 진화")
local previewNextName = makeLabel({
	Size = UDim2.new(0, 170, 0, 20), Position = UDim2.new(1, -184, 0, 192),
	TextSize = 14, Font = Enum.Font.GothamBold,
}, enhancePanel)
local previewNowName = makeLabel({
	Size = UDim2.new(0, 170, 0, 20), Position = UDim2.new(0, 14, 0, 192),
	TextSize = 14, Font = Enum.Font.GothamBold,
}, enhancePanel)

local enhanceInfo = makeLabel({
	Size = UDim2.new(1, -40, 0, 150), Position = UDim2.new(0, 20, 0, 218),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	RichText = true,
}, enhancePanel)

local enhanceResult = makeLabel({
	Size = UDim2.new(1, -24, 0, 28), Position = UDim2.new(0, 12, 0, 376),
	Font = Enum.Font.GothamBold, TextSize = 17,
}, enhancePanel)

local enhanceButton = makeButton({
	Size = UDim2.new(0, 170, 0, 44), Position = UDim2.new(0, 20, 1, -58),
	Text = "강화하기", TextSize = 18, BackgroundColor3 = GREEN,
}, enhancePanel, function()
	Remotes.Enhance:FireServer()
end)

makeButton({
	Size = UDim2.new(0, 170, 0, 44), Position = UDim2.new(1, -190, 1, -58),
	Text = "닫기", TextSize = 18, BackgroundColor3 = GRAY,
}, enhancePanel, function()
	enhancePanel.Visible = false
end)

local function refreshEnhance()
	local level = player:GetAttribute("WeaponLevel") or 0
	local gold = player:GetAttribute("Gold") or 0
	local name, color = weaponText(level)
	enhanceWeapon.Text = name
	enhanceWeapon.TextColor3 = color

	local typeKey = player:GetAttribute("WeaponType") or "Pistol"
	local tierIndex = Config.GetWeaponTierIndex(level)
	local tiers = Config.Weapon.Tiers
	previewNow(typeKey, tierIndex)
	previewNowName.Text = Config.GetWeaponName(typeKey, level)
	previewNowName.TextColor3 = tiers[tierIndex].Color
	if tierIndex < #tiers then
		local nextTier = tiers[tierIndex + 1]
		previewNext(typeKey, tierIndex + 1)
		previewNextName.Text = string.format("%s (%d/%d)", nextTier.Name, nextTier.Index, #tiers)
		previewNextName.TextColor3 = nextTier.Rainbow and Color3.fromRGB(255, 120, 255) or nextTier.Color
	else
		previewNext(typeKey, tierIndex)
		previewNextName.Text = "마지막 무기!"
		previewNextName.TextColor3 = Color3.fromRGB(255, 217, 102)
	end

	local lines = {
		string.format("공격력 배율  x%.2f", Config.GetDamageMultiplier(level)),
		string.format("무기 크기      x%.2f", Config.GetWeaponScale(level)),
	}

	if level >= Config.Weapon.MaxLevel then
		table.insert(lines, "\n<font color='#ffd966'>마지막 무기를 최대로 강화했어요!</font>")
		enhanceButton.Text = "MAX"
		enhanceButton.BackgroundColor3 = GRAY
	else
		local cost = Config.GetEnhanceCost(level)
		table.insert(lines, string.format("공격력 배율 다음 단계  x%.2f", Config.GetDamageMultiplier(level + 1)))
		-- 강화하면 무엇이 달라지는지: 단계마다 총에 링이 생기고 탄이 커지고, 마지막 단계를 넘으면 새 무기
		local curTier = Config.GetWeaponTier(level)
		local stageNow = Config.GetWeaponStage(level)
		table.insert(lines, string.format("<font color='#9ad7ff'>이 무기 단계 %s  (+%d/%d)</font>", Config.StageBar(level), stageNow, curTier.Steps))
		table.insert(lines, "<font color='#bbbbcc'>강화할 때마다: 공격력 증가 · 총에 빛나는 링 추가 · 발사체가 조금 커져요</font>")
		table.insert(lines, string.format("\n강화 비용  <font color='#ffd966'>%d G</font>  (보유 %d G)", cost, gold))
		table.insert(lines, string.format("성공 확률  %d%%  (실패해도 단계는 유지)", math.floor(Config.GetEnhanceChance(level) * 100 + 0.5)))

		if tierIndex < #tiers then
			local nextTier = tiers[tierIndex + 1]
			table.insert(lines, string.format("<font color='#9ad7ff'>다음 무기 [%s] 까지 %d단계 — %s</font>", nextTier.Name, nextTier.MinLevel - level, Config.WeaponTypes[nextTier.Class].Desc))
		end
		enhanceButton.Text = "강화하기"
		enhanceButton.BackgroundColor3 = gold >= cost and GREEN or GRAY
	end
	enhanceInfo.Text = table.concat(lines, "\n")
end

Remotes.Enhance.OnClientEvent:Connect(function(ok, message)
	if ok then -- 성공하면 다음 진화까지 남은 단계를 알려줘서 "하나만 더" 하고 싶게 만든다
		local level = player:GetAttribute("WeaponLevel") or 0
		for _, tier in ipairs(Config.Weapon.Tiers) do
			if tier.MinLevel > level then
				message = string.format("%s  ✨ %s 까지 %d단계!", message, tier.Name, tier.MinLevel - level)
				break
			end
		end
	end
	enhanceResult.Text = message
	enhanceResult.TextColor3 = ok and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 130, 130)
	refreshEnhance()
end)

Remotes.OpenEnhance.OnClientEvent:Connect(function()
	enhanceResult.Text = ""
	refreshEnhance()
	enhancePanel.Visible = true
end)

------------------------------------------------------------
-- 로비: 장비창 (갑옷 / 장갑 / 신발 강화 + 보스 티켓 뽑기)
------------------------------------------------------------
local gearPanel = makePanel({
	Size = UDim2.new(0, 780, 0, 500),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Visible = false,
}, gui)

makeLabel({
	Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8),
	Text = "🛡 장비 · 뽑기", Font = Enum.Font.GothamBlack, TextSize = 24,
}, gearPanel)

local gearMessage = makeLabel({
	Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0, 12, 0, 50),
	Font = Enum.Font.GothamBold, TextSize = 16, RichText = true,
}, gearPanel)

local gearRows = {}
for index, slot in ipairs(Config.Gear.Slots) do
	local card = makePanel({
		Size = UDim2.new(0.5, -18, 0, 88), Position = UDim2.new(((index - 1) % 2) * 0.5, ((index - 1) % 2 == 0) and 12 or 6, 0, 98 + ((index - 1) // 2) * 96),
		BackgroundColor3 = Color3.fromRGB(40, 40, 58),
	}, gearPanel)
	local nameLabel = makeLabel({
		Size = UDim2.new(1, -150, 0, 26), Position = UDim2.new(0, 12, 0, 6),
		Font = Enum.Font.GothamBlack, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, RichText = true,
	}, card)
	local statLabel = makeLabel({
		Size = UDim2.new(1, -150, 0, 22), Position = UDim2.new(0, 12, 0, 34),
		TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, RichText = true,
	}, card)
	local costLabel = makeLabel({
		Size = UDim2.new(1, -150, 0, 22), Position = UDim2.new(0, 12, 0, 58),
		TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, RichText = true,
		TextColor3 = Color3.fromRGB(200, 200, 215),
	}, card)
	local button = makeButton({
		Size = UDim2.new(0, 120, 0, 34), Position = UDim2.new(1, -132, 0.5, -17), Text = "강화",
	}, card, function()
		Remotes.Gear:FireServer("Enhance", slot.Key)
	end)
	gearRows[slot.Key] = { Name = nameLabel, Stat = statLabel, Cost = costLabel, Button = button }
end

local gachaCard = makePanel({
	Size = UDim2.new(1, -24, 0, 100), Position = UDim2.new(0, 12, 0, 390),
	BackgroundColor3 = Color3.fromRGB(55, 40, 80),
}, gearPanel)
local ticketLabel = makeLabel({
	Size = UDim2.new(0.5, -12, 0, 30), Position = UDim2.new(0, 12, 0, 8),
	Font = Enum.Font.GothamBlack, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left,
}, gachaCard)
local rateParts = {}
for index, rate in ipairs(Config.Gacha.Rates) do
	table.insert(rateParts, string.format("%s %d%%", Config.Gear.RarityNames[index], rate))
end
makeLabel({
	Size = UDim2.new(1, -24, 0, 46), Position = UDim2.new(0, 12, 0, 44),
	Text = table.concat(rateParts, " · ") .. "\n같은 부위의 같거나 낮은 등급은 골드로 교환돼요. 티켓은 던전 보스 / 필드 보스에게서 나와요.",
	TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(205, 200, 225),
}, gachaCard)
local rollButton = makeButton({
	Size = UDim2.new(0, 180, 0, 34), Position = UDim2.new(1, -192, 0, 8),
	Text = "🎫 뽑기 (티켓 1장)", BackgroundColor3 = Color3.fromRGB(150, 70, 230),
}, gachaCard, function()
	Remotes.Gear:FireServer("Roll")
end)

makeButton({
	Size = UDim2.new(0, 64, 0, 28), Position = UDim2.new(1, -76, 0, 10), Text = "닫기", TextSize = 14, BackgroundColor3 = GRAY,
}, gearPanel, function()
	gearPanel.Visible = false
end)

local function refreshGear()
	local gold = player:GetAttribute("Gold") or 0
	local tickets = player:GetAttribute("Tickets") or 0
	local maxLevel = Config.Gear.MaxLevel

	for _, slot in ipairs(Config.Gear.Slots) do
		local row = gearRows[slot.Key]
		local rarity = player:GetAttribute("Gear_" .. slot.Key .. "_R") or 0
		local level = player:GetAttribute("Gear_" .. slot.Key .. "_L") or 0

		if rarity <= 0 then
			row.Name.Text = slot.Name .. " — 비어 있음"
			row.Stat.Text = slot.StatName .. " 효과 · 뽑기로 얻을 수 있어요"
			row.Cost.Text = ""
			row.Button.Text = "—"
			row.Button.BackgroundColor3 = GRAY
		else
			local color = Config.Gear.RarityColors[rarity]
			row.Name.Text = string.format("<font color='#%s'>[%s] %s</font>  +%d", color:ToHex(), Config.Gear.RarityNames[rarity], slot.Names[rarity], level)
			local statText = Config.FormatGearStat(slot.Key, Config.GetGearStat(slot.Key, rarity, level))
			if level < maxLevel then
				statText ..= "   →   " .. Config.FormatGearStat(slot.Key, Config.GetGearStat(slot.Key, rarity, level + 1))
				local cost = Config.GetGearCost(slot.Key, rarity, level)
				row.Cost.Text = string.format("강화 비용 <font color='#ffd966'>%d G</font> · 성공 %d%%", cost, math.floor(Config.GetGearEnhanceChance(level) * 100 + 0.5))
				row.Button.Text = "강화"
				row.Button.BackgroundColor3 = gold >= cost and GREEN or GRAY
			else
				row.Cost.Text = "최대 강화 단계!"
				row.Button.Text = "MAX"
				row.Button.BackgroundColor3 = GRAY
			end
			row.Stat.Text = statText
		end
	end

	ticketLabel.Text = string.format("🎫 티켓 %d장", tickets)
	rollButton.BackgroundColor3 = tickets > 0 and Color3.fromRGB(150, 70, 230) or GRAY
end

Remotes.Gear.OnClientEvent:Connect(function(action, result)
	if action ~= "Result" then return end
	local color
	if result.Roll then
		color = Config.Gear.RarityColors[result.Roll.Rarity]
	else
		color = result.Ok and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 130, 130)
	end
	gearMessage.Text = result.Message
	gearMessage.TextColor3 = color
	refreshGear()
end)

-- 뽑기 연출: 영웅 이상이 나오면 화면이 어두워지고 카드가 튀어나온다 (등급이 높을수록 길고 화려하게). 아무 곳이나 누르면 닫힌다.
do
	local ICONS = { Armor = "🛡", Gloves = "🧤", Boots = "👢", Helmet = "⛑", Ring = "💍", Necklace = "📿" }
	Remotes.Gear.OnClientEvent:Connect(function(action, result)
		local roll = action == "Result" and result.Roll
		if not roll or roll.Rarity < 3 then return end
		local old = gui:FindFirstChild("GachaReveal")
		if old then old:Destroy() end

		local rarity = roll.Rarity
		local color = Config.Gear.RarityColors[rarity]
		local hold = ({ 1.5, 2.2, 3.0 })[rarity - 2]
		local root = create("TextButton", {
			Name = "GachaReveal", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1,
			Text = "", AutoButtonColor = false, ZIndex = 60,
		}, gui)
		local function fade(object, goal, time, style)
			TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
		end
		fade(root, { BackgroundTransparency = 0.3 }, 0.25)

		-- 퍼져 나가는 빛 고리 (등급이 높을수록 많이)
		for i = 1, rarity - 1 do
			task.delay((i - 1) * 0.22, function()
				if not root.Parent then return end
				local ring = create("Frame", {
					Size = UDim2.new(0, 40, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
					BackgroundTransparency = 1, ZIndex = 61,
				}, root)
				create("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
				create("UIStroke", { Color = color, Thickness = 8 }, ring)
				fade(ring, { Size = UDim2.new(0, 900, 0, 900) }, 0.9)
				local stroke = ring:FindFirstChildOfClass("UIStroke")
				fade(stroke, { Transparency = 1, Thickness = 1 }, 0.9)
			end)
		end

		-- 번쩍임
		local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = rarity == 5 and Color3.new(1, 1, 1) or color, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 70 }, root)
		fade(flash, { BackgroundTransparency = 1 }, 0.5)

		-- 카드
		local card = create("Frame", {
			Size = UDim2.new(0, 60, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
			BackgroundColor3 = Color3.fromRGB(24, 22, 36), BorderSizePixel = 0, ZIndex = 62,
		}, root)
		rounded(card, 16)
		local stroke = create("UIStroke", { Color = color, Thickness = 5 }, card)
		if rarity == 5 then -- 신화: 무지개 테두리가 돈다
			local gradient = create("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
					ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
				}),
			}, stroke)
			task.spawn(function()
				local rotation = 0
				while root.Parent do
					rotation += 6
					gradient.Rotation = rotation
					task.wait()
				end
			end)
		end
		fade(card, { Size = UDim2.new(0, 340, 0, 220) }, 0.45, Enum.EasingStyle.Back)

		task.delay(0.3, function()
			if not root.Parent then return end
			makeLabel({ Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 0, 14), Text = ICONS[roll.Slot] or "🎁", TextSize = 56, ZIndex = 63 }, card)
			makeLabel({
				Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 92), Text = string.format("★ %s ★", Config.Gear.RarityNames[rarity]),
				TextSize = rarity >= 4 and 30 or 26, Font = Enum.Font.GothamBlack, TextColor3 = color, ZIndex = 63,
			}, card)
			makeLabel({
				Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 134), Text = roll.Name or "", TextSize = 20,
				Font = Enum.Font.GothamBold, ZIndex = 63,
			}, card)
			makeLabel({
				Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -28), Text = roll.Equipped and "장착했어요!" or "가방에 넣었어요",
				TextSize = 13, TextColor3 = Color3.fromRGB(190, 190, 210), ZIndex = 63,
			}, card)
		end)

		local function close()
			if not root.Parent then return end
			fade(root, { BackgroundTransparency = 1 }, 0.25)
			fade(card, { Size = UDim2.new(0, 60, 0, 40) }, 0.25)
			game:GetService("Debris"):AddItem(root, 0.3)
		end
		root.Activated:Connect(close)
		task.delay(hold, close)
	end)
end

Remotes.OpenGear.OnClientEvent:Connect(function()
	gearMessage.Text = ""
	refreshGear()
	gearPanel.Visible = true
end)

------------------------------------------------------------
-- 로비: 파티 패널
------------------------------------------------------------
local lobbyFrame = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1 }, gui)

local partyPanel = makePanel({
	Size = UDim2.new(0, 270, 0, 420),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 16),
}, lobbyFrame)

local partyTitle = makeLabel({
	Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 10, 0, 8),
	Font = Enum.Font.GothamBlack, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
}, partyPanel)

local memberList = create("Frame", {
	Size = UDim2.new(1, -20, 0, 140), Position = UDim2.new(0, 10, 0, 40), BackgroundTransparency = 1,
}, partyPanel)
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, memberList)

local leaveButton = makeButton({
	Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 186),
	Text = "파티 나가기", BackgroundColor3 = RED,
}, partyPanel, function()
	Remotes.Party:FireServer("Leave")
end)

makeLabel({
	Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 0, 224),
	Text = "로비 플레이어 (초대)", Font = Enum.Font.GothamBold, TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(190, 190, 210),
}, partyPanel)

local playerList = create("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -256), Position = UDim2.new(0, 10, 0, 248),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 4,
}, partyPanel)
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, playerList)

local partyData = nil -- 서버가 보내준 현재 파티 {Id, Leader, Members = {{UserId, Name}}}

local function isPartyLeaderOrSolo()
	return partyData == nil or partyData.Leader == player.UserId
end

local function refreshParty()
	local count = partyData and #partyData.Members or 1
	partyTitle.Text = string.format("파티 (%d/%d)", count, Config.Party.MaxSize)

	clearChildren(memberList)
	if partyData then
		for index, member in ipairs(partyData.Members) do
			local row = makePanel({ Size = UDim2.new(1, 0, 0, 30), LayoutOrder = index, BackgroundColor3 = Color3.fromRGB(45, 45, 65) }, memberList)
			local isLeader = member.UserId == partyData.Leader
			local target = Players:GetPlayerByUserId(member.UserId)
			local level = target and target:GetAttribute("WeaponLevel") or 0
			makeLabel({
				Size = UDim2.new(1, -60, 1, 0), Position = UDim2.new(0, 8, 0, 0),
				Text = string.format("%s%s  (+%d)", isLeader and "👑 " or "", member.Name, level),
				TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14,
			}, row)
			if partyData.Leader == player.UserId and member.UserId ~= player.UserId then
				makeButton({
					Size = UDim2.new(0, 48, 0, 22), Position = UDim2.new(1, -52, 0.5, -11),
					Text = "추방", TextSize = 12, BackgroundColor3 = RED,
				}, row, function()
					Remotes.Party:FireServer("Kick", member.UserId)
				end)
			end
		end
	else
		makeLabel({
			Size = UDim2.new(1, 0, 0, 40), Text = "파티가 없어요.\n아래에서 초대해보세요!",
			TextSize = 14, TextColor3 = Color3.fromRGB(190, 190, 210),
		}, memberList)
	end
	leaveButton.Visible = partyData ~= nil

	clearChildren(playerList)
	local canInvite = isPartyLeaderOrSolo() and (not partyData or #partyData.Members < Config.Party.MaxSize)
	local order = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other:GetAttribute("Zone") == "Lobby" then
			order += 1
			local inParty = (other:GetAttribute("PartyId") or 0) ~= 0
			local row = makePanel({ Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, BackgroundColor3 = Color3.fromRGB(45, 45, 65) }, playerList)
			makeLabel({
				Size = UDim2.new(1, -64, 1, 0), Position = UDim2.new(0, 8, 0, 0),
				Text = string.format("%s  (+%d)", other.DisplayName, other:GetAttribute("WeaponLevel") or 0),
				TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14,
			}, row)
			if inParty then
				makeLabel({
					Size = UDim2.new(0, 56, 1, 0), Position = UDim2.new(1, -60, 0, 0),
					Text = "파티중", TextSize = 12, TextColor3 = Color3.fromRGB(150, 150, 170),
				}, row)
			elseif canInvite then
				makeButton({
					Size = UDim2.new(0, 48, 0, 22), Position = UDim2.new(1, -52, 0.5, -11),
					Text = "초대", TextSize = 12, BackgroundColor3 = GREEN,
				}, row, function()
					Remotes.Party:FireServer("Invite", other.UserId)
				end)
			end
		end
	end
end

-- 여러 신호가 한꺼번에 와도 한 번만 다시 그리도록
local partyRefreshQueued = false
local function queuePartyRefresh()
	if partyRefreshQueued then return end
	partyRefreshQueued = true
	task.defer(function()
		partyRefreshQueued = false
		refreshParty()
	end)
end

local watched = {}
local function watchPlayer(other)
	if watched[other] then return end
	watched[other] = true
	other:GetAttributeChangedSignal("Zone"):Connect(queuePartyRefresh)
	other:GetAttributeChangedSignal("PartyId"):Connect(queuePartyRefresh)
	other:GetAttributeChangedSignal("WeaponLevel"):Connect(queuePartyRefresh)
end

for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end
Players.PlayerAdded:Connect(function(other)
	watchPlayer(other)
	queuePartyRefresh()
end)
Players.PlayerRemoving:Connect(function(other)
	watched[other] = nil
	queuePartyRefresh()
end)

-- 초대 팝업
local invitePanel = makePanel({
	Size = UDim2.new(0, 340, 0, 100),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 160),
	Visible = false,
}, gui)
local inviteLabel = makeLabel({
	Size = UDim2.new(1, -20, 0, 44), Position = UDim2.new(0, 10, 0, 6),
	Font = Enum.Font.GothamBold, TextSize = 17,
}, invitePanel)
local pendingInvite = nil

local function closeInvite(decline)
	if pendingInvite and decline then
		Remotes.Party:FireServer("Decline", pendingInvite.UserId)
	end
	pendingInvite = nil
	invitePanel.Visible = false
end

makeButton({
	Size = UDim2.new(0, 140, 0, 36), Position = UDim2.new(0, 20, 1, -46),
	Text = "수락", BackgroundColor3 = GREEN,
}, invitePanel, function()
	if pendingInvite then
		Remotes.Party:FireServer("Accept", pendingInvite.UserId)
	end
	closeInvite(false)
end)
makeButton({
	Size = UDim2.new(0, 140, 0, 36), Position = UDim2.new(1, -160, 1, -46),
	Text = "거절", BackgroundColor3 = RED,
}, invitePanel, function()
	closeInvite(true)
end)

Remotes.Party.OnClientEvent:Connect(function(action, a, b)
	if action == "State" then
		partyData = a
		queuePartyRefresh()
	elseif action == "Invite" then
		local invite = { UserId = a, Name = b }
		pendingInvite = invite
		inviteLabel.Text = string.format("%s 님이 파티에 초대했어요!", b)
		invitePanel.Visible = true
		task.delay(Config.Party.InviteTimeout, function()
			if pendingInvite == invite then
				closeInvite(false)
			end
		end)
	end
end)

-- (무기 강화 / 장비 뽑기는 광장의 모루 / 뽑기 기계 앞에서만 한다. 화면 하단 버튼은 없앴다)

makeLabel({
	Size = UDim2.new(0, 560, 0, 40), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16),
	Text = "북쪽 던전 게이트 · 서쪽 허수아비 훈련장 · 동쪽 끝 사냥 필드   |   Shift 달리기 · Q 대시 · R 자동공격 · I 메뉴 · M 음악",
	TextSize = 14, TextColor3 = Color3.fromRGB(220, 220, 235), TextStrokeTransparency = 0.5,
}, lobbyFrame)

------------------------------------------------------------
-- 던전: 웨이브 배너 / 보스 체력바 / 스탯 패널 / 결과
------------------------------------------------------------
local dungeonFrame = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false }, gui)

local banner = makePanel({
	Size = UDim2.new(0, 420, 0, 96), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16),
}, dungeonFrame)
local bannerTitle = makeLabel({
	Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 6),
	Font = Enum.Font.GothamBlack, TextSize = 26,
}, banner)
local bannerSub = makeLabel({
	Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 44),
	TextSize = 16, TextColor3 = Color3.fromRGB(210, 210, 230),
}, banner)
local bannerMutator = makeLabel({
	Size = UDim2.new(1, -16, 0, 20), Position = UDim2.new(0, 8, 0, 70),
	TextSize = 13, TextColor3 = Color3.fromRGB(255, 205, 100), Font = Enum.Font.GothamBold,
}, banner)

local bossBar = makePanel({
	Size = UDim2.new(0, 460, 0, 26), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Visible = false,
}, dungeonFrame)
local bossFill = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(200, 40, 50), BorderSizePixel = 0 }, bossBar)
rounded(bossFill)
local bossName = makeLabel({
	Size = UDim2.new(1, 0, 1, 0), Font = Enum.Font.GothamBold, TextSize = 15, TextStrokeTransparency = 0.4,
}, bossBar)

-- 특성 선택 패널 (웨이브 클리어마다 3개 중 1개, 숫자키 1/2/3)
local statPanel = makePanel({
	Size = UDim2.new(0, 380, 0, 170), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16),
}, dungeonFrame)
local statStroke = create("UIStroke", { Color = Color3.fromRGB(255, 210, 90), Thickness = 0, Transparency = 0 }, statPanel)

local statPoints = makeLabel({
	Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 10, 0, 8),
	Font = Enum.Font.GothamBlack, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left,
}, statPanel)

local perkOffer = {}   -- 지금 고를 수 있는 특성 키 목록 (서버가 보내준다)
local perkCards = {}
-- 특성 카드: 화면 가운데 아래에 큼직한 카드 3장이 가로로 뜬다 (큰 아이콘 + 이름 + 설명, 숫자키 1/2/3 또는 클릭)
local pickFrame = create("Frame", {
	Size = UDim2.new(0, 640, 0, 214), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150),
	BackgroundTransparency = 1, Visible = false,
}, dungeonFrame)
makeLabel({
	Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 0), Text = "✨ 특성을 고르세요!  (숫자키 1 / 2 / 3 또는 클릭)",
	Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = Color3.fromRGB(255, 225, 100), TextStrokeTransparency = 0.3,
}, pickFrame)
for index = 1, Config.Perks.ChoiceCount do
	local card = makeButton({
		Size = UDim2.new(0, 200, 0, 176), Position = UDim2.new(0, (index - 1) * 220, 0, 34),
		Text = "", BackgroundColor3 = Color3.fromRGB(38, 40, 62),
	}, pickFrame, function()
		local key = perkOffer[index]
		if key then
			Remotes.Upgrade:FireServer(key)
		end
	end)
	create("UIStroke", { Color = Color3.fromRGB(255, 210, 90), Thickness = 2, Transparency = 0.2 }, card)
	local icon = makeLabel({
		Size = UDim2.new(1, 0, 0, 52), Position = UDim2.new(0, 0, 0, 16), TextSize = 40,
	}, card)
	local text = makeLabel({
		Size = UDim2.new(1, -16, 1, -72), Position = UDim2.new(0, 8, 0, 70),
		TextSize = 14, RichText = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
	}, card)
	makeLabel({
		Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(0, 6, 0, 6), Text = tostring(index),
		Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = Color3.fromRGB(255, 225, 100),
	}, card)
	perkCards[index] = { Button = card, Text = text, Icon = icon }
end

local perkSummary = makeLabel({
	Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 0, 40),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextSize = 13, RichText = true, TextColor3 = Color3.fromRGB(200, 200, 220),
}, statPanel)

local readyButton = makeButton({
	Size = UDim2.new(1, -20, 0, 34), Position = UDim2.new(0, 10, 0, 84),
	Text = "준비 완료", BackgroundColor3 = GREEN, Visible = false,
}, statPanel, function()
	Remotes.Dungeon:FireServer("Ready")
end)

makeButton({
	Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 1, -30),
	Text = "던전 나가기", TextSize = 13, BackgroundColor3 = GRAY,
}, statPanel, function()
	Remotes.Dungeon:FireServer("Leave")
end)

local dungeonState = nil
local openDungeonSelect -- 던전 선택창 (아래에서 정의)

------------------------------------------------------------
-- 배경음악: Config.Audio.Music 에 소리 ID를 넣으면 로비 / 던전 / 보스전마다 부드럽게 바뀐다
------------------------------------------------------------
local tracks = {}
for name, id in pairs(Config.Audio.Music) do
	if id ~= 0 then
		local sound = Instance.new("Sound")
		sound.Name = "Music_" .. name
		sound.SoundId = "rbxassetid://" .. id
		sound.Looped = true
		sound.Volume = 0
		sound.Parent = SoundService
		tracks[name] = sound
	end
end

if next(tracks) == nil and RunService:IsStudio() then
	print("[음악] 배경음악이 비어 있어요. ReplicatedStorage > AudioIds 스크립트에 오디오 ID(숫자)를 적으면 로비 / 필드 / 던전 / 보스 음악이 나와요. (README의 '소리 넣는 법' 참고)")
end

-- 설정창에서 바꾸는 값
local settings = { Shake = true, Radar = true, ShotVolume = 1 }
local toggleHelp -- 도움말/설정창 (아래에서 정의)

local musicEnabled = true   -- M 키로 켜고 끈다
local currentMusic = nil
local musicScale = 1       -- 설정창에서 조절 (0 ~ 1.5)
local function musicVolume()
	return musicEnabled and Config.Audio.MusicVolume * musicScale or 0
end

local function playMusic(name)
	if name == currentMusic then return end
	currentMusic = name
	for trackName, sound in pairs(tracks) do
		if trackName == name then
			if not sound.IsPlaying then
				sound:Play()
			end
			TweenService:Create(sound, TweenInfo.new(1.5), { Volume = musicVolume() }):Play()
		else
			local fade = TweenService:Create(sound, TweenInfo.new(1.5), { Volume = 0 })
			fade.Completed:Connect(function()
				if currentMusic ~= trackName then
					sound:Pause()
				end
			end)
			fade:Play()
		end
	end
end

local function toggleMusic()
	musicEnabled = not musicEnabled
	for name, sound in pairs(tracks) do
		if name == currentMusic then
			TweenService:Create(sound, TweenInfo.new(0.4), { Volume = musicVolume() }):Play()
		end
	end
	toast(musicEnabled and "🔊 배경음악 켜짐 (M)" or "🔇 배경음악 꺼짐 (M)")
end

local function updateMusic()
	local zone = currentZone()
	if zone == "Lobby" then
		playMusic("Lobby")
	elseif zone == "Field" then
		playMusic(tracks.Field and "Field" or "Lobby")
	elseif dungeonState and dungeonState.Phase == "Boss" then
		playMusic("Boss")
	else
		playMusic("Dungeon")
	end
end

local function refreshStats()
	local picking = #perkOffer > 0
	statPoints.Text = picking and "✨ 특성을 고르세요!" or "특성 (던전 동안만 유지)"
	statPoints.TextColor3 = picking and Color3.fromRGB(255, 220, 90) or Color3.new(1, 1, 1)

	pickFrame.Visible = picking
	for index, card in ipairs(perkCards) do
		local key = perkOffer[index]
		card.Button.Visible = key ~= nil
		if key then
			local perk = Config.Perks[key]
			local stacks = player:GetAttribute(perk.Attr) or 0
			card.Icon.Text = perk.Icon
			card.Text.Text = string.format("<b><font size='17'>%s</font></b>\n<font color='#ffd966'>Lv.%d → %d</font>\n<font color='#c8c8dc'>%s</font>",
				perk.Name, stacks, stacks + 1, perk.Desc)
		end
	end

	local parts = {}
	for _, key in ipairs(Config.Perks.Order) do
		local perk = Config.Perks[key]
		local stacks = player:GetAttribute(perk.Attr) or 0
		if stacks > 0 then
			table.insert(parts, string.format("%s%s %d", perk.Icon, perk.Name, stacks))
		end
	end
	perkSummary.Text = #parts > 0 and ("내 특성: " .. table.concat(parts, "  ·  ")) or "내 특성: 아직 없음"

	local inStatPhase = dungeonState and dungeonState.Phase == "StatPhase"
	statStroke.Thickness = inStatPhase and 3 or 0
	readyButton.Visible = inStatPhase == true
	if inStatPhase then
		readyButton.Text = string.format("준비 완료 (%d/%d)", dungeonState.ReadyCount, dungeonState.MemberCount)
	end
end

local function refreshBanner()
	local state = dungeonState
	banner.Visible = state ~= nil and state.Phase ~= "Ended"
	bossBar.Visible = state ~= nil and state.BossRatio ~= nil
	if not state then return end
	bannerMutator.Text = state.MutatorText or ""

	if state.BossRatio then
		bossFill.Size = UDim2.new(math.clamp(state.BossRatio, 0, 1), 0, 1, 0)
		bossName.Text = state.BossName or "BOSS"
	end

	if state.Phase == "Starting" then
		bannerTitle.Text = string.format("%s 입장!", state.TypeName or "던전")
		bannerSub.Text = string.format("[%s] %d초 후 첫 웨이브 시작", state.DifficultyName or "", state.TimeLeft)
	elseif state.Phase == "Wave" then
		bannerTitle.Text = state.TotalWaves == 0 and string.format("🏯 %d층", state.Wave) or string.format("구역 %d / %d", state.Wave, state.TotalWaves)
		bannerSub.Text = string.format("%s · %s · 남은 몬스터 %d · 앞으로 쭉!", state.TypeName or "", state.DifficultyName or "", state.MonstersLeft)
	elseif state.Phase == "StatPhase" then
		bannerTitle.Text = string.format("특성 선택  %d초", state.TimeLeft)
		bannerSub.Text = (state.TotalWaves ~= 0 and state.Wave >= state.TotalWaves) and "웨이브 클리어! 다음은 보스전!" or string.format("웨이브 %d 클리어! 특성 카드를 고르세요 (1 / 2 / 3)", state.Wave)
	elseif state.Phase == "Moving" then
		bannerTitle.Text = state.StageText or "다음 방으로 이동하세요"
		bannerSub.Text = "하늘색 빛기둥을 따라가세요"
	elseif state.Phase == "Event" then
		bannerTitle.Text = state.StageText or "이벤트 방"
		bannerSub.Text = "특별한 방이에요!"
	elseif state.Phase == "Boss" then
		bannerTitle.Text = "BOSS"
		bannerSub.Text = string.format("남은 몬스터: %d", state.MonstersLeft)
	end
end

-- 결과 화면
local resultPanel = makePanel({
	Size = UDim2.new(0, 460, 0, 340), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0), Visible = false,
}, dungeonFrame)
local resultTitle = makeLabel({
	Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 0, 12), Font = Enum.Font.GothamBlack, TextSize = 36,
}, resultPanel)
local resultInfo = makeLabel({
	Size = UDim2.new(1, -20, 0, 200), Position = UDim2.new(0, 10, 0, 72), TextSize = 17, RichText = true, TextYAlignment = Enum.TextYAlignment.Top,
}, resultPanel)
makeButton({
	Size = UDim2.new(0, 200, 0, 40), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	Text = "지금 로비로", TextSize = 17,
}, resultPanel, function()
	Remotes.Dungeon:FireServer("Leave")
end)

local resultToken = 0
local function showResult(result)
	resultToken += 1
	local token = resultToken
	resultPanel.Visible = true
	resultTitle.Text = result.Victory and "🏆 던전 클리어!" or "💀 던전 실패"
	resultTitle.TextColor3 = result.Victory and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(255, 110, 110)

	task.spawn(function()
		for remaining = result.ReturnDelay, 1, -1 do
			if token ~= resultToken or not resultPanel.Visible then return end
			local lootLines = {}
			for _, entry in ipairs(result.Loot or {}) do
				table.insert(lootLines, string.format("<font color='#%s' size='15'>%s</font>", Config.Gear.RarityColors[entry.Rarity]:ToHex(), entry.Text))
			end
			resultInfo.Text = string.format(
				"%s\n획득 골드  +%d G   🎫 티켓 +%d\n%s\n%d초 후 로비로 이동",
				result.TotalWaves == 0 and string.format("🏯 도달 %d층 (최고 %d층)", result.Wave, player:GetAttribute("TowerBest") or 0) or string.format("도달 웨이브 %d / %d", result.Wave, result.TotalWaves), result.Gold, result.Tickets or 0,
				#lootLines > 0 and ("<b>📦 보스 상자</b>\n" .. table.concat(lootLines, "\n")) or "", remaining
			)
			task.wait(1)
		end
	end)
end

Remotes.Dungeon.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		dungeonState = data
		-- 특성 고르는 시간이 아니면 후보를 지운다 (Perks 이벤트가 State 보다 먼저 도착해도 지워지지 않도록 여기서만 처리)
		if data.Phase ~= "StatPhase" then
			perkOffer = {}
		end
		refreshBanner()
		refreshStats()
		updateMusic()
	elseif action == "Perks" then
		perkOffer = data.Keys or {}
		refreshStats()
	elseif action == "Result" then
		showResult(data)
	elseif action == "OpenSelect" then
		openDungeonSelect()
	end
end)

------------------------------------------------------------
-- 구역 전환 / 정보 갱신
------------------------------------------------------------
local function refreshInfo()
	local level = player:GetAttribute("WeaponLevel") or 0
	local name, color = weaponText(level)
	local zone = currentZone()
	local zoneText = zone == "Lobby" and "로비" or zone == "Dungeon" and "던전" or string.format("필드 (최고 %d구역)", player:GetAttribute("MaxZone") or 0)

	local characterLevel = player:GetAttribute("Level") or 1
	local xp = player:GetAttribute("XP") or 0
	local xpNeeded = player:GetAttribute("XPNeeded") or 1
	local maxed = characterLevel >= Config.Level.Max
	local blocked = not maxed and characterLevel >= Config.GetLevelCap(player:GetAttribute("GatePassed") or 0)
	xpFill.Size = UDim2.new((maxed or blocked) and 1 or math.clamp(xp / xpNeeded, 0, 1), 0, 1, 0)
	xpFill.BackgroundColor3 = blocked and Color3.fromRGB(255, 170, 60) or Color3.fromRGB(110, 200, 255)
	local xpText = maxed and "MAX" or blocked and "돌파 필요!" or string.format("%d / %d XP", xp, xpNeeded)

	local keys = player:GetAttribute("Keys") or 0
	local keyCap = Config.Keys.Max + (player:GetAttribute("KeyCapBonus") or 0)
	local keyNext = player:GetAttribute("KeyNext") or 0
	local keyText = "가득"
	if keys < keyCap and keyNext > 0 then
		keyText = Config.FormatDuration(keyNext - os.time())
	end

	infoLabel.Text = string.format(
		"🎖 <font color='#8fd8ff'>Lv.%d</font>  <font size='12' color='#aaaacc'>%s</font>\n💰 <font color='#ffd966'>%d G</font>   🎫 <font color='#d9a6ff'>%d</font>\n🗝 <font color='#a6f0c8'>%d/%d</font> <font size='12' color='#aaaacc'>(%s)</font>\n⚡ 전투력 <font color='#ffe16e'>%d</font>\n⚔ <font color='#%s'>%s</font>\n📍 %s",
		characterLevel, xpText,
		player:GetAttribute("Gold") or 0, player:GetAttribute("Tickets") or 0,
		keys, keyCap, keyText,
		player:GetAttribute("Power") or 0,
		color:ToHex(), name, zoneText
	)
end

-- 열쇠 회복 시간이 흐르는 걸 보여주려고 1초마다 정보를 갱신
task.spawn(function()
	while true do
		task.wait(1)
		local keys = player:GetAttribute("Keys") or 0
		if keys < Config.Keys.Max + (player:GetAttribute("KeyCapBonus") or 0) then
			refreshInfo()
		end
	end
end)

local function refreshZone()
	local zone = currentZone()
	lobbyFrame.Visible = zone ~= "Dungeon"
	dungeonFrame.Visible = zone == "Dungeon"
	-- 무기 강화 / 장비 뽑기 버튼은 로비에서만 (필드 / 던전에서는 숨기고, 열려 있던 창도 닫는다)
	for _, child in ipairs(lobbyFrame:GetChildren()) do
		if child.Name == "LobbyOnlyButton" then
			child.Visible = zone == "Lobby"
		end
	end
	if zone ~= "Lobby" then
		enhancePanel.Visible = false
		gearPanel.Visible = false
	end
	if zone ~= "Dungeon" then
		dungeonState = nil
		resultToken += 1
		resultPanel.Visible = false
		bossBar.Visible = false
	else
		enhancePanel.Visible = false
		gearPanel.Visible = false
		invitePanel.Visible = false
	end
	refreshInfo()
	refreshStats()
	refreshBanner()
	queuePartyRefresh()
	updateMusic()
end

player.AttributeChanged:Connect(function(attribute)
	if attribute == "Zone" then
		refreshZone()
		return
	end
	refreshInfo()
	refreshStats()
	if enhancePanel.Visible then
		refreshEnhance()
	end
	if gearPanel.Visible then
		refreshGear()
	end
end)

refreshZone()
refreshEnhance()

------------------------------------------------------------
-- 입력: 마우스 방향 공격 (누르고 있으면 연사), 숫자키 스탯 투자
------------------------------------------------------------
local holding = false
local nextAttack = 0

------------------------------------------------------------
-- Shift 달리기 / Q 대시
------------------------------------------------------------
local sprinting = false
local sliding = false

local function applySpeed()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local bonus = (player:GetAttribute("GearSpeed") or 0) + (player:GetAttribute("TrainSpeed") or 0) + (player:GetAttribute("PetSpeed") or 0) -- 신발 장비 + 신속 단련
		humanoid.WalkSpeed = (sprinting and Config.Player.RunSpeed or Config.Player.WalkSpeed) + bonus
	end
end

player:GetAttributeChangedSignal("GearSpeed"):Connect(applySpeed)
player:GetAttributeChangedSignal("TrainSpeed"):Connect(applySpeed)
player:GetAttributeChangedSignal("PetSpeed"):Connect(applySpeed)

-- Q: 대시. 이동 방향(가만히 있으면 바라보는 방향)으로 순간 폭발적으로 튀어 나간다. 공중에서도 쓸 수 있고
-- (공중에선 높이가 유지된 채 수평으로 휙), 최대 DashCharges 번까지 연속으로 쓸 수 있다. 쓴 만큼 시간이 지나면 하나씩 충전.
-- 연출: 잔상(몸 모양 유령) + 바람 줄기 + 화면 FOV 확 벌어짐.
settings.DashCharges = Config.Player.DashCharges  -- 남은 대시 횟수 (스킬바에 표시)
settings.DashRefillAt = 0                        -- 다음 충전 시각

local function spawnAfterimage(character, color)
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 0.9 then
			local ghost = Instance.new("Part")
			ghost.Anchored, ghost.CanCollide, ghost.CanQuery, ghost.CanTouch = true, false, false, false
			ghost.Size = part.Size * 1.05
			ghost.CFrame = part.CFrame
			ghost.Material = Enum.Material.Neon
			ghost.Color = color
			ghost.Transparency = 0.45
			ghost.Parent = workspace
			TweenService:Create(ghost, TweenInfo.new(0.35), { Transparency = 1, Size = part.Size * 0.6 }):Play()
			game:GetService("Debris"):AddItem(ghost, 0.4)
		end
	end
end

local function slide()
	if sliding then return end
	local now = os.clock()
	local P = Config.Player
	if settings.DashCharges <= 0 then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end
	if settings.DashCharges == P.DashCharges then -- 가득 찬 상태에서 처음 쓰면 충전 타이머 시작
		settings.DashRefillAt = now + P.DashCooldown
	end
	settings.DashCharges -= 1
	sliding = true

	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z).Unit
	local airborne = humanoid.FloorMaterial == Enum.Material.Air

	local attachment = Instance.new("Attachment")
	attachment.Parent = root

	-- 땅에서는 중력 그대로, 공중에서는 높이를 유지한 채 수평으로 쏜다 (건즈식 공중 대시)
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	velocity.MaxAxesForce = Vector3.new(math.huge, airborne and math.huge or 0, math.huge)
	velocity.VectorVelocity = direction * P.DashSpeed
	velocity.Parent = root

	-- 바람 줄기 (몸 뒤로 길게)
	local trailTop = Instance.new("Attachment")
	trailTop.Position = Vector3.new(0, 1.6, 0)
	trailTop.Parent = root
	local trailBottom = Instance.new("Attachment")
	trailBottom.Position = Vector3.new(0, -2.6, 0)
	trailBottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = trailTop
	trail.Attachment1 = trailBottom
	trail.Lifetime = 0.35
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(160, 230, 255), Color3.fromRGB(255, 255, 255))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = root

	-- 출발 먼지 / 충격
	local puff = Instance.new("Attachment")
	puff.Position = Vector3.new(0, -2.6, 0)
	puff.Parent = root
	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Lifetime = NumberRange.new(0.3, 0.6)
	dust.Speed = NumberRange.new(8, 18)
	dust.SpreadAngle = Vector2.new(70, 70)
	dust.Color = ColorSequence.new(Color3.fromRGB(235, 235, 245))
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 4) })
	dust.Parent = puff
	dust:Emit(airborne and 14 or 26)

	local autoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)

	local started = os.clock()
	local lastGhost = 0
	local connection
	local function finish()
		connection:Disconnect()
		velocity:Destroy()
		attachment:Destroy()
		trail.Enabled = false
		if humanoid.Parent then
			humanoid.AutoRotate = autoRotate
		end
		-- 끝났을 때 속도를 조금 남겨서 뚝 멈추지 않고 이어 달리게 한다
		if root.Parent then
			local vertical = root.AssemblyLinearVelocity.Y
			root.AssemblyLinearVelocity = direction * P.RunSpeed * 1.1 + Vector3.new(0, vertical, 0)
		end
		sliding = false
		task.delay(0.6, function()
			puff:Destroy()
			trail:Destroy()
			trailTop:Destroy()
			trailBottom:Destroy()
		end)
	end
	connection = RunService.Heartbeat:Connect(function()
		local t = (os.clock() - started) / P.DashTime
		if t >= 1 or not root.Parent or humanoid.Health <= 0 then
			finish()
			return
		end
		-- 시작은 폭발적으로, 끝은 부드럽게 (ease-out)
		velocity.VectorVelocity = direction * (P.DashSpeed * (1 - t * t * 0.7))
		if os.clock() - lastGhost > 0.035 then
			lastGhost = os.clock()
			spawnAfterimage(character, airborne and Color3.fromRGB(255, 190, 120) or Color3.fromRGB(120, 210, 255))
		end
	end)
end

player.CharacterAdded:Connect(function(character)
	character:WaitForChild("Humanoid")
	applySpeed()
	sliding = false
end)

RunService.RenderStepped:Connect(function(dt)
	local target = sliding and 108 or sprinting and 80 or 70
	camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 8)
end)

------------------------------------------------------------
-- 조준 / 공격 / 자동 공격(락온, R)
------------------------------------------------------------
local autoMode = false
local lockTarget = nil     -- { Kind = "Dummy" | "Monster", Instance, Part }
local nextSearch = 0

local autoLabel = makeLabel({
	Size = UDim2.new(0, 460, 0, 30), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -128),
	BackgroundColor3 = Color3.fromRGB(20, 20, 30), BackgroundTransparency = 0.25,
	Font = Enum.Font.GothamBold, TextSize = 16, Visible = false, RichText = true,
}, gui)
rounded(autoLabel)

local lockHighlight = Instance.new("Highlight")
lockHighlight.FillTransparency = 1
lockHighlight.OutlineColor = Color3.fromRGB(255, 220, 80)
lockHighlight.OutlineTransparency = 0
lockHighlight.Enabled = false
lockHighlight.Parent = workspace

local function targetName(target)
	if not target then return "대상 찾는 중..." end
	if target.Kind == "Dummy" then
		local index = tonumber(string.sub(target.Instance.Name, 6))
		local info = index and Config.Dummy.List[index]
		return info and string.format("x%s 허수아비", tostring(info.Multiplier)) or "허수아비"
	end
	return "몬스터"
end

local function updateLockVisual()
	autoLabel.Visible = autoMode
	if autoMode then
		autoLabel.Text = string.format("🔒 자동 공격 <font color='#ffe16e'>ON</font> (R) · %s", targetName(lockTarget))
	end
	if autoMode and lockTarget and lockTarget.Instance.Parent then
		lockHighlight.Adornee = lockTarget.Instance
		lockHighlight.Enabled = true
	else
		lockHighlight.Adornee = nil
		lockHighlight.Enabled = false
	end
end

local function weaponRange()
	return Config.GetPlayerWeapon(player).Range
end

-- 이 허수아비를 지금 캐릭터 레벨로 때려서 골드를 받을 수 있는가?
local function dummyUsable(model)
	local index = tonumber(string.sub(model.Name, 6))
	local info = index and Config.Dummy.List[index]
	return info ~= nil and (player:GetAttribute("Level") or 1) >= info.RequiredLevel
end

-- 맞은 Instance 가 락온할 수 있는 대상(허수아비 / 필드 몬스터 / 던전 몬스터)이면 대상 정보를 만든다
local function resolveTarget(instance)
	if not instance then return nil end

	local dummies = workspace:FindFirstChild("Dummies")
	if dummies and instance:IsDescendantOf(dummies) then
		local model = instance:FindFirstAncestorOfClass("Model")
		if model and model.PrimaryPart and string.sub(model.Name, 1, 5) == "Dummy" then
			return { Kind = "Dummy", Instance = model, Part = model.PrimaryPart }
		end
		return nil
	end

	local parent = instance.Parent
	if parent and parent.Name == "FieldMonsters" and parent.Parent == workspace then
		return { Kind = "Monster", Instance = instance, Part = instance }
	end
	if parent and parent.Name == "Monsters" and parent.Parent and string.sub(parent.Parent.Name, 1, 8) == "Dungeon_" then
		return { Kind = "Monster", Instance = instance, Part = instance }
	end
	return nil
end

-- 화면 안에 있고(뒤쪽 / 화면 밖 제외) 사이에 벽이 없어서 실제로 "보이는" 대상인가
local function isTargetVisible(target, root)
	local position = target.Part.Position
	local _, onScreen = camera:WorldToViewportPoint(position)
	if not onScreen then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local result = workspace:Raycast(origin, position - origin, params)
	return result == nil or result.Instance == target.Part or result.Instance:IsDescendantOf(target.Instance)
end

local function isTargetValid(target, root)
	if not target or not target.Instance.Parent or not target.Part.Parent then return false end
	if target.Kind == "Dummy" and not dummyUsable(target.Instance) then return false end
	-- 던전은 몬스터가 방마다 잠들어 있으니, 가까이(깨어나는 거리) 있는 것만 자동 조준한다
	local reach = currentZone() == "Dungeon" and math.min(weaponRange() * 0.95, 80) or weaponRange() * 0.95
	if (target.Part.Position - root.Position).Magnitude > reach then return false end
	return isTargetVisible(target, root)
end

-- 지금 구역에서 때릴 수 있는 가장 가까운 대상
local function findNearestTarget(root)
	local zone = currentZone()
	local best, bestDistance = nil, math.huge

	local function consider(target)
		if isTargetValid(target, root) then
			-- 점수 = 화면 중앙(조준점)에서 떨어진 정도 + 거리 약간. 내가 보고 있는 쪽의 적이 우선이고, 비슷하면 가까운 적.
			local screen = camera:WorldToViewportPoint(target.Part.Position)
			local viewport = camera.ViewportSize
			local fromCenter = (Vector2.new(screen.X, screen.Y) - viewport / 2).Magnitude / viewport.Y -- 0 = 정중앙
			local distance = (target.Part.Position - root.Position).Magnitude
			local score = fromCenter * 100 + distance * 0.35
			if score < bestDistance then
				best, bestDistance = target, score
			end
		end
	end

	if zone == "Lobby" then
		local dummies = workspace:FindFirstChild("Dummies")
		local bestDummy = -1
		if dummies then
			for _, model in ipairs(dummies:GetChildren()) do
				if model:IsA("Model") and model.PrimaryPart then
					-- 허수아비는 "내 레벨로 칠 수 있는 가장 높은 레벨"(보상 배율이 큰 쪽)을 우선한다
					local target = { Kind = "Dummy", Instance = model, Part = model.PrimaryPart }
					if isTargetValid(target, root) then
						local order = tonumber(string.sub(model.Name, 6)) or 0
						if order > bestDummy then
							bestDummy = order
							best = target
						end
					end
				end
			end
		end
	elseif zone == "Field" then
		local folder = workspace:FindFirstChild("FieldMonsters")
		if folder then
			for _, part in ipairs(folder:GetChildren()) do
				consider({ Kind = "Monster", Instance = part, Part = part })
			end
		end
	elseif zone == "Dungeon" then
		for _, child in ipairs(workspace:GetChildren()) do
			if string.sub(child.Name, 1, 8) == "Dungeon_" then
				local monsters = child:FindFirstChild("Monsters")
				if monsters then
					for _, part in ipairs(monsters:GetChildren()) do
						consider({ Kind = "Monster", Instance = part, Part = part })
					end
				end
			end
		end
	end
	return best
end

local function getAimPoint(screenPosition)
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if result then
		return result.Position, result.Instance
	end
	return ray.Origin + ray.Direction * 300, nil
end

local hitMarker = 0      -- 적중 시 조준점이 색을 바꾸는 시간
local hitMarkerCrit = false
local shake = 0          -- 카메라 흔들림 세기
local crosshairKick = 0 -- 쏠 때마다 조준점이 벌어졌다 돌아오는 연출용

-- 월드 좌표를 향해 캐릭터를 돌려세우고 서버에 공격 요청
local function fireAt(worldPoint)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	if not sliding then
		local flat = Vector3.new(worldPoint.X - root.Position.X, 0, worldPoint.Z - root.Position.Z)
		if flat.Magnitude > 1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end
	crosshairKick = 10
	Remotes.Attack:FireServer(worldPoint)
end

local function attack(screenPosition)
	local point, instance = getAimPoint(screenPosition)

	-- 자동 공격 중에 대상을 직접 클릭하면 그 대상으로 락온을 바꾼다 (배율이 다른 허수아비를 고를 수 있음)
	if autoMode then
		local target = resolveTarget(instance)
		if target then
			if target.Kind == "Dummy" and not dummyUsable(target.Instance) then
				toast("🔒 이 허수아비는 캐릭터 레벨이 더 필요해요")
			else
				lockTarget = target
				updateLockVisual()
			end
		end
	end
	fireAt(point)
end

local function toggleAuto()
	autoMode = not autoMode
	lockTarget = nil
	nextSearch = 0
	updateLockVisual()
	toast(autoMode and "🔒 자동 공격 ON — 허수아비/몬스터를 직접 클릭하면 그 대상으로 고정돼요 (R로 끄기)" or "자동 공격 OFF")
end

-- 튜토리얼 허수아비 미션이 끝나면 서버가 알려준다 -> 자동 공격이 켜져 있으면 끈다
player:GetAttributeChangedSignal("AutoOffTick"):Connect(function()
	if autoMode then
		toggleAuto()
	end
end)

local function attackCooldown()
	local speedPoints = player:GetAttribute("SpeedPoints") or 0
	return Config.Player.BaseCooldown * Config.GetPlayerWeapon(player).Cooldown / (1 + speedPoints * Config.Player.SpeedPerPoint)
end

------------------------------------------------------------
-- 메뉴 (I): 캐릭터 / 무기 / 퀘스트 / 업적 / 랭킹
------------------------------------------------------------
local questState = nil   -- 서버가 보내준 퀘스트/업적/칭호 상태
local rankList = {}      -- 서버가 보내준 전투력 랭킹

-- 화면 오른쪽의 작은 전투력 랭킹 (로비 / 필드에서 항상 보인다. 광장의 랭킹판을 대신한다)
do
	local mini = makePanel({
		Size = UDim2.new(0, 270, 0, 138), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 444),
	}, lobbyFrame)
	makeLabel({
		Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 0, 6), Text = "🏆 전투력 랭킹",
		Font = Enum.Font.GothamBlack, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 225, 120),
	}, mini)
	local body = makeLabel({
		Size = UDim2.new(1, -20, 1, -32), Position = UDim2.new(0, 10, 0, 28), RichText = true, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "집계 중...",
	}, mini)
	Remotes.Rank.OnClientEvent:Connect(function(action, data)
		if action ~= "List" then return end
		local lines = {}
		for index = 1, math.min(5, #data) do
			local entry = data[index]
			local medal = index == 1 and "🥇" or index == 2 and "🥈" or index == 3 and "🥉" or (index .. ".")
			local mine = entry.Name == player.DisplayName
			table.insert(lines, string.format("%s <font color='#%s'>%s</font>  <font color='#ffe16e'>⚡%d</font>", medal, mine and "78ff8c" or "ffffff", entry.Name, entry.Power))
		end
		body.Text = #lines > 0 and table.concat(lines, "\n") or "아직 기록이 없어요"
	end)
	Remotes.Rank:FireServer("Request")
end

local menuPanel = makePanel({
	Size = UDim2.new(0, 880, 0, 600),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Visible = false,
}, gui)

makeLabel({
	Size = UDim2.new(1, -90, 0, 36), Position = UDim2.new(0, 16, 0, 8),
	Text = "📋 메뉴", Font = Enum.Font.GothamBlack, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left,
}, menuPanel)

makeButton({
	Size = UDim2.new(0, 64, 0, 28), Position = UDim2.new(1, -76, 0, 10), Text = "닫기 (I)", TextSize = 13, BackgroundColor3 = GRAY,
}, menuPanel, function()
	menuPanel.Visible = false
end)

local TABS = {
	{ Key = "Inventory", Name = "캐릭터" }, -- 3D 캐릭터 + 장비 칸 + 가방 (메뉴를 열면 가장 먼저 보인다)
	{ Key = "Character", Name = "정보" },
	{ Key = "Weapon", Name = "무기" },
	{ Key = "Growth", Name = "성장" },
	{ Key = "Skill", Name = "스킬" },
	{ Key = "Pet", Name = "펫" },
	{ Key = "Quest", Name = "퀘스트" },
	{ Key = "Ach", Name = "업적" },
	{ Key = "Rank", Name = "랭킹" },
	{ Key = "Shop", Name = "상점" },
}
local currentTab = "Inventory"
local tabButtons = {}

local menuContent = create("ScrollingFrame", {
	Size = UDim2.new(1, -24, 1, -108), Position = UDim2.new(0, 12, 0, 96),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, menuPanel)
create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, menuContent)

local rowOrder = 0
local function newRow(height, color)
	rowOrder += 1
	return makePanel({
		Size = UDim2.new(1, -10, 0, height), LayoutOrder = rowOrder,
		BackgroundColor3 = color or Color3.fromRGB(40, 40, 58),
	}, menuContent)
end

local function rowText(row, text, size, rightMargin)
	return makeLabel({
		Size = UDim2.new(1, -(rightMargin or 24), 1, -10), Position = UDim2.new(0, 12, 0, 5),
		Text = text, TextSize = size or 15, RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
	}, row)
end

local function sectionTitle(text)
	local row = newRow(26, Color3.fromRGB(30, 30, 44))
	rowText(row, text, 14)
end

local function hex(color)
	return color:ToHex()
end

local function buildCharacterTab()
	local weaponType = Config.GetPlayerWeapon(player)
	local health = Config.Player.BaseHealth + (player:GetAttribute("HealthPoints") or 0) * Config.Player.HealthPerPoint + (player:GetAttribute("GearHealth") or 0) + Config.GetLevelHealth(player:GetAttribute("Level") or 1)
	local crit = ((player:GetAttribute("CritPoints") or 0) * Config.Player.CritPerPoint + (player:GetAttribute("GearCrit") or 0) + (weaponType.CritBonus or 0)) * 100
	local speed = Config.Player.WalkSpeed + (player:GetAttribute("GearSpeed") or 0)

	local summary = newRow(142)
	local menuLevel = player:GetAttribute("Level") or 1
	rowText(summary, string.format(
		"🎖 <font color='#8fd8ff'>Lv.%d</font>  (%s)   공격력 +%d%% · 체력 +%d\n⚡ 전투력 <font color='#ffe16e'>%d</font>\n❤ 최대 체력 %d    🎯 치명타 확률 %.1f%%    💨 이동속도 %.1f\n💰 %d G    🎫 티켓 %d장\n🏔 필드 최고 %d구역 돌파    🏰 던전 클리어 %d회",
		menuLevel,
		menuLevel >= Config.Level.Max and "MAX" or string.format("%d / %d XP", player:GetAttribute("XP") or 0, player:GetAttribute("XPNeeded") or 1),
		math.floor((Config.GetLevelDamageMult(menuLevel) - 1) * 100 + 0.5), Config.GetLevelHealth(menuLevel),
		player:GetAttribute("Power") or 0, health, crit, speed,
		player:GetAttribute("Gold") or 0, player:GetAttribute("Tickets") or 0,
		player:GetAttribute("MaxZone") or 0, questState and questState.Stats and questState.Stats.DungeonClears or 0
	), 16)

	sectionTitle("장착 중인 장비")
	local level = player:GetAttribute("WeaponLevel") or 0
	local weaponName, weaponColor = weaponText(level)
	local weaponRow = newRow(40)
	rowText(weaponRow, string.format("🔫 무기   <font color='#%s'>%s</font>", hex(weaponColor), weaponName))

	for _, slot in ipairs(Config.Gear.Slots) do
		local rarity = player:GetAttribute("Gear_" .. slot.Key .. "_R") or 0
		local gearLevel = player:GetAttribute("Gear_" .. slot.Key .. "_L") or 0
		local row = newRow(40)
		if rarity <= 0 then
			rowText(row, string.format("🛡 %s   <font color='#888888'>비어 있음 (보스 티켓으로 뽑기)</font>", slot.Name))
		else
			local color = Config.Gear.RarityColors[rarity]
			rowText(row, string.format("🛡 %s   <font color='#%s'>[%s] %s +%d</font>   %s", slot.Name, hex(color),
				Config.Gear.RarityNames[rarity], slot.Names[rarity], gearLevel,
				Config.FormatGearStat(slot.Key, Config.GetGearStat(slot.Key, rarity, gearLevel))))
		end
	end

	sectionTitle("📖 스탯 설명")
	do
		local glossary = {}
		for _, key in ipairs({ "Health", "Crit", "Speed", "Damage", "Xp", "Luck", "Haste", "Shot" }) do
			local info = Config.StatDesc[key]
			table.insert(glossary, string.format("<b>%s</b>  <font color='#bbbbcc'>%s</font>", info.Name, info.Desc))
		end
		local row = newRow(#glossary * 22 + 16)
		rowText(row, table.concat(glossary, "\n"), 13)
	end

	do -- 환생
		local prestige = player:GetAttribute("Prestige") or 0
		local ready = (player:GetAttribute("Level") or 1) >= Config.Level.Max and prestige < Config.Prestige.Max
		local row = newRow(64)
		rowText(row, string.format("🌟 <b>환생 %d / %d</b>  (영구 공격력 +%d%%)\n<font size='13' color='#bbbbcc'>레벨 %d 에서 환생하면 레벨이 1로 돌아가고 영구 공격력 +%d%%. 장비/무기/돌파는 그대로예요. (로비에서)</font>",
			prestige, Config.Prestige.Max, math.floor(prestige * Config.Prestige.DamagePerRank * 100 + 0.5), Config.Level.Max, Config.Prestige.DamagePerRank * 100), 14, 190)
		makeButton({
			Size = UDim2.new(0, 160, 0, 36), Position = UDim2.new(1, -172, 0.5, -18),
			Text = prestige >= Config.Prestige.Max and "MAX" or "환생하기", BackgroundColor3 = ready and Color3.fromRGB(200, 150, 40) or GRAY,
		}, row, function()
			Remotes.Meta:FireServer("Prestige")
		end)
	end

	sectionTitle("칭호 (업적을 달성하면 해금, 머리 위 이름표에 표시)")
	local titles = questState and questState.Titles or {}
	local equipped = questState and questState.Equipped
	if #titles == 0 then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>아직 해금한 칭호가 없어요. 업적 탭에서 도전해보세요!</font>")
	end
	for _, title in ipairs(titles) do
		local row = newRow(40)
		rowText(row, string.format("『%s』", title), 16, 150)
		local isEquipped = title == equipped
		makeButton({
			Size = UDim2.new(0, 110, 0, 28), Position = UDim2.new(1, -122, 0.5, -14),
			Text = isEquipped and "해제" or "장착", BackgroundColor3 = isEquipped and RED or GREEN,
		}, row, function()
			Remotes.Quest:FireServer("Title", isEquipped and "" or title)
		end)
	end
end

local function buildWeaponTab()
	local level = player:GetAttribute("WeaponLevel") or 0
	local tiers = Config.Weapon.Tiers
	local current = Config.GetWeaponTier(level)
	local stage = Config.GetWeaponStage(level)
	sectionTitle(string.format("🔫 무기 도감 — 무기마다 정해진 횟수만큼 강화하면 다음 무기로 자동 진화해요 (총 %d종)", #tiers))

	local header = newRow(250)
	local classInfo = Config.WeaponTypes[current.Class]
	local nextTier = tiers[current.Index + 1]

	-- 왼쪽: 지금 무기 3D 모델 + 발사체 시연 (총구에서 실제 탄 모양이 날아가는 걸 반복해서 보여준다)
	do
		local viewport = create("ViewportFrame", {
			Size = UDim2.new(0, 250, 0, 226), Position = UDim2.new(0, 12, 0, 12), BackgroundColor3 = Color3.fromRGB(20, 22, 34), BorderSizePixel = 0,
			Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1),
		}, header)
		rounded(viewport, 10)
		create("UIStroke", { Color = current.Color, Thickness = 2 }, viewport)
		local cam = create("Camera", { FieldOfView = 40 }, viewport)
		viewport.CurrentCamera = cam
		local previews = ReplicatedStorage:FindFirstChild("WeaponPreviews")
		local source = previews and previews:FindFirstChild("W" .. current.Index)
		if source then
			local model = source:Clone()
			model.Parent = viewport
			local handle = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			local cf, size = model:GetBoundingBox()
			local reach = math.max(size.X, size.Y, size.Z)
			local dir = handle and handle.CFrame.LookVector or Vector3.new(0, 0, -1) -- 총구 방향
			local side = handle and handle.CFrame.RightVector or Vector3.new(1, 0, 0)
			local muzzle = cf.Position + dir * (size.Z / 2 + 0.2)
			-- 총구가 오른쪽을 향하도록 카메라를 둔다
			local camPos = cf.Position + side * reach * 1.7 * (dir:Cross(Vector3.yAxis).Unit:Dot(side) >= 0 and -1 or 1) + Vector3.new(0, reach * 0.2, 0)
			cam.CFrame = CFrame.lookAt(camPos, cf.Position + dir * reach * 0.9)
			local shot = current.Shot or { Style = "Ball", Size = 0.6, Speed = 260 }
			local bolt = shot.Style == "Bolt" or shot.Style == "Rocket"
			local bullet = Instance.new("Part")
			bullet.Anchored, bullet.CanCollide = true, false
			bullet.Material = Enum.Material.Neon
			bullet.Color = current.Color
			bullet.Shape = bolt and Enum.PartType.Block or Enum.PartType.Ball
			local thick = math.clamp(shot.Size * 0.22, 0.12, 0.9)
			bullet.Size = bolt and Vector3.new(thick, thick, math.clamp((shot.Length or 3) * 0.35, 0.6, 2.4)) or Vector3.new(thick * 1.6, thick * 1.6, thick * 1.6)
			bullet.Parent = viewport
			local pellets = classInfo.Pellets
			local extra = {}
			for i = 2, math.min(pellets, 6) do -- 산탄: 여러 발이 퍼져 나간다
				extra[i] = bullet:Clone()
				extra[i].Parent = viewport
			end
			local clock = 0
			local connection
			connection = RunService.RenderStepped:Connect(function(dt)
				if not viewport:IsDescendantOf(game) then
					connection:Disconnect()
					return
				end
				clock += dt
				local period = math.clamp(classInfo.Cooldown * 1.0, 0.6, 1.6) -- 발사 간격에 비례해서 반복
				local t = (clock % period) / period
				local travel = t * reach * 2.6
				bullet.CFrame = CFrame.lookAt(muzzle + dir * travel, muzzle + dir * (travel + 1))
				bullet.Transparency = t > 0.85 and (t - 0.85) / 0.15 or 0
				for i, part in pairs(extra) do
					local angle = math.rad(((i - 1) / math.max(1, math.min(pellets, 6) - 1) - 0.5) * 2 * 28)
					local fan = (CFrame.Angles(0, angle, 0)):VectorToWorldSpace(dir)
					part.CFrame = CFrame.lookAt(muzzle + fan * travel, muzzle + fan * (travel + 1))
					part.Transparency = bullet.Transparency
				end
			end)
		end
		makeLabel({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -22), Text = "발사 시연", TextSize = 11, TextColor3 = Color3.fromRGB(150, 160, 190) }, viewport)
	end

	-- 오른쪽: 공격 방식 설명 (한 번에 몇 발 / 얼마나 빨리 / 맞으면 어떻게 되는지)
	local SHOT_NAMES = { Ball = "작은 탄환", Bolt = "빛줄기 탄", Orb = "에너지 구체", Cannon = "대형 포탄", Fire = "불꽃 덩이", Rocket = "로켓탄", Rainbow = "무지개 광구" }
	local shotInfo = current.Shot or { Style = "Ball" }
	local behavior = {}
	if classInfo.Pellets > 1 then table.insert(behavior, string.format("한 번에 %d발이 부채꼴로 퍼짐", classInfo.Pellets)) end
	if classInfo.Splash then table.insert(behavior, string.format("맞은 곳이 폭발 (범위 %d)", classInfo.Splash)) end
	if classInfo.Pierce then table.insert(behavior, string.format("적 %d마리까지 관통", classInfo.Pierce + 1)) end
	if (classInfo.CritBonus or 0) > 0 then table.insert(behavior, string.format("치명타 +%d%%", math.floor(classInfo.CritBonus * 100 + 0.5))) end
	if #behavior == 0 then table.insert(behavior, "곧게 날아가 한 마리를 맞힘") end
	local rate = 1 / math.max(0.05, classInfo.Cooldown * Config.Player.BaseCooldown)
	makeLabel({
		Size = UDim2.new(1, -290, 1, -20), Position = UDim2.new(0, 274, 0, 10), RichText = true, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Text = string.format(
			"<font size='20'><b><font color='#%s'>[%d/%d] %s</font></b></font>  <font color='#ffd966'>+%d / %d</font>\n%s\n<font color='#bbbbcc'>%s</font>\n\n<b>🔫 공격 방식</b>\n<font color='#dfe6ff'>• 탄 모양: %s\n• %s\n• 초당 약 %.1f발 · 한 발 x%.2f · 사거리 %d</font>\n\n%s",
			hex(current.Color), current.Index, #tiers, current.Name, stage, current.Steps, Config.StageBar(level), classInfo.Desc,
			SHOT_NAMES[shotInfo.Style] or "탄환", table.concat(behavior, " · "),
			rate, classInfo.DamageMult, classInfo.Range,
			nextTier and string.format("<font color='#9ad7ff'>%d번 더 강화하면 [%s]로 진화\n→ %s</font>", current.Steps - stage, nextTier.Name, Config.WeaponTypes[nextTier.Class].Desc) or "<font color='#ffd966'>마지막 무기예요!</font>"
		),
	}, header)

	-- 도감: 지나온 무기 / 지금 / 앞으로 만날 무기 (모두 이름이 보여서 "저걸 갖고 싶다"가 생기게)
	for _, tier in ipairs(tiers) do
		local owned = tier.Index < current.Index
		local isCurrent = tier.Index == current.Index
		local row = newRow(34, isCurrent and Color3.fromRGB(45, 70, 50) or (owned and Color3.fromRGB(34, 38, 48) or Color3.fromRGB(28, 28, 38)))
		local classOf = Config.WeaponTypes[tier.Class]
		local mark = isCurrent and "▶" or (owned and "✔" or "🔒")
		local nameColor = (owned or isCurrent) and hex(tier.Color) or "777788"
		rowText(row, string.format("%s  <font color='#aaaabb'>%d.</font> <font color='#%s'><b>%s</b></font>   <font size='12' color='#8888aa'>%s · +%d 단계부터</font>",
			mark, tier.Index, nameColor, tier.Name, classOf.Name, tier.MinLevel), 14, 24)
	end
end

local function buildProgressRows(entries, remoteAction, showTitle)
	if not entries then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>불러오는 중...</font>")
		return
	end
	for _, entry in ipairs(entries) do
		local done = entry.Progress >= entry.Goal
		local row = newRow(66, entry.Claimed and Color3.fromRGB(32, 38, 36) or Color3.fromRGB(40, 40, 58))
		local titleText = showTitle and entry.Title and string.format("   <font color='#9ad7ff'>칭호 『%s』</font>", entry.Title) or ""
		rowText(row, string.format(
			"<font size='16'><b>%s</b></font>%s\n<font color='#bbbbcc'>%s</font>\n<font color='#%s'>%d / %d</font>   <font color='#ffd966'>보상 %s</font>",
			entry.Name, titleText, entry.Desc, done and "78ff8c" or "ffffff", entry.Progress, entry.Goal, entry.Reward
		), 14, 160)

		local label, color, enabled
		if entry.Claimed then
			label, color = "완료", GRAY
		elseif done then
			label, color, enabled = "보상 받기", GREEN, true
		else
			label, color = "진행 중", GRAY
		end
		makeButton({
			Size = UDim2.new(0, 120, 0, 32), Position = UDim2.new(1, -132, 0.5, -16), Text = label, BackgroundColor3 = color,
		}, row, function()
			if enabled then
				Remotes.Quest:FireServer(remoteAction, entry.Id)
			end
		end)
	end
end

local function buildRankTab()
	sectionTitle("🏆 전투력 랭킹 TOP 10 (화면 오른쪽 작은 랭킹과 같아요)")
	if #rankList == 0 then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>집계 중이에요...</font>")
	end
	for index, entry in ipairs(rankList) do
		local row = newRow(36, entry.Name == player.DisplayName and Color3.fromRGB(60, 52, 28) or nil)
		local medal = index == 1 and "🥇" or index == 2 and "🥈" or index == 3 and "🥉" or string.format("%d.", index)
		rowText(row, string.format("%s  <b>%s</b>   ⚡ %d", medal, entry.Name, entry.Power), 16)
	end
end

local refreshMenu -- (메뉴 다시 그리기: 아래에서 정의)
local inventoryState = nil   -- 가방 (서버가 보내준 아이템 목록)
local growthState = nil      -- 훈련소 / 돌파 상태
local growthReceivedAt = 0   -- growthState 를 받은 시각(os.clock) - 남은 시간 계산용

local SLOT_NAMES = {}
for _, slot in ipairs(Config.Gear.Slots) do
	SLOT_NAMES[slot.Key] = slot.Name
end

local function buildInventoryTab()
	local state = inventoryState
	if not state then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>가방을 불러오는 중...</font>")
		return
	end

	local header = newRow(56)
	rowText(header, string.format(
		"🎒 가방 <b>%d / %d</b>      ✨ 에센스 <font color='#9ad7ff'>%d</font>\n<font size='13' color='#bbbbcc'>칸을 누르면 자세히 보여요. 자동 분해를 켜 두면 낮은 등급은 줍자마자 분해돼요.</font>",
		state.BagCount, state.Capacity, state.Essence
	), 15, 320)
	makeButton({
		Size = UDim2.new(0, 150, 0, 28), Position = UDim2.new(1, -310, 0, 14),
		Text = "자동 분해: " .. Config.Inventory.AutoScrapNames[state.AutoScrap], TextSize = 13, BackgroundColor3 = Color3.fromRGB(70, 110, 220),
	}, header, function()
		Remotes.Inventory:FireServer("AutoScrap", (state.AutoScrap + 1) % 4)
	end)
	makeButton({
		Size = UDim2.new(0, 150, 0, 28), Position = UDim2.new(1, -156, 0, 14),
		Text = "희귀 이하 일괄 분해", TextSize = 13, BackgroundColor3 = RED,
	}, header, function()
		Remotes.Inventory:FireServer("ScrapBelow", 2)
	end)

	-- 장착 중인 장비 / 가방 장비 구분 + 세트 착용 수
	local equipped, bag, setCounts, byId = {}, {}, {}, {}
	for _, item in ipairs(state.Items) do
		byId[item.Id] = item
		if item.Equipped then
			equipped[item.Slot] = item
			if item.Set then
				setCounts[item.Set] = (setCounts[item.Set] or 0) + 1
			end
		else
			table.insert(bag, item)
		end
	end
	local selectedId = menuContent:GetAttribute("SelectedItem")
	local selected = selectedId and byId[selectedId]
	if not selected then
		selected = equipped.Armor or equipped.Helmet or equipped.Gloves or equipped.Boots or equipped.Ring or equipped.Necklace or bag[1]
	end

	-- 등급 테두리: 등급이 높을수록 굵고 밝고, 영웅 이상은 숨 쉬듯 빛나며, 신화는 무지개가 돈다
	local function rarityOutline(frame, rarity, thick)
		local color = Config.Gear.RarityColors[rarity]
		local stroke = create("UIStroke", { Color = color, Thickness = thick or ({ 2, 2, 3, 3.5, 4.5 })[rarity], ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
		if rarity >= 3 then
			TweenService:Create(stroke, TweenInfo.new(rarity >= 4 and 0.9 or 1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = rarity >= 4 and 0.55 or 0.4 }):Play()
		end
		if rarity >= 5 then
			local gradient = create("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 80)),
					ColorSequenceKeypoint.new(0.4, Color3.fromRGB(90, 255, 120)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 220, 255)),
					ColorSequenceKeypoint.new(0.8, Color3.fromRGB(150, 100, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
				}),
			}, stroke)
			TweenService:Create(gradient, TweenInfo.new(2.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
		end
		return stroke
	end

	local SLOT_ICONS = { Armor = "🛡", Gloves = "🧤", Boots = "👢", Weapon = "🔫", Helmet = "⛑", Ring = "💍", Necklace = "📿" }

	-- ===== 위쪽: 캐릭터(가운데 3D) + 장비 칸(양옆) + 선택한 아이템 설명 =====
	local top = newRow(420, Color3.fromRGB(30, 32, 46))

	-- 3D 캐릭터: 지금 입고 있는 모습 그대로 복제해서 보여주고, 천천히 돈다
	local viewport = create("ViewportFrame", {
		Size = UDim2.new(0, 230, 0, 330), Position = UDim2.new(0, 108, 0, 12), BackgroundColor3 = Color3.fromRGB(20, 22, 34), BorderSizePixel = 0,
		Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1),
	}, top)
	rounded(viewport, 10)
	create("UIStroke", { Color = Color3.fromRGB(90, 110, 170), Thickness = 2 }, viewport)
	local cam = create("Camera", { FieldOfView = 38 }, viewport)
	viewport.CurrentCamera = cam
	local character = player.Character
	if character then
		character.Archivable = true
		local clone = character:Clone()
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("BillboardGui") or descendant:IsA("ForceField") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		clone.Parent = viewport
		local pivot = clone:GetPivot()
		local spin = settings.InvSpin or 0 -- 메뉴가 갱신돼 다시 그려져도 회전 각도를 이어간다
		local connection
		connection = RunService.RenderStepped:Connect(function(dt)
			if not viewport:IsDescendantOf(game) then
				connection:Disconnect()
				return
			end
			spin += dt * 0.9
			settings.InvSpin = spin
			clone:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, spin, 0))
			cam.CFrame = CFrame.lookAt(pivot.Position + Vector3.new(0, 1.2, 12.5), pivot.Position + Vector3.new(0, 0.4, 0))
		end)
	end
	makeLabel({ Size = UDim2.new(0, 230, 0, 22), Position = UDim2.new(0, 108, 0, 350), Text = string.format("⚡ 전투력 %d", player:GetAttribute("Power") or 0), TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110) }, top)

	-- 장비 칸 4개: 왼쪽(무기 / 장갑), 오른쪽(갑옷 / 신발)
	local function slotBox(slotKey, x, y)
		local item = equipped[slotKey]
		local rarity = item and item.Rarity or 0
		local box = makeButton({
			Size = UDim2.new(0, 88, 0, 88), Position = UDim2.new(0, x, 0, y), Text = "",
			BackgroundColor3 = item and Color3.fromRGB(46, 48, 68) or Color3.fromRGB(34, 34, 48), AutoButtonColor = true,
		}, top, function()
			if item then
				menuContent:SetAttribute("SelectedItem", item.Id)
				refreshMenu()
			end
		end)
		rounded(box, 10)
		if slotKey == "Weapon" then
			local tier = Config.GetWeaponTier(player:GetAttribute("WeaponLevel") or 0)
			rarityOutline(box, 4, 3.5).Color = tier.Color
			makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 6), Text = "🔫", TextSize = 32 }, box)
			makeLabel({ Size = UDim2.new(1, -6, 0, 36), Position = UDim2.new(0, 3, 0, 46), Text = tier.Name, TextSize = 12, TextWrapped = true, TextColor3 = tier.Color, Font = Enum.Font.GothamBold }, box)
		elseif item then
			rarityOutline(box, rarity)
			makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 4), Text = SLOT_ICONS[slotKey], TextSize = 32 }, box)
			makeLabel({ Size = UDim2.new(1, -6, 0, 16), Position = UDim2.new(0, 3, 0, 44), Text = Config.ItemDisplayName(item), TextSize = 11, TextWrapped = true, TextColor3 = Config.Gear.RarityColors[rarity], Font = Enum.Font.GothamBold }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 64), Text = string.format("+%d", item.Level), TextSize = 13, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack }, box)
			if item.Unique then
				makeLabel({ Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(1, -18, 0, 2), Text = "✦", TextSize = 14, TextColor3 = Color3.fromRGB(255, 184, 77) }, box)
			end
		else
			create("UIStroke", { Color = Color3.fromRGB(70, 70, 90), Thickness = 1.5 }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 10), Text = SLOT_ICONS[slotKey], TextSize = 30, TextTransparency = 0.6 }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 56), Text = "비어 있음", TextSize = 12, TextColor3 = Color3.fromRGB(120, 120, 140) }, box)
		end
		return box
	end
	-- 왼쪽: 투구 / 갑옷 / 장갑   오른쪽: 목걸이 / 반지 / 신발   오른쪽 아래: 무기
	slotBox("Helmet", 10, 12)
	slotBox("Armor", 10, 108)
	slotBox("Gloves", 10, 204)
	slotBox("Necklace", 350, 12)
	slotBox("Ring", 350, 108)
	slotBox("Boots", 350, 204)
	slotBox("Weapon", 350, 300)

	-- 선택한 아이템 설명
	local detail = create("Frame", { Size = UDim2.new(1, -462, 1, -24), Position = UDim2.new(0, 450, 0, 12), BackgroundColor3 = Color3.fromRGB(24, 26, 38), BorderSizePixel = 0 }, top)
	rounded(detail, 10)
	if selected then
		local color = Config.Gear.RarityColors[selected.Rarity]
		rarityOutline(detail, selected.Rarity)
		local slot = Config.GetGearSlot(selected.Slot)
		local lines = {
			string.format("<font color='#%s' size='18'><b>[%s] %s</b></font>  +%d", hex(color), Config.Gear.RarityNames[selected.Rarity], Config.ItemDisplayName(selected), selected.Level),
			string.format("<font color='#aaaacc' size='12'>%s · 점수 %d%s</font>", slot.Name, selected.Score, selected.Equipped and " · 장착 중" or ""),
			"<font size='13' color='#ddddee'>기본  " .. Config.FormatGearStat(selected.Slot, Config.GetGearStat(selected.Slot, selected.Rarity, selected.Level)) .. "</font>"
				.. (Config.StatDesc[slot.Stat] and ("\n<font size='11' color='#8a8aa8'>   → " .. Config.StatDesc[slot.Stat].Desc .. "</font>") or ""),
		}
		for _, affix in ipairs(selected.Affixes) do
			local info = Config.StatDesc[affix.Stat]
			table.insert(lines, "<font size='13' color='#9ad7ff'>◆ " .. Config.FormatAffix(affix.Stat, affix.Value) .. "</font>"
				.. (info and ("\n<font size='11' color='#8a8aa8'>   → " .. info.Desc .. "</font>") or ""))
		end
		if selected.Unique and Config.Uniques[selected.Unique] then
			table.insert(lines, "<font size='13' color='#ffb84d'>✦ 유니크: " .. Config.Uniques[selected.Unique].Desc .. "</font>")
		end
		if selected.Set and Config.Sets[selected.Set] then
			local setDef = Config.Sets[selected.Set]
			local b2, b3 = {}, {}
			for _, b in ipairs(setDef.Bonuses[2]) do table.insert(b2, Config.FormatBonus(b.Stat, b.Value)) end
			for _, b in ipairs(setDef.Bonuses[3]) do table.insert(b3, Config.FormatBonus(b.Stat, b.Value)) end
			if setDef.Zone then
				table.insert(lines, string.format("<font size='12' color='#%s'><b>📍 구역 %d · %s 에서만 떨어지는 전용 장비!</b></font>", hex(setDef.Color), setDef.Zone, Config.Field.ZoneNames[setDef.Zone]))
			end
			table.insert(lines, string.format("<font size='12' color='#%s'>◈ 세트 [%s] %d/3\n  2부위: %s\n  3부위: %s</font>", hex(setDef.Color), setDef.Name, setCounts[selected.Set] or 0, table.concat(b2, ", "), table.concat(b3, ", ")))
		end
		-- 지금 장착한 같은 부위 장비와 비교
		local current = equipped[selected.Slot]
		if current and current.Id ~= selected.Id then
			local diff = selected.Score - current.Score
			table.insert(lines, diff >= 0 and string.format("<font color='#78ff8c'>장착 중인 것보다 ▲ +%d</font>", diff) or string.format("<font color='#ff8c8c'>장착 중인 것보다 ▼ %d</font>", diff))
		end
		makeLabel({
			Size = UDim2.new(1, -20, 1, -64), Position = UDim2.new(0, 10, 0, 8), Text = table.concat(lines, "\n"), TextSize = 14, RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		}, detail)
		if not selected.Equipped then
			makeButton({ Size = UDim2.new(0, 96, 0, 30), Position = UDim2.new(0, 10, 1, -40), Text = "장착", TextSize = 14, BackgroundColor3 = GREEN }, detail, function()
				Remotes.Inventory:FireServer("Equip", selected.Id)
			end)
			makeButton({ Size = UDim2.new(0, 96, 0, 30), Position = UDim2.new(0, 112, 1, -40), Text = "분해", TextSize = 14, BackgroundColor3 = RED }, detail, function()
				Remotes.Inventory:FireServer("Scrap", selected.Id)
			end)
		end
		if #selected.Affixes > 0 then
			makeButton({
				Size = UDim2.new(0, 120, 0, 30), Position = UDim2.new(1, -130, 1, -40),
				Text = string.format("재굴림 ✨%d", Config.Inventory.RerollEssence[selected.Rarity]), TextSize = 12, BackgroundColor3 = Color3.fromRGB(70, 110, 220),
			}, detail, function()
				Remotes.Inventory:FireServer("Reroll", selected.Id)
			end)
		end
	else
		makeLabel({ Size = UDim2.new(1, -20, 1, -20), Position = UDim2.new(0, 10, 0, 10), Text = "장비가 없어요.\n필드에서 몬스터를 잡거나 뽑기로 얻어보세요!", TextSize = 15, TextColor3 = Color3.fromRGB(150, 150, 170) }, detail)
	end

	-- ===== 아래쪽: 가방 칸(격자) =====
	sectionTitle(string.format("🎒 가방 (%d / %d) — 칸을 누르면 위에 자세히 나와요", state.BagCount, state.Capacity))
	local columns = 10
	local rowsNeeded = math.max(1, math.ceil(#bag / columns))
	local gridRow = newRow(rowsNeeded * 76 + 14)
	if #bag == 0 then
		makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "가방이 비어 있어요", TextSize = 15, TextColor3 = Color3.fromRGB(130, 130, 150) }, gridRow)
	end
	create("UIGridLayout", { CellSize = UDim2.new(0, 68, 0, 68), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, gridRow)
	create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10) }, gridRow)
	for order, item in ipairs(bag) do
		local tile = makeButton({
			Text = "", LayoutOrder = order,
			BackgroundColor3 = (selected and selected.Id == item.Id) and Color3.fromRGB(70, 74, 104) or Color3.fromRGB(42, 44, 62), AutoButtonColor = true,
		}, gridRow, function()
			menuContent:SetAttribute("SelectedItem", item.Id)
			refreshMenu()
		end)
		rounded(tile, 8)
		rarityOutline(tile, item.Rarity, (selected and selected.Id == item.Id) and 5 or nil)
		makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 4), Text = SLOT_ICONS[item.Slot], TextSize = 26 }, tile)
		makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 36), Text = string.format("+%d", item.Level), TextSize = 12, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack }, tile)
		local equippedItem = equipped[item.Slot]
		local compare = ""
		if equippedItem then
			compare = item.Score > equippedItem.Score and "▲" or (item.Score < equippedItem.Score and "▼" or "")
		else
			compare = "▲"
		end
		if compare ~= "" then
			makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(1, -16, 0, 3), Text = compare, TextSize = 12, TextColor3 = compare == "▲" and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 120, 120), Font = Enum.Font.GothamBlack }, tile)
		end
		if item.Unique then
			makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 2, 0, 3), Text = "✦", TextSize = 12, TextColor3 = Color3.fromRGB(255, 184, 77) }, tile)
		end
		if item.Set then
			makeLabel({ Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -14), Text = "세트", TextSize = 10, TextColor3 = Config.Sets[item.Set].Color, Font = Enum.Font.GothamBold }, tile)
		end
	end
end

-- 서버가 보낸 시점 기준으로 남은 시간 계산 (내 PC 시계와 서버 시계가 달라도 정확)
local function growthRemaining(endAt)
	return endAt - (growthState.ServerTime + (os.clock() - growthReceivedAt))
end

local function buildGrowthTab()
	local state = growthState
	if not state then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>불러오는 중...</font>")
		return
	end

	local header = newRow(78)
	rowText(header, string.format(
		"⏱ 시간 단축권 <font color='#ffe16e'><b>%s</b></font> 보유      🏋 훈련 슬롯 <b>%d / %d</b> 사용 중\n<font size='13' color='#bbbbcc'>훈련과 돌파는 시간이 지나면 저절로 끝나요 (접속하지 않아도 흘러요). 시간 단축권으로 기다리는 시간을 줄일 수 있고, 퀘스트로도 조금씩 얻어요. 돈을 쓰지 않아도 모두 도달할 수 있어요.</font>",
		Config.FormatDuration(state.TimeSkip), #state.Jobs, state.Slots
	), 15, 24)

	sectionTitle("🏋 훈련소 — 영구적으로 강해져요")
	for _, stat in ipairs(Config.Growth.Stats.Order) do
		local def = Config.Growth.Stats[stat]
		local level = state.Levels[stat] or 0
		local job
		for _, candidate in ipairs(state.Jobs) do
			if candidate.Stat == stat then
				job = candidate
			end
		end

		local current = Config.FormatTrainEffect(stat, level)
		local nextText = level < Config.Growth.MaxLevel and ("  →  " .. Config.FormatTrainEffect(stat, level + 1)) or "  (최대)"
		local status
		if job then
			status = string.format("<font color='#ffd966'>훈련 중 · 남은 시간 %s</font>", Config.FormatDuration(growthRemaining(job.EndAt)))
		elseif level >= Config.Growth.MaxLevel then
			status = "<font color='#78ff8c'>최대 단계!</font>"
		else
			status = string.format("<font color='#bbbbcc'>필요 시간 %s · 💰 %d G</font>", Config.FormatDuration(Config.GetTrainTime(level)), Config.GetTrainGold(level))
		end

		local row = newRow(84)
		rowText(row, string.format("<font size='17'><b>%s %s</b></font>  Lv.%d / %d\n<font color='#ddddee'>%s%s</font>\n%s",
			def.Icon, def.Name, level, Config.Growth.MaxLevel, current, nextText, status), 14, 190)

		if job then
			makeButton({
				Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
				Text = "⏱ 단축권 사용", TextSize = 14, BackgroundColor3 = state.TimeSkip > 0 and Color3.fromRGB(200, 130, 40) or GRAY,
			}, row, function()
				Remotes.Growth:FireServer("Skip", "Train", stat)
			end)
		elseif level < Config.Growth.MaxLevel then
			makeButton({
				Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
				Text = "훈련 시작", TextSize = 15, BackgroundColor3 = GREEN,
			}, row, function()
				Remotes.Growth:FireServer("Train", stat)
			end)
		end
	end

	sectionTitle("🚧 돌파 — 레벨이 막히는 구간을 넘어요")
	local gateIndex
	for index, gate in ipairs(Config.Growth.Gates) do
		if gate > state.GatePassed then
			gateIndex = index
			break
		end
	end

	local gateRow = newRow(92)
	if not gateIndex then
		rowText(gateRow, "<font color='#78ff8c'>모든 돌파를 마쳤어요! 최대 레벨까지 자유롭게 성장할 수 있어요.</font>")
	else
		local gateLevel = Config.Growth.Gates[gateIndex]
		local myLevel = player:GetAttribute("Level") or 1
		local text
		if state.GateJob then
			text = string.format("<font size='17'><b>레벨 %d 돌파 중</b></font>\n<font color='#ffd966'>남은 시간 %s</font>", state.GateJob.Level, Config.FormatDuration(growthRemaining(state.GateJob.EndAt)))
		else
			text = string.format("<font size='17'><b>레벨 %d 돌파</b></font>   (현재 Lv.%d)\n<font color='#bbbbcc'>필요 시간 %s · 💰 %d G</font>\n<font size='13' color='#bbbbcc'>%s</font>",
				gateLevel, myLevel, Config.FormatDuration(Config.Growth.GateTime[gateIndex]), Config.Growth.GateGold[gateIndex],
				myLevel >= gateLevel and "지금 돌파할 수 있어요!" or string.format("레벨 %d 에 도달하면 돌파할 수 있어요", gateLevel))
		end
		rowText(gateRow, text, 14, 190)

		if state.GateJob then
			makeButton({
				Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
				Text = "⏱ 단축권 사용", TextSize = 14, BackgroundColor3 = state.TimeSkip > 0 and Color3.fromRGB(200, 130, 40) or GRAY,
			}, gateRow, function()
				Remotes.Growth:FireServer("Skip", "Gate")
			end)
		else
			makeButton({
				Size = UDim2.new(0, 160, 0, 34), Position = UDim2.new(1, -172, 0.5, -17),
				Text = "돌파 시작", TextSize = 15, BackgroundColor3 = myLevel >= gateLevel and GREEN or GRAY,
			}, gateRow, function()
				Remotes.Growth:FireServer("Gate")
			end)
		end
	end
end

local function auraUnlockText(aura)
	local unlock = aura.Unlock
	if unlock == "Free" then return "기본 제공" end
	if unlock.Ach then
		for _, achievement in ipairs(Config.Achievements) do
			if achievement.Id == unlock.Ach then
				return "업적 달성: " .. achievement.Name
			end
		end
	end
	if unlock.Pass then return Config.Shop.Passes[unlock.Pass].Name .. " 전용" end
	if unlock.Product then return "상점 상품: " .. Config.Shop.Products[unlock.Product].Name end
	return ""
end

local function shopButtonLabel(id)
	if id > 0 then return "구매", GREEN end
	if RunService:IsStudio() then return "테스트 지급", Color3.fromRGB(200, 130, 40) end
	return "준비 중", GRAY
end

local function buildShopTab()
	local note = newRow(52)
	rowText(note, "<font size='13' color='#bbbbcc'>상점은 <b>시간을 줄여주는 것</b>과 편의, 꾸미기를 팔아요. 돈을 쓰지 않아도 모든 성장에 도달할 수 있고, 장비는 필드에서 직접 얻어야 해요.</font>", 13)

	sectionTitle("⭐ 패스")
	for _, key in ipairs(Config.Shop.PassOrder) do
		local def = Config.Shop.Passes[key]
		local owned = key == "VIP" and player:GetAttribute("Vip") == true
		local row = newRow(76)
		rowText(row, string.format("<font size='17'><b>%s</b></font>\n<font size='13' color='#bbbbcc'>%s</font>", def.Name, def.Desc), 14, 170)
		local label, color = shopButtonLabel(def.PassId)
		makeButton({
			Size = UDim2.new(0, 130, 0, 34), Position = UDim2.new(1, -142, 0.5, -17),
			Text = owned and "보유 중" or label, TextSize = 14, BackgroundColor3 = owned and GRAY or color,
		}, row, function()
			if not owned then
				Remotes.Shop:FireServer("Buy", "Pass", key)
			end
		end)
	end

	sectionTitle("🛍 상품")
	local now = os.time()
	for _, key in ipairs(Config.Shop.ProductOrder) do
		local def = Config.Shop.Products[key]
		local extra = ""
		if def.Grant.XpBoost and (player:GetAttribute("XpBoostUntil") or 0) > now then
			extra = string.format("  <font color='#78ff8c'>적용 중 %s</font>", Config.FormatDuration(player:GetAttribute("XpBoostUntil") - now))
		elseif def.Grant.LuckBoost and (player:GetAttribute("LuckBoostUntil") or 0) > now then
			extra = string.format("  <font color='#78ff8c'>적용 중 %s</font>", Config.FormatDuration(player:GetAttribute("LuckBoostUntil") - now))
		end
		local row = newRow(66)
		rowText(row, string.format("<font size='16'><b>%s</b></font>%s\n<font size='13' color='#bbbbcc'>%s</font>", def.Name, extra, def.Desc), 14, 170)
		local label, color = shopButtonLabel(def.ProductId)
		makeButton({
			Size = UDim2.new(0, 130, 0, 32), Position = UDim2.new(1, -142, 0.5, -16), Text = label, TextSize = 14, BackgroundColor3 = color,
		}, row, function()
			Remotes.Shop:FireServer("Buy", "Product", key)
		end)
	end

	sectionTitle("✨ 오라 (꾸미기 · 능력치 없음 · 다른 플레이어에게도 보여요)")
	local current = player:GetAttribute("Aura") or ""
	for _, key in ipairs(Config.Auras.Order) do
		local aura = Config.Auras[key]
		local owned = player:GetAttribute("AuraOwned_" .. key) == true
		local row = newRow(56)
		rowText(row, string.format("<font color='#%s' size='16'><b>%s</b></font>\n<font size='13' color='#bbbbcc'>%s</font>",
			hex(aura.Color), aura.Name, owned and "보유 중" or ("🔒 " .. auraUnlockText(aura))), 14, 170)
		if owned then
			local equipped = current == key
			makeButton({
				Size = UDim2.new(0, 130, 0, 30), Position = UDim2.new(1, -142, 0.5, -15),
				Text = equipped and "해제" or "장착", TextSize = 14, BackgroundColor3 = equipped and RED or GREEN,
			}, row, function()
				Remotes.Shop:FireServer("Aura", equipped and "" or key)
			end)
		end
	end
end

local metaState = nil

local function buildSkillTab()
	sectionTitle("⚔ 스킬 강화 — 골드로 레벨업. 레벨이 오를수록 강해지고 쿨타임이 줄어요. (필드/던전에서 C 치료 · V 궁극기)")
	local U = Config.SkillUpgrade
	for _, key in ipairs(Config.Skills.Order) do
		local cfg = Config.Skills[key]
		local level = metaState and metaState.Skills[key] or 1
		local lv = level - 1
		local detail
		if key == "Barrier" then
			detail = string.format("지속 %.1f초", cfg.Duration + U.BarrierDuration * lv)
		elseif key == "Blast" then
			detail = string.format("범위 %.1f · 공격력 x%.2f", cfg.Radius + U.BlastRadius * lv, cfg.Mult * (1 + U.BlastMult * lv))
		elseif key == "Heal" then
			detail = string.format("체력 %d%% 회복", math.floor((cfg.Ratio + U.HealRatio * lv) * 100 + 0.5))
		else
			detail = string.format("공격력 x%.2f (게이지 %d)", cfg.Mult * (1 + U.UltMult * lv), cfg.Cost)
		end
		local row = newRow(74)
		rowText(row, string.format("<font size='17'><b>[%s] %s %s</b></font>  <font color='#ffd966'>Lv.%d / %d</font>\n<font color='#bbbbcc'>%s</font>\n<font color='#9ad7ff'>%s · 쿨타임 %.1f초</font>",
			cfg.Key, cfg.Icon, cfg.Name, level, U.MaxLevel, cfg.Desc, detail, cfg.Cooldown * (1 - U.CooldownPerLevel * lv)), 14, 190)
		local maxed = level >= U.MaxLevel
		makeButton({
			Size = UDim2.new(0, 150, 0, 34), Position = UDim2.new(1, -162, 0.5, -17),
			Text = maxed and "MAX" or string.format("강화 %d G", Config.GetSkillUpgradeCost(level)),
			BackgroundColor3 = maxed and GRAY or GREEN,
		}, row, function()
			if not maxed then
				Remotes.Meta:FireServer("SkillUp", key)
			end
		end)
	end
end

local function buildPetTab()
	local owned = metaState and metaState.Owned or {}
	local equipped = metaState and metaState.Equipped
	local P = Config.Pets
	local header = newRow(64)
	rowText(header, string.format("🥚 펫 알을 부화시켜 펫을 모아요. 같은 펫이 또 나오면 펫 레벨 업 (최대 %d)\n<font color='#bbbbcc' size='13'>장착한 펫은 캐릭터를 따라다니며 능력치를 줘요. 알 부화는 로비에서만 가능.</font>", P.MaxLevel), 14, 210)
	makeButton({
		Size = UDim2.new(0, 190, 0, 40), Position = UDim2.new(1, -202, 0.5, -20),
		Text = string.format("🥚 알 부화 %d G", P.EggCost), BackgroundColor3 = Color3.fromRGB(200, 130, 40), TextSize = 15,
	}, header, function()
		Remotes.Meta:FireServer("Hatch")
	end)

	for _, key in ipairs(P.Order) do
		local pet = P[key]
		local level = owned[key]
		local color = P.RarityColors[pet.Rarity]
		local row = newRow(58, level and Color3.fromRGB(40, 40, 58) or Color3.fromRGB(30, 30, 40))
		if level then
			rowText(row, string.format("<font color='#%s' size='16'><b>[%s] %s</b></font>  <font color='#ffd966'>Lv.%d</font>\n<font color='#9ad7ff'>%s</font>",
				hex(color), P.RarityNames[pet.Rarity], pet.Name, level, Config.FormatPetStat(key, level)), 14, 150)
			local isEquipped = equipped == key
			makeButton({
				Size = UDim2.new(0, 120, 0, 32), Position = UDim2.new(1, -132, 0.5, -16),
				Text = isEquipped and "해제" or "장착", BackgroundColor3 = isEquipped and RED or GREEN,
			}, row, function()
				Remotes.Meta:FireServer("Equip", isEquipped and "" or key)
			end)
		else
			rowText(row, string.format("<font color='#777788' size='16'><b>[%s] ???</b></font>\n<font color='#666677'>아직 못 얻었어요 · %s</font>",
				P.RarityNames[pet.Rarity], Config.FormatPetStat(key, 1)), 14, 150)
		end
	end
end

Remotes.Meta.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		metaState = data
		if menuPanel.Visible and (currentTab == "Skill" or currentTab == "Pet") then
			refreshMenu()
		end
	end
end)

function refreshMenu()
	for _, tab in ipairs(TABS) do
		tabButtons[tab.Key].BackgroundColor3 = tab.Key == currentTab and Color3.fromRGB(70, 110, 220) or GRAY
	end

	clearChildren(menuContent)
	rowOrder = 0
	if currentTab == "Character" then
		buildCharacterTab()
	elseif currentTab == "Inventory" then
		buildInventoryTab()
	elseif currentTab == "Growth" then
		buildGrowthTab()
	elseif currentTab == "Shop" then
		buildShopTab()
	elseif currentTab == "Weapon" then
		buildWeaponTab()
	elseif currentTab == "Skill" then
		buildSkillTab()
	elseif currentTab == "Pet" then
		buildPetTab()
	elseif currentTab == "Quest" then
		sectionTitle("📅 오늘의 일일 퀘스트 (매일 바뀌어요)")
		buildProgressRows(questState and questState.Daily, "Claim", false)
	elseif currentTab == "Ach" then
		sectionTitle("🏅 업적 — 달성하면 보상과 칭호를 받아요")
		buildProgressRows(questState and questState.Achievements, "ClaimAch", true)
	elseif currentTab == "Rank" then
		buildRankTab()
	end
end

local function selectTab(key)
	currentTab = key
	if key == "Quest" or key == "Ach" or key == "Character" then
		Remotes.Quest:FireServer("Request")
	elseif key == "Rank" then
		Remotes.Rank:FireServer("Request")
	elseif key == "Inventory" then
		Remotes.Inventory:FireServer("Request")
	elseif key == "Growth" then
		Remotes.Growth:FireServer("Request")
	elseif key == "Skill" or key == "Pet" then
		Remotes.Meta:FireServer("Request")
	end
	refreshMenu()
end

for index, tab in ipairs(TABS) do
	tabButtons[tab.Key] = makeButton({
		Size = UDim2.new(0, 80, 0, 34), Position = UDim2.new(0, 14 + (index - 1) * 85, 0, 52), Text = tab.Name, TextSize = 14,
	}, menuPanel, function()
		selectTab(tab.Key)
	end)
end

local function toggleMenu()
	menuPanel.Visible = not menuPanel.Visible
	if menuPanel.Visible then
		selectTab(currentTab)
	end
end

makeButton({
	Size = UDim2.new(0, 110, 0, 32), Position = UDim2.new(0, 16, 0, 244), Text = "📋 메뉴 (I)", TextSize = 14,
	BackgroundColor3 = Color3.fromRGB(60, 70, 120),
}, gui, toggleMenu)

Remotes.Quest.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		questState = data
		if menuPanel.Visible then
			refreshMenu()
		end
	end
end)

Remotes.Inventory.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		inventoryState = data
		if menuPanel.Visible and currentTab == "Inventory" then
			refreshMenu()
		end
	end
end)

Remotes.Growth.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		growthState = data
		growthReceivedAt = os.clock()
		if menuPanel.Visible and (currentTab == "Growth" or currentTab == "Character") then
			refreshMenu()
		end
	end
end)

-- 남은 시간 / 부스터 시간이 흐르는 탭은 1초마다 갱신
task.spawn(function()
	while true do
		task.wait(1)
		if menuPanel.Visible and (currentTab == "Growth" or currentTab == "Shop") then
			refreshMenu()
		end
	end
end)

Remotes.Rank.OnClientEvent:Connect(function(action, data)
	if action == "List" then
		rankList = data
		if menuPanel.Visible and currentTab == "Rank" then
			refreshMenu()
		end
	end
end)

-- 골드/장비/무기 등이 바뀌면 열려 있는 메뉴도 갱신 (한꺼번에 여러 번 와도 한 번만)
local menuRefreshQueued = false
player.AttributeChanged:Connect(function()
	if not menuPanel.Visible or menuRefreshQueued then return end
	menuRefreshQueued = true
	task.defer(function()
		menuRefreshQueued = false
		if menuPanel.Visible then
			refreshMenu()
		end
	end)
end)

------------------------------------------------------------
-- 던전 선택창 (게이트): 종류 + 난이도
------------------------------------------------------------
local refreshSelect
local selectedType = "Cave"
local selectedDifficulty = "Normal"

local selectPanel = makePanel({
	Size = UDim2.new(0, 890, 0, 500),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Visible = false,
}, gui)

makeLabel({
	Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8),
	Text = "⚔ 던전 선택", Font = Enum.Font.GothamBlack, TextSize = 24,
}, selectPanel)

local typeCards = {}
for index, key in ipairs(Config.Dungeon.Types.Order) do
	local info = Config.Dungeon.Types[key]
	local card = makeButton({
		Size = UDim2.new(0, 200, 0, 170), Position = UDim2.new(0, 14 + (index - 1) * 212, 0, 54),
		Text = "", BackgroundColor3 = Color3.fromRGB(40, 40, 58), AutoButtonColor = true,
	}, selectPanel, function()
		selectedType = key
		refreshSelect()
	end)
	create("UIStroke", { Color = info.Torch, Thickness = 0, Name = "Stroke" }, card)
	makeLabel({
		Size = UDim2.new(1, -16, 1, -12), Position = UDim2.new(0, 8, 0, 6), RichText = true,
		Text = string.format("<font size='20'><b>%s</b></font>\n\n<font color='#bbbbcc' size='13'>%s</font>\n\n%s\n권장 전투력 %d",
			info.Name, info.Desc, info.Endless and "웨이브 ∞ (최고 층 도전)" or ("웨이브 " .. info.Waves .. " + 보스"), info.RecommendedPower),
		TextSize = 15, TextYAlignment = Enum.TextYAlignment.Top,
	}, card)
	typeCards[key] = card
end

makeLabel({
	Size = UDim2.new(1, -28, 0, 22), Position = UDim2.new(0, 14, 0, 236),
	Text = "난이도", Font = Enum.Font.GothamBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
}, selectPanel)

local difficultyButtons = {}
for index, key in ipairs(Config.Dungeon.Difficulties.Order) do
	local info = Config.Dungeon.Difficulties[key]
	difficultyButtons[key] = makeButton({
		Size = UDim2.new(0, 200, 0, 40), Position = UDim2.new(0, 14 + (index - 1) * 212, 0, 262),
		Text = string.format("%s  🗝%d", info.Name, info.KeyCost), TextSize = 18, BackgroundColor3 = GRAY,
	}, selectPanel, function()
		selectedDifficulty = key
		refreshSelect()
	end)
end

local summaryLabel = makeLabel({
	Size = UDim2.new(1, -28, 0, 110), Position = UDim2.new(0, 14, 0, 314), RichText = true,
	TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, selectPanel)

function refreshSelect()
	for key, card in pairs(typeCards) do
		card.Stroke.Thickness = key == selectedType and 3 or 0
	end
	for key, button in pairs(difficultyButtons) do
		local info = Config.Dungeon.Difficulties[key]
		button.BackgroundColor3 = key == selectedDifficulty and info.Color:Lerp(Color3.fromRGB(30, 30, 40), 0.35) or GRAY
	end

	local dungeonType = Config.Dungeon.Types[selectedType]
	local difficulty = Config.Dungeon.Difficulties[selectedDifficulty]
	summaryLabel.Text = string.format(
		"<b>%s · %s</b>\n%s → 보스 <font color='#ff9a9a'>%s</font>\n권장 전투력 <font color='#ffe16e'>%d</font>  (내 전투력 %d)\n골드 x%.1f · 티켓 %d장 · 보스 상자 장비 %d개\n🗝 열쇠 <b>%d개</b> 필요 (보유 %d개) — 시간이 지나면 저절로 차요",
		dungeonType.Name, difficulty.Name, dungeonType.Endless and "끝없는 웨이브 (나의 최고 층 " .. (player:GetAttribute("TowerBest") or 0) .. ")" or ("웨이브 " .. dungeonType.Waves .. "개"), dungeonType.Boss.Name,
		dungeonType.RecommendedPower, player:GetAttribute("Power") or 0,
		dungeonType.GoldMult * difficulty.GoldMult, difficulty.Tickets, Config.Loot.DungeonChestCount,
		difficulty.KeyCost, player:GetAttribute("Keys") or 0
	)
end

makeButton({
	Size = UDim2.new(0, 280, 0, 46), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14),
	Text = "입장하기", TextSize = 20, BackgroundColor3 = GREEN,
}, selectPanel, function()
	selectPanel.Visible = false
	Remotes.Dungeon:FireServer("Start", selectedType, selectedDifficulty)
end)

makeButton({
	Size = UDim2.new(0, 280, 0, 46), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14),
	Text = "닫기", TextSize = 20, BackgroundColor3 = GRAY,
}, selectPanel, function()
	selectPanel.Visible = false
end)

openDungeonSelect = function()
	refreshSelect()
	selectPanel.Visible = true
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	if currentZone() == "Dungeon" then
		selectPanel.Visible = false
	end
	lockTarget = nil
	updateLockVisual()
end)

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

------------------------------------------------------------
-- 워프 메뉴: 필드 캠프 비콘 / 필드 입구에서 열린다. 마을이나 도달한 구역의 캠프로 바로 이동.
------------------------------------------------------------
local warpPanel = makePanel({
	Size = UDim2.new(0, 440, 0, 520),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Visible = false,
}, gui)

makeLabel({
	Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8),
	Text = "⛺ 워프", Font = Enum.Font.GothamBlack, TextSize = 24,
}, warpPanel)
makeLabel({
	Size = UDim2.new(1, -28, 0, 36), Position = UDim2.new(0, 14, 0, 44),
	Text = "도달한 구역의 캠프로 이동할 수 있어요. 필드에서 죽으면 가까웠던 캠프에서 부활해요.",
	TextSize = 13, TextColor3 = Color3.fromRGB(190, 190, 210),
}, warpPanel)

local warpList = create("Frame", { Size = UDim2.new(1, -28, 1, -140), Position = UDim2.new(0, 14, 0, 84), BackgroundTransparency = 1 }, warpPanel)
create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, warpList)

makeButton({
	Size = UDim2.new(1, -28, 0, 36), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14),
	Text = "닫기", TextSize = 16, BackgroundColor3 = GRAY,
}, warpPanel, function()
	warpPanel.Visible = false
end)

local function refreshWarp()
	clearChildren(warpList)
	local reached = math.max(1, player:GetAttribute("MaxZone") or 0)

	local function addRow(order, text, unlocked, zone)
		makeButton({
			Size = UDim2.new(1, 0, 0, 36), LayoutOrder = order, Text = text, TextSize = 15,
			BackgroundColor3 = unlocked and Color3.fromRGB(60, 90, 160) or GRAY, TextXAlignment = Enum.TextXAlignment.Left,
		}, warpList, function()
			if unlocked then
				warpPanel.Visible = false
				Remotes.Warp:FireServer("Go", zone)
			end
		end)
	end

	addRow(0, "  🏠 마을 (로비)", true, 0)
	for zone = 1, Config.Field.ZoneCount do
		local unlocked = zone <= reached
		local zoneSet = Config.Sets[Config.Sets.ZoneKeys[zone]]
		addRow(zone, string.format("  %s 구역 %d · %s   (몬스터 Lv.%d)  %s %s 세트", unlocked and "⛺" or "🔒", zone, Config.Field.ZoneNames[zone], Config.Field.GetZoneLevel(zone), zoneSet.Icon, zoneSet.Name), unlocked, zone)
	end
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	if currentZone() == "Dungeon" then
		warpPanel.Visible = false
	end
end)

Remotes.Warp.OnClientEvent:Connect(function(action)
	if action == "Open" then
		refreshWarp()
		warpPanel.Visible = true
	end
end)

------------------------------------------------------------
-- 입력
--   마우스: 조준 방향 공격(누르고 있으면 연사) / R: 자동 공격(락온) / Q: 대시 / Shift: 달리기
--   I: 메뉴 / 던전 안: 숫자키 1 2 3 스탯 투자
------------------------------------------------------------
do
------------------------------------------------------------
-- 전투 피드백: 피격 시 화면이 붉게 번쩍임 / 체력이 낮으면 붉은 경고 / 연속 처치 콤보 표시
------------------------------------------------------------
local hurtFlash = create("Frame", {
	Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(220, 20, 20), BackgroundTransparency = 1,
	BorderSizePixel = 0, ZIndex = 0, Active = false,
}, gui)
local flashStrength = 0
local lowHealthRatio = 1

local comboLabel = makeLabel({
	Size = UDim2.new(0, 260, 0, 60), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.4, 0),
	Font = Enum.Font.GothamBlack, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Right, Visible = false,
	TextColor3 = Color3.fromRGB(255, 190, 60), TextStrokeTransparency = 0.2,
}, gui)

local function watchHealth(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < last - 0.5 then
			flashStrength = math.clamp(flashStrength + (last - health) / humanoid.MaxHealth * 3 + 0.25, 0, 0.6)
		end
		last = health
		lowHealthRatio = health / math.max(1, humanoid.MaxHealth)
	end)
end
if player.Character then
	task.spawn(watchHealth, player.Character)
end
player.CharacterAdded:Connect(watchHealth)

RunService.RenderStepped:Connect(function(dt)
	flashStrength = math.max(0, flashStrength - dt * 1.4)
	local pulse = 0
	if lowHealthRatio < 0.3 and lowHealthRatio > 0 then
		pulse = (0.12 + 0.1 * math.sin(os.clock() * 6)) * (1 - lowHealthRatio / 0.3)
	end
	hurtFlash.BackgroundTransparency = 1 - math.max(flashStrength, pulse)

	local combo = player:GetAttribute("Combo") or 0
	comboLabel.Visible = combo >= 2
	if combo >= 2 then
		local bonus = math.min(Config.Combo.MaxStacks, combo) * Config.Combo.DamagePerStack
		comboLabel.Text = string.format("🔥 콤보 x%d\n공격력 +%d%%", combo, math.floor(bonus * 100 + 0.5))
		comboLabel.TextSize = math.clamp(24 + combo * 0.4, 24, 40)
		local left = (player:GetAttribute("ComboUntil") or 0) - os.clock()
		comboLabel.TextTransparency = left < 1 and 0.5 or 0
	end
end)
end

do
------------------------------------------------------------
-- 레이더: 주변 몬스터 위치를 원형 지도에 표시 (빨강 일반 / 노랑 엘리트 / 보라 보스 / 금색 황금 고블린)
-- 위쪽 = 카메라가 보는 방향. 범위 밖 몬스터는 가장자리에 작게 표시된다.
------------------------------------------------------------
local RADAR_SIZE, RADAR_RANGE = 150, 100
local radarFrame = create("Frame", {
	Size = UDim2.new(0, RADAR_SIZE, 0, RADAR_SIZE), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16),
	BackgroundColor3 = Color3.fromRGB(14, 18, 28), BackgroundTransparency = 0.25, BorderSizePixel = 0, Visible = false,
}, gui)
create("UICorner", { CornerRadius = UDim.new(1, 0) }, radarFrame)
create("UIStroke", { Color = Color3.fromRGB(110, 150, 220), Thickness = 2 }, radarFrame)
create("Frame", { -- 나 (중앙)
	Size = UDim2.new(0, 8, 0, 8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(90, 220, 255), BorderSizePixel = 0, ZIndex = 3,
}, radarFrame)
local radarDots = {}

local function radarDot(index)
	local dot = radarDots[index]
	if not dot then
		dot = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 2 }, radarFrame)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
		radarDots[index] = dot
	end
	return dot
end

RunService.RenderStepped:Connect(function()
	local zone = currentZone()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	radarFrame.Visible = settings.Radar and (zone == "Field" or zone == "Dungeon") and root ~= nil
	if not radarFrame.Visible then return end

	local look = camera.CFrame.LookVector
	local yaw = math.atan2(look.X, -look.Z) -- 카메라가 -Z를 볼 때 0
	local cosY, sinY = math.cos(yaw), math.sin(yaw)
	local used = 0
	for _, part in ipairs(CollectionService:GetTagged("Monster")) do
		if part:IsDescendantOf(workspace) and used < 60 then
			local offset = part.Position - root.Position
			local rx = offset.X * cosY + offset.Z * sinY   -- 오른쪽
			local ry = offset.X * sinY - offset.Z * cosY   -- 앞쪽 (+)
			local dist = math.sqrt(rx * rx + ry * ry)
			if dist < 400 then
				used += 1
				local clamped = dist > RADAR_RANGE
				local scale = clamped and RADAR_RANGE / dist or 1
				local px = 0.5 + (rx * scale) / RADAR_RANGE * 0.47
				local py = 0.5 - (ry * scale) / RADAR_RANGE * 0.47
				local dot = radarDot(used)
				local size = CollectionService:HasTag(part, "RadarBoss") and 11 or (CollectionService:HasTag(part, "RadarGold") and 10 or 6)
				if clamped then size = math.max(4, size - 2) end
				dot.Size = UDim2.new(0, size, 0, size)
				dot.Position = UDim2.new(px, 0, py, 0)
				dot.BackgroundColor3 = CollectionService:HasTag(part, "RadarBoss") and Color3.fromRGB(190, 90, 255)
					or CollectionService:HasTag(part, "RadarGold") and Color3.fromRGB(255, 215, 50)
					or CollectionService:HasTag(part, "RadarElite") and Color3.fromRGB(255, 190, 60)
					or Color3.fromRGB(255, 80, 80)
				dot.BackgroundTransparency = clamped and 0.5 or 0
				dot.Visible = true
			end
		end
	end
	for i = used + 1, #radarDots do
		radarDots[i].Visible = false
	end
end)
end

------------------------------------------------------------
-- 스킬 (C 응급 치료 / V 궁극기): 하단 스킬바 + 쿨타임 표시
------------------------------------------------------------
local useSkill
local skillByKey = {}
local skillSlots = {}
local skillCooldownTotal = {}
local skillReadyAt = {}   -- [skillKey] = 이 시각(os.clock) 이후 사용 가능
local skillBar = create("Frame", {
	Size = UDim2.new(0, (#Config.Skills.Order + 1) * 68, 0, 64), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	BackgroundTransparency = 1, Visible = false,
}, gui)
for index, skillKey in ipairs(Config.Skills.Order) do
	local cfg = Config.Skills[skillKey]
	skillByKey[Enum.KeyCode[cfg.KeyCode]] = skillKey
	local slot = create("Frame", {
		Size = UDim2.new(0, 62, 0, 62), Position = UDim2.new(0, index * 68, 0, 0),
		BackgroundColor3 = Color3.fromRGB(28, 28, 42), BorderSizePixel = 0,
	}, skillBar)
	rounded(slot)
	local slotStroke = create("UIStroke", { Color = skillKey == "Ult" and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(110, 150, 220), Thickness = 2 }, slot)
	makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 4), Text = cfg.Icon, TextSize = 24 }, slot)
	makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 34), Text = cfg.Name, TextSize = 10 }, slot)
	makeLabel({ Size = UDim2.new(0, 18, 0, 16), Position = UDim2.new(0, 3, 0, 3), Text = cfg.Key, TextSize = 12, Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 220, 90) }, slot)
	local cover = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0,
	}, slot)
	rounded(cover)
	local timer = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 20, Font = Enum.Font.GothamBlack }, slot)
	if UserInputService.TouchEnabled then -- 모바일: 스킬 칸을 눌러서 사용
		local tap = create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 5 }, slot)
		tap.Activated:Connect(function()
			useSkill(skillKey)
		end)
	end
	skillSlots[skillKey] = { Cover = cover, Timer = timer, Stroke = slotStroke }
end

-- 대시(Q) 칸: 스킬처럼 쿨타임 / 남은 횟수가 보인다 (칸을 눌러도 대시)
do
	local slot = create("Frame", { Size = UDim2.new(0, 62, 0, 62), Position = UDim2.new(0, 0, 0, 0), BackgroundColor3 = Color3.fromRGB(28, 28, 42), BorderSizePixel = 0 }, skillBar)
	rounded(slot)
	create("UIStroke", { Color = Color3.fromRGB(120, 210, 255), Thickness = 2 }, slot)
	makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 4), Text = "💨", TextSize = 24 }, slot)
	makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 34), Text = "대시", TextSize = 10 }, slot)
	makeLabel({ Size = UDim2.new(0, 18, 0, 16), Position = UDim2.new(0, 3, 0, 3), Text = "Q", TextSize = 12, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 220, 90) }, slot)
	local cover = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0 }, slot)
	rounded(cover)
	local charges = makeLabel({ Size = UDim2.new(0, 20, 0, 18), Position = UDim2.new(1, -22, 0, 3), TextSize = 14, Font = Enum.Font.GothamBlack }, slot)
	local timer = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 20, Font = Enum.Font.GothamBlack }, slot)
	if UserInputService.TouchEnabled then
		create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 5 }, slot).Activated:Connect(function()
			slide()
		end)
	end
	RunService.RenderStepped:Connect(function()
		local P = Config.Player
		local now = os.clock()
		-- 충전: 쿨타임(DashCooldown)마다 1회씩 돌아온다 (로비에서도 계속 돈다)
		if settings.DashCharges < P.DashCharges and now >= settings.DashRefillAt then
			settings.DashCharges += 1
			settings.DashRefillAt = settings.DashCharges < P.DashCharges and now + P.DashCooldown or 0
		end
		charges.Text = tostring(settings.DashCharges)
		charges.TextColor3 = settings.DashCharges > 0 and Color3.fromRGB(150, 230, 255) or Color3.fromRGB(255, 120, 120)
		if settings.DashCharges < P.DashCharges then
			local remain = settings.DashRefillAt - now
			cover.Size = UDim2.new(1, 0, settings.DashCharges == 0 and math.clamp(remain / P.DashCooldown, 0, 1) or 0.25, 0)
			timer.Text = settings.DashCharges == 0 and string.format("%.1f", math.max(0, remain)) or ""
		else
			cover.Size = UDim2.new(1, 0, 0, 0)
			timer.Text = ""
		end
	end)
end

function useSkill(skillKey)
	local zone = currentZone()
	if zone ~= "Field" and zone ~= "Dungeon" then
		toast("스킬은 필드와 던전에서만 쓸 수 있어요.")
		return
	end
	if os.clock() < (skillReadyAt[skillKey] or 0) then return end
	Remotes.Skill:FireServer("Use", skillKey, getAimPoint(UserInputService:GetMouseLocation()))
end

Remotes.Skill.OnClientEvent:Connect(function(action, skillKey, cooldown)
	if action == "Cast" and Config.Skills[skillKey] then
		skillCooldownTotal[skillKey] = cooldown or Config.Skills[skillKey].Cooldown
		skillReadyAt[skillKey] = os.clock() + skillCooldownTotal[skillKey]
	end
end)

RunService.RenderStepped:Connect(function()
	local zone = currentZone()
	skillBar.Visible = zone == "Field" or zone == "Dungeon"
	if not skillBar.Visible then return end
	for skillKey, slot in pairs(skillSlots) do
		local cfg = Config.Skills[skillKey]
		local remain = (skillReadyAt[skillKey] or 0) - os.clock()
		if skillKey == "Ult" then
			local charge = player:GetAttribute("UltCharge") or 0
			local full = charge >= cfg.Cost
			slot.Cover.Size = UDim2.new(1, 0, 1 - math.clamp(charge / cfg.Cost, 0, 1), 0)
			slot.Timer.Text = full and "" or string.format("%d%%", math.floor(charge))
			slot.Timer.TextSize = 16
			-- 가득 차면 테두리가 두껍게 깜빡여서 "지금 쓸 수 있다"를 알려준다
			slot.Stroke.Thickness = full and (3 + 2 * math.abs(math.sin(os.clock() * 5))) or 2
			slot.Stroke.Color = full and Color3.fromRGB(255, 225, 90) or Color3.fromRGB(255, 90, 90)
		elseif remain > 0 then
			slot.Cover.Size = UDim2.new(1, 0, math.clamp(remain / (skillCooldownTotal[skillKey] or cfg.Cooldown), 0, 1), 0)
			slot.Timer.Text = string.format("%.0f", math.ceil(remain))
		else
			slot.Cover.Size = UDim2.new(1, 0, 0, 0)
			slot.Timer.Text = ""
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = true
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = true
		applySpeed()
	elseif input.KeyCode == Enum.KeyCode.H then
		toggleHelp()
	elseif skillByKey[input.KeyCode] then
		useSkill(skillByKey[input.KeyCode])
	elseif input.KeyCode == Enum.KeyCode.Q then
		slide()
	elseif input.KeyCode == Enum.KeyCode.R then
		toggleAuto()
	elseif input.KeyCode == Enum.KeyCode.I then
		toggleMenu()
	elseif input.KeyCode == Enum.KeyCode.M then
		toggleMusic()
	elseif input.UserInputType == Enum.UserInputType.Touch then
		local inset = GuiService:GetGuiInset()
		attack(Vector2.new(input.Position.X, input.Position.Y) + inset)
	elseif currentZone() == "Dungeon" then
		local keys = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3 }
		local pick = perkOffer[keys[input.KeyCode] or 0]
		if pick then
			Remotes.Upgrade:FireServer(pick)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = false
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = false
		applySpeed()
	end
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextAttack then return end

	if holding then
		nextAttack = now + attackCooldown()
		attack(UserInputService:GetMouseLocation())
	elseif autoMode then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then return end

		if not isTargetValid(lockTarget, root) and now >= nextSearch then
			nextSearch = now + 0.4 -- 대상 탐색은 0.4초에 한 번만
			lockTarget = findNearestTarget(root)
			updateLockVisual()
		end
		if lockTarget and isTargetValid(lockTarget, root) then
			nextAttack = now + attackCooldown()
			fireAt(lockTarget.Part.Position)
		end
	end
end)

------------------------------------------------------------
-- 조준점: 마우스 화살표 대신 십자 격자 조준점이 마우스를 따라다닌다.
--   쏠 때마다 살짝 벌어졌다 돌아오고, 자동 공격으로 대상을 잡으면 노란색이 된다.
--   메뉴 창이 열려 있거나 버튼 위에 있을 땐 원래 화살표 마우스로 돌아온다.
------------------------------------------------------------
local hasMouse = UserInputService.MouseEnabled
local playerGui = player:WaitForChild("PlayerGui")

local crosshair = create("Frame", {
	Name = "Crosshair", Size = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 100,
}, gui)

local function makeCrosshairPart(width, height)
	local part = create("Frame", {
		Size = UDim2.new(0, width, 0, height), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 100,
	}, crosshair)
	create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, part)
	return part
end

local barUp = makeCrosshairPart(2, 11)
local barDown = makeCrosshairPart(2, 11)
local barLeft = makeCrosshairPart(11, 2)
local barRight = makeCrosshairPart(11, 2)
local centerDot = makeCrosshairPart(3, 3)

local function isMouseOverButton(position)
	for _, object in ipairs(playerGui:GetGuiObjectsAtPosition(position.X, position.Y)) do
		if object:IsA("GuiButton") and object.Visible then
			return true
		end
	end
	return false
end

RunService.RenderStepped:Connect(function(dt)
	local modalOpen = menuPanel.Visible or enhancePanel.Visible or gearPanel.Visible or selectPanel.Visible or warpPanel.Visible
	local position = UserInputService:GetMouseLocation()
	local show = hasMouse and not modalOpen and player.Character ~= nil and not isMouseOverButton(position)

	UserInputService.MouseIconEnabled = not show
	crosshair.Visible = show
	if not show then return end

	crosshairKick = math.max(0, crosshairKick - dt * 55)
	local gap = 7 + crosshairKick + (holding and 2 or 0)
	local color = (autoMode and lockTarget) and Color3.fromRGB(255, 225, 90) or Color3.new(1, 1, 1)
	hitMarker = math.max(0, hitMarker - dt)
	if hitMarker > 0 then
		color = hitMarkerCrit and Color3.fromRGB(255, 70, 60) or Color3.fromRGB(255, 200, 70)
		gap += 4 * (hitMarker / 0.18)
	end

	crosshair.Position = UDim2.fromOffset(position.X, position.Y)
	barUp.Position = UDim2.fromOffset(0, -gap - 5)
	barDown.Position = UDim2.fromOffset(0, gap + 5)
	barLeft.Position = UDim2.fromOffset(-gap - 5, 0)
	barRight.Position = UDim2.fromOffset(gap + 5, 0)
	for _, part in ipairs({ barUp, barDown, barLeft, barRight, centerDot }) do
		part.BackgroundColor3 = color
	end
end)

do
------------------------------------------------------------
-- 타격감: 적중 표시 / 적중음 / 치명타·처치 시 카메라 흔들림
------------------------------------------------------------
local function playUiSound(id, volume, pitch)
	if not id or id == 0 then return end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. id
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.Parent = game:GetService("SoundService")
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 3)
end

Remotes.Hit.OnClientEvent:Connect(function(isCrit, killed)
	hitMarker = killed and 0.3 or 0.18
	hitMarkerCrit = isCrit or killed
	if killed then
		shake = math.max(shake, 0.5)
		playUiSound(Config.Audio.Kill, 0.6, 1)
	elseif isCrit then
		shake = math.max(shake, 0.25)
		playUiSound(Config.Audio.Hit, 0.5, 1.25)
	else
		playUiSound(Config.Audio.Hit, 0.35, 1)
	end
end)

player:GetAttributeChangedSignal("ShakeTick"):Connect(function() -- 서버가 보내는 화면 흔들림 (운석 충돌 등)
		shake = math.max(shake, player:GetAttribute("ShakeStrength") or 0.5)
	end)

	RunService:BindToRenderStep("HitShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shake <= 0.01 or not settings.Shake then
		shake = 0
		return
	end
	shake = math.max(0, shake - dt * 2.5)
	local amount = shake * 0.012
	camera.CFrame = camera.CFrame * CFrame.Angles((math.random() - 0.5) * amount, (math.random() - 0.5) * amount, 0)
end)
end

do
------------------------------------------------------------
-- 도움말 / 설정 (H 키 또는 왼쪽 버튼). 처음 안내는 튜토리얼 미션이 맡는다.
------------------------------------------------------------
local helpPanel = makePanel({
	Size = UDim2.new(0, 560, 0, 580), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Visible = false,
}, gui)
makeLabel({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8), Text = "⚙ 설정 / ❓ 도움말", Font = Enum.Font.GothamBlack, TextSize = 22 }, helpPanel)
makeLabel({
	Size = UDim2.new(1, -40, 0, 280), Position = UDim2.new(0, 20, 0, 50), RichText = true, TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	Text = table.concat({
		"<b>이동/공격</b>  WASD 이동 · Shift 달리기 · Q 대시 · 마우스 클릭(누르고 있으면 연사) 공격",
		"<b>자동 공격</b>  R — 가장 가까운 적을 자동으로 조준 (적을 클릭하면 그 대상으로 고정)",
		"<b>스킬</b>  C 응급 치료 · V 궁극기(적을 공격해 게이지 100%를 채우면 사용)  — 필드/던전에서 사용",
		"<b>메뉴</b>  I — 가방 · 무기 · 성장 · 스킬 · 펫 · 퀘스트 · 업적 · 랭킹 · 상점",
		"<b>음악</b>  M — 켜기/끄기",
		"",
		"<b>🎯 게임 흐름</b>",
		"1. 로비 허수아비로 골드를 벌어 무기를 강화하세요 (허수아비는 캐릭터 레벨로 열려요)",
		"2. 동쪽 <b>필드</b>에서 몬스터를 잡아 장비를 얻고 레벨을 올리세요 (황금 고블린을 놓치지 마세요!)",
		"3. 북쪽 <b>던전</b>은 열쇠가 필요해요. 웨이브마다 특성 카드를 고르고, 보스 상자에서 장비를 얻어요",
		"4. 성장 탭에서 훈련을 걸어두고, 장비 세트/유니크를 모아 전투력을 키우세요",
		"5. 최고 레벨이 되면 <b>환생</b>으로 영구 보너스를 받고 다시 도전할 수 있어요",
	}, "\n"),
}, helpPanel)

local function settingButton(y, labelFn, onClick)
	local button
	button = makeButton({
		Size = UDim2.new(1, -40, 0, 32), Position = UDim2.new(0, 20, 0, y), Text = labelFn(), TextSize = 14, BackgroundColor3 = Color3.fromRGB(55, 65, 100),
	}, helpPanel, function()
		onClick()
		button.Text = labelFn()
	end)
end
-- 슬라이더: 막대를 클릭하거나 드래그해서 0% ~ 200% 사이를 1% 단위로 조절한다
local function settingSlider(y, title, getValue, setValue)
	local maxValue = 2
	local caption = makeLabel({
		Size = UDim2.new(1, -40, 0, 18), Position = UDim2.new(0, 20, 0, y), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
	}, helpPanel)
	local bar = create("Frame", {
		Size = UDim2.new(1, -40, 0, 12), Position = UDim2.new(0, 20, 0, y + 22), BackgroundColor3 = Color3.fromRGB(55, 65, 100), BorderSizePixel = 0,
	}, helpPanel)
	rounded(bar, 6)
	local fill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(110, 170, 255), BorderSizePixel = 0 }, bar)
	rounded(fill, 6)
	local knob = create("Frame", {
		Size = UDim2.new(0, 18, 0, 18), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3,
	}, bar)
	rounded(knob, 9)

	local function refresh()
		local value = getValue()
		local ratio = math.clamp(value / maxValue, 0, 1)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		knob.Position = UDim2.new(ratio, 0, 0.5, 0)
		caption.Text = string.format("%s: %d%%", title, math.floor(value * 100 + 0.5))
	end
	local function setFromX(x)
		local ratio = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
		setValue(math.floor(ratio * maxValue * 100 + 0.5) / 100)
		refresh()
	end
	local dragging = false
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	refresh()
end

settingSlider(334, "🔊 배경음악 볼륨", function() return musicScale end, function(value)
	musicScale = value
	for name, sound in pairs(tracks) do
		if name == currentMusic then
			sound.Volume = musicVolume()
		end
	end
end)
settingSlider(380, "🔫 총소리 볼륨", function() return settings.ShotVolume end, function(value)
	settings.ShotVolume = value
end)
settingButton(428, function() return "📳 화면 흔들림: " .. (settings.Shake and "켜짐" or "꺼짐") end, function() settings.Shake = not settings.Shake end)
settingButton(468, function() return "📡 레이더: " .. (settings.Radar and "켜짐" or "꺼짐") end, function() settings.Radar = not settings.Radar end)
makeButton({
	Size = UDim2.new(0, 160, 0, 36), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Text = "닫기 (H)", BackgroundColor3 = GRAY,
}, helpPanel, function()
	helpPanel.Visible = false
end)

function toggleHelp()
	helpPanel.Visible = not helpPanel.Visible
end

-- 총소리 볼륨: 서버가 만든 "GunShot" 소리가 생길 때 내 설정 배율을 곱한다 (0이면 끔)
workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Sound") and instance.Name == "GunShot" then
		instance.Volume = instance.Volume * settings.ShotVolume
	end
end)

makeButton({
	Size = UDim2.new(0, 110, 0, 32), Position = UDim2.new(0, 16, 0, 282), Text = "⚙ 설정 (H)", TextSize = 14,
	BackgroundColor3 = Color3.fromRGB(60, 90, 100),
}, gui, toggleHelp)


end

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

-- 메뉴 키(I): Roblox 기본 카메라가 I / O 키를 "확대 / 축소"에 쓰고 있어서 입력이 먼저 가로채질 수 있다.
-- 더 높은 우선순위로 직접 등록해서 I 가 항상 메뉴를 열도록 한다.
do
	local ContextActionService = game:GetService("ContextActionService")
	ContextActionService:BindActionAtPriority("DungeonMenuToggle", function(_, state)
		if state == Enum.UserInputState.Begin then
			toggleMenu()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.I)
end

-- 건즈식 이동: 2단 점프 (공중에서 점프 키를 한 번 더 누르면 한 번 더 뛴다)
do
	local jd = { Used = 0, Last = 0 } -- (지역 변수 개수 제한 때문에 표 하나로 묶음)

	local function bindCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not humanoid or not root then return end
		jd.Used = 0
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.Climbing then
				jd.Used = 0
			end
		end)
	end
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)

	-- 공중 판정은 "발밑이 비었는가"(FloorMaterial)로 한다. (Humanoid 상태 이름은 점프 직후 / 오르막 등에서 어긋나기 쉬움)
	-- 스페이스 키 입력(InputBegan)과 JumpRequest(모바일 점프 버튼) 둘 다 받고, 0.2초 안의 중복은 무시한다.
	jd.Try = function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or humanoid.Health <= 0 then return end
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			jd.Used = 0
			return
		end
		local now = os.clock()
		if jd.Used >= 1 or now - jd.Last < 0.2 then return end
		jd.Used += 1
		jd.Last = now
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, 52, velocity.Z)
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		-- 공중에서 한 번 더 뛴 표시: 발밑에 퍼지는 고리
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.Material = Enum.Material.Neon
		ring.Color = Color3.fromRGB(150, 220, 255)
		ring.Transparency = 0.3
		ring.Size = Vector3.new(0.3, 3, 3)
		ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = workspace
		TweenService:Create(ring, TweenInfo.new(0.4), { Size = Vector3.new(0.3, 11, 11), Transparency = 1 }):Play()
		game:GetService("Debris"):AddItem(ring, 0.5)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.Space then
			jd.Try()
		end
	end)
	UserInputService.JumpRequest:Connect(jd.Try)
	RunService.Heartbeat:Connect(function() -- 땅에 닿아 있으면 점프 횟수 회복
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
			jd.Used = 0
		end
	end)
end
