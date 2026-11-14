-- CodexClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: CodexClient)
-- 📖 도감: 오른쪽 가운데 버튼 / J 키로 연다. 첫 탭 = 구역 안내(몬스터 / 군주 / 드롭 확률 / 세트), 그다음 몬스터(처음 잡기 전엔 ???) / 세트 / 무기 / 유니크 / 장비
-- 서버 기록은 MetaService (Remotes.Meta "Codex") 에서 받는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local Odds = require(ReplicatedStorage:WaitForChild("Odds"))
local create, rounded, makeLabel, makeButton = Kit.create, Kit.rounded, Kit.makeLabel, Kit.makeButton

local gui = create("ScreenGui", { Name = "CodexGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6 }, playerGui)

local openButton = makeButton({
	Name = "CodexButton", Size = UDim2.new(0, 52, 0, 52), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
	Text = "📖\nCodex", TextSize = 10, BackgroundColor3 = Color3.fromRGB(46, 52, 92),
}, gui, function() end)
rounded(openButton, 10)

local panel = create("Frame", {
	Name = "CodexPanel", Size = UDim2.new(0, 500, 0, 520), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(18, 20, 34), BorderSizePixel = 0, Visible = false,
}, gui)
rounded(panel, 14)
-- 작은 화면(폰 가로 높이 약 360~414)에서도 창이 잘리지 않게 화면에 맞춰 줄인다 (PC 는 1.0 그대로)
local panelScale = create("UIScale", {}, panel)
local function fitPanel()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	panelScale.Scale = math.clamp(math.min(viewport.X / 540, viewport.Y / 560), 0.55, math.max(1, game:GetService("Players").LocalPlayer:GetAttribute("UiMul") or 1))
end
fitPanel()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel) end
game:GetService("Players").LocalPlayer:GetAttributeChangedSignal("UiMul"):Connect(fitPanel)
create("UIStroke", { Color = Color3.fromRGB(130, 150, 230), Thickness = 2, Transparency = 0.25, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
makeLabel({ Size = UDim2.new(1, -100, 0, 34), Position = UDim2.new(0, 16, 0, 8), Text = "📖 Codex", TextSize = 20, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left }, panel)
makeButton({ Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -84, 0, 12), Text = "Close (J)", TextSize = 12, BackgroundColor3 = Color3.fromRGB(54, 58, 82) }, panel, function() panel.Visible = false end)

local summary = makeLabel({ Size = UDim2.new(1, -32, 0, 18), Position = UDim2.new(0, 16, 0, 42), TextSize = 11, TextColor3 = Color3.fromRGB(180, 188, 220), TextXAlignment = Enum.TextXAlignment.Left }, panel)
local list = create("ScrollingFrame", {
	Size = UDim2.new(1, -24, 1, -112), Position = UDim2.new(0, 12, 0, 100), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 5, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel)
create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, list)

local data = { Kills = {}, Boss = {}, Sets = {}, Items = {} }
local tab = "Guide"
local tabButtons = {}
local order = 0
local function nextOrder() order += 1 return order end

local function row(height, color)
	local f = create("Frame", { Size = UDim2.new(1, -8, 0, height), BackgroundColor3 = color or Color3.fromRGB(30, 34, 54), BorderSizePixel = 0, LayoutOrder = nextOrder() }, list)
	rounded(f, 8)
	return f
end

local function hex(c)
	return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function rebuild()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	order = 0
	for key, button in pairs(tabButtons) do
		button.BackgroundColor3 = key == tab and Color3.fromRGB(62, 96, 196) or Color3.fromRGB(40, 44, 68)
	end
	local F = Config.Field
	if tab == "Guide" then
		-- 구역 안내 (표가 아니라 카드): 구역 색 띠 머리 / 몬스터 메달 줄 / 드롭 등급 막대(색 비율) / 세트 문장과 세트 효과 메달 / 관문 알약
		local luck = Odds.LuckOf(player)
		local myZone = player:GetAttribute("MaxZone") or 1
		local L = Config.Loot
		local function pill(parent, x, y, text, color)
			local f = create("Frame", { Size = UDim2.new(0, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(0, x, 0, y), BackgroundColor3 = color, BackgroundTransparency = 0.55, BorderSizePixel = 0 }, parent)
			rounded(f, 10)
			create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, f)
			makeLabel({ Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = text, TextSize = 10, Font = Enum.Font.GothamBold }, f)
			return f
		end
		local function rarityBar(parent, x, y, w, zone, kind, title)
			makeLabel({ Size = UDim2.new(0, 56, 0, 14), Position = UDim2.new(0, x, 0, y - 1), Text = title, TextSize = 10, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 205, 230) }, parent)
			local back = create("Frame", { Size = UDim2.new(0, w, 0, 12), Position = UDim2.new(0, x + 58, 0, y), BackgroundColor3 = Color3.fromRGB(14, 16, 26), BorderSizePixel = 0, ClipsDescendants = true }, parent)
			rounded(back, 6)
			local cursor, best = 0, nil
			for _, entry in ipairs(Odds.Field(zone, kind, luck)) do
				if entry.Pct > 0 then
					local seg = create("Frame", { Size = UDim2.new(entry.Pct / 100, 0, 1, 0), Position = UDim2.new(cursor / 100, 0, 0, 0), BackgroundColor3 = entry.Color, BorderSizePixel = 0 }, back)
					create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 185)) }, seg)
					cursor += entry.Pct
					best = entry
				end
			end
			if best then -- 막대 끝: 가장 높은 등급과 그 확률 (나머지는 색 비율로 본다)
				makeLabel({ Size = UDim2.new(0, 120, 0, 14), Position = UDim2.new(0, x + 64 + w, 0, y - 1), RichText = true, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
					Text = string.format("<font color='#%s'><b>%s</b></font> %s", hex(best.Color), best.Name, Odds.Format(best.Pct)) }, parent)
			end
		end
		for z = 1, F.ZoneCount do
			local locked = z > myZone
			local setKey = Config.Sets.ZoneKeys and Config.Sets.ZoneKeys[z]
			local setDef = setKey and Config.Sets[setKey]
			local tint = setDef and setDef.Color or Color3.fromRGB(120, 140, 220)
			local card = row(224, Color3.fromRGB(22, 24, 40))
			card:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 14)
			create("UIStroke", { Color = tint, Thickness = 1.5, Transparency = locked and 0.7 or 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
			-- 머리 띠: 구역 색 그라데이션 + 큰 이름 + 권장 전투력 알약
			local band = create("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = tint, BorderSizePixel = 0 }, card)
			rounded(band, 14)
			create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, locked and 0.6 or 0.15), NumberSequenceKeypoint.new(1, 0.95) }) }, band)
			makeLabel({ Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.new(0, 12, 0, 0), RichText = true, TextSize = 15, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left,
				TextStrokeTransparency = 0.4, Text = string.format("%s ZONE %d  <font size='12'>%s</font>", setDef and setDef.Icon or "📍", z, F.ZoneNames[z]) }, band)
			makeLabel({ Size = UDim2.new(0, 150, 1, 0), Position = UDim2.new(1, -160, 0, 0), RichText = true, TextSize = 11, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right,
				Text = locked and "<font color='#b8bcd4'>🔒 not reached yet</font>" or string.format("<font color='#ffe16e'>⚡ Recommended %s</font>  <font color='#ff8a8a'>%s</font>", tostring(F.RecommendPower[z] or 0), string.rep("☠", math.min(z, 5))) }, band)
			-- 몬스터 메달 줄 + 군주(왕관)
			local keys = {}
			for key in pairs(F.ZonePools[z] or {}) do table.insert(keys, key) end
			table.sort(keys)
			local x = 10
			for _, key in ipairs(keys) do
				local info = Config.Codex.Monsters[key]
				if info and x < 380 then
					Kit.medal(card, { Size = 38, Position = UDim2.new(0, x + 6, 0, 42), Color = tint, Icon = info.Icon, TextSize = 18, Muted = locked })
					makeLabel({ Size = UDim2.new(0, 52, 0, 22), Position = UDim2.new(0, x, 0, 82), Text = info.Name, TextSize = 9, TextWrapped = true, TextColor3 = Color3.fromRGB(200, 205, 228) }, card)
					x += 54
				end
			end
			Kit.medal(card, { Size = 44, Position = UDim2.new(1, -62, 0, 39), Color = Color3.fromRGB(255, 196, 80), Icon = "👑", TextSize = 20, Tier = 4, Muted = locked })
			makeLabel({ Size = UDim2.new(0, 74, 0, 22), Position = UDim2.new(1, -77, 0, 84), Text = Config.Codex.Bosses[z] or "Lord", TextSize = 9, TextWrapped = true, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 220, 140) }, card)
			-- 드롭: 확률 알약 + 등급 막대 (색 비율)
			pill(card, 10, 112, string.format("🎁 monster %d%% · elite %d%% · Lord %d%%", math.floor(L.DropChance.Normal * 100 + 0.5), math.floor(L.DropChance.Elite * 100 + 0.5), math.floor(L.DropChance.Boss * 100 + 0.5)), Color3.fromRGB(70, 80, 130))
			local need = F.Gate and F.Gate.KillsNeeded and F.Gate.KillsNeeded[z]
			if need then pill(card, 300, 112, string.format("🚪 %d kills → Lord", need), Color3.fromRGB(90, 70, 50)) end
			rarityBar(card, 10, 140, 230, z, "Normal", "Monster")
			rarityBar(card, 10, 158, 230, z, "Boss", "Lord")
			-- 세트 문장 + 세트 효과 메달
			if setDef then
				Kit.medal(card, { Size = 30, Position = UDim2.new(0, 10, 0, 178), Color = setDef.Color, Icon = setDef.Icon or "★", TextSize = 14, Muted = locked })
				local parts = {}
				for _, bonus in ipairs(setDef.Bonuses[3] or {}) do table.insert(parts, Config.FormatBonus(bonus.Stat, bonus.Value)) end
				makeLabel({ Size = UDim2.new(0, 190, 0, 30), Position = UDim2.new(0, 46, 0, 178), RichText = true, TextSize = 9, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
					Text = string.format("<font color='#%s' size='11'><b>%s Set</b></font>\n<font color='#c8cce0'>%s</font>", hex(setDef.Color), setDef.Name, table.concat(parts, " · ")) }, card)
				local aug = setDef.Aug and Config.AugInfo[setDef.Aug]
				if aug then
					Kit.medal(card, { Size = 30, Position = UDim2.new(0, 244, 0, 178), Color = aug.Color, Icon = aug.Icon, TextSize = 14, Tier = 3, Muted = locked })
					makeLabel({ Size = UDim2.new(1, -290, 0, 30), Position = UDim2.new(0, 280, 0, 178), RichText = true, TextSize = 9, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
						Text = string.format("<font color='#%s' size='11'><b>%s</b></font>\n<font color='#c8cce0'>%s</font>", hex(aug.Color), aug.Name, aug.Desc) }, card)
				end
			end
		end
		local AB = Config.Inventory.AugBoostChance or {}
		summary.Text = "Odds include your current Luck" -- (길면 잘려서: 나머지는 맨 아래 쪽지로)
		local note = row(40, Color3.fromRGB(30, 28, 46))
		makeLabel({ Size = UDim2.new(1, -20, 1, 0), Position = UDim2.new(0, 10, 0, 0), RichText = true, TextSize = 10, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 204, 228),
			Text = string.format("★ Mythic: unique %d%% (dungeon chests 30%%+) · +1 set-effect option: Legendary %d%% / Mythic %d%%",
				math.floor((Config.Uniques.FieldChance or 0) * 100 + 0.5), math.floor((AB[4] or 0) * 100 + 0.5), math.floor((AB[5] or 0) * 100 + 0.5)) }, note)
	elseif tab == "Monster" then
		local total, found = 0, 0
		local seen = {}
		for zone = 1, F.ZoneCount do
			local head = row(26, Color3.fromRGB(44, 50, 84))
			makeLabel({ Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = string.format("Zone %d · %s", zone, F.ZoneNames[zone]), TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, head)
			local keys = {}
			for key in pairs(F.ZonePools[zone] or {}) do table.insert(keys, key) end
			table.sort(keys)
			for _, key in ipairs(keys) do
				local info = Config.Codex.Monsters[key]
				if info then
					local kills = data.Kills[key] or 0
					if not seen[key] then seen[key] = true total += 1 if kills > 0 then found += 1 end end
					local r = row(46)
					makeLabel({ Size = UDim2.new(0, 40, 1, 0), Position = UDim2.new(0, 4, 0, 0), Text = kills > 0 and info.Icon or "❔", TextSize = 20 }, r)
					makeLabel({ Size = UDim2.new(1, -150, 0, 20), Position = UDim2.new(0, 48, 0, 3), Text = kills > 0 and info.Name or "???", TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, r)
					makeLabel({ Size = UDim2.new(1, -150, 0, 20), Position = UDim2.new(0, 48, 0, 23), Text = kills > 0 and info.Desc or "Not met yet", TextSize = 10, TextColor3 = Color3.fromRGB(170, 176, 200), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, r)
					makeLabel({ Size = UDim2.new(0, 90, 1, 0), Position = UDim2.new(1, -96, 0, 0), Text = kills > 0 and ("Kills " .. kills) or "", TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 225, 120), TextXAlignment = Enum.TextXAlignment.Right }, r)
				end
			end
			local bossKills = data.Boss[tostring(zone)] or 0
			total += 1
			if bossKills > 0 then found += 1 end
			local r = row(50, Color3.fromRGB(52, 36, 44))
			makeLabel({ Size = UDim2.new(0, 40, 1, 0), Position = UDim2.new(0, 4, 0, 0), Text = bossKills > 0 and "👑" or "❔", TextSize = 20 }, r)
			makeLabel({ Size = UDim2.new(1, -150, 0, 22), Position = UDim2.new(0, 48, 0, 5), Text = bossKills > 0 and string.format("%s (Lord of %s)", Config.Codex.Bosses[zone] or "Lord", F.ZoneNames[zone]) or "??? (Lord of this zone)", TextSize = 12, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 170, 160), TextXAlignment = Enum.TextXAlignment.Left }, r)
			makeLabel({ Size = UDim2.new(1, -150, 0, 18), Position = UDim2.new(0, 48, 0, 27), Text = bossKills > 0 and "The boss waiting at the end of the zone. Aim for the weak-point orb" or "Defeat it to open the next zone", TextSize = 10, TextColor3 = Color3.fromRGB(190, 170, 175), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, r)
			makeLabel({ Size = UDim2.new(0, 90, 1, 0), Position = UDim2.new(1, -96, 0, 0), Text = bossKills > 0 and ("Kills " .. bossKills) or "", TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 225, 120), TextXAlignment = Enum.TextXAlignment.Right }, r)
		end
		summary.Text = string.format("Monsters met %d / %d (incl. zone lords)", found, total)
	elseif tab == "Set" then
		local found = 0
		for zone = 1, F.ZoneCount do
			local key = Config.Sets.ZoneKeys[zone]
			local setDef = key and Config.Sets[key]
			if setDef then
				local got = data.Sets[key] or 0
				if got > 0 then found += 1 end
				local augInfo = setDef.Aug and Config.AugInfo[setDef.Aug]
				local r = row(124, Color3.fromRGB(28, 32, 52))
				create("UIStroke", { Color = setDef.Color, Thickness = got > 0 and 2 or 1, Transparency = got > 0 and 0 or 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, r)
				makeLabel({ Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(0, 4, 0, 4), Text = setDef.Icon, TextSize = 24 }, r)
				makeLabel({ Size = UDim2.new(1, -150, 0, 22), Position = UDim2.new(0, 48, 0, 5), Text = string.format("%s  <font size='10' color='#aab0c8'>Zone %d %s</font>", setDef.Name, zone, F.ZoneNames[zone]), RichText = true, TextSize = 13, Font = Enum.Font.GothamBlack, TextColor3 = setDef.Color, TextXAlignment = Enum.TextXAlignment.Left }, r)
				makeLabel({ Size = UDim2.new(0, 96, 0, 22), Position = UDim2.new(1, -102, 0, 5), Text = got > 0 and ("Got " .. got) or "Not obtained", TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = got > 0 and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(150, 150, 170), TextXAlignment = Enum.TextXAlignment.Right }, r)
				local lines = {}
				for _, tier in ipairs({ 2, 3 }) do
					local parts = {}
					for _, b in ipairs(setDef.Bonuses[tier]) do table.insert(parts, Config.FormatBonus(b.Stat, b.Value)) end
					table.insert(lines, string.format("<b>%d pc</b> %s", tier, table.concat(parts, ", ")))
				end
				if augInfo then
					table.insert(lines, string.format("<font color='#%s'><b>%s %s</b></font>  %s", hex(augInfo.Color), augInfo.Icon, augInfo.Name, augInfo.Desc))
				end
				makeLabel({ Size = UDim2.new(1, -20, 0, 82), Position = UDim2.new(0, 10, 0, 40), Text = table.concat(lines, "\n"), RichText = true, TextSize = 10, TextColor3 = Color3.fromRGB(205, 210, 232), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, r)
			end
		end
		summary.Text = string.format("Sets obtained %d / %d  ·  Monsters / lord of that zone drop them at a set rate", found, F.ZoneCount)
	elseif tab == "Weapon" then
		-- 무기 도감: 100종 (10개 시대 x 10종류). 지금 무기 단계까지 온 무기만 이름이 공개된다 (새 저장 데이터 없이 WeaponLevel 로 계산)
		local reached = Config.GetWeaponTier(player:GetAttribute("WeaponLevel") or 0).Index
		local perEra = #Config.WeaponTypes.Order
		local eras = math.ceil(#Config.Weapon.Tiers / perEra)
		for era = 1, eras do
			local firstIndex = (era - 1) * perEra + 1
			local head = row(26, Color3.fromRGB(44, 50, 84))
			local foundInEra = math.max(0, math.min(perEra, reached - firstIndex + 1))
			makeLabel({ Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = string.format("%s  ·  %d / %d", Config.GetEraName(era), foundInEra, perEra), TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, head)
			local r = row(86)
			local left, right = {}, {}
			for k = 1, perEra do
				local tier = Config.Weapon.Tiers[firstIndex + k - 1]
				if tier then
					local text = firstIndex + k - 1 <= reached and string.format("<font color='#%s'>%s</font>", hex(tier.Color or Color3.new(1, 1, 1)), tier.Name) or "<font color='#6b7088'>???</font>"
					table.insert(k <= perEra / 2 and left or right, text)
				end
			end
			makeLabel({ Size = UDim2.new(0.5, -14, 1, -10), Position = UDim2.new(0, 10, 0, 5), Text = table.concat(left, "\n"), RichText = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, r)
			makeLabel({ Size = UDim2.new(0.5, -14, 1, -10), Position = UDim2.new(0.5, 4, 0, 5), Text = table.concat(right, "\n"), RichText = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, r)
		end
		summary.Text = string.format("Weapons reached %d / %d  ·  Enhance your weapon to meet the next one", reached, #Config.Weapon.Tiers)
	elseif tab == "Unique" then
		local found = 0
		do -- 어디서 얻나: 유니크는 신화 장비에만 붙고, 주로 던전 쪽 보상에서 나온 신화에 붙는다
			local U = Config.Uniques
			local r = row(118, Color3.fromRGB(58, 44, 30))
			create("UIStroke", { Color = Color3.fromRGB(255, 184, 77), Thickness = 1.5, Transparency = 0.3 }, r)
			makeLabel({ Size = UDim2.new(1, -20, 1, -10), Position = UDim2.new(0, 10, 0, 5), RichText = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
				Text = table.concat({
					"<font size='13' color='#ffb84d'><b>📍 Where to get Unique effects</b></font>  <font color='#c8cce0'>(only on Mythic gear)</font>",
					string.format("🏰 <b>Dungeon boss chests</b>  <font color='#ffd966'>%d%% → up to %d%% (deeper = higher)</font>", math.floor(U.Chance * 100 + 0.5), math.floor(U.MaxChance * 100 + 0.5)),
					"👹 <b>Boss Rush rewards</b> · 👑 <b>Final Lord reward</b>  <font color='#78ff8c'>guaranteed</font>",
					string.format("🌲 <b>Field Mythic drops</b> <font color='#c8cce0'>(Zone 5+)</font>  <font color='#ffd966'>%d%%</font>", math.floor((U.FieldChance or 0.08) * 100 + 0.5)),
					"<font color='#8a90aa'>🎰 Gear gacha Mythics never carry a Unique</font>",
				}, "\n") }, r)
		end
		for _, key in ipairs(Config.Uniques.Order) do
			local info = Config.Uniques[key]
			local got = data.Items["U_" .. key] or 0
			if got > 0 then found += 1 end
			local r = row(54, Color3.fromRGB(46, 38, 64))
			makeLabel({ Size = UDim2.new(0, 40, 1, 0), Position = UDim2.new(0, 4, 0, 0), Text = got > 0 and "✨" or "❔", TextSize = 20 }, r)
			makeLabel({ Size = UDim2.new(1, -150, 0, 22), Position = UDim2.new(0, 48, 0, 6), Text = got > 0 and info.Name or "???", TextSize = 13, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 140), TextXAlignment = Enum.TextXAlignment.Left }, r)
			makeLabel({ Size = UDim2.new(1, -150, 0, 20), Position = UDim2.new(0, 48, 0, 28), Text = got > 0 and info.Desc or "Mythic gear · dungeon chests / Boss Rush / Final Lord", TextSize = 10, TextColor3 = Color3.fromRGB(190, 196, 225), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, r)
			makeLabel({ Size = UDim2.new(0, 90, 1, 0), Position = UDim2.new(1, -96, 0, 0), Text = got > 0 and ("Got " .. got) or "Not obtained", TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = got > 0 and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(150, 150, 170), TextXAlignment = Enum.TextXAlignment.Right }, r)
		end
		summary.Text = string.format("Unique effects found %d / %d  ·  Mythic gear can carry one", found, #Config.Uniques.Order)
	else
		-- 장비 도감: 부위마다 5개 등급 이름. 얻어 본 등급만 공개된다
		local total, found = 0, 0
		for _, slot in ipairs(Config.Gear.Slots) do
			local r = row(64)
			local parts = {}
			for rarity, name in ipairs(slot.Names) do
				total += 1
				local got = (data.Items[slot.Key .. rarity] or 0) > 0
				if got then found += 1 end
				local color = Config.Gear.RarityColors[rarity] or Color3.new(1, 1, 1)
				table.insert(parts, got and string.format("<font color='#%s'>%s</font>", hex(color), name) or "<font color='#6b7088'>???</font>")
			end
			makeLabel({ Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 0, 4), Text = string.format("%s · %s", slot.Name, slot.StatName), TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, r)
			makeLabel({ Size = UDim2.new(1, -20, 0, 36), Position = UDim2.new(0, 10, 0, 24), Text = table.concat(parts, "  ·  "), RichText = true, TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, r)
		end
		summary.Text = string.format("Gear found %d / %d  ·  Higher-rarity gear you have held shows its name", found, total)
	end
end

for index, def in ipairs({ { "Guide", "🗺 Guide" }, { "Monster", "👾 Monsters" }, { "Set", "🛡 Sets" }, { "Weapon", "🔫 Weapons" }, { "Unique", "✨ Uniques" }, { "Gear", "🎽 Gear" } }) do
	local button = makeButton({ -- (탭 6개: 폭을 줄였다)
		Size = UDim2.new(0, 74, 0, 30), Position = UDim2.new(0, 14 + (index - 1) * 79, 0, 64), Text = def[2], TextSize = 10,
	}, panel, function() tab = def[1] rebuild() end)
	rounded(button, 8)
	tabButtons[def[1]] = button
end

local function toggle(open)
	if open == nil then open = not panel.Visible end
	panel.Visible = open
	if open then
		Remotes.Meta:FireServer("Codex")
		rebuild()
	end
end
openButton.Activated:Connect(function() toggle() end)

Remotes.Meta.OnClientEvent:Connect(function(action, payload)
	if action == "Codex" and typeof(payload) == "table" then
		data = { Kills = payload.Kills or {}, Boss = payload.Boss or {}, Sets = payload.Sets or {}, Items = payload.Items or {} }
		if panel.Visible then rebuild() end
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.J then toggle() end
end)
player:GetAttributeChangedSignal("OpenCodex"):Connect(function() toggle() end) -- 왼쪽 메뉴 버튼(MenuDockClient)

-- 튜토리얼 / 던전 / 심연 등 전투 화면에서는 버튼만 숨긴다 (J 키는 그대로)
local function refreshButton()
	-- 오른쪽 가운데 떠 있던 도감 버튼은 숨긴다: 왼쪽 메뉴 버튼 줄(MenuDockClient)에 도감 버튼이 있고, DPS 미터와 겹쳤다. (J 키는 그대로)
	openButton.Visible = false
end
player:GetAttributeChangedSignal("ClearedZone"):Connect(refreshButton)
player:GetAttributeChangedSignal("TutorialActive"):Connect(refreshButton)
player:GetAttributeChangedSignal("Zone"):Connect(refreshButton)
player:GetAttributeChangedSignal("InDoomArena"):Connect(refreshButton)
refreshButton()
rebuild()
