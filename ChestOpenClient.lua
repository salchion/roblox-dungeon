-- ChestOpenClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: ChestOpenClient)
-- 던전 보스를 쓰러뜨린 뒤 "상자를 여는" 연출: 상자가 흔들리다 터지고, 장비가 한 장씩 등급 색으로 펼쳐진다.
--   서버가 보내는 결과(Remotes.Dungeon "Result")의 Loot 목록을 그대로 보여 주기만 한다 (뽑기 / 확률은 서버가 이미 정했다).
--   연출 중에는 Attribute "ChestOpening" 이 켜져 있어서 결과 카드가 전리품 목록을 잠깐 가린다. 화면을 누르면 건너뛴다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, rounded, makeLabel, makeButton = Kit.create, Kit.rounded, Kit.makeLabel, Kit.makeButton

local player = Players.LocalPlayer

local gui = create("ScreenGui", { Name = "ChestGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20, Enabled = false }, player:WaitForChild("PlayerGui"))
local dim = create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.04, Text = "", AutoButtonColor = false, ZIndex = 30 }, gui) -- (카드가 나오는 동안은 아래 결과 창이 비치지 않게 거의 검게)
local stage = create("Frame", { Size = UDim2.new(0, 560, 0, 320), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1, ZIndex = 31 }, gui)
local scale = create("UIScale", {}, stage)
local hint = makeLabel({ Size = UDim2.new(1, 0, 0, 20), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Text = "", Visible = false, TextSize = 12, TextColor3 = Color3.fromRGB(190, 195, 220), ZIndex = 32 }, stage)

local function fit()
	local size = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(size.X / 640, size.Y / 380), 0.5, 1.2)
end
fit()

local token = 0
local summaryShown = false -- 카드 아래 골드 / 버튼이 떠 있는 동안은 화면을 눌러도 닫히지 않는다 (버튼으로 닫는다)
local function close()
	token += 1
	summaryShown = false
	gui.Enabled = false
	dim.Visible = true
	stage.Position = UDim2.new(0.5, 0, 0.5, 0)
	player:SetAttribute("ChestOpening", nil)
	for _, child in ipairs(stage:GetChildren()) do
		if child:IsA("GuiObject") and child ~= hint then child:Destroy() end
	end
end
-- (카드가 다 나온 뒤 버튼으로만 닫는다: 중간에 닫으면 골드 / 로비로 버튼을 놓친다)
dim.MouseButton1Click:Connect(function() end)

local function tween(object, time, props, style, direction)
	local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- 터질 때 사방으로 퍼지는 반짝이
local function sparks(color, count)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.3
		local distance = math.random(120, 230)
		local dot = create("Frame", {
			Size = UDim2.new(0, 10, 0, 10), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -10),
			BackgroundColor3 = color, BorderSizePixel = 0, Rotation = math.random(0, 90), ZIndex = 33,
		}, stage)
		rounded(dot, 3)
		tween(dot, 0.7, {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.5, math.sin(angle) * distance * 0.7 - 10),
			BackgroundTransparency = 1, Size = UDim2.new(0, 3, 0, 3),
		})
		task.delay(0.8, function() dot:Destroy() end)
	end
end

local function commaText(n)
	return (tostring(math.floor(n or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function play(loot, data)
	local sweep = data.Sweep == true
	token += 1
	local mine = token
	close()
	token = mine
	gui.Enabled = true
	player:SetAttribute("ChestOpening", true)
	fit()
	local function alive() return token == mine and gui.Enabled end

	local best = 1
	for _, entry in ipairs(loot) do best = math.max(best, entry.Rarity or 1) end
	local bestColor = Config.Gear.RarityColors[best] or Color3.fromRGB(255, 225, 120)

	-- 1) 상자가 흔들린다 (점점 세게)
	local chest = makeLabel({ Size = UDim2.new(0, 160, 0, 140), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -10), Text = "🎁", TextSize = 110, ZIndex = 33 }, stage)
	local glow = create("UIStroke", { Color = bestColor, Thickness = 0, Transparency = 0.2 }, chest)
	for i = 1, 6 do
		if not alive() then return end
		local amount = 6 + i * 3
		tween(chest, 0.08, { Rotation = (i % 2 == 0 and -amount or amount), Size = UDim2.new(0, 160 + i * 6, 0, 140 + i * 5) })
		task.wait(0.11)
	end
	if not alive() then return end

	-- 2) 터진다: 번쩍임 + 반짝이
	local flash = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.2, ZIndex = 34 }, gui)
	tween(flash, 0.35, { BackgroundTransparency = 1 })
	task.delay(0.4, function() flash:Destroy() end)
	tween(chest, 0.25, { Size = UDim2.new(0, 300, 0, 260), TextTransparency = 1, Rotation = 0 })
	sparks(bestColor, 18)
	pcall(SoundBank.Play, SoundService, "Dungeon_Clear")
	task.wait(0.35)
	chest:Destroy()

	-- 번 골드 / 티켓: 카드 아래에 같이 떠 있는다 (결과 창을 따로 또 보지 않게)
	local chipRow = {}
	for index, spec in ipairs({
		{ Text = "💰 +" .. commaText(data.Gold) .. " G", Color = Color3.fromRGB(255, 220, 110), X = -112 },
		{ Text = "🎫 +" .. commaText(data.Tickets), Color = Color3.fromRGB(220, 170, 255), X = 112 },
	}) do
		local chip = makeLabel({ Size = UDim2.new(0, 200, 0, 38), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, spec.X, 0.5, 132), Text = spec.Text, TextSize = 21, Font = Enum.Font.GothamBlack,
			TextColor3 = spec.Color, BackgroundTransparency = 1, BackgroundColor3 = Color3.fromRGB(30, 28, 48), TextTransparency = 1, ZIndex = 33 }, stage)
		rounded(chip, 12)
		create("UIStroke", { Color = spec.Color, Thickness = 1.5, Transparency = 0.35 }, chip)
		tween(chip, 0.4, { BackgroundTransparency = 0, TextTransparency = 0 })
		chipRow[index] = chip
	end
	-- 2) 장비가 한 장씩 펼쳐진다: 부위 그림 + 이름 + 상태 배지가 있는 카드 (높은 등급일수록 크고 오래 머문다)
	local ICONS = { Armor = "🛡", Gloves = "🧤", Boots = "👢", Helmet = "⛑", Ring = "💍", Necklace = "📿", Weapon = "🔫" }
	local count = math.max(1, #loot)
	local cardWidth = math.clamp(math.floor(520 / count) - 12, 120, 170)
	local cardHeight = 210
	for index, entry in ipairs(loot) do
		if not alive() then return end
		local rarity = entry.Rarity or 1
		local color = Config.Gear.RarityColors[rarity] or Color3.new(1, 1, 1)
		local x = (index - (count + 1) / 2) * (cardWidth + 12)
		local slotDef = entry.Slot and Config.GetGearSlot(entry.Slot)
		local card = create("Frame", {
			Size = UDim2.new(0, cardWidth, 0, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0.5, -10),
			BackgroundColor3 = Color3.fromRGB(22, 22, 36), BorderSizePixel = 0, ZIndex = 33, ClipsDescendants = true,
		}, stage)
		rounded(card, 14)
		create("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(Color3.fromRGB(22, 22, 36), 0.45), Color3.fromRGB(22, 22, 36)) }, card)
		local stroke = create("UIStroke", { Color = color, Thickness = rarity >= 4 and 4 or 2.5, Transparency = 0 }, card)
		if rarity >= 5 then -- 신화: 테두리 무지개
			local rainbow = create("UIGradient", { Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 80)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 120)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 200, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
			}) }, stroke)
			TweenService:Create(rainbow, TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
		end
		-- 등급 띠
		local pill = makeLabel({ Size = UDim2.new(0, 84, 0, 20), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Text = Config.Gear.RarityNames[rarity] or "", Font = Enum.Font.GothamBlack, TextSize = 12,
			TextColor3 = Color3.fromRGB(20, 20, 30), BackgroundTransparency = 0, BackgroundColor3 = color, ZIndex = 35 }, card)
		rounded(pill, 10)
		-- 부위 그림 (등급 색 원 안)
		local disc = create("Frame", { Size = UDim2.new(0, 70, 0, 70), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 38), BackgroundColor3 = color:Lerp(Color3.fromRGB(18, 18, 30), 0.65), BorderSizePixel = 0, ZIndex = 34 }, card)
		rounded(disc, 35)
		create("UIStroke", { Color = color, Thickness = 2, Transparency = 0.2 }, disc)
		local iconLabel = makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = ICONS[entry.Slot] or "🎁", TextSize = 38, ZIndex = 35 }, disc)
		-- 이름 (등급 이름과 아이템 이름을 따로 두어 번역이 각각 된다)
		local setDef = entry.Set and Config.Sets[entry.Set]
		local itemName = slotDef and slotDef.Names[rarity] or ""
		makeLabel({ Size = UDim2.new(1, -12, 0, 34), Position = UDim2.new(0, 6, 0, 114), Text = itemName, TextSize = 13, Font = Enum.Font.GothamBold, TextWrapped = true, TextColor3 = Color3.fromRGB(240, 242, 252), ZIndex = 35 }, card)
		local tag = ""
		local tagColor = Color3.fromRGB(190, 195, 220)
		if entry.Unique and Config.Uniques[entry.Unique] then
			tag, tagColor = "✦ " .. Config.Uniques[entry.Unique].Name, Color3.fromRGB(255, 190, 90)
		elseif setDef then
			tag, tagColor = (setDef.Icon or "✦") .. " " .. setDef.Name, setDef.Color
		end
		makeLabel({ Size = UDim2.new(1, -8, 0, 16), Position = UDim2.new(0, 4, 0, 150), Text = tag, TextSize = 10, Font = Enum.Font.GothamBold, TextColor3 = tagColor, ZIndex = 35 }, card)
		-- 상태 배지: 장착 / 가방 / 분해
		local badgeText, badgeColor
		if entry.Status == "Equipped" then
			badgeText, badgeColor = "⚔ Equipped", Color3.fromRGB(46, 150, 96)
		elseif entry.Status == "Bag" then
			badgeText, badgeColor = "🎒 In bag", Color3.fromRGB(60, 110, 200)
		else
			badgeText, badgeColor = string.format("♻ Essence +%d", entry.Essence or 0), Color3.fromRGB(88, 90, 112)
		end
		local badge = makeLabel({ Size = UDim2.new(1, -20, 0, 24), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Text = badgeText, TextSize = 12, Font = Enum.Font.GothamBold,
			TextColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BackgroundColor3 = badgeColor, ZIndex = 35 }, card)
		rounded(badge, 12)
		tween(card, 0.3, { Size = UDim2.new(0, cardWidth, 0, cardHeight) }, Enum.EasingStyle.Back)
		tween(iconLabel, 0.35, { TextSize = 42 }, Enum.EasingStyle.Back)
		if rarity >= 4 then
			sparks(color, rarity >= 5 and 22 or 12)
			pcall(SoundBank.Play, SoundService, "Rare_Drop")
		end
		task.wait(rarity >= 5 and 0.95 or (rarity >= 4 and 0.75 or 0.5))
	end
	task.wait(0.6)
	if token ~= mine then return end
	-- 끝: 카드 / 골드 아래에 버튼 (소탕은 확인으로 닫고, 던전은 로비로 돌아간다)
	hint.Visible = false
	summaryShown = true
	local back = makeButton({ Size = UDim2.new(0, 200, 0, 42), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 188), Text = sweep and "OK" or "Back to Lobby",
		TextSize = 15, BackgroundColor3 = Color3.fromRGB(58, 120, 210), ZIndex = 34 }, stage, function()
		if not sweep then Remotes.Dungeon:FireServer("Leave") end
		close()
	end)
	rounded(back, 21)
	if sweep then -- 소탕은 마을에서 일어나 구역이 바뀌지 않는다: 버튼을 못 눌러도 스스로 닫힌다
		task.delay(15, function() if token == mine then close() end end)
	end
end

Remotes.Dungeon.OnClientEvent:Connect(function(action, data)
	if action ~= "Result" or typeof(data) ~= "table" or data.Victory ~= true then return end
	local loot = data.Loot
	if typeof(loot) ~= "table" or #loot == 0 then return end
	task.spawn(play, loot, data)
end)

player:GetAttributeChangedSignal("Zone"):Connect(function()
	if player:GetAttribute("Zone") ~= "Dungeon" and gui.Enabled then close() end
end)
