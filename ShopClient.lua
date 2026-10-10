-- ShopClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: ShopClient)
-- 🎁 상점 창. PlayerClient 가 너무 커져서 분리했다.
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
		uiScale.Scale = math.clamp(math.min(viewport.X / 1100, viewport.Y / 720), 0.55, 1)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

-- 미리보기 알림 (HUD 의 토스트와 같은 모양)
local toastLabel = makeLabel({
	Name = "ToastLabel", Size = UDim2.new(0, 400, 0, 74), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -430, 1, -250),
	BackgroundColor3 = Color3.fromRGB(16, 18, 30), BackgroundTransparency = 0.08, Font = Enum.Font.GothamBold, TextSize = 16,
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
create("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 1.5, Transparency = 0.35 }, SHOP.Panel)
makeLabel({
	Size = UDim2.new(1, -120, 0, 36), Position = UDim2.new(0, 16, 0, 8),
	Text = "🎁 상점", Font = Enum.Font.GothamBlack, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left,
}, SHOP.Panel)
makeButton({
	Size = UDim2.new(0, 64, 0, 28), Position = UDim2.new(1, -76, 0, 10), Text = "닫기", TextSize = 13, BackgroundColor3 = GRAY,
}, SHOP.Panel, function()
	SHOP.Panel.Visible = false
end)
SHOP.Content = create("ScrollingFrame", {
	Size = UDim2.new(1, -24, 1, -60), Position = UDim2.new(0, 12, 0, 48),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, SHOP.Panel)
create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, SHOP.Content)

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

SHOP.Cat = "Rec"
SHOP.Timers = {}
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
	toast(string.format("👀 [%s] 미리보기 5초!", name))
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

function SHOP.Card(parent, order, o)
	local acc, mute = o.Acc, o.Owned and not o.Prev
	local card = makePanel({ Size = UDim2.new(0, 100, 0, 190), LayoutOrder = order, BackgroundColor3 = Color3.fromRGB(28, 31, 48) }, parent)
	local stroke = create("UIStroke", { Color = acc, Thickness = 1.2, Transparency = mute and 0.85 or 0.6 }, card)
	card.MouseEnter:Connect(function() stroke.Transparency = 0.15 end)
	card.MouseLeave:Connect(function() stroke.Transparency = mute and 0.85 or 0.6 end)
	local dark, fade = acc:Lerp(Color3.fromRGB(28, 31, 48), 0.7), mute and 0.5 or 0
	local head = create("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = fade, BorderSizePixel = 0 }, card)
	rounded(head, 12)
	create("UIGradient", { Rotation = 90, Color = ColorSequence.new(acc, dark) }, head)
	create("Frame", { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 52), BackgroundColor3 = dark, BackgroundTransparency = fade, BorderSizePixel = 0 }, card)
	makeLabel({ Size = UDim2.new(1, 0, 1, -6), Text = o.Icon, TextSize = 36, TextTransparency = fade }, head)
	if o.Owned then
		makeLabel({ Size = UDim2.new(0, 80, 0, 18), Position = UDim2.new(0, 10, 0, 8), Text = o.Ribbon or "✔ 보유", TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(178, 238, 190), TextXAlignment = Enum.TextXAlignment.Left }, card)
	end
	if o.Badge then
		local badge = makeLabel({ Size = UDim2.new(0, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Text = o.Badge, TextSize = 12, Font = Enum.Font.GothamBold, TextWrapped = false, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(196, 84, 72) }, card)
		rounded(badge, 10)
		create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, badge)
	end
	makeLabel({ Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 0, 68), Text = o.Name, TextSize = 15, Font = Enum.Font.GothamBold, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = mute and Color3.fromRGB(150, 156, 180) or Color3.fromRGB(240, 242, 250) }, card)
	makeLabel({ Size = UDim2.new(1, -20, 0, 32), Position = UDim2.new(0, 10, 0, 91), Text = o.Desc, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(160, 166, 192) }, card)
	if o.Pips then
		makeLabel({ Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 0, 126), Text = o.Pips, TextSize = 14, RichText = true, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left }, card)
	end
	if o.Status or o.Timer then
		local st = makeLabel({ Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 0, 126), Text = o.Status or "", TextSize = 13, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(120, 255, 140) }, card)
		if o.Timer then table.insert(SHOP.Timers, { st, o.Timer }) end
	end
	local b = o.Btn
	makeButton({
		Size = o.Prev and UDim2.new(0.62, -14, 0, 30) or UDim2.new(1, -20, 0, 30), Position = o.Prev and UDim2.new(0.38, 4, 0, 152) or UDim2.new(0, 10, 0, 152),
		Text = b[1], TextSize = 14, BackgroundColor3 = b[2], Active = b[3] ~= nil, AutoButtonColor = b[3] ~= nil,
	}, card, b[3])
	if o.Prev then
		makeButton({ Size = UDim2.new(0.38, -10, 0, 30), Position = UDim2.new(0, 10, 0, 152), Text = "👀 미리보기", TextSize = 13, BackgroundColor3 = Color3.fromRGB(58, 70, 124) }, card, o.Prev)
	end
end

function SHOP.ProdCard(parent, order, key)
	local def = Config.Shop.Products[key]
	local label, color = shopButtonLabel(def.ProductId)
	local o = { Icon = def.Icon or "🎁", Name = def.Name, Desc = def.Desc, Acc = SHOP.Acc[def.Category] or SHOP.Acc.Rec, Badge = def.Badge,
		Btn = { label, color, function() Remotes.Shop:FireServer("Buy", "Product", key) end } }
	local tier = def.Tier
	if tier then
		local lv, pips = SHOP.Level(tier.Group), {}
		for i = 1, tier.Steps do
			pips[i] = string.format("<font color='%s'>%s</font>", i <= lv and "#ffd24a" or (i <= tier.Step and "#e8ecff" or "#5c627e"), i <= tier.Step and "★" or "☆")
		end
		o.Owned = tier.Step <= lv
		o.Pips = table.concat(pips) .. string.format("  <font color='#8a90aa' size='12'>%d/%d단계 · %s</font>", tier.Step, tier.Steps, o.Owned and "보유" or (tier.Step == lv + 1 and "다음 단계" or "상위 단계"))
		if o.Owned then o.Btn = { "✔ 보유 중", GRAY } end
	end
	for g, attr in pairs(SHOP.Boost) do
		if def.Grant[g] then o.Timer = attr end
	end
	local stack = def.Grant.TrainSlot and "TrainSlotBonus" or (def.Grant.Bag and "BagBonus")
	if stack then
		local n = (player:GetAttribute(stack) or 0) - (player:GetAttribute("Vip") == true and (def.Grant.Bag and Config.Shop.Vip.Bag or Config.Shop.Vip.TrainSlots) or 0)
		if n > 0 then o.Status = "보유 +" .. n end
	end
	SHOP.Card(parent, order, o)
end

function SHOP.CosCard(parent, order, k, key)
	local kind, item = k[1], Config[k[2]][key]
	local owned = player:GetAttribute(kind .. "Owned_" .. key) == true
	local equipped = player:GetAttribute(kind) == key
	local pk = type(item.Unlock) == "table" and item.Unlock.Product
	local def = pk and Config.Shop.Products[pk]
	local o = { Icon = k[3], Name = item.Name, Acc = item.Color:Lerp(Color3.fromRGB(40, 44, 70), 0.3), Badge = def and def.Badge, Owned = owned,
		Ribbon = equipped and "★ 착용 중", Desc = owned and "능력치 없는 꾸미기 · 다른 플레이어에게도 보여요" or ("🔒 " .. auraUnlockText(item)),
		Prev = function() SHOP.Preview(kind, key, item.Name) end }
	if owned then
		o.Btn = { equipped and "해제" or "장착", equipped and RED or GREEN, function()
			if kind == "Aura" then Remotes.Shop:FireServer("Aura", equipped and "" or key) else Remotes.Shop:FireServer("Cosmetic", kind, equipped and "" or key) end
		end }
	elseif def then
		local label, color = shopButtonLabel(def.ProductId)
		o.Btn = { label, color, function() Remotes.Shop:FireServer("Buy", "Product", pk) end }
	else
		o.Btn = { "🔒 잠김", GRAY }
	end
	SHOP.Card(parent, order, o)
end

function SHOP.Sig()
	local now, s = os.time(), { SHOP.Cat, SHOP.Cols(), SHOP.Level("IdleMult"), SHOP.Level("IdleCap"), tostring(player:GetAttribute("Vip")), player:GetAttribute("TrainSlotBonus"), player:GetAttribute("BagBonus") }
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
	local C, cols = SHOP.Content, SHOP.Cols()
	clearChildren(C)
	SHOP.Timers = {}
	local pass = Config.Shop.Passes.VIP
	local vip = player:GetAttribute("Vip") == true
	local hero = makePanel({ Size = UDim2.new(1, -10, 0, 118), LayoutOrder = 1, BackgroundColor3 = Color3.new(1, 1, 1) }, C)
	create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(30, 34, 64), Color3.fromRGB(104, 82, 36)) }, hero)
	create("UIStroke", { Color = Color3.fromRGB(230, 190, 100), Thickness = 1.5, Transparency = 0.45 }, hero)
	local crown = create("Frame", { Size = UDim2.new(0, 76, 0, 76), Position = UDim2.new(0, 16, 0.5, -38), BackgroundColor3 = Color3.fromRGB(255, 214, 102), BackgroundTransparency = 0.82, BorderSizePixel = 0 }, hero)
	rounded(crown, 38)
	makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "👑", TextSize = 48 }, crown)
	makeLabel({ Size = UDim2.new(1, -320, 0, 28), Position = UDim2.new(0, 108, 0, 12), Text = pass.Name .. (vip and "  ✔ 이용 중" or ""), TextSize = 22, Font = Enum.Font.GothamBlack, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 224, 140) }, hero)
	local chips = create("Frame", { Size = UDim2.new(1, -330, 0, 60), Position = UDim2.new(0, 108, 0, 48), BackgroundTransparency = 1 }, hero)
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	for i, text in ipairs(pass.Benefits or {}) do
		local chip = makeLabel({ Size = UDim2.new(0, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Text = text, TextSize = 13, TextWrapped = false, BackgroundTransparency = 0.86, BackgroundColor3 = Color3.fromRGB(255, 224, 140), TextColor3 = Color3.fromRGB(255, 232, 170) }, chips)
		rounded(chip, 12)
		create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, chip)
	end
	local label, color = shopButtonLabel(pass.PassId)
	makeButton({
		Size = UDim2.new(0, 170, 0, 48), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), TextSize = 16,
		Text = vip and "✔ 보유 중" or ("👑 " .. label), BackgroundColor3 = vip and GRAY or (pass.PassId > 0 and GREEN or Color3.fromRGB(200, 140, 40)),
	}, hero, function()
		if not vip then Remotes.Shop:FireServer("Buy", "Pass", "VIP") end
	end)

	local row = create("Frame", { Size = UDim2.new(1, -10, 0, 34), LayoutOrder = 2, BackgroundTransparency = 1 }, C)
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for i, cat in ipairs(Config.Shop.Categories) do
		local on = cat.Key == SHOP.Cat
		makeButton({
			Size = UDim2.new(0, 112, 0, 34), LayoutOrder = i, Text = cat.Name, TextSize = 14, Font = on and Enum.Font.GothamBlack or Enum.Font.GothamBold,
			BackgroundColor3 = on and SHOP.Acc[cat.Key] or Color3.fromRGB(38, 42, 64), TextColor3 = on and Color3.new(1, 1, 1) or Color3.fromRGB(170, 176, 200),
		}, row, function()
			SHOP.Cat, SHOP.Top = cat.Key, true
			SHOP.Refresh()
		end)
	end

	local cw = math.floor((826 - 8 * (cols - 1)) / cols) - 1
	local grid = create("Frame", { Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, BackgroundTransparency = 1 }, C)
	create("UIGridLayout", { CellSize = UDim2.new(0, cw, 0, 190), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local n = 0
	if SHOP.Cat == "Deco" then
		for _, k in ipairs(SHOP.Kinds) do
			for _, key in ipairs(Config[k[2]].Order) do
				n += 1
				SHOP.CosCard(grid, n, k, key)
			end
		end
	else
		for _, key in ipairs(Config.Shop.ProductOrder) do
			local def = Config.Shop.Products[key]
			if SHOP.Cat == "Rec" and def.Featured or def.Category == SHOP.Cat then
				n += 1
				local cos
				for _, k in ipairs(SHOP.Kinds) do
					if def.Grant[k[1]] then cos = k; SHOP.CosCard(grid, n, k, def.Grant[k[1]]) end
				end
				if not cos then SHOP.ProdCard(grid, n, key) end
			end
		end
	end
	makeLabel({ Size = UDim2.new(1, -10, 0, 36), LayoutOrder = 4, Text = "상점은 시간을 줄여주는 것과 편의, 꾸미기를 팔아요. 돈을 쓰지 않아도 모든 성장에 도달할 수 있고, 장비는 필드에서 직접 얻어야 해요.", TextSize = 12, TextColor3 = Color3.fromRGB(130, 136, 164) }, C)
end

function SHOP.Refresh()
	if not SHOP.Panel.Visible then return end
	local sig = SHOP.Sig()
	if sig ~= SHOP.LastSig then
		SHOP.LastSig = sig
		local y = SHOP.Top and 0 or SHOP.Content.CanvasPosition.Y
		SHOP.Top = nil
		local ok, err = pcall(SHOP.Build)
		if not ok then warn("[Shop] " .. tostring(err)) end
		task.defer(function() SHOP.Content.CanvasPosition = Vector2.new(0, y) end)
	end
	local now = os.time()
	for _, t in ipairs(SHOP.Timers) do
		local left = (player:GetAttribute(t[2]) or 0) - now
		if t[1].Parent then t[1].Text = left > 0 and ("⏳ 적용 중 " .. Config.FormatDuration(left)) or "" end
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
