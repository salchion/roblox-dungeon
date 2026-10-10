-- CodexClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: CodexClient)
-- 📖 도감: 오른쪽 가운데 버튼 / J 키로 연다. 탭 둘: 몬스터(구역별, 처음 잡기 전엔 ???) / 세트 장비(효과를 미리 볼 수 있다)
-- 서버 기록은 MetaService (Remotes.Meta "Codex") 에서 받는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, rounded, makeLabel, makeButton = Kit.create, Kit.rounded, Kit.makeLabel, Kit.makeButton

local gui = create("ScreenGui", { Name = "CodexGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6 }, playerGui)

local openButton = makeButton({
	Name = "CodexButton", Size = UDim2.new(0, 52, 0, 52), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
	Text = "📖\n도감", TextSize = 12, BackgroundColor3 = Color3.fromRGB(46, 52, 92),
}, gui, function() end)
rounded(openButton, 10)

local panel = create("Frame", {
	Name = "CodexPanel", Size = UDim2.new(0, 500, 0, 520), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(18, 20, 34), BorderSizePixel = 0, Visible = false,
}, gui)
rounded(panel, 14)
create("UIStroke", { Color = Color3.fromRGB(130, 150, 230), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
makeLabel({ Size = UDim2.new(1, -100, 0, 34), Position = UDim2.new(0, 16, 0, 8), Text = "📖 도감", TextSize = 22, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left }, panel)
makeButton({ Size = UDim2.new(0, 70, 0, 30), Position = UDim2.new(1, -82, 0, 10), Text = "닫기 (J)", TextSize = 13, BackgroundColor3 = Color3.fromRGB(54, 58, 82) }, panel, function() panel.Visible = false end)

local summary = makeLabel({ Size = UDim2.new(1, -32, 0, 18), Position = UDim2.new(0, 16, 0, 42), TextSize = 13, TextColor3 = Color3.fromRGB(180, 188, 220), TextXAlignment = Enum.TextXAlignment.Left }, panel)
local list = create("ScrollingFrame", {
	Size = UDim2.new(1, -24, 1, -112), Position = UDim2.new(0, 12, 0, 100), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 5, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, panel)
create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, list)

local data = { Kills = {}, Boss = {}, Sets = {} }
local tab = "Monster"
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
	if tab == "Monster" then
		local total, found = 0, 0
		local seen = {}
		for zone = 1, F.ZoneCount do
			local head = row(26, Color3.fromRGB(44, 50, 84))
			makeLabel({ Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = string.format("%d구역 · %s", zone, F.ZoneNames[zone]), TextSize = 14, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, head)
			local keys = {}
			for key in pairs(F.ZonePools[zone] or {}) do table.insert(keys, key) end
			table.sort(keys)
			for _, key in ipairs(keys) do
				local info = Config.Codex.Monsters[key]
				if info then
					local kills = data.Kills[key] or 0
					if not seen[key] then seen[key] = true total += 1 if kills > 0 then found += 1 end end
					local r = row(46)
					makeLabel({ Size = UDim2.new(0, 40, 1, 0), Position = UDim2.new(0, 4, 0, 0), Text = kills > 0 and info.Icon or "❔", TextSize = 24 }, r)
					makeLabel({ Size = UDim2.new(1, -150, 0, 20), Position = UDim2.new(0, 48, 0, 3), Text = kills > 0 and info.Name or "???", TextSize = 14, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, r)
					makeLabel({ Size = UDim2.new(1, -150, 0, 20), Position = UDim2.new(0, 48, 0, 23), Text = kills > 0 and info.Desc or "아직 만나지 못했어요", TextSize = 12, TextColor3 = Color3.fromRGB(170, 176, 200), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, r)
					makeLabel({ Size = UDim2.new(0, 90, 1, 0), Position = UDim2.new(1, -96, 0, 0), Text = kills > 0 and ("처치 " .. kills) or "", TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 225, 120), TextXAlignment = Enum.TextXAlignment.Right }, r)
				end
			end
			local bossKills = data.Boss[tostring(zone)] or 0
			total += 1
			if bossKills > 0 then found += 1 end
			local r = row(50, Color3.fromRGB(52, 36, 44))
			makeLabel({ Size = UDim2.new(0, 40, 1, 0), Position = UDim2.new(0, 4, 0, 0), Text = bossKills > 0 and "👑" or "❔", TextSize = 24 }, r)
			makeLabel({ Size = UDim2.new(1, -150, 0, 22), Position = UDim2.new(0, 48, 0, 5), Text = bossKills > 0 and string.format("%s (%s의 군주)", Config.Codex.Bosses[zone] or "군주", F.ZoneNames[zone]) or "??? (이 구역의 군주)", TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 170, 160), TextXAlignment = Enum.TextXAlignment.Left }, r)
			makeLabel({ Size = UDim2.new(1, -150, 0, 18), Position = UDim2.new(0, 48, 0, 27), Text = bossKills > 0 and "구역 끝에서 기다리는 보스. 약점 구슬을 노려요" or "쓰러뜨려야 다음 구역이 열려요", TextSize = 12, TextColor3 = Color3.fromRGB(190, 170, 175), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, r)
			makeLabel({ Size = UDim2.new(0, 90, 1, 0), Position = UDim2.new(1, -96, 0, 0), Text = bossKills > 0 and ("처치 " .. bossKills) or "", TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 225, 120), TextXAlignment = Enum.TextXAlignment.Right }, r)
		end
		summary.Text = string.format("만난 몬스터 %d / %d 종 (구역 군주 포함)", found, total)
	else
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
				makeLabel({ Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(0, 4, 0, 4), Text = setDef.Icon, TextSize = 28 }, r)
				makeLabel({ Size = UDim2.new(1, -150, 0, 22), Position = UDim2.new(0, 48, 0, 5), Text = string.format("%s  <font size='12' color='#aab0c8'>%d구역 %s</font>", setDef.Name, zone, F.ZoneNames[zone]), RichText = true, TextSize = 15, Font = Enum.Font.GothamBlack, TextColor3 = setDef.Color, TextXAlignment = Enum.TextXAlignment.Left }, r)
				makeLabel({ Size = UDim2.new(0, 96, 0, 22), Position = UDim2.new(1, -102, 0, 5), Text = got > 0 and ("획득 " .. got .. "개") or "미획득", TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = got > 0 and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(150, 150, 170), TextXAlignment = Enum.TextXAlignment.Right }, r)
				local lines = {}
				for _, tier in ipairs({ 2, 3 }) do
					local parts = {}
					for _, b in ipairs(setDef.Bonuses[tier]) do table.insert(parts, Config.FormatBonus(b.Stat, b.Value)) end
					table.insert(lines, string.format("<b>%d부위</b> %s", tier, table.concat(parts, ", ")))
				end
				if augInfo then
					table.insert(lines, string.format("<font color='#%s'><b>%s %s</b></font>  %s", hex(augInfo.Color), augInfo.Icon, augInfo.Name, augInfo.Desc))
				end
				makeLabel({ Size = UDim2.new(1, -20, 0, 82), Position = UDim2.new(0, 10, 0, 40), Text = table.concat(lines, "\n"), RichText = true, TextSize = 12, TextColor3 = Color3.fromRGB(205, 210, 232), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, r)
			end
		end
		summary.Text = string.format("얻어 본 세트 %d / %d  ·  그 구역 몬스터 / 군주가 떨구거나, 세트 조각으로 각인해요", found, F.ZoneCount)
	end
end

for index, def in ipairs({ { "Monster", "👾 몬스터" }, { "Set", "🛡 세트 장비" } }) do
	local button = makeButton({
		Size = UDim2.new(0, 140, 0, 30), Position = UDim2.new(0, 16 + (index - 1) * 148, 0, 64), Text = def[2], TextSize = 14,
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
		data = { Kills = payload.Kills or {}, Boss = payload.Boss or {}, Sets = payload.Sets or {} }
		if panel.Visible then rebuild() end
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.J then toggle() end
end)

-- 튜토리얼 / 던전 / 심연 등 전투 화면에서는 버튼만 숨긴다 (J 키는 그대로)
local function refreshButton()
	local zone = player:GetAttribute("Zone")
	openButton.Visible = zone == "Lobby" or zone == "Field"
	if player:GetAttribute("InDoomArena") then openButton.Visible = false end
end
player:GetAttributeChangedSignal("Zone"):Connect(refreshButton)
player:GetAttributeChangedSignal("InDoomArena"):Connect(refreshButton)
refreshButton()
rebuild()
