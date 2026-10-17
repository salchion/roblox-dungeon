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
	Size = UDim2.new(0, 480, 0, 420), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(22, 24, 38), BackgroundTransparency = 0.02, Visible = false, ZIndex = 10,
}, gui)
create("UIStroke", { Color = Color3.fromRGB(150, 130, 230), Thickness = 2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)

local title = makeLabel({ Size = UDim2.new(1, -110, 0, 36), Position = UDim2.new(0, 18, 0, 10), Text = "", Font = Enum.Font.GothamBlack, TextSize = 21, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, panel)
makeButton({ Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -86, 0, 13), Text = "Close", BackgroundColor3 = Color3.fromRGB(54, 58, 82), ZIndex = 11 }, panel, function()
	panel.Visible = false
end)
makeLabel({ Size = UDim2.new(1, -36, 0, 20), Position = UDim2.new(0, 18, 0, 46), Text = "Deeper depths have better drop odds and tougher monsters. The dungeon theme is random.", TextSize = 12, TextColor3 = Color3.fromRGB(180, 188, 220), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, panel)

local typeKey, depth = nil, 1

local function bestOf(key) return player:GetAttribute("DepthBest_" .. tostring(key)) or 0 end

local depthLabel = makeLabel({ Size = UDim2.new(0, 180, 0, 44), Position = UDim2.new(0.5, -90, 0, 74), Text = "", Font = Enum.Font.GothamBlack, TextSize = 26, ZIndex = 11 }, panel)
local info = makeLabel({ Size = UDim2.new(1, -36, 0, 18), Position = UDim2.new(0, 18, 0, 120), Text = "", TextSize = 12, TextColor3 = Color3.fromRGB(255, 225, 130), ZIndex = 11 }, panel)
local body = makeLabel({
	Size = UDim2.new(1, -36, 0, 190), Position = UDim2.new(0, 18, 0, 142), RichText = true, TextSize = 13, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 11, Text = "",
}, panel)

local function hex(color) return color:ToHex() end

local function refresh()
	if not typeKey then return end
	local frontier = bestOf(typeKey) + 1
	depth = math.clamp(depth, 1, frontier)
	local key = Config.Dungeon.DepthKey(depth)
	local difficulty = Config.Dungeon.GetDifficulty(key)
	title.Text = "🏰 Dungeon"
	depthLabel.Text = "Depth " .. depth
	depthLabel.TextColor3 = difficulty.Color
	info.Text = string.format("Cleared up to depth %d  ·  You can enter up to depth %d", bestOf(typeKey), frontier)

	local entries = Odds.Chest(typeKey, key, Odds.LuckOf(player))
	local parts = {}
	for _, e in ipairs(entries) do
		table.insert(parts, string.format("<font color='#%s'><b>%s</b></font> %s", hex(e.Color), e.Name, Odds.Format(e.Pct)))
	end
	local lines = {
		string.format("<b>🎁 Boss chest · %d gear pieces</b>", Config.Loot.DungeonChestCount),
		table.concat(parts, "  ·  "),
		string.format("✦ Unique effect on Mythic gear: <b>%.1f%%</b>", Odds.ChestUnique(key)),
		"",
		string.format("🔑 Entry: <b>%d key</b> (or 1 of your daily free entries)", difficulty.KeyCost),
		string.format("🎫 Tickets for the boss: <b>%d</b>  ·  Gold / XP x%.1f", difficulty.Tickets, difficulty.GoldMult),
		string.format("👹 Monster health x%.1f  ·  damage x%.1f", difficulty.HealthMult, difficulty.DamageMult),
	}
	body.Text = table.concat(lines, "\n")
end

local function stepper(text, delta, x)
	makeButton({ Size = UDim2.new(0, 46, 0, 40), Position = UDim2.new(0.5, x, 0, 76), Text = text, TextSize = 16, BackgroundColor3 = Color3.fromRGB(60, 72, 130), ZIndex = 11 }, panel, function()
		depth += delta
		refresh()
	end)
end
stepper("«", -5, -160)
stepper("◀", -1, -106)
stepper("▶", 1, 60)
stepper("»", 5, 114)

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
