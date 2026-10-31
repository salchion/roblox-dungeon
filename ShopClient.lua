-- ShopClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: ShopClient)
-- 🎁 Shop 창. PlayerClient 가 너무 커져서 분리했다.
--   열기 : 플레이어 Attribute "OpenShop" 이 바뀔 때마다 토글 (MobileLayoutClient 의 🎁 버튼이 설정)
--   상호 배제 : 열릴 때 HUD.MenuPanel 을 숨기고, PlayerClient 는 메뉴가 열릴 때 ShopGui.ShopPanel 을 숨긴다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, rounded, makePanel, makeLabel, makeButton = Kit.create, Kit.rounded, Kit.makePanel, Kit.makeLabel, Kit.makeButton

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GREEN = Color3.fromRGB(56, 156, 98)
local RED = Color3.fromRGB(196, 78, 82)
local GRAY = Color3.fromRGB(54, 58, 82)

local function clearChildren(container)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local gui = create("ScreenGui", { Name = "ShopGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1 }, playerGui)
do -- HUD 와 같은 맞춤 (모바일에서는 MobileLayoutClient 가 이 UIScale 을 덮어쓴다)
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local function fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(viewport.X / 1100, viewport.Y / 720), 0.55, math.max(1, game:GetService("Players").LocalPlayer:GetAttribute("UiMul") or 1))
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	game:GetService("Players").LocalPlayer:GetAttributeChangedSignal("UiMul"):Connect(fit)
end

-- 미리보기 알림 (HUD 의 토스트와 같은 모양)
local toastLabel = makeLabel({
	Name = "ToastLabel", Size = UDim2.new(0, 400, 0, 74), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -430, 1, -250),
	BackgroundColor3 = Color3.fromRGB(16, 18, 30), BackgroundTransparency = 0.08, Font = Enum.Font.GothamBold, TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left, Visible = false,
}, gui)
create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10) }, toastLabel)
create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 1.5, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, toastLabel)
rounded(toastLabel, 12)
local toastToken = 0
local function toast(text)
	toastToken += 1
	local token = toastToken
	local pg = gui.Parent
	local cy = pg:GetAttribute("UiToastY")
	local y = cy or -250
	local tx = cy and pg:GetAttribute("UiToastX") or 14
	toastLabel.Text = text
	toastLabel.Position = UDim2.new(0, -430, 1, y)
	toastLabel.Visible = true
	TweenService:Create(toastLabel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, tx, 1, y) }):Play()
	task.delay(4, function()
		if token == toastToken then toastLabel.Visible = false end
	end)
end

local SHOP = { PreviewToken = 0 }
SHOP.Panel = makePanel({
	Name = "ShopPanel",
	Size = UDim2.new(0, 860, 0, 580), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.55, 0),
	BackgroundColor3 = Color3.fromRGB(16, 18, 30), BackgroundTransparency = 0.03, Visible = false,
}, gui)
create("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 2, Transparency = 0.25 }, SHOP.Panel)
makeLabel({
	Size = UDim2.new(1, -120, 0, 36), Position = UDim2.new(0, 16, 0, 8),
	Text = "🎁 Shop", Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left,
}, SHOP.Panel)
makeButton({
	Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -84, 0, 12), Text = "Close", TextSize = 12, BackgroundColor3 = Color3.fromRGB(54, 58, 82),
}, SHOP.Panel, function()
	SHOP.Panel.Visible = false
end)
-- 창 모양 (표처럼 줄줄이 늘어선 카드 대신): 왼쪽 = VIP + 카테고리 / 가운데 = 상품 구슬 칸 / 오른쪽 = 고른 상품의 큰 설명 + 구매 버튼
SHOP.Content = create("Frame", { Size = UDim2.new(1, -24, 1, -60), Position = UDim2.new(0, 12, 0, 48), BackgroundTransparency = 1 }, SHOP.Panel)

local function auraUnlockText(aura)
	local unlock = aura.Unlock
	if unlock == "Free" then return "Default" end
	if unlock.Ach then
		for _, achievement in ipairs(Config.Achievements) do
			if achievement.Id == unlock.Ach then
				return "Achievement: " .. achievement.Name
			end
		end
	end
	if unlock.Pass then return Config.Shop.Passes[unlock.Pass].Name .. " only" end
	if unlock.Product then return "Shop item: " .. Config.Shop.Products[unlock.Product].Name end
	return ""
end

local function shopButtonLabel(id)
	if id > 0 then return "Buy", GREEN end
	if RunService:IsStudio() then return "Test Grant", Color3.fromRGB(200, 130, 40) end
	return "Coming Soon", GRAY
end

SHOP.Cat = "Rec"
SHOP.Timers, SHOP.Items = {}, {}
SHOP.Acc = { Rec = Color3.fromRGB(214, 140, 72), Idle = Color3.fromRGB(78, 150, 196), Growth = Color3.fromRGB(88, 166, 112), Deco = Color3.fromRGB(166, 104, 200), Currency = Color3.fromRGB(200, 168, 80) }
SHOP.Kinds = { { "Aura", "Auras", "✨" }, { "Banner", "Banners", "🚩" }, { "Mount", "Mounts", "🛹" } }
SHOP.Boost = { XpBoost = "XpBoostUntil", LuckBoost = "LuckBoostUntil", IdleBoost = "IdleBoostUntil" }
SHOP.Tier = { IdleMult = { "IdleMultBonus", "MultTiers" }, IdleCap = { "IdleCapBonusHours", "CapTiers" } }

function SHOP.Level(group)
	local t = SHOP.Tier[group]
	local v = player:GetAttribute(t[1]) or 0
	if group == "IdleMult" and player:GetAttribute("Vip") == true then v -= Config.Idle.VipBonus end
	local lv = 0
	for i, need in ipairs(Config.Idle[t[2]]) do
		if v >= need - 0.001 then lv = i end
	end
	return lv
end

function SHOP.Preview(kind, key, name)
	local character = player.Character
	if not character then return end
	local Cosmetics = require(game:GetService("ReplicatedStorage"):WaitForChild("Cosmetics"))
	SHOP.PreviewToken = SHOP.PreviewToken + 1
	local token = SHOP.PreviewToken
	SHOP.Panel.Visible = false
	Cosmetics.Clear(character, kind)
	Cosmetics.Build(kind, key, character, true)
	toast(string.format("👀 [%s] 5-second preview!", name))
	task.delay(5, function()
		if SHOP.PreviewToken ~= token then return end
		Cosmetics.Clear(character, kind, true)
		local equipped = player:GetAttribute(kind) or ""
		if equipped ~= "" and Config[kind == "Aura" and "Auras" or (kind == "Banner" and "Banners" or "Mounts")][equipped] then
			Cosmetics.Build(kind, equipped, character)
		end
		SHOP.Panel.Visible = true
	end)
end

-- 상품 칸: 둥근 구슬 아이콘 + 이름 한 줄. 누르면 오른쪽 상세 패널에 나온다
function SHOP.Card(parent, order, o)
	o.Id = o.Id or o.Name
	SHOP.Items[o.Id] = o
	if not SHOP.Sel or not SHOP.Items[SHOP.Sel] then SHOP.Sel = o.Id end
	local chosen = SHOP.Sel == o.Id
	local acc, mute = o.Acc, o.Owned and not o.Prev
	local tile = create("TextButton", { Size = UDim2.new(0, 100, 0, 112), LayoutOrder = order, BackgroundColor3 = chosen and Color3.fromRGB(44, 46, 74) or Color3.fromRGB(26, 28, 44), BorderSizePixel = 0, Text = "", AutoButtonColor = true }, parent)
	rounded(tile, 14)
	create("UIStroke", { Color = chosen and Color3.new(1, 1, 1) or acc, Thickness = chosen and 2.5 or 1.2, Transparency = chosen and 0.1 or (mute and 0.8 or 0.5) }, tile)
	local orb = create("Frame", { Size = UDim2.new(0, 64, 0, 64), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = mute and 0.5 or 0, BorderSizePixel = 0 }, tile)
	rounded(orb, 32)
	create("UIGradient", { Rotation = 90, Color = ColorSequence.new(acc, acc:Lerp(Color3.fromRGB(20, 22, 36), 0.65)) }, orb)
	create("UIStroke", { Color = acc:Lerp(Color3.new(1, 1, 1), 0.35), Thickness = 2, Transparency = mute and 0.6 or 0.1 }, orb)
	makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = o.Icon, TextSize = 30, TextTransparency = mute and 0.4 or 0 }, orb)
	makeLabel({ Size = UDim2.new(1, -10, 0, 28), Position = UDim2.new(0, 5, 0, 78), Text = o.Name, TextSize = 11, Font = Enum.Font.GothamBold, TextWrapped = true, TextColor3 = mute and Color3.fromRGB(150, 156, 180) or Color3.fromRGB(240, 242, 250) }, tile)
	if o.Badge then
		local badge = makeLabel({ Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Text = o.Badge, TextSize = 9, Font = Enum.Font.GothamBold, TextWrapped = false, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(196, 84, 72), ZIndex = 3 }, tile)
		rounded(badge, 8)
		create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, badge)
	end
	if o.Owned then
		makeLabel({ Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(0, 6, 0, 6), Text = o.Ribbon and "★" or "✔", TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(150, 245, 170), ZIndex = 3 }, tile)
	end
	tile.Activated:Connect(function()
		SHOP.Sel = o.Id
		SHOP.LastSig = nil
		SHOP.Refresh()
	end)
end

-- 오른쪽 상세 패널: 큰 구슬 + 이름 + 설명 + 단계 / 남은 시간 + 버튼
function SHOP.Detail(parent, o)
	local acc = o.Acc
	local panel = makePanel({ Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(24, 26, 42) }, parent)
	create("UIStroke", { Color = acc, Thickness = 2, Transparency = 0.3 }, panel)
	local glow = create("Frame", { Size = UDim2.new(0, 170, 0, 170), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 92), BackgroundColor3 = acc, BackgroundTransparency = 0.85, BorderSizePixel = 0 }, panel)
	rounded(glow, 85)
	local orb = create("Frame", { Size = UDim2.new(0, 112, 0, 112), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 92), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, panel)
	rounded(orb, 56)
	create("UIGradient", { Rotation = 90, Color = ColorSequence.new(acc, acc:Lerp(Color3.fromRGB(20, 22, 36), 0.6)) }, orb)
	create("UIStroke", { Color = acc:Lerp(Color3.new(1, 1, 1), 0.4), Thickness = 3 }, orb)
	makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = o.Icon, TextSize = 54 }, orb)
	if o.Badge then
		local badge = makeLabel({ Size = UDim2.new(0, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 154), Text = o.Badge, TextSize = 10, Font = Enum.Font.GothamBold, TextWrapped = false, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(196, 84, 72) }, panel)
		rounded(badge, 10)
		create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, badge)
	end
	makeLabel({ Size = UDim2.new(1, -24, 0, 26), Position = UDim2.new(0, 12, 0, 180), Text = o.Name .. ((o.Owned and o.Ribbon) and ("  " .. o.Ribbon) or ""), TextSize = 17, Font = Enum.Font.GothamBlack, TextWrapped = true, TextColor3 = Color3.fromRGB(255, 236, 180) }, panel)
	makeLabel({ Size = UDim2.new(1, -24, 0, 110), Position = UDim2.new(0, 12, 0, 210), Text = o.Desc or "", TextSize = 12, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(190, 196, 220) }, panel)
	if o.Pips then
		makeLabel({ Size = UDim2.new(1, -24, 0, 20), Position = UDim2.new(0, 12, 1, -112), Text = o.Pips, TextSize = 13, RichText = true, TextWrapped = false }, panel)
	end
	if o.Status or o.Timer then
		local st = makeLabel({ Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 1, -90), Text = o.Status or "", TextSize = 12, TextWrapped = false, TextColor3 = Color3.fromRGB(120, 255, 140) }, panel)
		if o.Timer then table.insert(SHOP.Timers, { st, o.Timer }) end
	end
	local b = o.Btn
	local side = o.Prev or o.OddsKind
	local buy = makeButton({
		Size = side and UDim2.new(0.62, -14, 0, 46) or UDim2.new(1, -24, 0, 46), Position = side and UDim2.new(0.38, 2, 1, -60) or UDim2.new(0, 12, 1, -60),
		Text = b[1], TextSize = 15, Font = Enum.Font.GothamBlack, BackgroundColor3 = b[2], Active = b[3] ~= nil, AutoButtonColor = b[3] ~= nil,
	}, panel, b[3])
	rounded(buy, 23)
	if o.OddsKind then
		rounded(makeButton({ Size = UDim2.new(0.38, -14, 0, 46), Position = UDim2.new(0, 12, 1, -60), Text = "📊 Odds", TextSize = 12, BackgroundColor3 = Color3.fromRGB(58, 70, 124) }, panel, function()
			player:SetAttribute("OddsKind", o.OddsKind)
			player:SetAttribute("OddsOpen", os.clock())
		end), 23)
	end
	if o.Prev then
		rounded(makeButton({ Size = UDim2.new(0.38, -14, 0, 46), Position = UDim2.new(0, 12, 1, -60), Text = "👀 Preview", TextSize = 12, BackgroundColor3 = Color3.fromRGB(58, 70, 124) }, panel, o.Prev), 23)
	end
end

function SHOP.ProdCard(parent, order, key)
	local def = Config.Shop.Products[key]
	local label, color = shopButtonLabel(def.ProductId)
	local o = { Id = "P:" .. key, Icon = def.Icon or "🎁", Name = def.Name, Desc = def.Desc, Acc = SHOP.Acc[def.Category] or SHOP.Acc.Rec, Badge = def.Badge,
		Btn = { label, color, function() Remotes.Shop:FireServer("Buy", "Product", key) end } }
	if def.PaidRandom then -- 유료 랜덤 아이템: "Odds" 버튼으로 확률을 보여 주고, 지역 제한이 걸린 계정은 살 수 없다
		o.OddsKind = def.OddsKind
		if player:GetAttribute("PaidRandomRestricted") == true then o.Btn = { "Not available in your region", GRAY } end
	end
	local tier = def.Tier
	if tier then
		local lv, pips = SHOP.Level(tier.Group), {}
		for i = 1, tier.Steps do
			pips[i] = string.format("<font color='%s'>%s</font>", i <= lv and "#ffd24a" or (i <= tier.Step and "#e8ecff" or "#5c627e"), i <= tier.Step and "★" or "☆")
		end
		o.Owned = tier.Step <= lv
		o.Pips = table.concat(pips) .. string.format("  <font color='#8a90aa' size='10'>Step %d/%d · %s</font>", tier.Step, tier.Steps, o.Owned and "Owned" or (tier.Step == lv + 1 and "Next step" or "Higher step"))
		if o.Owned then o.Btn = { "✔ Owned", GRAY } end
	end
	for g, attr in pairs(SHOP.Boost) do
		if def.Grant[g] then o.Timer = attr end
	end
	local stack = def.Grant.TrainSlot and "TrainSlotBonus" or (def.Grant.Bag and "BagBonus")
	if stack then
		local n = (player:GetAttribute(stack) or 0) - (player:GetAttribute("Vip") == true and (def.Grant.Bag and Config.Shop.Vip.Bag or Config.Shop.Vip.TrainSlots) or 0)
		if n > 0 then o.Status = "Owned +" .. n end
	end
	SHOP.Card(parent, order, o)
end

function SHOP.CosCard(parent, order, k, key)
	local kind, item = k[1], Config[k[2]][key]
	local owned = player:GetAttribute(kind .. "Owned_" .. key) == true
	local equipped = player:GetAttribute(kind) == key
	local pk = type(item.Unlock) == "table" and item.Unlock.Product
	local def = pk and Config.Shop.Products[pk]
	local o = { Id = kind .. ":" .. key, Icon = k[3], Name = item.Name, Acc = item.Color:Lerp(Color3.fromRGB(40, 44, 70), 0.3), Badge = def and def.Badge, Owned = owned,
		Ribbon = equipped and "★ Equipped", Desc = owned and "Cosmetic only, no stats · visible to other players" or ("🔒 " .. auraUnlockText(item)),
		Prev = function() SHOP.Preview(kind, key, item.Name) end }
	if owned then
		o.Btn = { equipped and "Unequip" or "Equip", equipped and RED or GREEN, function()
			if kind == "Aura" then Remotes.Shop:FireServer("Aura", equipped and "" or key) else Remotes.Shop:FireServer("Cosmetic", kind, equipped and "" or key) end
		end }
	elseif def then
		local label, color = shopButtonLabel(def.ProductId)
		o.Btn = { label, color, function() Remotes.Shop:FireServer("Buy", "Product", pk) end }
	else
		o.Btn = { "🔒 Locked", GRAY }
	end
	SHOP.Card(parent, order, o)
end

function SHOP.Sig()
	local now, s = os.time(), { SHOP.Cat, SHOP.Cols(), SHOP.Level("IdleMult"), SHOP.Level("IdleCap"), tostring(player:GetAttribute("Vip")), tostring(player:GetAttribute("PaidRandomRestricted")), player:GetAttribute("TrainSlotBonus"), player:GetAttribute("BagBonus") }
	for _, attr in pairs(SHOP.Boost) do s[#s + 1] = (player:GetAttribute(attr) or 0) > now and 1 or 0 end
	for _, k in ipairs(SHOP.Kinds) do
		s[#s + 1] = player:GetAttribute(k[1])
		for _, key in ipairs(Config[k[2]].Order) do s[#s + 1] = player:GetAttribute(k[1] .. "Owned_" .. key) == true and 1 or 0 end
	end
	return table.concat(s, "|")
end

function SHOP.Cols()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize.X < 760 and 2 or 3
end

function SHOP.Build()
	local C = SHOP.Content
	clearChildren(C)
	SHOP.Timers, SHOP.Items = {}, {}
	local pass = Config.Shop.Passes.VIP
	local vip = player:GetAttribute("Vip") == true
	local LEFT, RIGHT = 150, 270
	-- 왼쪽: VIP 칸 (누르면 오른쪽에 혜택) + 카테고리 세로 버튼
	local side = create("Frame", { Size = UDim2.new(0, LEFT, 1, 0), BackgroundTransparency = 1 }, C)
	local label, color = shopButtonLabel(pass.PassId)
	local vipO = { Id = "VIP", Icon = "👑", Name = pass.Name, Acc = Color3.fromRGB(230, 180, 80), Owned = vip, Ribbon = vip and "✔ Active" or nil,
		Desc = table.concat(pass.Benefits or {}, "\n"),
		Btn = vip and { "✔ Owned", GRAY } or { "👑 " .. label, pass.PassId > 0 and GREEN or Color3.fromRGB(200, 140, 40), function() Remotes.Shop:FireServer("Buy", "Pass", "VIP") end } }
	SHOP.Items.VIP = vipO
	local vipCard = create("TextButton", { Size = UDim2.new(1, 0, 0, 86), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Text = "", AutoButtonColor = true }, side)
	rounded(vipCard, 14)
	create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(120, 92, 36), Color3.fromRGB(40, 34, 60)) }, vipCard)
	create("UIStroke", { Color = SHOP.Sel == "VIP" and Color3.new(1, 1, 1) or Color3.fromRGB(230, 190, 100), Thickness = SHOP.Sel == "VIP" and 2.5 or 1.5, Transparency = 0.2 }, vipCard)
	makeLabel({ Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 0, 4), Text = "👑", TextSize = 34 }, vipCard)
	makeLabel({ Size = UDim2.new(1, -8, 0, 32), Position = UDim2.new(0, 4, 0, 48), Text = pass.Name .. (vip and "\n✔ Active" or ""), TextSize = 12, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 224, 140) }, vipCard)
	vipCard.Activated:Connect(function()
		SHOP.Sel = "VIP"
		SHOP.LastSig = nil
		SHOP.Refresh()
	end)
	for i, cat in ipairs(Config.Shop.Categories) do
		local on = cat.Key == SHOP.Cat
		local btn = makeButton({
			Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 0, 96 + (i - 1) * 52), Text = cat.Name, TextSize = 13, Font = on and Enum.Font.GothamBlack or Enum.Font.GothamBold,
			BackgroundColor3 = on and SHOP.Acc[cat.Key] or Color3.fromRGB(34, 38, 58), TextColor3 = on and Color3.new(1, 1, 1) or Color3.fromRGB(170, 176, 200),
		}, side, function()
			SHOP.Cat, SHOP.Top, SHOP.Sel = cat.Key, true, nil
			SHOP.LastSig = nil
			SHOP.Refresh()
		end)
		rounded(btn, 22)
	end

	-- 가운데: 상품 구슬 칸
	local mid = create("ScrollingFrame", {
		Size = UDim2.new(1, -(LEFT + RIGHT + 24), 1, 0), Position = UDim2.new(0, LEFT + 12, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 5, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, C)
	SHOP.Grid = mid
	create("UIGridLayout", { CellSize = UDim2.new(0, 120, 0, 124), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, mid)
	create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }, mid)
	local n = 0
	if SHOP.Cat == "Deco" then
		for _, k in ipairs(SHOP.Kinds) do
			for _, key in ipairs(Config[k[2]].Order) do
				n += 1
				SHOP.CosCard(mid, n, k, key)
			end
		end
	else
		for _, key in ipairs(Config.Shop.ProductOrder) do
			local def = Config.Shop.Products[key]
			if SHOP.Cat == "Rec" and def.Featured or def.Category == SHOP.Cat then
				n += 1
				local cos
				for _, k in ipairs(SHOP.Kinds) do
					if def.Grant[k[1]] then cos = k; SHOP.CosCard(mid, n, k, def.Grant[k[1]]) end
				end
				if not cos then SHOP.ProdCard(mid, n, key) end
			end
		end
	end

	-- 오른쪽: 고른 상품
	local right = create("Frame", { Size = UDim2.new(0, RIGHT, 1, -30), Position = UDim2.new(1, -RIGHT, 0, 0), BackgroundTransparency = 1 }, C)
	local o = SHOP.Items[SHOP.Sel]
	if o then SHOP.Detail(right, o) end
	makeLabel({ Size = UDim2.new(0, RIGHT, 0, 26), Position = UDim2.new(1, -RIGHT, 1, -26), Text = "The Shop sells time savers, conveniences, and cosmetics. You can reach every level of progress without spending, and gear must be earned in the field.", TextSize = 8, TextWrapped = true, TextColor3 = Color3.fromRGB(130, 136, 164) }, C)
end

function SHOP.Refresh()
	if not SHOP.Panel.Visible then return end
	local sig = SHOP.Sig()
	if sig ~= SHOP.LastSig then
		SHOP.LastSig = sig
		local y = (SHOP.Top or not SHOP.Grid) and 0 or SHOP.Grid.CanvasPosition.Y
		SHOP.Top = nil
		local ok, err = pcall(SHOP.Build)
		if not ok then warn("[Shop] " .. tostring(err)) end
		task.defer(function() if SHOP.Grid then SHOP.Grid.CanvasPosition = Vector2.new(0, y) end end)
	end
	local now = os.time()
	for _, t in ipairs(SHOP.Timers) do
		local left = (player:GetAttribute(t[2]) or 0) - now
		if t[1].Parent then t[1].Text = left > 0 and ("⏳ Active " .. Config.FormatDuration(left)) or "" end
	end
end

function SHOP.Open()
	if SHOP.Panel.Visible then
		SHOP.Panel.Visible = false
		return
	end
	local hud = playerGui:FindFirstChild("HUD")
	local menu = hud and hud:FindFirstChild("MenuPanel")
	if menu then menu.Visible = false end -- 큰 창은 한 번에 하나
	SHOP.Panel.Visible = true
	SHOP.LastSig = nil
	SHOP.Refresh()
end
player:GetAttributeChangedSignal("OpenShop"):Connect(SHOP.Open)

for _, cosmeticKind in ipairs({ "Aura", "Banner", "Mount" }) do
	player:GetAttributeChangedSignal(cosmeticKind):Connect(function()
		if SHOP.Panel.Visible then SHOP.Refresh() end
	end)
end

task.spawn(function()
	while true do
		task.wait(1)
		if SHOP.Panel.Visible then SHOP.Refresh() end
	end
end)

local refreshQueued = false
player.AttributeChanged:Connect(function()
	if not SHOP.Panel.Visible or refreshQueued then return end
	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		if SHOP.Panel.Visible then SHOP.Refresh() end
	end)
end)
