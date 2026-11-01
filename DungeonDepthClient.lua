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
local panel = makePanel({
	Size = UDim2.new(0, 480, 0, 392), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(22, 24, 38), BackgroundTransparency = 0.02, Visible = false, ZIndex = 10,
}, gui)
create("UIStroke", { Color = Color3.fromRGB(150, 130, 230), Thickness = 2, Transparency = 0.25, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)

local title = makeLabel({ Size = UDim2.new(1, -110, 0, 36), Position = UDim2.new(0, 18, 0, 10), Text = "", Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, panel)
makeButton({ Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -84, 0, 12), TextSize = 12, Text = "Close", BackgroundColor3 = Color3.fromRGB(54, 58, 82), ZIndex = 11 }, panel, function()
	panel.Visible = false
end)

local typeKey, depth = nil, 1

local function bestOf(key) return player:GetAttribute("DepthBest_" .. tostring(key)) or 0 end

local depthLabel = makeLabel({ Size = UDim2.new(0, 180, 0, 44), Position = UDim2.new(0.5, -90, 0, 54), Text = "", Font = Enum.Font.GothamBlack, TextSize = 26, ZIndex = 11 }, panel)
local info = makeLabel({ Size = UDim2.new(1, -36, 0, 18), Position = UDim2.new(0, 18, 0, 102), Text = "", TextSize = 12, TextColor3 = Color3.fromRGB(255, 225, 130), ZIndex = 11 }, panel)

-- 글줄 대신 작은 카드로: 입장 열쇠 / 보스 티켓 / 골드·경험치 / 몬스터 강함
local function tile(index, caption)
	local width = (480 - 36 - 3 * 8) / 4
	local box = create("Frame", { Size = UDim2.new(0, width, 0, 62), Position = UDim2.new(0, 18 + (index - 1) * (width + 8), 0, 130), BackgroundColor3 = Color3.fromRGB(32, 34, 54), BorderSizePixel = 0, ZIndex = 11 }, panel)
	rounded(box, 10)
	local value = makeLabel({ Size = UDim2.new(1, -6, 0, 30), Position = UDim2.new(0, 3, 0, 6), Text = "", TextSize = 17, Font = Enum.Font.GothamBlack, ZIndex = 12 }, box)
	makeLabel({ Size = UDim2.new(1, -6, 0, 16), Position = UDim2.new(0, 3, 0, 38), Text = caption, TextSize = 10, TextColor3 = Color3.fromRGB(170, 176, 205), ZIndex = 12 }, box)
	return value
end
local tileKey = tile(1, "Entry key")
local tileTickets = tile(2, "Boss tickets")
local tileGold = tile(3, "Gold / XP")
local tileMonster = tile(4, "Monster HP / Damage")
tileMonster.TextSize = 13

local chestHead = makeLabel({ Size = UDim2.new(1, -36, 0, 20), Position = UDim2.new(0, 18, 0, 206), Text = "", RichText = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, panel)
local rarityChips = {}
for index = 1, #Config.Gear.RarityNames do
	local width = (480 - 36 - 4 * 6) / 5
	local box = create("Frame", { Size = UDim2.new(0, width, 0, 48), Position = UDim2.new(0, 18 + (index - 1) * (width + 6), 0, 232), BackgroundColor3 = Color3.fromRGB(32, 34, 54), BorderSizePixel = 0, ZIndex = 11 }, panel)
	rounded(box, 10)
	local stroke = create("UIStroke", { Thickness = 1.5, Transparency = 0.3 }, box)
	local nameLabel = makeLabel({ Size = UDim2.new(1, -4, 0, 18), Position = UDim2.new(0, 2, 0, 5), Text = "", TextSize = 11, Font = Enum.Font.GothamBold, ZIndex = 12 }, box)
	local pctLabel = makeLabel({ Size = UDim2.new(1, -4, 0, 20), Position = UDim2.new(0, 2, 0, 23), Text = "", TextSize = 13, Font = Enum.Font.GothamBlack, ZIndex = 12 }, box)
	rarityChips[index] = { Stroke = stroke, Name = nameLabel, Pct = pctLabel }
end
local uniqueChip = makeLabel({ Size = UDim2.new(0.5, -24, 0, 30), Position = UDim2.new(0, 18, 0, 290), Text = "", TextSize = 12, Font = Enum.Font.GothamBold, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(52, 42, 30), TextColor3 = Color3.fromRGB(255, 200, 110), ZIndex = 11 }, panel)
rounded(uniqueChip, 10)
local setChip = makeLabel({ Size = UDim2.new(0.5, -24, 0, 30), Position = UDim2.new(0.5, 6, 0, 290), Text = "", TextSize = 12, Font = Enum.Font.GothamBold, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(32, 48, 40), TextColor3 = Color3.fromRGB(150, 235, 170), ZIndex = 11 }, panel)
rounded(setChip, 10)

local function refresh()
	if not typeKey then return end
	local frontier = bestOf(typeKey) + 1
	depth = math.clamp(depth, 1, Config.Dungeon.Depth.MaxDepth) -- 아무 깊이나 고를 수 있다 (예전엔 최고 깊이 + 1 까지)
	local key = Config.Dungeon.DepthKey(depth)
	local difficulty = Config.Dungeon.GetDifficulty(key)
	title.Text = "🏰 Dungeon"
	depthLabel.Text = "Depth " .. depth
	depthLabel.TextColor3 = difficulty.Color
	info.Text = string.format("Cleared up to depth %d  ·  next: %d", bestOf(typeKey), frontier)

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
	for index, chip in ipairs(rarityChips) do
		local e = entries[index]
		chip.Name.Visible, chip.Pct.Visible = e ~= nil, e ~= nil
		if e then
			chip.Name.Text, chip.Name.TextColor3 = e.Name, e.Color
			chip.Pct.Text, chip.Pct.TextColor3 = Odds.Format(e.Pct), Color3.new(1, 1, 1)
			chip.Stroke.Color = e.Color
		end
	end
	uniqueChip.Text = string.format("✦ Unique %.1f%%", Odds.ChestUnique(key))
	local chance, zones = Odds.ChestSet(key, player:GetAttribute("ClearedZone") or 0)
	setChip.Text = #zones == 0 and "🧩 Set: clear a zone lord" or string.format("🧩 Set %.0f%%", chance)
end

local function stepper(text, delta, x)
	makeButton({ Size = UDim2.new(0, 46, 0, 40), Position = UDim2.new(0.5, x, 0, 56), Text = text, TextSize = 16, BackgroundColor3 = Color3.fromRGB(60, 72, 130), ZIndex = 11 }, panel, function()
		depth += delta
		refresh()
	end)
end
stepper("«", -10, -160)
stepper("◀", -1, -106)
stepper("▶", 1, 60)
stepper("»", 10, 114)

makeButton({ Size = UDim2.new(0, 210, 0, 44), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -16), Text = "Enter", TextSize = 17, BackgroundColor3 = Color3.fromRGB(58, 160, 90), ZIndex = 11 }, panel, function()
	if not typeKey then return end
	panel.Visible = false
	Remotes.Dungeon:FireServer("StartDepth", typeKey, depth)
end)
makeButton({ Size = UDim2.new(0, 210, 0, 44), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -16), Text = "📊 Full odds table", TextSize = 14, BackgroundColor3 = Color3.fromRGB(60, 72, 130), ZIndex = 11 }, panel, function()
	player:SetAttribute("OddsKind", "Chest") -- OddsClient 가 확률 창을 연다
	player:SetAttribute("OddsOpen", os.clock())
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
player:GetAttributeChangedSignal("Zone"):Connect(function()
	if player:GetAttribute("Zone") ~= "Lobby" then panel.Visible = false end
end)
