-- OddsClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: OddsClient)
-- 유료 랜덤 아이템 정책: 구매 전에 모든 결과의 확률(%)을 보여 준다. "Odds" 버튼(상점 카드 / 장비 뽑기 / 던전 선택)이 이 창을 연다.
--   열기: player:SetAttribute("OddsKind", "Gacha" | "Chest" | "Luck") 후 player:SetAttribute("OddsOpen", os.clock())
-- 확률 계산은 ReplicatedStorage.Odds (서버가 실제로 뽑을 때도 같은 모듈을 쓴다). 행운 효과가 켜져 있으면 숫자가 같이 바뀐다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Odds = require(ReplicatedStorage:WaitForChild("Odds"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, rounded, makePanel, makeLabel, makeButton = Kit.create, Kit.rounded, Kit.makePanel, Kit.makeLabel, Kit.makeButton

local player = Players.LocalPlayer

local gui = create("ScreenGui", { Name = "OddsGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 80 }, player:WaitForChild("PlayerGui"))
local uiScale = create("UIScale", {}, gui)
local function fit()
	local viewport = workspace.CurrentCamera.ViewportSize
	uiScale.Scale = math.clamp(math.min(viewport.X / 900, viewport.Y / 640), 0.6, 1)
end
fit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

local panel = makePanel({
	Size = UDim2.new(0, 640, 0, 520), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(22, 24, 38), BackgroundTransparency = 0.02, Visible = false, ZIndex = 10,
}, gui)
create("UIStroke", { Color = Color3.fromRGB(120, 140, 230), Thickness = 2, Transparency = 0.25, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
local title = makeLabel({ Size = UDim2.new(1, -110, 0, 40), Position = UDim2.new(0, 18, 0, 10), Text = "Drop Odds", Font = Enum.Font.GothamBlack, TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, panel)
makeButton({ Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -84, 0, 12), TextSize = 12, Text = "Close", BackgroundColor3 = Color3.fromRGB(54, 58, 82), ZIndex = 11 }, panel, function()
	panel.Visible = false
end)
local scroll = create("ScrollingFrame", {
	Size = UDim2.new(1, -28, 1, -64), Position = UDim2.new(0, 14, 0, 54), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 6, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 11,
}, panel)
local body = makeLabel({
	Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, RichText = true, TextSize = 14, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 12, Text = "",
}, scroll)

local function hex(color) return color:ToHex() end

local function rarityLine(entries)
	local parts = {}
	for _, e in ipairs(entries) do
		table.insert(parts, string.format("<font color='#%s'><b>%s</b></font> %s", hex(e.Color), e.Name, Odds.Format(e.Pct)))
	end
	return table.concat(parts, "   ·   ")
end

local function total(entries)
	local sum = 0
	for _, e in ipairs(entries) do sum += e.Pct end
	return Odds.Format(sum)
end

local function luckText(luck)
	return string.format("%+.0f%%", luck * 100)
end

local function gachaText()
	local g = Odds.Gacha()
	local slots = {}
	for _, s in ipairs(g.Slots) do table.insert(slots, string.format("%s %s", s.Name, Odds.Format(s.Pct))) end
	return table.concat({
		"<b>🎰 Gear Gacha — each ticket gives 1 gear piece</b>",
		"",
		"<b>Rarity</b> (total " .. total(g.Rarities) .. ")",
		rarityLine(g.Rarities),
		"",
		"<b>Gear slot</b> (total 100.00%)",
		table.concat(slots, "   ·   "),
		"",
		string.format("<b>Mythic gear</b> has a %s chance to carry a Unique effect (one of %d).", Odds.Format(g.UniqueChance), #Config.Uniques.Order),
		"",
		"Bonus stats on every piece roll randomly within a range that depends on its rarity (shown on the item).",
		"Every result is useful: gear you can't improve on is converted into Gold and Essence.",
		"Your Luck stat and Luck Booster do <b>not</b> change gacha odds.",
	}, "\n")
end

local function chestText()
	local luck = Odds.LuckOf(player)
	local lines = {
		"<b>🏰 Dungeon boss chest — " .. Config.Loot.DungeonChestCount .. " gear pieces per chest</b>",
		string.format("Your Luck right now: <b>%s</b>  (gear %s%s)", luckText(luck), luckText(player:GetAttribute("GearLuck") or 0),
			(player:GetAttribute("LuckBoostUntil") or 0) > os.time() and (" + Luck Booster " .. luckText(Config.Shop.LuckBoostBonus)) or ""),
		"Luck and the boss bonus multiply the weights of Epic and above; the percentages below already include them.",
		"",
	}
	local depths = { 1, 5, 9, 13, 17, 21, 30 }
	local best = player:GetAttribute("DepthBest_All") or 0
	table.insert(lines, string.format("<b>Dungeon depth</b>  (your record: depth %d · the dungeon theme is random, odds are the same)", best))
	for _, depth in ipairs({ 1, 5, 9, 13, 17, 21, 30 }) do
		local entries = Odds.Chest("Cave", Config.Dungeon.DepthKey(depth), luck)
		table.insert(lines, string.format("Depth %d (total %s, Unique %s, keys %d): %s", depth, total(entries),
			Odds.Format(Odds.ChestUnique(Config.Dungeon.DepthKey(depth))), Config.Dungeon.DepthKeyCost(depth), rarityLine(entries)))
	end
	table.insert(lines, "")
	table.insert(lines, "<b>Zone set gear</b> (each chest piece can be a field-zone set piece; only zones whose lord you have defeated can appear, the deepest 3 that fit the depth)")
	for _, depth in ipairs({ 1, 5, 9, 13, 17, 21, 30 }) do
		local chance, zones = Odds.ChestSet(Config.Dungeon.DepthKey(depth), player:GetAttribute("ClearedZone") or 0)
		table.insert(lines, string.format("Depth %d: %s%s", depth, Odds.Format(chance), #zones > 0 and (" (zones " .. zones[1] .. "–" .. zones[#zones] .. ")") or " (no zone cleared yet)"))
	end
	table.insert(lines, "")
	table.insert(lines, "Odds rise smoothly with every depth; the depth window shows the exact odds of the depth you pick.")
	table.insert(lines, "Gear slot is uniformly random (each slot equal chance). Every result is useful: gear you can't improve on is converted into Gold and Essence.")
	return table.concat(lines, "\n")
end

local function luckBoosterText()
	local base = Odds.LuckOf(player, false)
	local boosted = Odds.LuckOf(player, true)
	local active = (player:GetAttribute("LuckBoostUntil") or 0) > os.time()
	local lines = {
		"<b>🍀 Luck Booster — effect on gear drop odds</b>",
		string.format("Your Luck without the booster: <b>%s</b> · with the booster: <b>%s</b>%s", luckText(base), luckText(boosted), active and "   <font color='#78ff8c'>(active now)</font>" or ""),
		"Luck multiplies the weights of Epic, Legendary and Mythic drops (not Common / Rare). Elite monsters add x" .. Config.Loot.EliteBonus .. ", bosses x" .. Config.Loot.BossBonus .. ".",
		"Odds below are for a regular monster drop, per zone. These tables already update with your current Luck.",
		"",
		"<b>Without the booster</b>",
	}
	for zone = 1, #Config.Loot.ZoneRarity do
		table.insert(lines, string.format("Zone %d: %s", zone, rarityLine(Odds.Field(zone, "Normal", base))))
	end
	table.insert(lines, "")
	table.insert(lines, "<b>With the booster</b>")
	for zone = 1, #Config.Loot.ZoneRarity do
		table.insert(lines, string.format("Zone %d: %s", zone, rarityLine(Odds.Field(zone, "Normal", boosted))))
	end
	table.insert(lines, "")
	table.insert(lines, "The booster does not change gacha odds. Every drop is useful: gear you can't improve on is converted into Gold and Essence.")
	return table.concat(lines, "\n")
end

local TITLES = { Gacha = "Gear Gacha Odds", Chest = "Dungeon Chest Odds", Luck = "Luck Booster Odds" }

local function open()
	local kind = player:GetAttribute("OddsKind") or "Gacha"
	title.Text = "📊 " .. (TITLES[kind] or "Drop Odds")
	body.Text = kind == "Chest" and chestText() or (kind == "Luck" and luckBoosterText() or gachaText())
	scroll.CanvasPosition = Vector2.new(0, 0)
	panel.Visible = true
end

player:GetAttributeChangedSignal("OddsOpen"):Connect(open)
