-- DungeonDepthClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: DungeonDepthClient)
-- 던전 입장구 앞에서 뜨는 "깊이 고르기" 창 (설계: DUNGEON_DEPTH.md).
--   ◀ ▶ 로 깊이를 고르면 그 깊이의 보스 상자 확률(%)과 유니크 확률 / 열쇠 / 보상이 바로 보인다. 깊이는 "최고 깊이 + 1" 까지.
--   서버(DungeonService)가 Remotes.Dungeon "OpenDepth" 로 창을 열고, [입장]은 "StartDepth" 로 보낸다 (서버가 레벨 / 깊이 / 열쇠를 다시 검사한다).
--   확률 계산은 ReplicatedStorage.Odds (서버가 실제로 뽑을 때도 같은 모듈).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Odds = require(ReplicatedStorage:WaitForChild("Odds"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, rounded, makePanel, makeLabel, makeButton = Kit.create, Kit.rounded, Kit.makePanel, Kit.makeLabel, Kit.makeButton

local player = Players.LocalPlayer

local gui = create("ScreenGui", { Name = "DepthGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9 }, player:WaitForChild("PlayerGui"))
-- 게임 느낌의 입장 화면 (표처럼 보이던 것을 바꿨다):
--   왼쪽 큰 그림판(던전 이름 / 보스 / 소개 + 깊이 고르기) · 오른쪽 보상(상자 등급 막대) · 아래 정보 줄 + 큰 [입장] 버튼
local W, H = 780, 460
local panel = makePanel({
	Size = UDim2.new(0, W, 0, H), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(16, 16, 26), BackgroundTransparency = 0.02, Visible = false, ZIndex = 10, ClipsDescendants = true,
}, gui)
create("UIStroke", { Color = Color3.fromRGB(214, 170, 90), Thickness = 2, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
local fit = create("UIScale", {}, panel) -- (작은 화면: 창 전체를 화면에 맞게 줄인다)
local function refit()
	local size = gui.AbsoluteSize
	fit.Scale = math.min(1, (size.X - 24) / W, (size.Y - 24) / H)
end
refit()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)

local THEME = { -- 던전마다 그림판 색 / 상징
	Cave = { Top = Color3.fromRGB(70, 110, 50), Bottom = Color3.fromRGB(26, 22, 18), Icon = "👺", Accent = Color3.fromRGB(170, 230, 110) },
	Ice = { Top = Color3.fromRGB(60, 120, 190), Bottom = Color3.fromRGB(14, 22, 40), Icon = "❄", Accent = Color3.fromRGB(150, 220, 255) },
	Fire = { Top = Color3.fromRGB(190, 70, 30), Bottom = Color3.fromRGB(36, 14, 10), Icon = "🔥", Accent = Color3.fromRGB(255, 170, 90) },
	All = { Top = Color3.fromRGB(92, 50, 150), Bottom = Color3.fromRGB(18, 12, 30), Icon = "👺", Accent = Color3.fromRGB(255, 200, 110) },
}
local CYCLE = { "👺", "❄", "🔥" } -- 깊이 던전: 세 던전의 상징이 번갈아 나온다

-- ===== 왼쪽 그림판 =====
local hero = create("Frame", { Size = UDim2.new(0, 470, 0, 340), Position = UDim2.new(0, 14, 0, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 11, ClipsDescendants = true }, panel)
rounded(hero, 14)
local heroGrad = create("UIGradient", { Rotation = 90 }, hero)
local heroStroke = create("UIStroke", { Thickness = 1.5, Transparency = 0.4 }, hero)
-- 뒤쪽에서 퍼지는 빛줄기 (그림 대신 분위기)
local raysHolder = create("Frame", { Size = UDim2.new(0, 520, 0, 520), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.78, 0, 0.42, 0), BackgroundTransparency = 1, ZIndex = 11 }, hero)
local rays = {}
for k = 0, 11 do
	local ray = create("Frame", { Size = UDim2.new(0, 26, 0.5, 0), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, 0), Rotation = k * 30, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 11 }, raysHolder)
	create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) }) }, ray)
	rays[#rays + 1] = ray
end
local bossIcon = makeLabel({ Size = UDim2.new(0, 200, 0, 200), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.78, 0, 0.42, 0), Text = "", TextSize = 150, Font = Enum.Font.GothamBlack, TextTransparency = 0.05, ZIndex = 12 }, hero)
-- 아래쪽 어둡게 (글자가 잘 보이게)
local shade = create("Frame", { Size = UDim2.new(1, 0, 0.62, 0), Position = UDim2.new(0, 0, 0.38, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 12 }, hero)
create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) }) }, shade)

local typeName = makeLabel({ Size = UDim2.new(1, -28, 0, 46), Position = UDim2.new(0, 16, 0, 14), Text = "", TextSize = 38, Font = Enum.Font.FredokaOne, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 244, 220), ZIndex = 14 }, hero)
create("UIStroke", { Color = Color3.fromRGB(20, 14, 10), Thickness = 3 }, typeName)
local bossLine = makeLabel({ Size = UDim2.new(1, -28, 0, 22), Position = UDim2.new(0, 18, 0, 62), Text = "", TextSize = 15, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 14 }, hero)
create("UIStroke", { Color = Color3.fromRGB(20, 14, 10), Thickness = 1.5 }, bossLine)
local descLine = makeLabel({ Size = UDim2.new(0.62, -18, 0, 70), Position = UDim2.new(0, 18, 0, 92), Text = "", TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(232, 228, 240), ZIndex = 14 }, hero)
create("UIStroke", { Color = Color3.fromRGB(10, 10, 14), Thickness = 1, Transparency = 0.3 }, descLine)

-- 깊이 고르기 (그림판 아래쪽)
local depthBar = create("Frame", { Size = UDim2.new(1, -28, 0, 56), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), BackgroundColor3 = Color3.fromRGB(10, 10, 16), BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 14 }, hero)
rounded(depthBar, 12)
create("UIStroke", { Color = Color3.fromRGB(214, 170, 90), Thickness = 1, Transparency = 0.5 }, depthBar)
local depthLabel = makeLabel({ Size = UDim2.new(0, 170, 1, 0), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Text = "", Font = Enum.Font.FredokaOne, TextSize = 30, ZIndex = 15 }, depthBar)
create("UIStroke", { Color = Color3.fromRGB(20, 14, 10), Thickness = 2 }, depthLabel)
local info = makeLabel({ Size = UDim2.new(1, -28, 0, 16), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Text = "", TextSize = 11, TextColor3 = Color3.fromRGB(255, 225, 130), ZIndex = 14 }, hero)
local stepInfo = makeLabel({ Size = UDim2.new(1, -28, 0, 14), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Text = "", TextSize = 10, TextColor3 = Color3.fromRGB(190, 190, 210), ZIndex = 14 }, hero)

local typeKey, depth = nil, 1
local function bestOf(key) return player:GetAttribute("DepthBest_" .. tostring(key)) or 0 end

-- ===== 오른쪽 보상 =====
local side = create("Frame", { Size = UDim2.new(0, W - 470 - 42, 0, 340), Position = UDim2.new(0, 470 + 28, 0, 14), BackgroundColor3 = Color3.fromRGB(26, 24, 38), BorderSizePixel = 0, ZIndex = 11 }, panel)
rounded(side, 14)
create("UIStroke", { Color = Color3.fromRGB(90, 80, 130), Thickness = 1, Transparency = 0.4 }, side)
makeButton({ Size = UDim2.new(0, 64, 0, 26), Position = UDim2.new(1, -72, 0, 8), TextSize = 11, Text = "Close", BackgroundColor3 = Color3.fromRGB(54, 58, 82), ZIndex = 13 }, side, function()
	panel.Visible = false
end)
local title = makeLabel({ Size = UDim2.new(1, -90, 0, 26), Position = UDim2.new(0, 14, 0, 8), Text = "", Font = Enum.Font.GothamBlack, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }, side)
local chestHead = makeLabel({ Size = UDim2.new(1, -28, 0, 20), Position = UDim2.new(0, 14, 0, 42), Text = "", RichText = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }, side)
local rarityChips = {}
for index = 1, #Config.Gear.RarityNames do
	local y = 70 + (index - 1) * 34
	local nameLabel = makeLabel({ Size = UDim2.new(0, 70, 0, 18), Position = UDim2.new(0, 14, 0, y), Text = "", TextSize = 12, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }, side)
	local pctLabel = makeLabel({ Size = UDim2.new(0, 70, 0, 18), Position = UDim2.new(1, -84, 0, y), Text = "", TextSize = 12, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 12 }, side)
	local barBack = create("Frame", { Size = UDim2.new(1, -28, 0, 6), Position = UDim2.new(0, 14, 0, y + 21), BackgroundColor3 = Color3.fromRGB(44, 42, 60), BorderSizePixel = 0, ZIndex = 12 }, side)
	rounded(barBack, 3)
	local bar = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0, ZIndex = 13 }, barBack)
	rounded(bar, 3)
	rarityChips[index] = { Name = nameLabel, Pct = pctLabel, Bar = bar, Back = barBack }
end
local uniqueChip = makeLabel({ Size = UDim2.new(0.5, -18, 0, 28), Position = UDim2.new(0, 14, 1, -74), Text = "", TextSize = 11, Font = Enum.Font.GothamBold, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(52, 42, 30), TextColor3 = Color3.fromRGB(255, 200, 110), ZIndex = 12 }, side)
rounded(uniqueChip, 14)
local setChip = makeLabel({ Size = UDim2.new(0.5, -18, 0, 28), Position = UDim2.new(0.5, 4, 1, -74), Text = "", TextSize = 11, Font = Enum.Font.GothamBold, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(32, 48, 40), TextColor3 = Color3.fromRGB(150, 235, 170), ZIndex = 12 }, side)
rounded(setChip, 14)
makeButton({ Size = UDim2.new(1, -28, 0, 30), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Text = "📊 Odds", TextSize = 12, BackgroundColor3 = Color3.fromRGB(60, 72, 130), ZIndex = 13 }, side, function()
	player:SetAttribute("OddsKind", "Chest") -- OddsClient 가 확률 창을 연다
	player:SetAttribute("OddsOpen", os.clock())
end)

-- ===== 아래 정보 줄 + 버튼 =====
local function infoCell(index, caption)
	local x = 14 + (index - 1) * 108
	local value = makeLabel({ Size = UDim2.new(0, 110, 0, 24), Position = UDim2.new(0, x, 1, -88), Text = "", TextSize = 18, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }, panel)
	makeLabel({ Size = UDim2.new(0, 110, 0, 14), Position = UDim2.new(0, x, 1, -62), Text = caption, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(160, 160, 182), ZIndex = 12 }, panel)
	if index > 1 then
		create("Frame", { Size = UDim2.new(0, 1, 0, 34), Position = UDim2.new(0, x - 8, 1, -86), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.85, BorderSizePixel = 0, ZIndex = 12 }, panel)
	end
	return value
end
local tileKey = infoCell(1, "Entry key")
local tileTickets = infoCell(2, "Boss tickets")
local tileGold = infoCell(3, "Gold / XP")
local tileMonster = infoCell(4, "Monster HP / Damage")
tileMonster.TextSize = 15

local sweepButton = makeButton({ Size = UDim2.new(0, 146, 0, 50), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -176, 1, -16), Text = "⚡ Sweep", TextSize = 12, TextWrapped = true, BackgroundColor3 = Color3.fromRGB(150, 110, 40), ZIndex = 12 }, panel, function()
	if not typeKey then return end
	panel.Visible = false
	Remotes.Dungeon:FireServer("Sweep")
end)
local enterButton = makeButton({ Size = UDim2.new(0, 150, 0, 50), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Text = "Enter", TextSize = 20, Font = Enum.Font.GothamBlack, BackgroundColor3 = Color3.fromRGB(206, 150, 50), ZIndex = 12 }, panel, function()
	if not typeKey then return end
	panel.Visible = false
	Remotes.Dungeon:FireServer("StartDepth", typeKey, depth)
end)
create("UIStroke", { Color = Color3.fromRGB(255, 226, 150), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, enterButton)

local function refresh()
	if not typeKey then return end
	local frontier = bestOf(typeKey) + 1
	depth = math.clamp(depth, 1, Config.Dungeon.Depth.MaxDepth) -- 아무 깊이나 고를 수 있다
	local key = Config.Dungeon.DepthKey(depth)
	local difficulty = Config.Dungeon.GetDifficulty(key)
	local typeInfo = Config.Dungeon.Types[typeKey]
	local theme = THEME[typeKey] or THEME.All
	heroGrad.Color = ColorSequence.new(theme.Top, theme.Bottom)
	heroStroke.Color = theme.Accent
	for _, ray in ipairs(rays) do ray.BackgroundColor3 = theme.Accent end
	if typeInfo then
		bossIcon.Text = theme.Icon
		typeName.Text = typeInfo.Name
		bossLine.Text = string.format("👑 Boss: %s", typeInfo.Boss.Name)
		descLine.Text = typeInfo.Desc or ""
	else -- 깊이 던전: 매번 던전 / 보스가 무작위 (고블린 동굴 / 얼음 성채 / 화염 신전)
		typeName.Text = "The Depths"
		local names = {}
		for _, key in ipairs(Config.Dungeon.Types.Order) do
			local t = Config.Dungeon.Types[key]
			if t and t.Boss then table.insert(names, t.Boss.Name) end
		end
		bossLine.Text = string.format("👑 Boss: %s", table.concat(names, " / "))
		descLine.Text = "A random dungeon awaits each run: Goblin Cave, Ice Fortress or Flame Temple. Go deeper for stronger monsters and better chests!"
	end
	bossLine.TextColor3 = theme.Accent
	title.Text = "🎁 Rewards"
	depthLabel.Text = "Depth " .. depth
	depthLabel.TextColor3 = difficulty.Color
	info.Text = string.format("Cleared up to depth %d  ·  next: %d", bestOf(typeKey), frontier)

	local G = Config.Dungeon.Depth
	stepInfo.Text = string.format("Each depth up: monster HP +%d%% · damage +%d%% · gold +%d%% · better chest odds", math.floor((G.HealthGrowth - 1) * 100 + 0.5), math.floor((G.DamageGrowth - 1) * 100 + 0.5), math.floor((G.GoldGrowth - 1) * 100 + 0.5))
	tileKey.Text = string.format("🔑 %d", difficulty.KeyCost)
	tileKey.TextColor3 = Color3.fromRGB(255, 224, 138)
	tileTickets.Text = string.format("🎫 %d", difficulty.Tickets)
	tileTickets.TextColor3 = Color3.fromRGB(220, 170, 255)
	tileGold.Text = string.format("💰 x%.1f", difficulty.GoldMult)
	tileGold.TextColor3 = Color3.fromRGB(255, 220, 110)
	tileMonster.Text = string.format("👹 x%.1f / x%.1f", difficulty.HealthMult, difficulty.DamageMult)
	tileMonster.TextColor3 = Color3.fromRGB(255, 140, 130)

	chestHead.Text = string.format("<b>🎁 Boss chest · %d gear pieces</b>", Config.Loot.DungeonChestCount)
	local entries = Odds.Chest(typeKey, key, Odds.LuckOf(player))
	local top = 0
	for _, e in ipairs(entries) do top = math.max(top, e.Pct or 0) end
	for index, chip in ipairs(rarityChips) do
		local e = entries[index]
		chip.Name.Visible, chip.Pct.Visible, chip.Back.Visible = e ~= nil, e ~= nil, e ~= nil
		if e then
			chip.Name.Text, chip.Name.TextColor3 = e.Name, e.Color
			chip.Pct.Text, chip.Pct.TextColor3 = Odds.Format(e.Pct), Color3.new(1, 1, 1)
			chip.Bar.BackgroundColor3 = e.Color
			chip.Bar.Size = UDim2.new(top > 0 and math.clamp((e.Pct or 0) / top, 0, 1) or 0, 0, 1, 0)
		end
	end
	do -- 소탕 버튼: 깬 최고 깊이 기준 (열쇠 / 받을 골드)
		local best = bestOf(typeKey)
		local gold = player:GetAttribute("SweepDepth") == best and player:GetAttribute("SweepGold") or 0
		if best >= 1 and gold and gold > 0 then
			sweepButton.Text = string.format("⚡ Sweep D%d  🔑%d", best, Config.Dungeon.DepthKeyCost(best))
			sweepButton.BackgroundColor3 = Color3.fromRGB(150, 110, 40)
		else
			sweepButton.Text = best >= 1 and "⚡ Sweep (clear once more)" or "⚡ Sweep (locked)"
			sweepButton.BackgroundColor3 = Color3.fromRGB(70, 66, 80)
		end
	end
	uniqueChip.Text = string.format("✦ Unique %.1f%%", Odds.ChestUnique(key))
	local chance, zones = Odds.ChestSet(key, player:GetAttribute("ClearedZone") or 0)
	setChip.Text = #zones == 0 and "🧩 Set: clear a zone lord" or string.format("🧩 Set %.0f%%", chance)
end

local function stepper(text, delta, x)
	makeButton({ Size = UDim2.new(0, 40, 0, 38), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0.5, 0), Text = text, TextSize = 15, BackgroundColor3 = Color3.fromRGB(70, 60, 40), ZIndex = 15 }, depthBar, function()
		depth += delta
		refresh()
	end)
end
stepper("«", -10, -170)
stepper("◀", -1, -122)
stepper("▶", 1, 122)
stepper("»", 10, 170)

task.spawn(function() -- 빛줄기가 천천히 돈다
	local t = 0
	while true do
		if panel.Visible then
			t += 0.05
			raysHolder.Rotation = t * 6
			bossIcon.Position = UDim2.new(0.78, 0, 0.42, math.sin(t * 1.5) * 4)
			if not Config.Dungeon.Types[typeKey or ""] then bossIcon.Text = CYCLE[math.floor(t / 1.6) % #CYCLE + 1] end
		end
		task.wait(0.05)
	end
end)

Remotes.Dungeon.OnClientEvent:Connect(function(action, data)
	if action ~= "OpenDepth" or typeof(data) ~= "table" or typeof(data.Type) ~= "string" then return end
	typeKey = data.Type
	depth = bestOf(typeKey) + 1 -- 기본은 최전선
	refresh()
	panel.Visible = true
end)

player:GetAttributeChangedSignal("DepthBest_All"):Connect(function()
	if panel.Visible then refresh() end
end)
player:GetAttributeChangedSignal("SweepGold"):Connect(function()
	if panel.Visible then refresh() end
end)
player:GetAttributeChangedSignal("Zone"):Connect(function()
	if player:GetAttribute("Zone") ~= "Lobby" then panel.Visible = false end
end)
