-- AugClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: AugClient)
-- ✨ 세트 효과 창 (Y 키 또는 "세트" 버튼): 칸 3개에 공격 / 방어 효과를 자유롭게 넣고, 칸에 넣은 효과만 켜진다 (방어 최대 2칸).
-- 공격 단계 = 세트 부위(2부위 Lv3 / 3~5부위 Lv6 / 6부위 Lv6 + 👑 각성), 방어 = 수호석 단계. 창 안쪽은 AugSlotsUI 모듈, 값은 서버(AugService)가 정하는 Attribute 에서 읽는다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))

local player = Players.LocalPlayer
local ZONES = #Config.Sets.ZoneAug -- (9번째 폭풍의 방벽 포함)
local function homeZone(z) return (Config.Sets.AugHomeZone and Config.Sets.AugHomeZone[z]) or z end -- (구역 세트가 없는 효과: 해금 / 가격 / "Zone N" 표시 기준 구역)
local TweenService = game:GetService("TweenService")

-- 수호석 강화는 마을(로비)에서만 된다: 서버 AugService.townOnly 와 같은 규칙 (튜토리얼 중에는 필드에서도 된다)
local function atTown()
	return player:GetAttribute("Zone") == "Lobby" or player:GetAttribute("TutorialActive") == true
end

-- 다음 단계 수호석이 모였나 (마을 여부와 상관없이): 방어 효과가 열려 있고 필요한 수호석이 있다. 공격 효과는 세트 장비로만 오른다
local function stoneReady(zone)
	if player:GetAttribute("AugOpenZ_" .. zone) ~= true then return false end
	local info = Config.AugInfo[Config.Sets.ZoneAug[zone]]
	if not (info and info.Defense) then return false end
	local stone = player:GetAttribute("AugStoneZ_" .. zone) or 0
	local need = Config.Guard.StoneCost[stone + 1]
	return need ~= nil and (player:GetAttribute("GuardStones") or 0) >= need
end

-- 지금 바로 올릴 수 있나 (⬆ 표시): (11-25 A-4) 수호석이 모였고 + 마을에 있을 때만. 필드에서 ⬆ 가 떠도 눌러서는 못 올린다
local function canUpgrade(zone)
	return atTown() and stoneReady(zone)
end

local gui = Instance.new("ScreenGui")
gui.Name = "AugGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function make(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local function label(props, parent)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextSize = props.TextSize or 14
	return make("TextLabel", props, parent)
end

local function button(props, parent, callback)
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextSize = props.TextSize or 14
	props.AutoButtonColor = true
	local b = make("TextButton", props, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	b.Activated:Connect(callback)
	return b
end

local function commas(n)
	return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- (11-25 A-3 / B-3) 예전에 창 위에 떠 있던 "🌟 Sets" 버튼(pill)과 그 빨간 점(badge), "Press Y!" 말풍선은 지웠다:
--   버튼을 항상 숨겨 둔(pill.Visible = false) 뒤라 화면에 한 번도 나오지 않는 죽은 코드였고,
--   지금은 왼쪽 메뉴의 "🌟 Sets" 버튼이 빨간 점까지 맡는다 (MenuDockClient).

-- 창 모양: 왼쪽에 내 캐릭터가 서 있고 그 둘레에 구역 효과 8개가 원으로 둘러선다 (무협 RPG 장비창처럼).
-- 오른쪽 패널에 고른 효과의 설명 + 버튼. 한 화면에 다 들어와서 스크롤이 없다.
local PANEL_W, PANEL_H = 1000, 600 -- (11-26: 소켓 3개 + 보석 후보 두 줄)
local RING_CX, RING_CY = 250, 312 -- 원들이 둘러서는 중심 (= 캐릭터)
local RING_RX, RING_RY = 172, 172
local ORB = 66
local BOX_X, BOX_W, BOX_H = 652, 332, 532

local panel = make("Frame", {
	Size = UDim2.new(0, PANEL_W, 0, PANEL_H), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	BackgroundColor3 = Color3.fromRGB(30, 22, 40), BorderSizePixel = 0, Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 14) }, panel)
make("UIStroke", { Color = Color3.fromRGB(201, 162, 74), Thickness = 3 }, panel) -- (다크 포지 금테)
make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(110, 96, 130)), Rotation = 90 }, panel)
local panelScale = make("UIScale", { Scale = 1 }, panel) -- 작은 화면에서는 통째로 줄인다
-- (11-25 A-1) 폰은 MobileLayoutClient 가 AugGui 화면 전체에 MobileScale(가로 폰이면 0.55)을 한 번 더 건다.
-- 그 위에서 창이 또 줄면 두 번 곱해져 0.3배까지 내려가 글씨를 못 읽었다: 화면 배율로 나눠서 "화면에 맞춘 크기"가 그대로 나오게 한다.
local screenScale = 1
local function readScreenScale()
	local scale = gui:FindFirstChild("MobileScale")
	screenScale = (scale and scale:IsA("UIScale") and scale.Scale > 0) and scale.Scale or 1
end
local function fitPanel()
	local camera = workspace.CurrentCamera
	if not camera then return end
	readScreenScale()
	local view = camera.ViewportSize
	local fit = math.clamp(math.min((view.X - 20) / PANEL_W, (view.Y - 20) / PANEL_H), 0.45, 1)
	local mul = math.max(1, screenScale) -- (PC: 화면 배율만큼 크게 = 예전과 같다 / 폰: 화면 배율로 나눈다)
	panelScale.Scale = fit * mul / screenScale
end
fitPanel()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel) end
gui.DescendantAdded:Connect(function(child) -- MobileLayoutClient 가 MobileScale 을 나중에 붙인다: 붙는 순간 / 값이 바뀔 때 다시 맞춘다
	if child:IsA("UIScale") then
		child:GetPropertyChangedSignal("Scale"):Connect(fitPanel)
		fitPanel()
	end
end)
task.defer(fitPanel) -- (그 스크립트가 먼저 돌아 이미 붙어 있었어도 한 번 더: 부딪히는 순서에 기대지 않는다)

-- (11-25) 창 안쪽 = 칸 3개 + 후보 + 칸 강화 + 비교 카드: 별도 모듈 AugSlotsUI (이 파일이 20만 자를 넘지 않게)
local SlotsUI = require(script.Parent:WaitForChild("AugSlotsUI")).Build(panel)

panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if panel.Visible and not player:GetAttribute("HintDone_SetsOpened") then
		player:SetAttribute("HintDone_SetsOpened", true) -- 바로 멈추게 여기서도 켠다 (서버가 저장한다)
		Remotes.Tutorial:FireServer("SetsOpened")
	end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Y then panel.Visible = not panel.Visible end
end)
player:GetAttributeChangedSignal("OpenAug"):Connect(function() panel.Visible = not panel.Visible end) -- 왼쪽 메뉴 버튼(MenuDockClient)
player:GetAttributeChangedSignal("AugFocusZone"):Connect(function() -- 장비 창 "내 세트" 카드의 ✨ 버튼: 그 구역 효과를 고른 채로 연다
	local zone = player:GetAttribute("AugFocusZone")
	if type(zone) ~= "number" then return end
	player:SetAttribute("AugFocusZone", nil)
	task.delay(0.05, function() -- (메뉴가 닫힌 다음에 연다)
		panel.Visible = true
		SlotsUI.Focus(math.clamp(math.floor(zone), 1, ZONES))
	end)
end)

-- 큰 창은 한 번에 하나만: 세트 효과 창을 열면 메뉴 창을 닫고, 메뉴 창을 열면 세트 효과 창을 닫는다 (두 창이 겹쳐 떠 있었다)
task.spawn(function()
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD", 30)
	local menu = hud and hud:WaitForChild("MenuPanel", 30)
	if not menu then return end
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if panel.Visible and menu.Visible then menu.Visible = false end
	end)
	menu:GetPropertyChangedSignal("Visible"):Connect(function()
		if menu.Visible and panel.Visible then panel.Visible = false end
	end)
end)

------------------------------------------------------------
-- 켜 둔 세트 효과 상태창: 필드 / 던전에서 오른쪽 위에 작게 (효과 이름 + 현재 몇 단계인지, 골드 단계 + 장비 단계)
------------------------------------------------------------
-- 켜 둔 세트 효과 카드 (오른쪽 위): 효과마다 한 줄 = 색 아이콘 + 이름 + 단계 점(노랑 = 골드 단계, 하늘 = 장비 단계) + 큰 "Lv.N".
-- 방금 발동한 효과는 줄이 환하게 켜진다 (예전: 작은 글자 한 덩어리라 잘 안 보였다)
local hudBox = make("Frame", {
	Size = UDim2.new(0, 244, 0, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 176),
	BackgroundColor3 = Color3.fromRGB(20, 22, 36), BackgroundTransparency = 0.1, BorderSizePixel = 0, Visible = false, ZIndex = 3,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, hudBox)
local hudStroke = make("UIStroke", { Color = Color3.fromRGB(255, 205, 120), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Transparency = 0.25 }, hudBox)
label({ Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 12, 0, 4), Text = "🌟 Set Effects", TextSize = 13, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 218, 120), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, hudBox)
local hudRows = {}

local procUntil = {} -- 효과 이름 -> 이 시각까지 "방금 발동" 표시
local function refreshHud()
	local zone = player:GetAttribute("Zone")
	for _, row in ipairs(hudRows) do row:Destroy() end
	hudRows = {}
	local y, count = 28, 0
	for z = 1, ZONES do
		if player:GetAttribute("AugOnZ_" .. z) == true then
			count += 1
			local attr = Config.Sets.ZoneAug[z]
			local info = Config.AugInfo[attr]
			local gold = player:GetAttribute("AugLvZ_" .. z) or 0
			local gear = player:GetAttribute("AugGearZ_" .. z) or 0
			local fired = (procUntil[attr] or 0) > os.clock() -- 방금 발동한 효과는 줄이 환하게 켜진다
			local row = make("Frame", {
				Size = UDim2.new(1, -12, 0, 36), Position = UDim2.new(0, 6, 0, y), BorderSizePixel = 0, ZIndex = 4,
				BackgroundColor3 = info.Color:Lerp(Color3.fromRGB(20, 22, 36), fired and 0.35 or 0.74),
			}, hudBox)
			make("UICorner", { CornerRadius = UDim.new(0, 9) }, row)
			make("UIStroke", { Color = fired and Color3.new(1, 1, 1) or info.Color, Thickness = fired and 2.5 or 1.4, Transparency = fired and 0 or 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row)
			label({ Size = UDim2.new(0, 34, 1, 0), Position = UDim2.new(0, 2, 0, 0), Text = info.Icon, TextSize = 21, ZIndex = 5 }, row)
			label({ Size = UDim2.new(1, -100, 0, 18), Position = UDim2.new(0, 38, 0, 3), Text = info.Name, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = fired and Color3.fromRGB(255, 255, 140) or Color3.new(1, 1, 1), ZIndex = 5 }, row)
			local pips = {}
			for i = 1, 6 do
				local color = i <= gold and "#ffd966" or (i <= gold + gear and "#8fe0ff" or "#566080")
				pips[i] = string.format("<font color='%s'>%s</font>", color, i <= gold + gear and "●" or "○")
			end
			label({ Size = UDim2.new(1, -100, 0, 14), Position = UDim2.new(0, 38, 0, 20), Text = table.concat(pips, " "), RichText = true, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }, row)
			label({ Size = UDim2.new(0, 56, 1, 0), Position = UDim2.new(1, -60, 0, 0), Text = "Lv." .. (gold + gear), TextSize = 18, Font = Enum.Font.GothamBlack,
				TextColor3 = Color3.fromRGB(150, 230, 255), TextStrokeTransparency = 0.5, ZIndex = 5 }, row)
			table.insert(hudRows, row)
			y += 40
		end
	end
	hudBox.Visible = false -- (오른쪽 위 "세트 효과" 목록은 뺐다: 머리 위 메달이 발동을 보여 준다. 자세한 건 세트 창에서)
	hudBox.Size = UDim2.new(0, 244, 0, y + 4)
end
-- 머리 위 세트 효과 메달: 장착한 세트 효과가 내 머리 위에 작은 메달로 늘 보이고, 터지는 순간 그 메달만 커지며 빛나고 이름 리본이 잠깐 뜬다
--   (예전: 맞은 자리 아이콘 / 화면 가운데 글자 / 오른쪽 위 목록이 따로 깜빡여서 무엇이 터졌는지 눈에 안 들어왔다). 내 화면에만 보인다
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local headBoard = Instance.new("BillboardGui")
headBoard.Name = "AugHeadMedals"
headBoard.Size = UDim2.new(0, 150, 0, 74)
headBoard.StudsOffset = Vector3.new(0, 3.6, 0)
headBoard.AlwaysOnTop = true
headBoard.LightInfluence = 0
headBoard.MaxDistance = 200
headBoard.ResetOnSpawn = false
headBoard.Enabled = false
headBoard.Parent = player:WaitForChild("PlayerGui")
local headRow = make("Frame", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 1, -42), BackgroundTransparency = 1 }, headBoard)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, headRow)
local headMedals = {} -- [효과 이름] = { Scale = UIScale, Holder = Frame }
local headRibbon
local function refreshHead()
	local zone = player:GetAttribute("Zone")
	local character = player.Character
	headBoard.Adornee = character and character:FindFirstChild("Head")
	for _, entry in pairs(headMedals) do entry.Holder:Destroy() end
	headMedals = {}
	local count = 0
	for z = 1, ZONES do
		if player:GetAttribute("AugOnZ_" .. z) == true then
			local attr = Config.Sets.ZoneAug[z]
			local info = Config.AugInfo[attr]
			if info then
				count += 1
				local holder = make("Frame", { Size = UDim2.new(0, 30, 0, 30), BackgroundTransparency = 1, LayoutOrder = z, Visible = false }, headRow) -- (평소에는 숨기고 발동할 때만 잠깐 보인다)
				local scale = make("UIScale", { Scale = 1 }, holder)
				local medal = Kit.medal(holder, { Size = 30, Color = info.Color, Icon = info.Icon, TextSize = 15, Tier = 2 })
				medal.Name = "Medal"
				local level = (player:GetAttribute("AugLvZ_" .. z) or 0) + (player:GetAttribute("AugGearZ_" .. z) or 0)
				local lv = label({ Size = UDim2.new(0, 18, 0, 12), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -6), Text = tostring(level), TextSize = 12, Font = Enum.Font.GothamBlack,
					TextColor3 = Color3.fromRGB(255, 233, 168), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(22, 18, 44), ZIndex = 6 }, holder)
				make("UICorner", { CornerRadius = UDim.new(0, 6) }, lv)
				headMedals[attr] = { Scale = scale, Holder = holder, Info = info }
			end
		end
	end
	headBoard.Enabled = count > 0 and headBoard.Adornee ~= nil and (zone == "Field" or zone == "Dungeon") and not player:GetAttribute("TutorialActive") and not player:GetAttribute("LowSpec")
end
local function popHead(attr, info)
	local entry = headMedals[attr]
	if not entry or not headBoard.Enabled then return end
	-- (메달은 보이지 않는다: 지저분해서 뺐다. 머리 위에는 얇은 이름 띠만 잠깐 뜬다)
	-- 이름 리본 (같은 때 하나만: 새로 터지면 바꿔 단다)
	if headRibbon then headRibbon:Destroy() end
	local ribbon = Kit.ribbon(headBoard, { Size = UDim2.new(0, 116, 0, 16), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -22), Color = info.Color, Text = info.Icon .. " " .. info.Name .. "!", TextSize = 11, ZIndex = 8 }) -- (얇은 띠)
	local ribbonScale = make("UIScale", { Scale = 0.7 }, ribbon)
	TweenService:Create(ribbonScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	headRibbon = ribbon
	task.delay(0.9, function()
		if headRibbon == ribbon then headRibbon = nil end
		ribbon:Destroy()
	end)
end
for _, name in ipairs({ "Zone", "TutorialActive", "LowSpec" }) do player:GetAttributeChangedSignal(name):Connect(refreshHead) end
for z = 1, ZONES do
	for _, prefix in ipairs({ "AugOnZ_", "AugLvZ_", "AugGearZ_" }) do player:GetAttributeChangedSignal(prefix .. z):Connect(refreshHead) end
end
player.CharacterAdded:Connect(function(character)
	character:WaitForChild("Head", 10)
	refreshHead()
end)
refreshHead()

for _, name in ipairs({ "Zone", "TutorialActive" }) do player:GetAttributeChangedSignal(name):Connect(refreshHud) end
for z = 1, ZONES do
	for _, prefix in ipairs({ "AugOnZ_", "AugLvZ_", "AugGearZ_" }) do player:GetAttributeChangedSignal(prefix .. z):Connect(refreshHud) end
end
refreshHud()

------------------------------------------------------------
-- 던전 시작 체험 효과: 8개 중 하나를 뽑는 연출(약 2.5초) -> 화면 오른쪽 위 구석에 작은 표시
------------------------------------------------------------
local corner = make("TextLabel", {
	Size = UDim2.new(0, 240, 0, 46), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 96), RichText = true, TextWrapped = true,
	BackgroundColor3 = Color3.fromRGB(26, 28, 42), BackgroundTransparency = 0.25, Font = Enum.Font.GothamBold, TextSize = 11,
	TextColor3 = Color3.new(1, 1, 1), Text = "", Visible = false, BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, corner)
local cornerStroke = make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, corner) -- (Border: 글자가 아니라 상자 테두리에만)

local function refreshCorner()
	local attr = player:GetAttribute("AugDemo")
	local info = typeof(attr) == "string" and Config.AugInfo[attr]
	local show = info and player:GetAttribute("Zone") == "Dungeon" and not corner:GetAttribute("Rolling")
	corner.Visible = show == true
	if show then
		local zone = table.find(Config.Sets.ZoneAug, attr) or 0
		corner.Text = string.format("%s <b>%s</b>  <font size='9' color='#ffd966'>Zone %d · Trial Lv.3</font>\n<font size='9' color='#c8d0e8'>%s</font>", info.Icon, info.Name, zone, info.Desc)
		cornerStroke.Color = info.Color
	end
end
player:GetAttributeChangedSignal("AugDemo"):Connect(refreshCorner)
player:GetAttributeChangedSignal("Zone"):Connect(refreshCorner)

local function playRollCompact(pick)
	local winner = Config.AugInfo[pick]
	if not winner then return end
	corner:SetAttribute("Rolling", true)
	corner.Visible = false
	local box = make("Frame", {
		Size = UDim2.new(0, 320, 0, 128), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.14, 0),
		BackgroundColor3 = Color3.fromRGB(26, 28, 42), BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 60,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, box)
	local stroke = make("UIStroke", { Color = Color3.fromRGB(255, 190, 110), Thickness = 2 }, box)
	label({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0, 6), Text = "🎲 This Dungeon's Trial Effect", TextSize = 12, ZIndex = 61 }, box)
	local icon = label({ Size = UDim2.new(0, 60, 0, 44), Position = UDim2.new(0, 14, 0, 32), Text = "?", TextSize = 29, ZIndex = 61 }, box)
	local name = label({ Size = UDim2.new(1, -88, 0, 44), Position = UDim2.new(0, 78, 0, 32), Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, RichText = true, ZIndex = 61 }, box)
	local detail = label({ Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0, 12, 0, 80), Text = "", TextSize = 10, TextWrapped = true, TextColor3 = Color3.fromRGB(200, 208, 232), Font = Enum.Font.GothamMedium, ZIndex = 61 }, box)
	local startedAt = os.clock()
	while os.clock() - startedAt < 1.3 do
		local info = Config.AugInfo[Config.Sets.ZoneAug[math.random(Config.Field.ZoneCount)]] -- (체험 뽑기는 공격 8개만)
		icon.Text, name.Text = info.Icon, info.Name
		name.TextColor3 = Color3.fromRGB(170, 175, 205)
		task.wait(0.07)
	end
	local winZone = table.find(Config.Sets.ZoneAug, pick) or 0
	icon.Text, name.Text = winner.Icon, string.format("%s\n<font size='10' color='#ffd966'>Zone %d set effect · Trial Lv.3</font>", winner.Name, winZone)
	detail.Text = winner.Desc
	name.TextColor3 = winner.Color
	stroke.Color = winner.Color
	task.wait(2.2)
	TweenService:Create(box, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	task.wait(0.3)
	box:Destroy()
	corner:SetAttribute("Rolling", nil)
	refreshCorner()
end

-- 튜토리얼 던전(처음 체험): 세트 효과 8개를 한 줄로 쭉 늘어놓고, 커서가 빠르게 훑다가 천천히 멈추며 하나가 "선택된다".
-- "세트 효과라는 게 구역마다 하나씩 8가지가 있구나" 를 알려 주는 안내를 겸한다.
local function tick(key, volume)
	pcall(function() if SoundBank.Has(key) then SoundBank.Play(game:GetService("SoundService"), key, { Volume = volume or 0.6 }) end end)
end
local function playRollFull(pick)
	local winner = Config.AugInfo[pick]
	if not winner then return end
	corner:SetAttribute("Rolling", true)
	corner.Visible = false
	local phoneLayout = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local cols = phoneLayout and 4 or 8
	local rows = 8 // cols
	local cardW, cardH, gap = 64, 86, 6
	local panelW = cols * cardW + (cols + 1) * gap + 20
	local panelH = 78 + rows * (cardH + gap) + 96
	local box = make("CanvasGroup", {
		Size = UDim2.new(0, panelW, 0, panelH), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.09, 0),
		BackgroundColor3 = Color3.fromRGB(22, 24, 38), BackgroundTransparency = 0.04, BorderSizePixel = 0, ZIndex = 60, GroupTransparency = 1,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, box)
	local stroke = make("UIStroke", { Color = Color3.fromRGB(190, 168, 110), Thickness = 2 }, box)
	label({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 10), Text = "✨ SET EFFECTS", TextSize = 18, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(235, 215, 160), ZIndex = 61 }, box)
	label({ Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 0, 36), Text = "Every zone has its own effect (8 in all). It fires by itself while you fight. Here is one to try!", TextSize = 11, TextWrapped = true, TextColor3 = Color3.fromRGB(190, 196, 220), Font = Enum.Font.GothamMedium, ZIndex = 61 }, box)
	local cards = {}
	for index = 1, 8 do
		local info = Config.AugInfo[Config.Sets.ZoneAug[index]]
		local col, row = (index - 1) % cols, (index - 1) // cols
		local card = make("Frame", {
			Size = UDim2.new(0, cardW, 0, cardH), Position = UDim2.new(0, 10 + gap + col * (cardW + gap), 0, 78 + row * (cardH + gap)),
			BackgroundColor3 = Color3.fromRGB(34, 36, 56), BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 61,
		}, box)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
		local cardStroke = make("UIStroke", { Color = Color3.fromRGB(70, 74, 104), Thickness = 1.5 }, card)
		local scale = make("UIScale", { Scale = 1 }, card)
		local zoneText = label({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 4), Text = "ZONE " .. index, TextSize = 9, TextColor3 = Color3.fromRGB(150, 156, 184), ZIndex = 62 }, card)
		local iconText = label({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 20), Text = info.Icon, TextSize = 28, ZIndex = 62 }, card)
		local nameText = label({ Size = UDim2.new(1, -6, 0, 26), Position = UDim2.new(0, 3, 0, 56), Text = info.Name, TextSize = 9, TextWrapped = true, TextColor3 = Color3.fromRGB(205, 210, 232), ZIndex = 62 }, card)
		cards[index] = { Card = card, Stroke = cardStroke, Scale = scale, Texts = { zoneText, iconText, nameText }, Color = info.Color }
	end
	local function setState(index, state)
		local c = cards[index]
		if not c then return end
		local active = state == "hover" or state == "win"
		c.Card.BackgroundTransparency = state == "dim" and 0.6 or (active and 0 or 0.1)
		c.Card.BackgroundColor3 = state == "win" and c.Color:Lerp(Color3.fromRGB(34, 36, 56), 0.65) or Color3.fromRGB(34, 36, 56)
		c.Stroke.Color = state == "win" and c.Color or (state == "hover" and Color3.fromRGB(255, 217, 102) or Color3.fromRGB(70, 74, 104))
		c.Stroke.Thickness = state == "win" and 4 or (state == "hover" and 3 or 1.5)
		c.Scale.Scale = state == "win" and 1.14 or (state == "hover" and 1.08 or 1)
		for _, text in ipairs(c.Texts) do text.TextTransparency = state == "dim" and 0.65 or 0 end
	end
	local nameLine = label({ Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 0, panelH - 92), Text = "", TextSize = 16, Font = Enum.Font.GothamBlack, ZIndex = 61, RichText = true }, box)
	local descLine = label({ Size = UDim2.new(1, -28, 0, 38), Position = UDim2.new(0, 14, 0, panelH - 66), Text = "", TextSize = 11, TextWrapped = true, TextColor3 = Color3.fromRGB(200, 208, 232), Font = Enum.Font.GothamMedium, ZIndex = 61 }, box)
	local hintLine = label({ Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 1, -26), Text = "", TextSize = 10, TextColor3 = Color3.fromRGB(255, 217, 102), ZIndex = 61 }, box)
	-- 돌아가는 동안 아래 빈칸에 "어떻게 얻나" 3단계를 보여 준다 (예전엔 멈출 때까지 아래 절반이 텅 비어 있었다)
	nameLine.Text = "<font color='#ffd966'>How to get them</font>"
	nameLine.TextColor3 = Color3.fromRGB(235, 215, 160)
	descLine.Text = "① Defeat a zone's Lord → its effect unlocks   ② Wear 2+ set pieces and put it in a slot (Y)   ③ It fires on its own in combat"
	TweenService:Create(box, TweenInfo.new(0.35), { GroupTransparency = 0 }):Play()
	task.wait(0.9) -- 8개를 먼저 훑어볼 시간

	local winIndex = table.find(Config.Sets.ZoneAug, pick) or 1
	local startIndex = math.random(8)
	local steps = 16 + ((winIndex - startIndex) % 8) + 1 -- 두 바퀴를 돌고 정확히 뽑힌 칸에서 멈춘다
	local previous
	for i = 1, steps do
		local index = ((startIndex - 1 + i - 1) % 8) + 1
		if previous then setState(previous, "idle") end
		setState(index, "hover")
		previous = index
		tick("Gacha_Tick", 0.5)
		task.wait(0.045 + 0.24 * (i / steps) ^ 3) -- 처음엔 빠르게, 끝에서 천천히
	end
	for index = 1, 8 do setState(index, index == winIndex and "win" or "dim") end
	stroke.Color = winner.Color
	nameLine.Text = string.format("%s  %s", winner.Icon, winner.Name)
	nameLine.TextColor3 = winner.Color
	descLine.Text = winner.Desc
	hintLine.Text = string.format("Zone %d set effect · Trial Lv.3 — for this dungeon only. Watch for it in combat!", winIndex)
	tick("Rare_Drop", 0.8)
	task.wait(4.6)
	TweenService:Create(box, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
	task.wait(0.45)
	box:Destroy()
	corner:SetAttribute("Rolling", nil)
	refreshCorner()
end

local function playRoll(pick)
	if player:GetAttribute("TutorialDungeonRun") == true then
		playRollFull(pick)
	else
		playRollCompact(pick)
	end
end

-- 세트 효과가 발동했을 때: 조준점 아래에 이름 팝업이 떠올랐다 사라지고, 오른쪽 위 목록의 그 효과가 잠깐 노랗게 켜지며 상자 테두리가 번쩍인다
local procLabels = {}
-- 발동 체감: 내 발밑에 그 효과 색의 고리가 퍼지고, 효과가 터진 자리 위로 아이콘이 떠오른다 (은은하게: 반투명 / 짧게). 저사양 모드면 생략
local procFolder = Instance.new("Folder")
procFolder.Name = "AugProcFx"
procFolder.Parent = workspace
local function procWorldFx(info, position)
	if player:GetAttribute("LowSpec") then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
		ring.Material = Enum.Material.Neon
		ring.Color = info.Color:Lerp(Color3.fromRGB(40, 40, 50), 0.25)
		ring.Transparency = 0.5
		ring.Size = Vector3.new(0.2, 3, 3)
		ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = procFolder
		TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, 15, 15), Transparency = 1 }):Play()
		task.delay(0.45, function() ring:Destroy() end)
	end
	if typeof(position) == "Vector3" then
		local anchor = Instance.new("Part")
		anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Position = position + Vector3.new(0, 5, 0)
		anchor.Parent = procFolder
		local board = Instance.new("BillboardGui")
		board.Size = UDim2.new(0, 54, 0, 54)
		board.AlwaysOnTop = true
		board.MaxDistance = 160
		board.Parent = anchor
		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(1, 0, 1, 0)
		icon.BackgroundTransparency = 1
		icon.Text = info.Icon
		icon.TextScaled = true
		icon.Font = Enum.Font.GothamBlack
		icon.Parent = board
		TweenService:Create(anchor, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = anchor.Position + Vector3.new(0, 5, 0) }):Play()
		task.delay(0.4, function() TweenService:Create(icon, TweenInfo.new(0.4), { TextTransparency = 1 }):Play() end)
		task.delay(0.85, function() anchor:Destroy() end)
	end
end

local lastProcPop = 0
local firstProcTaught = false
local lastWorldFx, worldFxWindow, worldFxBudget = {}, 0, 0
local function worldFxAllowed(attr) -- 세트 효과 발동 연출(고리 + 떠오르는 아이콘)은 같은 효과 0.3초에 한 번, 전체 1초에 5번까지 (후반에는 초당 수십 번 터져서 부품 / 글자가 쌓여 화면이 끊겼다)
	local now = os.clock()
	if now - (lastWorldFx[attr] or 0) < 0.3 then return false end
	if now - worldFxWindow >= 1 then worldFxWindow, worldFxBudget = now, 0 end
	if worldFxBudget >= 5 then return false end
	worldFxBudget += 1
	lastWorldFx[attr] = now
	return true
end
local taughtProc, teachLineShown = {}, false -- (이번 접속에서 이름을 한 번 알려 준 효과)
local function showProc(attr, position)
	local info = Config.AugInfo[attr]
	if not info then return end
	-- 머리 위 이름 표시는 기본 꺼짐 (세트 효과가 얼마나 일하는지는 오른쪽 DPS 미터기로 본다).
	-- 대신 각 효과가 이번 접속에서 처음 터질 때 딱 한 번 이름을 띄워 "이게 세트 효과" 라고 알려 준다. 설정에서 켜면 매번 띄운다
	if not player:GetAttribute("SetPopShow") then
		if taughtProc[attr] then return end
		taughtProc[attr] = true
		if headBoard.Enabled and headMedals[attr] then
			popHead(attr, info)
			if not teachLineShown then
				teachLineShown = true
				local teach = label({
					Size = UDim2.new(0, 460, 0, 22), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.64, 30),
					Text = "↑ That was your set effect! It fires on its own (see the DPS meter).", TextSize = 14, TextColor3 = Color3.fromRGB(255, 226, 140),
					TextStrokeTransparency = 0.35, TextStrokeColor3 = Color3.fromRGB(10, 10, 20), ZIndex = 40,
				}, gui)
				task.delay(3, function()
					TweenService:Create(teach, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
					task.delay(0.55, function() teach:Destroy() end)
				end)
			end
		end
		return
	end
	if worldFxAllowed(attr) then
		if headBoard.Enabled and headMedals[attr] then
			popHead(attr, info) -- 머리 위 메달이 보이면 그걸로 알려 준다 (맞은 자리 아이콘 / 화면 가운데 글자는 띄우지 않는다)
		else
			procWorldFx(info, position)
		end
	end
	if headBoard.Enabled and headMedals[attr] then -- 오른쪽 위 목록만 잠깐 켠다
		procUntil[attr] = os.clock() + 0.5
		refreshHud()
		task.delay(0.55, refreshHud)
		return
	end
	if os.clock() - lastProcPop < 1.4 then return end -- 화면 가운데 "충격파 샷!" 같은 글자는 1.4초에 한 번만 (세트 효과가 계속 터져서 글자가 쉴 새 없이 떴다. 효과 자체의 연출은 그대로)
	lastProcPop = os.clock()
	if player:GetAttribute("ModalOpen") then return end -- 메뉴 같은 큰 창이 열려 있으면 화면 가운데 글자를 띄우지 않는다 (창 위에 겹쳐 보였다)
	procUntil[attr] = os.clock() + 0.5
	refreshHud()
	task.delay(0.55, refreshHud)
	hudStroke.Thickness = 3
	hudStroke.Transparency = 0
	TweenService:Create(hudStroke, TweenInfo.new(0.5), { Thickness = 2, Transparency = 0.25 }):Play()
	if not firstProcTaught and player:GetAttribute("TutorialDungeonRun") == true and attr == player:GetAttribute("AugDemo") then
		-- 처음 체험한 세트 효과가 처음 터진 순간: "방금 그게 세트 효과" 라고 한 번만 짚어 준다 (보고 배운다)
		firstProcTaught = true
		local teach = label({
			Size = UDim2.new(0, 420, 0, 22), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.64, 30),
			Text = "↑ That was your set effect! It fires on its own.", TextSize = 14, TextColor3 = Color3.fromRGB(255, 226, 140),
			TextStrokeTransparency = 0.35, TextStrokeColor3 = Color3.fromRGB(10, 10, 20), ZIndex = 40,
		}, gui)
		task.delay(2.6, function()
			TweenService:Create(teach, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(0.55, function() teach:Destroy() end)
		end)
	end
	local slot = #procLabels
	local pop = label({
		Size = UDim2.new(0, 260, 0, 26), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.64, 26 * slot), Text = info.Icon .. "  " .. info.Name .. "!",
		TextSize = 17, TextColor3 = info.Color:Lerp(Color3.new(1, 1, 1), 0.35), TextStrokeTransparency = 0.35, TextStrokeColor3 = Color3.fromRGB(10, 10, 20), ZIndex = 40,
	}, gui)
	table.insert(procLabels, pop)
	local scale = make("UIScale", { Scale = 0.6 }, pop)
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.25, function()
		TweenService:Create(pop, TweenInfo.new(0.5), { Position = pop.Position - UDim2.new(0, 0, 0, 28), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(0.8, function()
		local at = table.find(procLabels, pop)
		if at then table.remove(procLabels, at) end
		pop:Destroy()
	end)
end

Remotes.Aug.OnClientEvent:Connect(function(action, pick, extra)
	if action == "Demo" then task.spawn(playRoll, pick)
	elseif action == "Proc" then showProc(pick, extra) end
end)
refreshCorner()

------------------------------------------------------------
-- 세트 효과 트리거 게이지 (스킬 바 옆 작은 원): 서버가 AugChargeZ_<구역> (0~100) 을 보낸다
--   맞힐수록 원이 아래에서 위로 차오르고, 꽉 차서 발동하면(값이 크게 떨어지면) 한 번 톡 커졌다 돌아온다
--   켜진 세트 효과 중 게이지형(Config.AugCharge.Interval: 충격파탄 / 낙뢰 / 유성우)만 그린다. 값이 바뀔 때 트윈 없이 바로 칠한다 (10Hz)
--   스킬 바 오른쪽은 자동 공격 버튼 자리라 왼쪽에 붙인다
------------------------------------------------------------
do
	local AC = Config.AugCharge
	if AC and AC.Interval then
		local holder = make("Frame", { Name = "AugChargeGauges", Size = UDim2.new(0, 0, 0, 44), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, -10, 0.5, 0), BackgroundTransparency = 1, Visible = false })
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
		local gauges = {} -- [zone] = { Frame, Fill(UIGradient), Scale, Last }
		local function fillSeq(f)
			if f <= 0 then return NumberSequence.new(1) end
			if f >= 1 then return NumberSequence.new(0) end
			return NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(f, 0), NumberSequenceKeypoint.new(math.min(1, f + 0.001), 1), NumberSequenceKeypoint.new(1, 1) })
		end
		for zone, attr in ipairs(Config.Sets.ZoneAug) do
			local info = Config.AugInfo[attr]
			if AC.Interval[attr] and info then
				local frame = make("Frame", { Size = UDim2.new(0, 40, 0, 40), BackgroundColor3 = Color3.fromRGB(22, 22, 36), BackgroundTransparency = 0.15, BorderSizePixel = 0, LayoutOrder = zone, Visible = false }, holder)
				make("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
				make("UIStroke", { Color = info.Color, Thickness = 2, Transparency = 0.2 }, frame)
				local fill = make("Frame", { Size = UDim2.new(1, -6, 1, -6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = info.Color, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, frame)
				make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
				local grad = make("UIGradient", { Rotation = -90, Transparency = fillSeq(0) }, fill) -- (아래 -> 위로 차오름)
				label({ Size = UDim2.new(1, 0, 1, 0), Text = info.Icon, TextSize = 18, ZIndex = 3 }, frame)
				local scale = make("UIScale", { Scale = 1 }, frame)
				gauges[zone] = { Frame = frame, Grad = grad, Scale = scale, Last = 0 }
			end
		end
		local function paint(zone)
			local g = gauges[zone]
			local pct = math.clamp(tonumber(player:GetAttribute("AugChargeZ_" .. zone)) or 0, 0, 100)
			g.Grad.Transparency = fillSeq(pct / 100)
			if g.Last >= 70 and pct <= 20 and holder.Visible and not player:GetAttribute("LowSpec") then -- 방금 발동: 한 번만 톡
				g.Scale.Scale = 1.25
				TweenService:Create(g.Scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			g.Last = pct
		end
		local function refreshGauges()
			local zone = player:GetAttribute("Zone")
			local any = false
			for z, g in pairs(gauges) do
				local on = player:GetAttribute("AugOnZ_" .. z) == true
				g.Frame.Visible = on
				any = any or on
			end
			holder.Visible = any and (zone == "Field" or zone == "Dungeon") and not player:GetAttribute("TutorialActive")
		end
		-- 연결은 처음 한 번만 (플레이어 속성은 리스폰해도 그대로라 다시 걸 필요가 없다)
		for z in pairs(gauges) do
			player:GetAttributeChangedSignal("AugChargeZ_" .. z):Connect(function() paint(z) end)
			player:GetAttributeChangedSignal("AugOnZ_" .. z):Connect(refreshGauges)
			paint(z)
		end
		for _, name in ipairs({ "Zone", "TutorialActive" }) do player:GetAttributeChangedSignal(name):Connect(refreshGauges) end
		refreshGauges()
		-- 스킬 바(HUD/SkillBar) 에 붙인다: 스킬 바를 따라 움직이고, 스킬 바가 숨으면 같이 숨는다. 스킬 바가 새로 생기면 다시 붙인다
		task.spawn(function()
			local playerGui = player:WaitForChild("PlayerGui")
			while true do
				if not (holder.Parent and holder.Parent.Name == "SkillBar" and holder.Parent:IsDescendantOf(playerGui)) then
					local bar
					local hud = playerGui:FindFirstChild("HUD")
					if hud then bar = hud:FindFirstChild("SkillBar", true) end
					if bar then holder.Parent = bar end
				end
				task.wait(2)
			end
		end)
	end
end
