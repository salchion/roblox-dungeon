-- InventoryTabUI (StarterPlayer > StarterPlayerScripts 안의 ModuleScript, 이름: InventoryTabUI)
-- 메뉴(B) > Character > Gear 탭: 장비 칸 6개 + 가방 목록 + 상세 창을 그린다.
-- PlayerClient 가 너무 커져서(Studio 스크립트 한도 200KB) 이 부분만 따로 뺐다. 필요한 것은 Init(env) 로 넘겨 받는다.
--   env: player, create, rounded, makeLabel, makeButton, GREEN, RED, GRAY, settings, menuContent, newRow, rowText, hex, refreshMenu(함수)

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))

local InventoryTab = {}
local upgradeAnchor -- 지금 화면의 장비 강화 블록 (결과 연출 위치)

function InventoryTab.Init(env)
local player, create, rounded = env.player, env.create, env.rounded
local makeLabel, makeButton = env.makeLabel, env.makeButton
local GREEN, RED, GRAY = env.GREEN, env.RED, env.GRAY
local settings, menuContent = env.settings, env.menuContent
local newRow, rowText, hex = env.newRow, env.rowText, env.hex
local function refreshMenu() env.refreshMenu() end

-- 장비 강화 결과 연출: 강화 블록 자리에 "SUCCESS! / FAILED" 가 크게 튀어나왔다 사라진다 (메뉴가 다시 그려져도 사라지지 않게 따로 띄운다)
upgradeAnchor = nil
local fxGui = Instance.new("ScreenGui")
fxGui.Name = "GearUpgradeFx"
fxGui.ResetOnSpawn, fxGui.IgnoreGuiInset, fxGui.DisplayOrder = false, true, 40
fxGui.Parent = player:WaitForChild("PlayerGui")
Remotes.Gear.OnClientEvent:Connect(function(action, result)
	if action ~= "Result" or type(result) ~= "table" or result.Roll or not upgradeAnchor or not upgradeAnchor.Parent then return end
	if upgradeAnchor.AbsoluteSize.X < 10 then return end
	local ok = result.Ok == true
	local center = upgradeAnchor.AbsolutePosition + upgradeAnchor.AbsoluteSize / 2
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromOffset(320, 60)
	label.Position = UDim2.fromOffset(center.X, center.Y)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 34
	label.Text = ok and "✨ SUCCESS!" or "💥 FAILED"
	label.TextColor3 = ok and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(255, 110, 100)
	label.TextStrokeTransparency = 0.1
	label.Parent = fxGui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if not ok then -- 실패: 좌우로 흔들린다
		task.spawn(function()
			for i = 1, 6 do
				label.Position = UDim2.fromOffset(center.X + (i % 2 == 0 and 1 or -1) * (10 - i), center.Y)
				task.wait(0.03)
			end
			label.Position = UDim2.fromOffset(center.X, center.Y)
		end)
	end
	task.delay(0.55, function()
		TweenService:Create(label, TweenInfo.new(0.45), { Position = UDim2.fromOffset(center.X, center.Y - 40), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	game:GetService("Debris"):AddItem(label, 1.1)
end)

-- 위쪽 정보 줄: 가방 / 정수 / 골드 (장비 강화에 골드를 쓰는데 골드가 안 보였다). 골드가 바뀌면 장비 탭이 열려 있는 동안 바로 따라간다
local infoState
local function infoText(state)
	local goldDigits = tostring(math.floor(player:GetAttribute("Gold") or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return string.format("🎒 Bag <b>%d / %d</b>    ✨ Essence <font color='#9ad7ff'><b>%d</b></font>    💰 <font color='#ffd966'><b>%s</b></font>", state.BagCount, state.Capacity, state.Essence, goldDigits)
end
player:GetAttributeChangedSignal("Gold"):Connect(function()
	local info = settings.MenuInfo
	if info and info.Text ~= "" and infoState then info.Text = infoText(infoState) end -- (다른 탭에서는 비어 있으니 건드리지 않는다)
end)

local function buildInventoryTab(state)
	if not state then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>Loading bag...</font>")
		return
	end

	infoState = state
	if settings.MenuInfo then settings.MenuInfo.Text = infoText(state) end

	local equipped, bag, setCounts, byId = {}, {}, {}, {}
	for _, item in ipairs(state.Items) do
		byId[item.Id] = item
		if item.Equipped then
			equipped[item.Slot] = item
			if item.Set then
				setCounts[item.Set] = (setCounts[item.Set] or 0) + 1
			end
		else
			table.insert(bag, item)
		end
	end
	local selectedId = menuContent:GetAttribute("SelectedItem")
	local selected = selectedId and byId[selectedId]
	if not selected then
		selected = equipped.Armor or equipped.Helmet or equipped.Gloves or equipped.Boots or equipped.Ring or equipped.Necklace or bag[1]
	end

	local function rarityOutline(frame, rarity, thick)
		local color = Config.Gear.RarityColors[rarity]
		local stroke = create("UIStroke", { Color = color, Thickness = thick or ({ 2, 2, 3, 3.5, 4.5 })[rarity], ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
		if rarity >= 3 then
			TweenService:Create(stroke, TweenInfo.new(rarity >= 4 and 0.9 or 1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = rarity >= 4 and 0.55 or 0.4 }):Play()
		end
		if rarity >= 5 then
			local gradient = create("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 220, 80)),
					ColorSequenceKeypoint.new(0.4, Color3.fromRGB(90, 255, 120)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 220, 255)),
					ColorSequenceKeypoint.new(0.8, Color3.fromRGB(150, 100, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
				}),
			}, stroke)
			TweenService:Create(gradient, TweenInfo.new(2.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
		end
		return stroke
	end

	local function setPips(count)
		return string.rep("●", math.min(count, 3)) .. string.rep("○", math.max(0, 3 - count))
	end
	-- 세트 장비 표시: 세트색 배경 틴트 + 안쪽 테두리 + 구역 리본 (2부위 이상 맞추면 더 밝고 숨 쉬듯 빛남)
	local function setDecor(tile, setKey, pieces, ribbonPos, ribbonSize, radius)
		local def = setKey and Config.Sets[setKey]
		if not def then return end
		local active = (pieces or 0) >= 2
		local tint = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = def.Color, BorderSizePixel = 0, ZIndex = 0, Active = false }, tile)
		rounded(tint, radius or 8)
		create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, active and 0.4 or 0.62), NumberSequenceKeypoint.new(1, active and 0.8 or 0.92) }) }, tint)
		local inner = create("Frame", { Size = UDim2.new(1, -6, 1, -6), Position = UDim2.new(0, 3, 0, 3), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Active = false }, tile)
		rounded(inner, (radius or 8) - 2)
		local stroke = create("UIStroke", { Color = def.Color, Thickness = active and 2 or 1.5, Transparency = active and 0 or 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inner)
		if active then
			TweenService:Create(stroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 }):Play()
		end
		local pill = create("Frame", { Size = ribbonSize, Position = ribbonPos, BackgroundColor3 = def.Color, BorderSizePixel = 0, ZIndex = 3, Active = false }, tile)
		rounded(pill, 6)
		makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = def.Zone and ("Z" .. def.Zone) or "Set", TextSize = 10, TextColor3 = Color3.fromRGB(20, 20, 30), Font = Enum.Font.GothamBlack, TextWrapped = false, ZIndex = 4 }, pill)
	end

	local SLOT_ICONS = { Armor = "🛡", Gloves = "🧤", Boots = "👢", Weapon = "🔫", Helmet = "⛑", Ring = "💍", Necklace = "📿" }

	-- 장착 방식 줄: "최강 장비"와 가진 세트가 한 줄에 칩으로 나란히 있고, 지금 쓰는 방식에 ✔ 가 붙는다. 칩을 누르면 그 방식으로 바로 갈아 끼운다 (이미 쓰는 칩을 다시 누르면 새로 얻은 장비까지 다시 맞춘다).
	-- (예전엔 "최고 장비 자동 장착" 버튼과 "세트 장착" 칩이 따로 있어서, 어느 쪽으로 껴졌는지 오락가락했다)
	do
		local owned = {} -- [세트] = 가진 부위 수 (가방 + 착용)
		local slotsSeen = {}
		for _, item in ipairs(state.Items) do
			if item.Set and Config.Sets[item.Set] then
				slotsSeen[item.Set] = slotsSeen[item.Set] or {}
				if not slotsSeen[item.Set][item.Slot] then
					slotsSeen[item.Set][item.Slot] = true
					owned[item.Set] = (owned[item.Set] or 0) + 1
				end
			end
		end
		local mode = state.EquipMode or "Best"
		local setRow = newRow(44, Color3.fromRGB(24, 26, 40))
		makeLabel({ Size = UDim2.new(0, 84, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = "Equip mode", TextSize = 12, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(225, 196, 118), TextXAlignment = Enum.TextXAlignment.Left }, setRow)
		-- 오른쪽 끝: 자동 분해 / 정리 (한 줄로 합쳐서 장비 칸이 한 화면에 들어오게)
		local scrapButton = makeButton({ Size = UDim2.new(0, 196, 0, 30), Position = UDim2.new(1, -314, 0.5, -15), RichText = true, TextWrapped = true, Text = "♻ <font size='9' color='#cfe0ff'>Auto-salvage</font>\n" .. Config.Inventory.AutoScrapNames[state.AutoScrap], TextSize = 10, BackgroundColor3 = Color3.fromRGB(70, 110, 220) }, setRow, function() -- (자동 분해 규칙이 버튼에 바로 보인다. 누르면 다음 규칙)
			Remotes.Inventory:FireServer("AutoScrap", (state.AutoScrap + 1) % 5)
		end)
		rounded(scrapButton, 14)
		local cleanButton = makeButton({ Size = UDim2.new(0, 108, 0, 28), Position = UDim2.new(1, -112, 0.5, -14), Text = "🧹 Smart Clean", TextSize = 11, BackgroundColor3 = Color3.fromRGB(176, 76, 84) }, setRow, function()
			Remotes.Inventory:FireServer("SmartClean")
		end)
		rounded(cleanButton, 14)
		local strip = create("ScrollingFrame", {
			Size = UDim2.new(1, -92 - 328, 1, -4), Position = UDim2.new(0, 92, 0, 2), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 3, ScrollingDirection = Enum.ScrollingDirection.X, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
		}, setRow)
		create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, strip)
		local function modeChip(order, key, text, color, active, disabled)
			local chip = makeButton({
				Size = UDim2.new(0, 0, 0, 32), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, RichText = true, TextSize = 12,
				Text = (active and "<font color='#78ff8c'>✔</font> " or "") .. text,
				BackgroundColor3 = active and color:Lerp(Color3.fromRGB(26, 28, 42), 0.45) or Color3.fromRGB(34, 37, 54),
			}, strip, function()
				if disabled then return end
				Remotes.Inventory:FireServer(key == "Best" and "AutoEquip" or "EquipSet", key)
			end)
			rounded(chip, 16)
			create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, chip)
			create("UIStroke", { Color = active and Color3.fromRGB(255, 255, 255) or color, Thickness = active and 2 or 1, Transparency = active and 0.1 or 0.55, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, chip)
		end
		-- 두 갈래로 나눈다: [⚡ 최강 장비] [🛡 세트 장비]. 세트 장비를 고른 때만 오른쪽에 가진 세트 칩이 나타난다 (세트 효과가 최강 장비 옆에 섞여 보이지 않게)
		local inSetMode = mode ~= "Best" and Config.Sets[mode] ~= nil
		local bestSet, bestScore = nil, -1
		for i, key in ipairs(Config.Sets.ZoneKeys) do
			if owned[key] and (owned[key] * 100 + i) > bestScore then bestSet, bestScore = key, owned[key] * 100 + i end
		end
		modeChip(0, "Best", "⚡ Best gear", Color3.fromRGB(80, 200, 130), not inSetMode)
		modeChip(1, bestSet or "Best", bestSet and "🛡 Set gear" or "🛡 Set gear <font size='10'>(no set yet)</font>", Color3.fromRGB(120, 150, 255), inSetMode, not bestSet)
		if inSetMode then
			makeLabel({ Size = UDim2.new(0, 14, 0, 32), LayoutOrder = 2, Text = "›", TextSize = 20, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(150, 156, 190) }, strip)
			for i, key in ipairs(Config.Sets.ZoneKeys) do
				if owned[key] then
					local def = Config.Sets[key]
					local worn = setCounts[key] or 0
					local effectOn = def.Zone and player:GetAttribute("AugOnZ_" .. def.Zone) == true
					modeChip(2 + i, key, string.format("%s %s  <font color='#ffe9a0'>%s</font>%s", def.Icon or "★", def.Name, setPips(math.min(worn, 3)), effectOn and "  <font color='#78ff8c'>● ON</font>" or ""), def.Color, mode == key)
				end
			end
		end
	end

	local top = newRow(372, Color3.fromRGB(26, 31, 58)) -- (예전 470: 아래쪽 칸이 잘려서 스크롤해야 했다)
	rounded(top, 18)
	create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 124, 150)) }, top)
	create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 1.3, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, top)

	-- 캐릭터 무대: 가장 높은 장비 등급 색으로 은은하게 빛나는 원 + 바닥 받침 (캐릭터 뒤)
	do
		local best = 0
		for _, item in pairs(equipped) do best = math.max(best, item.Rarity or 0) end
		local glow = best > 0 and Config.Gear.RarityColors[best] or Color3.fromRGB(255, 205, 110)
		local stage = create("Frame", { Size = UDim2.new(0, 230, 0, 282), Position = UDim2.new(0, 108, 0, 8), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 1 }, top)
		rounded(stage, 16)
		create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(42, 52, 96), Color3.fromRGB(12, 14, 26)) }, stage)
		create("UIStroke", { Color = Color3.fromRGB(110, 130, 200), Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, stage)
		stage.ClipsDescendants = true
		for index, spec in ipairs({ { 260, 0.9 }, { 190, 0.82 }, { 120, 0.7 } }) do -- 바깥에서 안쪽으로 점점 진해지는 빛 번짐
			local halo = create("Frame", { Size = UDim2.new(0, spec[1], 0, spec[1]), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.46, 0), BackgroundColor3 = glow, BackgroundTransparency = spec[2], BorderSizePixel = 0, ZIndex = 1 + index }, stage)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, halo)
		end
		local floorDisc = create("Frame", { Size = UDim2.new(0, 150, 0, 22), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 252), BackgroundColor3 = glow, BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 5 }, stage)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, floorDisc)
		create("UIStroke", { Color = Color3.fromRGB(255, 225, 150), Thickness = 1.5, Transparency = 0.3 }, floorDisc)
	end

	local viewport = create("ViewportFrame", {
		Size = UDim2.new(0, 230, 0, 282), Position = UDim2.new(0, 108, 0, 8), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 8,
		Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1),
	}, top)
	local cam = create("Camera", { FieldOfView = 38 }, viewport)
	viewport.CurrentCamera = cam
	local character = player.Character
	if character then
		character.Archivable = true
		local clone = character:Clone()
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("BillboardGui") or descendant:IsA("ForceField") then
				descendant:Destroy()
			elseif descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
		clone.Parent = viewport
		local pivot = clone:GetPivot()
		local spin = settings.InvSpin or 0
		local connection
		connection = RunService.RenderStepped:Connect(function(dt)
			if not viewport:IsDescendantOf(game) then
				connection:Disconnect()
				return
			end
			spin += dt * 0.9
			settings.InvSpin = spin
			clone:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, spin, 0))
			cam.CFrame = CFrame.lookAt(pivot.Position + Vector3.new(0, 1.2, 12.5), pivot.Position + Vector3.new(0, 0.4, 0))
		end)
	end
	makeLabel({ Size = UDim2.new(0, 230, 0, 22), Position = UDim2.new(0, 108, 0, 292), Text = string.format("⚡ Power %d", player:GetAttribute("Power") or 0), TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110) }, top)

	do
		local rowsShown = 0
		for _, key in ipairs(Config.Sets.ZoneKeys) do
			local count = setCounts[key] or 0
			if count >= 2 then
				local def = Config.Sets[key]
				local bar = create("Frame", { Size = UDim2.new(0, 230, 0, 24), Position = UDim2.new(0, 108, 0, 318 + rowsShown * 26), BackgroundColor3 = def.Color, BorderSizePixel = 0 }, top)
				rounded(bar, 8)
				create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.9) }) }, bar)
				local glow = create("UIStroke", { Color = def.Color, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, bar)
				TweenService:Create(glow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 }):Play()
				makeLabel({
					Size = UDim2.new(1, -10, 1, 0), Position = UDim2.new(0, 5, 0, 0), RichText = true, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
					Text = string.format("%s <b>%s</b>  <font color='#%s'>%s</font> %d/3", def.Icon or "★", def.Name, hex(def.Color), setPips(count), count),
				}, bar)
				rowsShown += 1
			end
		end
		if rowsShown == 0 then
			makeLabel({ Size = UDim2.new(0, 230, 0, 30), Position = UDim2.new(0, 108, 0, 318), Text = "Wear 1·2·3 pieces of the same zone set → set effect tiers 4·5·6 (Set window: Y)", TextSize = 10, TextWrapped = true, TextColor3 = Color3.fromRGB(120, 124, 150) }, top)
		end
	end
	local function slotBox(slotKey, x, y)
		local item = equipped[slotKey]
		local rarity = item and item.Rarity or 0
		local box = makeButton({
			Size = UDim2.new(0, 88, 0, 76), Position = UDim2.new(0, x, 0, y), Text = "",
			BackgroundColor3 = item and Config.Gear.RarityColors[rarity]:Lerp(Color3.fromRGB(20, 22, 36), 0.78) or Color3.fromRGB(26, 27, 42), AutoButtonColor = true, ZIndex = 9,
		}, top, function()
			if slotKey == "Weapon" then
				menuContent:SetAttribute("ShowWeapons", true) -- 무기 칸: 오른쪽에 무기 10형 목록을 보여준다
				refreshMenu()
			elseif item then
				menuContent:SetAttribute("ShowWeapons", nil)
				menuContent:SetAttribute("SelectedItem", item.Id)
				refreshMenu()
			end
		end)
		rounded(box, 14)
		create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 214)) }, box)
		local function iconDisc(color, icon, tier)
			Kit.medal(box, { Size = 44, Position = UDim2.new(0.5, -22, 0, 8), Color = color, Icon = icon, TextSize = 21, Tier = tier or 0, ZIndex = 10 })
		end
		local function accentBar(color) -- 칸 아래 등급 색 막대
			local bar = create("Frame", { Size = UDim2.new(0, 44, 0, 3), Position = UDim2.new(0.5, -22, 1, -7), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 10, Active = false }, box)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
		end
		if slotKey == "Weapon" then
			local weaponLevel = player:GetAttribute("WeaponLevel") or 0
			local tier = Config.GetLookTier(weaponLevel, Config.ResolveWeaponType(weaponLevel, player:GetAttribute("WeaponType")))
			rarityOutline(box, 4, 2).Color = tier.Color
			iconDisc(tier.Color, "🔫", 2)
			makeLabel({ Size = UDim2.new(1, -8, 0, 16), Position = UDim2.new(0, 4, 1, -21), Text = Config.WeaponTypes[tier.Class].Name, TextSize = 10, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = tier.Color, Font = Enum.Font.GothamBold, ZIndex = 10 }, box)
		elseif item then
			-- 깔끔하게: 아이콘 하나 + 아래 한 줄(+강화 단계, 지금 강화 가능하면 초록 ▲). 이름은 오른쪽 상세 칸에서 본다
			-- (예전엔 잘린 이름 / 구역 리본 / 단계 배지 / 깜빡이는 초록 원이 겹쳐서 지저분했다)
			local stroke = create("UIStroke", { Color = Config.Gear.RarityColors[rarity], Thickness = rarity >= 4 and 2 or 1.5, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, box)
			if rarity >= 5 then
				local g = create("UIGradient", { Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 220, 80)),
					ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
				}) }, stroke)
				TweenService:Create(g, TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 }):Play()
			end
			iconDisc(Config.Gear.RarityColors[rarity], SLOT_ICONS[slotKey], rarity)
			local canUp = item.Level < Config.Gear.MaxLevel and (player:GetAttribute("Gold") or 0) >= Config.GetGearCost(item.Slot, item.Rarity, item.Level)
			makeLabel({ Size = UDim2.new(1, -8, 0, 16), Position = UDim2.new(0, 4, 1, -21), RichText = true, TextSize = 12, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 220, 120), ZIndex = 10,
				Text = canUp and string.format("+%d <font color='#78ff8c'>▲</font>", item.Level) or string.format("+%d", item.Level) }, box)
			local def = item.Set and Config.Sets[item.Set]
			if def then -- 세트: 왼쪽 위 작은 세트색 점 (2부위 이상이면 테두리가 생긴다)
				local dot = create("Frame", { Size = UDim2.new(0, 9, 0, 9), Position = UDim2.new(0, 7, 0, 7), BackgroundColor3 = def.Color, BorderSizePixel = 0, ZIndex = 11, Active = false }, box)
				create("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
				if (setCounts[item.Set] or 0) >= 2 then create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.2 }, dot) end
			end
			if item.Unique then
				makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(1, -18, 0, 4), Text = "★", TextSize = 12, TextColor3 = Color3.fromRGB(255, 184, 77), ZIndex = 11 }, box)
			end
		else
			create("UIStroke", { Color = Color3.fromRGB(70, 74, 96), Thickness = 1, Transparency = 0.3 }, box)
			iconDisc(Color3.fromRGB(110, 114, 140), SLOT_ICONS[slotKey])
			makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 55), Text = "Empty", TextSize = 10, TextColor3 = Color3.fromRGB(120, 120, 140), ZIndex = 10 }, box)
		end
		return box
	end
	slotBox("Helmet", 10, 8)
	slotBox("Armor", 10, 92)
	slotBox("Gloves", 10, 176)
	slotBox("Necklace", 350, 8)
	slotBox("Ring", 350, 92)
	slotBox("Boots", 350, 176)
	slotBox("Weapon", 350, 260)
	do
		local petLevel = player:GetAttribute("PetLevel") or 0
		local look = Config.Pet.Looks[player:GetAttribute("PetLook") or "Orb"] or Config.Pet.Looks.Orb
		local box = makeButton({ Size = UDim2.new(0, 88, 0, 76), Position = UDim2.new(0, 10, 0, 260), Text = "", BackgroundColor3 = petLevel > 0 and Color3.fromRGB(46, 48, 68) or Color3.fromRGB(34, 34, 48), AutoButtonColor = true }, top, function()
			player:SetAttribute("OpenPet", os.clock())
		end)
		rounded(box, 16)
		create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(160, 160, 178)) }, box)
		if petLevel > 0 then
			create("UIStroke", { Color = Color3.fromRGB(255, 200, 90), Thickness = 2.5 }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 0, 2), Text = look.Icon, TextSize = 24 }, box)
			local nextFn
			for _, fn in ipairs(Config.Pet.Functions) do
				if fn.Level > petLevel then nextFn = fn break end
			end
			makeLabel({ Size = UDim2.new(1, -6, 0, 16), Position = UDim2.new(0, 3, 0, 36), Text = nextFn and string.format("▶ %s Lv.%d", nextFn.Icon, nextFn.Level) or "Max!", TextSize = 9, TextWrapped = true, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(190, 220, 255) }, box) -- 다음에 열리는 펫 기능
			makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 54), Text = string.format("Lv.%d", petLevel), TextSize = 11, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110) }, box)
		else
			create("UIStroke", { Color = Color3.fromRGB(70, 70, 90), Thickness = 1.5 }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 5), Text = "🐾", TextSize = 24, TextTransparency = 0.6 }, box)
			makeLabel({ Size = UDim2.new(1, -4, 0, 30), Position = UDim2.new(0, 2, 0, 44), Text = "Unlock\nPet (P)", TextSize = 9, TextWrapped = true, TextColor3 = Color3.fromRGB(150, 150, 175) }, box)
		end
	end
	local detail = create("Frame", { Size = UDim2.new(1, -462, 1, -24), Position = UDim2.new(0, 450, 0, 12), BackgroundColor3 = Color3.fromRGB(24, 26, 38), BorderSizePixel = 0 }, top)
	rounded(detail, 16)
	local showWeapons = menuContent:GetAttribute("ShowWeapons") == true
	if showWeapons then
		-- 무기 칸을 눌렀을 때: 10형 목록 (해금 / 사용 중 / 잠김) + 눌러서 바로 장착
		local weaponLevel = player:GetAttribute("WeaponLevel") or 0
		local equippedKey = Config.ResolveWeaponType(weaponLevel, player:GetAttribute("WeaponType"))
		local eraTier = Config.GetWeaponTier(weaponLevel)
		makeLabel({
			Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 0, 6), RichText = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
			Text = string.format("<font size='14'><b>🔫 Weapons</b></font>  <font color='#aab0cc'>%s · +%d</font>\n<font size='10' color='#9aa4cc'>A new weapon unlocks every 15 levels. Tap one to use it.</font>", Config.GetEraName(eraTier.Era), weaponLevel),
		}, detail)
		local list = create("ScrollingFrame", {
			Size = UDim2.new(1, -16, 1, -56), Position = UDim2.new(0, 8, 0, 50), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 5, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, detail)
		create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		for order, key in ipairs(Config.WeaponTypes.Order) do
			local info = Config.WeaponTypes[key]
			local look = Config.GetLookTier(weaponLevel, key)
			local open = Config.IsWeaponUnlocked(weaponLevel, key)
			local using = key == equippedKey
			local row = makeButton({
				Size = UDim2.new(1, -6, 0, 40), LayoutOrder = order, Text = "", AutoButtonColor = open and not using,
				BackgroundColor3 = using and Color3.fromRGB(45, 80, 55) or (open and Color3.fromRGB(40, 44, 60) or Color3.fromRGB(30, 30, 40)),
			}, list, function()
				if open and not using then
					Remotes.Weapon:FireServer("Equip", key)
					task.delay(0.35, refreshMenu)
				end
			end)
			rounded(row, 8)
			if using then create("UIStroke", { Color = Color3.fromRGB(120, 230, 150), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row) end
			makeLabel({
				Size = UDim2.new(1, -90, 1, 0), Position = UDim2.new(0, 8, 0, 0), RichText = true, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
				Text = string.format("<font size='12' color='#%s'><b>%s</b></font>\n<font color='#8f94b0'>%s</font>", open and hex(look.Color) or "777788", info.Name, info.Trait),
			}, row)
			makeLabel({
				Size = UDim2.new(0, 78, 1, 0), Position = UDim2.new(1, -82, 0, 0), TextSize = 10, Font = Enum.Font.GothamBold,
				TextColor3 = using and Color3.fromRGB(120, 230, 150) or (open and Color3.fromRGB(255, 217, 102) or Color3.fromRGB(255, 154, 110)),
				Text = using and "▶ In use" or (open and "Use" or string.format("🔒 +%d", Config.GetUnlockLevel(key))),
			}, row)
		end
		selected = nil
	end
	if selected then
		local color = Config.Gear.RarityColors[selected.Rarity]
		rarityOutline(detail, selected.Rarity, 2)
		local slot = Config.GetGearSlot(selected.Slot)
		-- 짧게: 기본 능력치 1줄 + 옵션 줄(값 + 범위 안 위치 %) + 유니크 / 세트 한 줄. 긴 설명 줄은 뺐다
		local lines = {
			string.format("<font color='#%s' size='15'><b>[%s] %s</b></font>  +%d", hex(color), Config.Gear.RarityNames[selected.Rarity], Config.ItemDisplayName(selected), selected.Level),
			string.format("<font color='#aaaacc' size='10'>%s · Score %d%s</font>", slot.Name, selected.Score, selected.Equipped and " · Equipped" or ""),
			"<font size='12' color='#ffffff'><b>Base</b>  " .. Config.FormatGearStat(selected.Slot, Config.GetGearStat(selected.Slot, selected.Rarity, selected.Level)) .. "</font>",
		}
		for _, affix in ipairs(selected.Affixes) do
			local lo, hi = Config.AffixRange(affix.Stat, selected.Rarity)
			local pos = hi > lo and math.clamp((affix.Value - lo) / (hi - lo), 0, 1) or 1
			local posColor = pos >= 0.75 and "#78ff8c" or (pos >= 0.4 and "#ffd966" or "#ff9a6e")
			table.insert(lines, string.format("<font size='12' color='#9ad7ff'>◆ %s</font> <font size='10' color='%s'><b>%d%%</b></font>", Config.FormatAffix(affix.Stat, affix.Value), posColor, math.floor(pos * 100 + 0.5)))
		end
		if selected.Unique and Config.Uniques[selected.Unique] then
			table.insert(lines, "<font size='12' color='#ffb84d'>★ " .. Config.Uniques[selected.Unique].Name .. "</font> <font size='10' color='#d9b878'>" .. Config.Uniques[selected.Unique].Desc .. "</font>")
		end
		if selected.Set and Config.Sets[selected.Set] then
			local setDef = Config.Sets[selected.Set]
			local have = setCounts[selected.Set] or 0
			local lit, dim = "#" .. hex(setDef.Color), "#6c7088"
			for _, tier in ipairs({ 2, 3 }) do
				local parts = {}
				for _, b in ipairs(setDef.Bonuses[tier]) do table.insert(parts, Config.FormatBonus(b.Stat, b.Value)) end
				local on = have >= tier
				table.insert(lines, string.format("<font size='10' color='%s'>%s %d pieces  %s</font>", on and lit or dim, on and "✔" or "○", tier, table.concat(parts, ", ")))
			end
		end
		local current = equipped[selected.Slot]
		if current and current.Id ~= selected.Id then
			local diff = selected.Score - current.Score
			table.insert(lines, diff >= 0 and string.format("<font color='#78ff8c'>vs. equipped ▲ +%d</font>", diff) or string.format("<font color='#ff8c8c'>vs. equipped ▼ %d</font>", diff))
		end
		local bandH = 0
		if selected.Set and Config.Sets[selected.Set] then
			local setDef = Config.Sets[selected.Set]
			local have = setCounts[selected.Set] or 0
			bandH = 32
			local band = create("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = setDef.Color, BorderSizePixel = 0 }, detail)
			rounded(band, 10)
			create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.85) }) }, band)
			makeLabel({
				Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 10, 0, 0), RichText = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
				Text = string.format("%s <b>%s Set</b>   %s %d/3 <font size='9'>worn</font>", setDef.Icon or "★", setDef.Name, setPips(have), have),
			}, band)
		end
		local hasBlock = selected.Equipped and selected.Level < Config.Gear.MaxLevel
		local multiH = hasBlock and 54 or 0 -- 장착 중이면 강화 블록(현재 -> 다음 / 확률 막대 / 버튼 2개)이 들어간다
		-- 재굴림 / 유니크 버튼 줄: 강화 블록이 있으면 그 아래 (블록 위에 겹쳐 강화 버튼을 가리던 문제)
		local btnY = bandH + 6
		if hasBlock and (selected.Unique or #selected.Affixes > 0) then
			btnY = bandH + 92
			multiH += 36
		end
		makeLabel({
			Size = UDim2.new(1, -20, 1, -52 - bandH - multiH), Position = UDim2.new(0, 10, 0, 46 + bandH + multiH), Text = table.concat(lines, "\n"), TextSize = 12, RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		}, detail)
		-- (강화 / 재굴림 / 장착 버튼은 상세 창 맨 위로 올렸다: 아래에 두면 메뉴 아래쪽에 가려졌다)
		if selected.Equipped then
			-- 장착 중인 장비는 여기서도 바로 강화 (뽑기 창의 강화와 같다: 로비에서만)
			if selected.Level < Config.Gear.MaxLevel then
				local cost = Config.GetGearCost(selected.Slot, selected.Rarity, selected.Level)
				local chanceRaw = Config.GetGearEnhanceChance(selected.Level)
				local chance = math.floor(chanceRaw * 100 + 0.5)
				local gold = player:GetAttribute("Gold") or 0
				-- 강화 블록: 왼쪽 = 지금 +N -> 다음 +N+1 과 효과 변화, 그 아래 성공 확률 막대 / 오른쪽 = 강화 버튼 (비용) + x10
				local block = create("Frame", { Size = UDim2.new(1, -20, 0, 84), Position = UDim2.new(0, 10, 0, bandH + 4), BackgroundColor3 = Color3.fromRGB(34, 30, 50), BorderSizePixel = 0 }, detail)
				rounded(block, 10)
				create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 1.5, Transparency = 0.35 }, block)
				create("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 160, 200)), Rotation = 90 }, block)
				makeLabel({
					Size = UDim2.new(1, -176, 0, 30), Position = UDim2.new(0, 12, 0, 4), RichText = true, Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left,
					Text = string.format("<font color='#cfd6f0'>+%d</font>  <font color='#ffd966'>▶</font>  <font color='#78ff8c'>+%d</font>", selected.Level, selected.Level + 1),
				}, block)
				local nowStat = Config.GetGearStat(selected.Slot, selected.Rarity, selected.Level)
				local nextStat = Config.GetGearStat(selected.Slot, selected.Rarity, selected.Level + 1)
				makeLabel({
					Size = UDim2.new(1, -176, 0, 16), Position = UDim2.new(0, 12, 0, 34), RichText = true, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
					Text = string.format("%s  <font color='#78ff8c'>→ %s</font>", Config.FormatGearStat(selected.Slot, nowStat), Config.FormatGearStat(selected.Slot, nextStat)),
				}, block)
				local barBack = create("Frame", { Size = UDim2.new(1, -176, 0, 18), Position = UDim2.new(0, 12, 0, 56), BackgroundColor3 = Color3.fromRGB(18, 18, 28), BorderSizePixel = 0 }, block)
				rounded(barBack, 9)
				local barColor = Color3.fromRGB(255, 90, 80):Lerp(Color3.fromRGB(110, 230, 120), math.clamp((chanceRaw - 0.35) / 0.65, 0, 1)) -- 확률이 높을수록 초록, 낮을수록 빨강
				local barFill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = barColor, BorderSizePixel = 0 }, barBack)
				rounded(barFill, 9)
				TweenService:Create(barFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(chanceRaw, 0, 1, 0) }):Play()
				makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = string.format("Success %d%%", chance), TextSize = 11, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.4, ZIndex = 3 }, barBack)
				local upgradeButton = makeButton({
					Size = UDim2.new(0, 152, 0, 40), Position = UDim2.new(1, -162, 0, 6),
					Text = string.format("🔨 Upgrade\n💰 %d G", cost), TextSize = 12, Font = Enum.Font.GothamBlack, BackgroundColor3 = gold >= cost and GREEN or Color3.fromRGB(95, 60, 62),
				}, block, function()
					Remotes.Gear:FireServer("Enhance", selected.Slot)
				end)
				if gold >= cost then -- 강화할 수 있을 때: 밝은 테두리가 숨 쉬듯 반짝여서 가장 먼저 눈에 들어오게
					local glow = create("UIStroke", { Color = Color3.fromRGB(200, 255, 215), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, upgradeButton)
					TweenService:Create(glow, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.75 }):Play()
				end
				makeButton({
					Size = UDim2.new(0, 152, 0, 28), Position = UDim2.new(1, -162, 0, 50),
					Text = "x10 Upgrade", TextSize = 11, BackgroundColor3 = Color3.fromRGB(60, 120, 200),
				}, block, function()
					Remotes.Gear:FireServer("Enhance", selected.Slot, 10)
				end)
				upgradeAnchor = block
			else
				makeButton({ Size = UDim2.new(0, 190, 0, 30), Position = UDim2.new(0, 10, 0, bandH + 6), Text = "Max Upgrade MAX", TextSize = 11, BackgroundColor3 = GRAY }, detail, function() end)
			end
		end
		if not selected.Equipped then
			makeButton({ Size = UDim2.new(0, 96, 0, 30), Position = UDim2.new(0, 10, 0, bandH + 6), Text = "Equip", TextSize = 12, BackgroundColor3 = GREEN }, detail, function()
				Remotes.Inventory:FireServer("Equip", selected.Id)
			end)
			makeButton({ Size = UDim2.new(0, 96, 0, 30), Position = UDim2.new(0, 112, 0, bandH + 6), Text = "Dismantle", TextSize = 12, BackgroundColor3 = RED }, detail, function()
				Remotes.Inventory:FireServer("Scrap", selected.Id)
			end)
		end
		if selected.Unique then -- 유니크 재굴림 (티켓)
			makeButton({
				Size = UDim2.new(0, 84, 0, 30), Position = UDim2.new(1, -220, 0, btnY),
				Text = string.format("★ 🎫%d", Config.Uniques.RerollTickets or 30), TextSize = 11, BackgroundColor3 = Color3.fromRGB(150, 90, 200),
			}, detail, function()
				Remotes.Inventory:FireServer("RerollUnique", selected.Id)
			end)
		end
		if #selected.Affixes > 0 then
			makeButton({
				Size = UDim2.new(0, 120, 0, 30), Position = UDim2.new(1, -130, 0, btnY),
				Text = string.format("Reroll ✨%d", Config.Inventory.RerollEssence[selected.Rarity]), TextSize = 10, BackgroundColor3 = Color3.fromRGB(70, 110, 220),
			}, detail, function()
				Remotes.Inventory:FireServer("Reroll", selected.Id)
			end)
		end
	elseif not showWeapons then
		makeLabel({ Size = UDim2.new(1, -20, 1, -20), Position = UDim2.new(0, 10, 0, 10), Text = "No gear yet.\nDefeat monsters in the field or use the gacha!", TextSize = 13, TextColor3 = Color3.fromRGB(150, 150, 170) }, detail)
	end

	-- 바꿔 끼기 줄: 고른 부위에 낄 수 있는 가방 장비를 바로 아래 한 줄로 (세트를 맞추는 재미: 칸을 누르면 후보가 바로 보인다)
	--   세트가 이어지는 것(끼면 그 세트 부위 수가 늘어나는 것)을 앞에, 그다음 점수 순. 누르면 위 상세 칸에서 비교 / 장착
	local swapSlot = (not showWeapons) and selected and selected.Slot
	if swapSlot and swapSlot ~= "Weapon" then
		local current = equipped[swapSlot]
		local candidates = {}
		for _, item in ipairs(bag) do
			if item.Slot == swapSlot then
				local setGain = 0
				if item.Set and Config.Sets[item.Set] and not (current and current.Set == item.Set) then
					setGain = (setCounts[item.Set] or 0) + 1 -- 끼면 이 세트가 몇 부위가 되는가
				end
				table.insert(candidates, { Item = item, SetGain = setGain })
			end
		end
		table.sort(candidates, function(x, y)
			local xs, ys = x.SetGain >= 2 and 1 or 0, y.SetGain >= 2 and 1 or 0 -- (2부위 이상이 되어 세트 효과가 켜지거나 강해지는 것 먼저)
			if xs ~= ys then return xs > ys end
			return x.Item.Score > y.Item.Score
		end)
		local slotDef = Config.GetGearSlot(swapSlot)
		local swapRow = newRow(#candidates > 0 and 112 or 40, Color3.fromRGB(30, 34, 54))
		makeLabel({ Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 0, 4), RichText = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
			Text = #candidates > 0
				and string.format("<font color='#9ad7ff'><b>🔁 %s %s</b></font>  <font color='#aab0cc'>%d in bag · tap one to compare and equip</font>", SLOT_ICONS[swapSlot] or "", slotDef and slotDef.Name or swapSlot, #candidates)
				or string.format("<font color='#9ad7ff'><b>🔁 %s %s</b></font>  <font color='#8f94b0'>No other gear for this slot in your bag</font>", SLOT_ICONS[swapSlot] or "", slotDef and slotDef.Name or swapSlot) }, swapRow)
		if #candidates > 0 then
			local strip = create("ScrollingFrame", { Size = UDim2.new(1, -20, 0, 80), Position = UDim2.new(0, 10, 0, 28), BackgroundTransparency = 1, BorderSizePixel = 0,
				ScrollBarThickness = 4, ScrollingDirection = Enum.ScrollingDirection.X, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X }, swapRow)
			create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, strip)
			for order, entry in ipairs(candidates) do
				local item = entry.Item
				local tile = makeButton({ Size = UDim2.new(0, 68, 0, 70), Text = "", LayoutOrder = order,
					BackgroundColor3 = (selected and selected.Id == item.Id) and Color3.fromRGB(70, 74, 104) or Color3.fromRGB(42, 44, 62), AutoButtonColor = true,
				}, strip, function()
					menuContent:SetAttribute("ShowWeapons", nil)
					menuContent:SetAttribute("SelectedItem", item.Id)
					refreshMenu()
				end)
				rounded(tile, 8)
				rarityOutline(tile, item.Rarity, (selected and selected.Id == item.Id) and 5 or nil)
				makeLabel({ Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, 3), Text = SLOT_ICONS[item.Slot] or "?", TextSize = 20 }, tile)
				makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 31), Text = string.format("+%d", item.Level), TextSize = 10, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack }, tile)
				local diff = current and (item.Score - current.Score) or item.Score
				if diff ~= 0 then -- 지금 낀 것보다 점수가 얼마나 높은 / 낮은가
					makeLabel({ Size = UDim2.new(1, -4, 0, 12), Position = UDim2.new(0, 2, 0, 44), Text = (diff > 0 and "▲" or "▼") .. math.abs(diff), TextSize = 9, Font = Enum.Font.GothamBold,
						TextColor3 = diff > 0 and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 130, 130) }, tile)
				end
				if item.Unique then
					makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 2, 0, 3), Text = "★", TextSize = 10, TextColor3 = Color3.fromRGB(255, 184, 77) }, tile)
				end
				if item.Set and Config.Sets[item.Set] then
					setDecor(tile, item.Set, setCounts[item.Set], UDim2.new(0, 4, 1, -15), UDim2.new(1, -8, 0, 12), 8)
					if entry.SetGain >= 2 then -- 끼면 세트가 2 / 3부위가 된다: 초록 표시
						local tag = makeLabel({ Size = UDim2.new(0, 30, 0, 13), Position = UDim2.new(1, -32, 0, 2), Text = string.format("%d/3", math.min(3, entry.SetGain)), TextSize = 9, Font = Enum.Font.GothamBlack,
							TextColor3 = Color3.fromRGB(20, 30, 20), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(120, 255, 140), ZIndex = 5 }, tile)
						rounded(tag, 6)
					end
				end
			end
		end
	end

	-- 가방 줄: 제목 (버튼 3개는 맨 위 버튼 줄로 옮겼다)
	local bagHeader = newRow(34, Color3.fromRGB(26, 28, 42))
	rowText(bagHeader, "<font color='#e1c476'><b>🎒 Bag — tap a slot to see details above</b></font>", 14)
	-- 합성: 남는 같은 등급 장비 3개(전설은 4개) + 에센스 -> 한 단계 위 등급 1개 (세트 / 유니크 / 착용 중은 재료로 안 쓴다)
	do
		local I = Config.Inventory
		local fuseRow = newRow(48, Color3.fromRGB(30, 26, 46))
		makeLabel({ Size = UDim2.new(0, 92, 1, 0), Position = UDim2.new(0, 10, 0, 0), RichText = true, TextXAlignment = Enum.TextXAlignment.Left, TextSize = 12, Font = Enum.Font.GothamBlack,
			Text = "<font color='#c9a6ff'>⚗ Fuse</font>\n<font size='10' color='#9a94b8'>same rarity</font>" }, fuseRow)
		local have = state.Fusable or {}
		for r = 1, 4 do
			local need, cost = I.FuseNeed[r], I.FuseEssence[r]
			local count = have[r] or 0
			local ready = count >= need and (state.Essence or 0) >= cost
			local fromC, toC = Config.Gear.RarityColors[r], Config.Gear.RarityColors[r + 1]
			local button = makeButton({
				Size = UDim2.new(0.25, -32, 0, 38), Position = UDim2.new((r - 1) * 0.25, 100 - (r - 1) * 24, 0.5, -19), RichText = true, TextSize = 11, Font = Enum.Font.GothamBold,
				Text = string.format("<font color='#%s'>%s</font> x%d → <font color='#%s'><b>%s</b></font>\n<font size='10' color='#cfd6e6'>%d owned · ✨%d</font>", fromC:ToHex(), Config.Gear.RarityNames[r], need, toC:ToHex(), Config.Gear.RarityNames[r + 1], count, cost),
				BackgroundColor3 = ready and Color3.fromRGB(96, 64, 160) or Color3.fromRGB(52, 48, 66), AutoButtonColor = ready,
			}, fuseRow, function()
				if ready then Remotes.Inventory:FireServer("Fuse", r) end
			end)
			button.TextTransparency = ready and 0 or 0.35
		end
	end
	local columns = 10
	local rowsNeeded = math.max(1, math.ceil(#bag / columns))
	local gridRow = newRow(rowsNeeded * 76 + 14)
	if #bag == 0 then
		makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = "Your bag is empty", TextSize = 13, TextColor3 = Color3.fromRGB(130, 130, 150) }, gridRow)
	end
	create("UIGridLayout", { CellSize = UDim2.new(0, 68, 0, 68), CellPadding = UDim2.new(0, 8, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, gridRow)
	create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10) }, gridRow)
	for order, item in ipairs(bag) do
		local tile = makeButton({
			Text = "", LayoutOrder = order,
			BackgroundColor3 = (selected and selected.Id == item.Id) and Color3.fromRGB(70, 74, 104) or Color3.fromRGB(42, 44, 62), AutoButtonColor = true,
		}, gridRow, function()
			menuContent:SetAttribute("ShowWeapons", nil)
			menuContent:SetAttribute("SelectedItem", item.Id)
			refreshMenu()
		end)
		rounded(tile, 8)
		rarityOutline(tile, item.Rarity, (selected and selected.Id == item.Id) and 5 or nil)
		makeLabel({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 4), Text = SLOT_ICONS[item.Slot], TextSize = 22 }, tile)
		makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 36), Text = string.format("+%d", item.Level), TextSize = 10, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack }, tile)
		local affixCount = #(item.Affixes or {})
		if affixCount > 0 or item.Unique then -- 옵션 개수 점: 높은 등급일수록 꽉 찬다 (★ = 유니크)
			makeLabel({ Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 0, item.Set and 42 or 52), Text = string.rep("◆", affixCount) .. (item.Unique and "★" or ""), TextSize = 8, TextColor3 = item.Unique and Color3.fromRGB(255, 200, 110) or Color3.fromRGB(140, 210, 255), Font = Enum.Font.GothamBlack }, tile)
		end
		local equippedItem = equipped[item.Slot]
		local compare = ""
		if equippedItem then
			compare = item.Score > equippedItem.Score and "▲" or (item.Score < equippedItem.Score and "▼" or "")
		else
			compare = "▲"
		end
		if compare ~= "" then
			makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(1, -16, 0, 3), Text = compare, TextSize = 10, TextColor3 = compare == "▲" and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 120, 120), Font = Enum.Font.GothamBlack }, tile)
		end
		if item.Unique then
			makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 2, 0, 3), Text = "★", TextSize = 10, TextColor3 = Color3.fromRGB(255, 184, 77) }, tile)
		end
		if item.Set then
			setDecor(tile, item.Set, setCounts[item.Set], UDim2.new(0, 5, 1, -17), UDim2.new(1, -10, 0, 14), 8)
		end
	end
end

return buildInventoryTab -- buildInventoryTab(inventoryState)
end

return InventoryTab
