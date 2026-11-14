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
	-- 세트 표시: 칸 오른쪽 위에 그 구역 아이콘이 든 세트색 동그라미 하나 (예전: 세트색 바탕 물들이기 + 아래 "Z3" 글자 띠 -> 지저분했다)
	--   세트 효과가 켜진 세트(2부위 이상)는 동그라미 테두리가 하얗게 빛난다. (ribbonPos / ribbonSize / radius 는 예전 호출과 맞추려고 남긴 인자)
	local function setDecor(tile, setKey, pieces, _ribbonPos, _ribbonSize, _radius)
		local def = setKey and Config.Sets[setKey]
		if not def then return end
		local active = (pieces or 0) >= 2
		local badge = create("Frame", { Size = UDim2.new(0, 20, 0, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -3, 0, 3), BackgroundColor3 = def.Color, BorderSizePixel = 0, ZIndex = 6, Active = false }, tile)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
		local stroke = create("UIStroke", { Color = active and Color3.new(1, 1, 1) or Color3.fromRGB(22, 18, 44), Thickness = active and 2 or 1.8, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)
		if active then
			TweenService:Create(stroke, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.5 }):Play()
		end
		makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = def.Icon or "★", TextSize = 12, TextWrapped = false, AutoLocalize = false, ZIndex = 7 }, badge)
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
		modeChip(0, "Best", "⚡ Strongest (sets counted)", Color3.fromRGB(80, 200, 130), not inSetMode)
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

	-- ===== 한 화면 장비 셋팅 (스크롤 없이) =====
	--   왼쪽: 지금 낀 칸 + 내 세트(모으는 중: 빠진 부위를 누르면 가방이 그 부위 / 세트로 걸러진다)
	--   가운데: 가방 (부위 / 세트 칩으로 거르기 + 정렬, 안에서만 스크롤) + 합성
	--   오른쪽: 고른 장비의 상세 / 비교 / 강화 / 장착
	-- (예전: 장비 칸 -> 바꿔 끼기 줄 -> 가방이 위아래로 길게 이어져서 계속 스크롤해야 했다)
	local MAIN_H, LEFT_W, RIGHT_W = 420, 248, 286 -- (왼쪽 / 오른쪽을 줄이고 가방을 넓혔다: 한 줄에 타일 5개)
	-- 다음에 할 일 한 줄: 무엇을 하면 좋은지 바로 알려 주고 버튼 하나로 한다 (화면이 복잡해서 뭘 해야 할지 몰랐다)
	do
		local tip, tipItem
		local bestUp, bestDiff = nil, 0
		local setPick, setTier = nil, 0
		for _, item in ipairs(bag) do
			local current = equipped[item.Slot]
			if not current then
				if not tip then
					tip = string.format("🛡 Your <b>%s</b> slot is empty — equip one", Config.GetGearSlot(item.Slot) and Config.GetGearSlot(item.Slot).Name or item.Slot)
					tipItem = item
				end
			else
				local diff = item.Score - current.Score
				if item.Set and Config.Sets[item.Set] and current.Set ~= item.Set then
					local after = (setCounts[item.Set] or 0) + 1
					local tierNow = (after >= 3 and 3) or (after >= 2 and 2) or 0
					if tierNow > 0 and tierNow > setTier and diff > -current.Score * 0.25 then setPick, setTier = item, tierNow end
				end
				if diff > bestDiff then bestUp, bestDiff = item, diff end
			end
		end
		if not tip and setPick then
			local def = Config.Sets[setPick.Set]
			tip = string.format("🧩 Equip this %s → <b>%s %d/3</b>: set bonus ON (and its set effect)", Config.GetGearSlot(setPick.Slot) and Config.GetGearSlot(setPick.Slot).Name or setPick.Slot, def.Name, setTier)
			tipItem = setPick
		elseif not tip and bestUp then
			tip = string.format("▲ A better <b>%s</b> is in your bag (Score +%d)", Config.GetGearSlot(bestUp.Slot) and Config.GetGearSlot(bestUp.Slot).Name or bestUp.Slot, bestDiff)
			tipItem = bestUp
		end
		local guide = newRow(36, tipItem and Color3.fromRGB(40, 60, 46) or Color3.fromRGB(30, 32, 48))
		makeLabel({ Size = UDim2.new(1, -150, 1, 0), Position = UDim2.new(0, 12, 0, 0), RichText = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
			Text = tip or "✔ You're wearing your best gear. Tap a slot to compare, or collect set gear in the field" }, guide)
		if tipItem then
			local go = makeButton({ Size = UDim2.new(0, 120, 0, 28), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Text = "Equip it", TextSize = 13, Font = Enum.Font.GothamBlack, BackgroundColor3 = GREEN }, guide, function()
				Remotes.Inventory:FireServer("Equip", tipItem.Id)
			end)
			rounded(go, 14)
			local show = makeButton({ Size = UDim2.new(0, 0, 0, 0), Text = "", BackgroundTransparency = 1 }, guide) -- (자리 맞춤)
			show:Destroy()
		end
	end
	local main = newRow(MAIN_H, Color3.fromRGB(20, 22, 34))
	main.BackgroundTransparency = 1
	local function panel(x, width, widthScale)
		local f = create("Frame", { Size = UDim2.new(widthScale or 0, width, 1, 0), Position = UDim2.new(0, x, 0, 0), BackgroundColor3 = Color3.fromRGB(26, 28, 44), BorderSizePixel = 0 }, main)
		rounded(f, 14)
		create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 1.2, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
		return f
	end
	local left = panel(0, LEFT_W)
	local middle = panel(LEFT_W + 8, -(LEFT_W + RIGHT_W + 16), 1)
	local right = create("Frame", { Size = UDim2.new(0, RIGHT_W, 1, 0), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1 }, main)
	if player:GetAttribute("BagSetPref") then -- 세트 효과 창의 "세트 장비 → 장비 창" 바로가기: 그 세트만 보이게
		menuContent:SetAttribute("BagSet", player:GetAttribute("BagSetPref"))
		menuContent:SetAttribute("BagSlot", nil)
		player:SetAttribute("BagSetPref", nil)
	end
	local filterSlot = menuContent:GetAttribute("BagSlot")
	local filterSet = menuContent:GetAttribute("BagSet")
	local sortMode = menuContent:GetAttribute("BagSort") or "Score"
	local function setFilter(slotKey, setKey)
		menuContent:SetAttribute("BagSlot", slotKey)
		menuContent:SetAttribute("BagSet", setKey)
		refreshMenu()
	end

	-- ---------- 왼쪽: 캐릭터 + 장비 칸 ----------
	do
		local best = 0
		for _, item in pairs(equipped) do best = math.max(best, item.Rarity or 0) end
		local glow = best > 0 and Config.Gear.RarityColors[best] or Color3.fromRGB(255, 205, 110)
		for index, spec in ipairs({ { 150, 0.88 }, { 100, 0.78 } }) do
			local halo = create("Frame", { Size = UDim2.new(0, spec[1], 0, spec[1]), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, LEFT_W / 2, 0, 112), BackgroundColor3 = glow, BackgroundTransparency = spec[2], BorderSizePixel = 0, ZIndex = 1 + index }, left)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, halo)
		end
		local viewport = create("ViewportFrame", {
			Size = UDim2.new(0, 104, 0, 176), Position = UDim2.new(0, LEFT_W / 2 - 52, 0, 26), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4,
			Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1),
		}, left)
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
		makeLabel({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 4), Text = string.format("⚡ Power %d", player:GetAttribute("Power") or 0), TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110), ZIndex = 5 }, left)
	end
	local function slotBox(slotKey, x, y)
		local item = equipped[slotKey]
		local rarity = item and item.Rarity or 0
		local box = makeButton({
			Size = UDim2.new(0, 58, 0, 54), Position = UDim2.new(0, x, 0, y), Text = "",
			BackgroundColor3 = item and Config.Gear.RarityColors[rarity]:Lerp(Color3.fromRGB(20, 22, 36), 0.78) or Color3.fromRGB(26, 27, 42), AutoButtonColor = true, ZIndex = 9,
		}, left, function()
			if slotKey == "Weapon" then
				menuContent:SetAttribute("ShowWeapons", true) -- 무기 칸: 오른쪽에 무기 목록
				refreshMenu()
			else -- 칸을 누르면 오른쪽에 지금 낀 것, 가운데 가방은 이 부위만 (바꿔 낄 후보)
				menuContent:SetAttribute("ShowWeapons", nil)
				if item then menuContent:SetAttribute("SelectedItem", item.Id) end
				setFilter(slotKey, nil)
			end
		end)
		rounded(box, 12)
		create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 214)) }, box)
		if filterSlot == slotKey then create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, box) end
		local function iconDisc(color, icon, tier)
			Kit.medal(box, { Size = 30, Position = UDim2.new(0.5, -15, 0, 4), Color = color, Icon = icon, TextSize = 17, Tier = tier or 0, ZIndex = 10 })
		end
		if slotKey == "Weapon" then
			local weaponLevel = player:GetAttribute("WeaponLevel") or 0
			local tier = Config.GetLookTier(weaponLevel, Config.ResolveWeaponType(weaponLevel, player:GetAttribute("WeaponType")))
			rarityOutline(box, 4, 2).Color = tier.Color
			iconDisc(tier.Color, "🔫", 2)
			makeLabel({ Size = UDim2.new(1, -6, 0, 14), Position = UDim2.new(0, 3, 1, -17), Text = Config.WeaponTypes[tier.Class].Name, TextSize = 9, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = tier.Color, Font = Enum.Font.GothamBold, ZIndex = 10 }, box)
		elseif item then
			if filterSlot ~= slotKey then rarityOutline(box, rarity, rarity >= 4 and 2 or 1.5) end
			iconDisc(Config.Gear.RarityColors[rarity], SLOT_ICONS[slotKey], rarity)
			local canUp = item.Level < Config.Gear.MaxLevel and (player:GetAttribute("Gold") or 0) >= Config.GetGearCost(item.Slot, item.Rarity, item.Level)
			makeLabel({ Size = UDim2.new(1, -6, 0, 14), Position = UDim2.new(0, 3, 1, -17), RichText = true, TextSize = 11, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 220, 120), ZIndex = 10,
				Text = canUp and string.format("+%d <font color='#78ff8c'>▲</font>", item.Level) or string.format("+%d", item.Level) }, box)
			if item.Set then setDecor(box, item.Set, setCounts[item.Set]) end
			if item.Unique then
				makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 3, 0, 3), Text = "★", TextSize = 11, TextColor3 = Color3.fromRGB(255, 184, 77), ZIndex = 11 }, box)
			end
		else
			create("UIStroke", { Color = Color3.fromRGB(70, 74, 96), Thickness = 1, Transparency = 0.3 }, box)
			iconDisc(Color3.fromRGB(110, 114, 140), SLOT_ICONS[slotKey])
			makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -17), Text = "Empty", TextSize = 9, TextColor3 = Color3.fromRGB(120, 120, 140), ZIndex = 10 }, box)
		end
		return box
	end
	slotBox("Helmet", 8, 28)
	slotBox("Armor", 8, 86)
	slotBox("Gloves", 8, 144)
	slotBox("Necklace", LEFT_W - 66, 28)
	slotBox("Ring", LEFT_W - 66, 86)
	slotBox("Boots", LEFT_W - 66, 144)
	slotBox("Weapon", LEFT_W - 66, 202)
	do -- 펫 칸 (왼쪽 아래)
		local petLevel = player:GetAttribute("PetLevel") or 0
		local look = Config.Pet.Looks[player:GetAttribute("PetLook") or "Orb"] or Config.Pet.Looks.Orb
		local box = makeButton({ Size = UDim2.new(0, 58, 0, 54), Position = UDim2.new(0, 8, 0, 202), Text = "", BackgroundColor3 = petLevel > 0 and Color3.fromRGB(46, 48, 68) or Color3.fromRGB(34, 34, 48), AutoButtonColor = true, ZIndex = 9 }, left, function()
			player:SetAttribute("OpenPet", os.clock())
		end)
		rounded(box, 12)
		create("UIStroke", { Color = petLevel > 0 and Color3.fromRGB(255, 200, 90) or Color3.fromRGB(70, 70, 90), Thickness = petLevel > 0 and 2 or 1.5 }, box)
		makeLabel({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 2), Text = petLevel > 0 and look.Icon or "🐾", TextSize = 18, TextTransparency = petLevel > 0 and 0 or 0.6, ZIndex = 10 }, box)
		makeLabel({ Size = UDim2.new(1, -4, 0, 22), Position = UDim2.new(0, 2, 0, 30), Text = petLevel > 0 and string.format("Lv.%d", petLevel) or "Unlock\nPet (P)", TextSize = petLevel > 0 and 11 or 9, TextWrapped = true, Font = Enum.Font.GothamBlack,
			TextColor3 = petLevel > 0 and Color3.fromRGB(255, 225, 110) or Color3.fromRGB(150, 150, 175), ZIndex = 10 }, box)
	end

	-- ---------- 왼쪽 아래: 내 세트 (모으는 중) ----------
	do
		makeLabel({ Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 10, 0, 262), Text = "🧩 My sets", TextSize = 13, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 217, 102) }, left)
		local list = create("ScrollingFrame", { Size = UDim2.new(1, -12, 1, -288), Position = UDim2.new(0, 6, 0, 282), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, left)
		create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		-- 가진 세트 (착용 + 가방): 어느 부위를 가졌는지
		local ownedSlots = {}
		for _, item in ipairs(state.Items) do
			if item.Set and Config.Sets[item.Set] then
				ownedSlots[item.Set] = ownedSlots[item.Set] or {}
				ownedSlots[item.Set][item.Slot] = true
			end
		end
		local keys = {}
		for _, key in ipairs(Config.Sets.ZoneKeys) do if ownedSlots[key] then table.insert(keys, key) end end
		table.sort(keys, function(a, b)
			local ca, cb = setCounts[a] or 0, setCounts[b] or 0
			if ca ~= cb then return ca > cb end
			return (Config.Sets[a].Zone or 0) > (Config.Sets[b].Zone or 0)
		end)
		if #keys == 0 then
			makeLabel({ Size = UDim2.new(1, -8, 0, 54), Text = "Set gear drops in the field (each zone has its own set). Wear 2–3 pieces of one set for bonuses — and its set effect turns on.", TextSize = 10, TextWrapped = true, TextColor3 = Color3.fromRGB(140, 144, 170) }, list)
		end
		for order, key in ipairs(keys) do
			local def = Config.Sets[key]
			local worn = math.min(3, setCounts[key] or 0)
			local card = create("Frame", { Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(32, 34, 52), BorderSizePixel = 0, LayoutOrder = order }, list)
			rounded(card, 10)
			create("UIStroke", { Color = def.Color, Thickness = worn >= 2 and 1.8 or 1, Transparency = worn >= 2 and 0.1 or 0.55 }, card)
			create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 6) }, card)
			create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, card)
			local pips = {}
			for i = 1, 3 do pips[i] = string.format("<font color='#%s'>●</font>", i <= worn and hex(def.Color) or "3a3c52") end
			local aug = def.Aug and Config.AugInfo[def.Aug]
			local effectOn = def.Zone and player:GetAttribute("AugOnZ_" .. def.Zone) == true
			local setButton = makeButton({ Size = UDim2.new(1, 0, 0, 18), Text = "", BackgroundTransparency = 1, AutoButtonColor = false, LayoutOrder = 1 }, card, function()
				setFilter(nil, key) -- 세트 이름을 누르면 가방이 이 세트만
			end)
			if def.Zone then -- ✨: 세트 효과 창에서 이 효과 보기 (메뉴를 닫고 연다)
				local jump = makeButton({ Size = UDim2.new(0, 24, 0, 18), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Text = "✨", TextSize = 11, BackgroundColor3 = Color3.fromRGB(70, 60, 110), ZIndex = 4 }, setButton, function()
					player:SetAttribute("OpenMenuTab", "Character:Gear|" .. tostring(os.clock())) -- (같은 탭 신호 = 메뉴 닫기)
					player:SetAttribute("AugFocusZone", def.Zone)
				end)
				rounded(jump, 9)
			end
			makeLabel({ Size = UDim2.new(1, 0, 1, 0), RichText = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBlack,
				Text = string.format("%s %s  %s%s", def.Icon or "★", def.Name, table.concat(pips, ""), worn >= 2 and "  <font color='#78ff8c' size='10'>ON</font>" or "") }, setButton)
			for _, tier in ipairs({ 2, 3 }) do
				local parts = {}
				for _, b in ipairs(def.Bonuses[tier] or {}) do table.insert(parts, "<font>" .. Config.FormatBonus(b.Stat, b.Value) .. "</font>") end
				makeLabel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, RichText = true, TextWrapped = true, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 + tier,
					TextColor3 = worn >= tier and Color3.fromRGB(200, 240, 210) or Color3.fromRGB(130, 134, 160),
					Text = string.format("%s %d · %s", worn >= tier and "✔" or "○", tier, table.concat(parts, " · ")) }, card)
			end
			if aug then
				makeLabel({ Size = UDim2.new(1, 0, 0, 14), RichText = true, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 5, TextColor3 = effectOn and Color3.fromRGB(150, 230, 255) or Color3.fromRGB(130, 134, 160),
					Text = string.format("%s %s %s", aug.Icon, aug.Name, effectOn and string.format("<font color='#78ff8c'>Lv.%d ON</font>", player:GetAttribute(def.Aug) or 0) or "") }, card)
			end
			-- 빠진 부위: 가방에 그 세트 부위가 있으면 눌러서 바로 찾는다
			local missing = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 6 }, card)
			create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, missing)
			local any = false
			for slotOrder, slot in ipairs(Config.Gear.Slots) do
				local wornThis = equipped[slot.Key] and equipped[slot.Key].Set == key
				if not wornThis and ownedSlots[key][slot.Key] and worn < 3 then
					any = true
					local chip = makeButton({ Size = UDim2.new(0, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.X, Text = string.format("+ %s", SLOT_ICONS[slot.Key] or "?"), TextSize = 11, LayoutOrder = slotOrder,
						BackgroundColor3 = Color3.fromRGB(46, 70, 52) }, missing, function()
						setFilter(slot.Key, key) -- 가방: 이 세트의 이 부위만
					end)
					rounded(chip, 10)
					create("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, chip)
				end
			end
			if not any then missing:Destroy() end
		end
	end

	-- ---------- 가운데: 가방 ----------
	do
		local filtered = {}
		for _, item in ipairs(bag) do
			if (not filterSlot or item.Slot == filterSlot) and (not filterSet or item.Set == filterSet) then
				local current = equipped[item.Slot]
				local setGain = 0
				if item.Set and Config.Sets[item.Set] and not (current and current.Set == item.Set) then setGain = (setCounts[item.Set] or 0) + 1 end
				table.insert(filtered, { Item = item, SetGain = setGain, Diff = current and (item.Score - current.Score) or item.Score })
			end
		end
		table.sort(filtered, function(x, y)
			if sortMode == "Rarity" and x.Item.Rarity ~= y.Item.Rarity then return x.Item.Rarity > y.Item.Rarity end
			if sortMode == "Set" then
				local xs, ys = x.SetGain >= 2 and 1 or 0, y.SetGain >= 2 and 1 or 0
				if xs ~= ys then return xs > ys end
			end
			return x.Item.Score > y.Item.Score
		end)
		makeLabel({ Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 10, 0, 6), RichText = true, TextSize = 12, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left,
			Text = string.format("🎒 Bag <font color='#aab0cc'>%d / %d</font>", state.BagCount, state.Capacity) }, middle)
		local function chipRow(y)
			local row = create("ScrollingFrame", { Size = UDim2.new(1, -12, 0, 26), Position = UDim2.new(0, 6, 0, y), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
				ScrollingDirection = Enum.ScrollingDirection.X, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X }, middle)
			create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, row)
			return row
		end
		local function chip(parent, order, text, on, onClick, color)
			local c = makeButton({ Size = UDim2.new(0, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.X, Text = text, TextSize = 12, LayoutOrder = order, RichText = true,
				BackgroundColor3 = on and Color3.fromRGB(90, 74, 30) or Color3.fromRGB(36, 38, 58) }, parent, onClick)
			rounded(c, 12)
			create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, c)
			create("UIStroke", { Color = on and Color3.fromRGB(255, 217, 102) or (color or Color3.fromRGB(90, 96, 130)), Thickness = on and 1.8 or 1, Transparency = on and 0 or 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, c)
			return c
		end
		local slotRow = chipRow(28)
		chip(slotRow, 0, "All", filterSlot == nil, function() setFilter(nil, filterSet) end)
		for i, slot in ipairs(Config.Gear.Slots) do
			chip(slotRow, i, SLOT_ICONS[slot.Key] or slot.Name, filterSlot == slot.Key, function() setFilter(filterSlot == slot.Key and nil or slot.Key, filterSet) end)
		end
		local setRow = chipRow(56)
		chip(setRow, 0, "All sets", filterSet == nil, function() setFilter(filterSlot, nil) end)
		for i, key in ipairs(Config.Sets.ZoneKeys) do
			local def = Config.Sets[key]
			local has = false
			for _, item in ipairs(bag) do if item.Set == key then has = true break end end
			if has then chip(setRow, i, def.Icon or "★", filterSet == key, function() setFilter(filterSlot, filterSet == key and nil or key) end, def.Color) end
		end
		local SORTS = { Score = "Sort: Score", Rarity = "Sort: Rarity", Set = "Sort: Set first" }
		local NEXT_SORT = { Score = "Set", Set = "Rarity", Rarity = "Score" }
		chip(setRow, 99, "⇅ " .. SORTS[sortMode], false, function()
			menuContent:SetAttribute("BagSort", NEXT_SORT[sortMode])
			refreshMenu()
		end)
		if filterSlot or filterSet then
			local caption = {}
			if filterSlot then table.insert(caption, (SLOT_ICONS[filterSlot] or "") .. " " .. (Config.GetGearSlot(filterSlot) and Config.GetGearSlot(filterSlot).Name or filterSlot)) end
			if filterSet and Config.Sets[filterSet] then table.insert(caption, (Config.Sets[filterSet].Icon or "") .. " " .. Config.Sets[filterSet].Name) end
			makeLabel({ Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 10, 0, 84), RichText = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(154, 215, 255),
				Text = string.format("%s · %d", table.concat(caption, " · "), #filtered) }, middle)
		end
		local grid = create("ScrollingFrame", { Size = UDim2.new(1, -8, 1, -156), Position = UDim2.new(0, 4, 0, 102), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, middle)
		create("UIGridLayout", { CellSize = UDim2.new(0, 54, 0, 54), CellPadding = UDim2.new(0, 8, 0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, grid)
		if #filtered == 0 then
			makeLabel({ Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 0, 110), Text = #bag == 0 and "Your bag is empty" or "Nothing matches this filter", TextSize = 12, TextColor3 = Color3.fromRGB(130, 130, 150) }, middle)
		end
		for order, entry in ipairs(filtered) do
			local item = entry.Item
			local isSel = selected and selected.Id == item.Id
			local tile = makeButton({ Text = "", LayoutOrder = order, BackgroundColor3 = isSel and Color3.fromRGB(70, 74, 104) or Color3.fromRGB(34, 36, 54), AutoButtonColor = true }, grid, function()
				menuContent:SetAttribute("ShowWeapons", nil)
				menuContent:SetAttribute("SelectedItem", item.Id)
				refreshMenu()
			end)
			rounded(tile, 10)
			rarityOutline(tile, item.Rarity, isSel and 4 or nil)
			makeLabel({ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 3), Text = SLOT_ICONS[item.Slot], TextSize = 18 }, tile)
			makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -17), Text = string.format("+%d", item.Level), TextSize = 10, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack }, tile)
			if entry.Diff ~= 0 then
				makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(1, -15, 1, -16), Text = entry.Diff > 0 and "▲" or "▼", TextSize = 10, Font = Enum.Font.GothamBlack,
					TextColor3 = entry.Diff > 0 and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 120, 120) }, tile)
			end
			if item.Unique then
				makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 2, 0, 2), Text = "★", TextSize = 10, TextColor3 = Color3.fromRGB(255, 184, 77) }, tile)
			end
			if item.AugBoost and Config.AugInfo[item.AugBoost] then
				makeLabel({ Size = UDim2.new(0, 16, 0, 14), Position = UDim2.new(0, 2, 1, -16), Text = Config.AugInfo[item.AugBoost].Icon, TextSize = 10, ZIndex = 4 }, tile)
			end
			if item.Set then
				setDecor(tile, item.Set, setCounts[item.Set])
				if entry.SetGain >= 2 then
					local tag = makeLabel({ Size = UDim2.new(0, 34, 0, 14), Position = UDim2.new(0, -4, 0, 30), Text = string.format("▲%d/3", math.min(3, entry.SetGain)), TextSize = 10, Font = Enum.Font.GothamBlack,
						TextWrapped = false, TextColor3 = Color3.fromRGB(20, 30, 20), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(120, 255, 140), ZIndex = 7 }, tile)
					rounded(tag, 6)
				end
			end
		end
		-- 합성: 가방 아래 버튼 하나 -> 누르면 가방 자리에 합성 화면이 크게 열린다 (예전: 좁은 칸에 버튼 4개가 쪼그라들어 무엇인지 몰랐다)
		local I = Config.Inventory
		local have = state.Fusable or {}
		local anyReady = false
		for r = 1, 4 do
			if (have[r] or 0) >= I.FuseNeed[r] and (state.Essence or 0) >= I.FuseEssence[r] then anyReady = true end
		end
		local fuseOpen = menuContent:GetAttribute("FuseOpen") == true
		local fuseToggle = makeButton({ Size = UDim2.new(1, -12, 0, 40), Position = UDim2.new(0, 6, 1, -46), RichText = true, TextSize = 13, Font = Enum.Font.GothamBlack,
			Text = fuseOpen and "◀ Back to bag" or ("⚗ Fuse spare gear into a higher rarity" .. (anyReady and "  <font color='#78ff8c'>● ready</font>" or "")),
			BackgroundColor3 = anyReady and Color3.fromRGB(96, 64, 160) or Color3.fromRGB(52, 48, 72) }, middle, function()
			menuContent:SetAttribute("FuseOpen", not fuseOpen)
			refreshMenu()
		end)
		rounded(fuseToggle, 20)
		if fuseOpen then
			local sheet = create("Frame", { Size = UDim2.new(1, -8, 1, -54), Position = UDim2.new(0, 4, 0, 4), BackgroundColor3 = Color3.fromRGB(30, 26, 46), BorderSizePixel = 0, ZIndex = 20 }, middle)
			rounded(sheet, 12)
			makeLabel({ Size = UDim2.new(1, -20, 0, 54), Position = UDim2.new(0, 10, 0, 6), RichText = true, TextWrapped = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21,
				Text = "<font size='14' color='#c9a6ff'><b>⚗ Fuse</b></font>\nSpare gear of the same rarity + ✨ Essence → 1 piece of the next rarity. Set, unique and equipped gear are never used." }, sheet)
			for r = 1, 4 do
				local need, cost = I.FuseNeed[r], I.FuseEssence[r]
				local count = have[r] or 0
				local ready = count >= need and (state.Essence or 0) >= cost
				local fromC, toC = Config.Gear.RarityColors[r], Config.Gear.RarityColors[r + 1]
				local rowF = create("Frame", { Size = UDim2.new(1, -16, 0, 58), Position = UDim2.new(0, 8, 0, 64 + (r - 1) * 64), BackgroundColor3 = Color3.fromRGB(40, 36, 60), BorderSizePixel = 0, ZIndex = 21 }, sheet)
				rounded(rowF, 10)
				create("UIStroke", { Color = ready and toC or Color3.fromRGB(70, 66, 96), Thickness = ready and 1.8 or 1 }, rowF)
				makeLabel({ Size = UDim2.new(1, -110, 1, 0), Position = UDim2.new(0, 10, 0, 0), RichText = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22,
					Text = string.format("<font color='#%s'><b>%s</b></font> x%d  →  <font color='#%s'><b>%s</b></font> x1\n<font size='11' color='%s'>You have %d · ✨%d</font>", fromC:ToHex(), Config.Gear.RarityNames[r], need, toC:ToHex(), Config.Gear.RarityNames[r + 1], count >= need and "#78ff8c" or "#aab0cc", count, cost) }, rowF)
				local b = makeButton({ Size = UDim2.new(0, 90, 0, 36), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Text = ready and "Fuse" or "Not enough", TextSize = ready and 14 or 10, Font = Enum.Font.GothamBlack,
					BackgroundColor3 = ready and Color3.fromRGB(110, 70, 190) or Color3.fromRGB(56, 52, 70), AutoButtonColor = ready, ZIndex = 22 }, rowF, function()
					if ready then Remotes.Inventory:FireServer("Fuse", r) end
				end)
				rounded(b, 18)
			end
		end
	end

	-- ---------- 오른쪽: 상세 / 비교 / 강화 / 장착 ----------
	local detail = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(24, 26, 38), BorderSizePixel = 0 }, right)
	rounded(detail, 14)
	local showWeapons = menuContent:GetAttribute("ShowWeapons") == true
	if showWeapons then
		-- 무기 칸을 눌렀을 때: 무기 목록 (해금 / 사용 중 / 잠김) + 눌러서 바로 장착
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
		local current = equipped[selected.Slot]
		local y = 8
		if selected.Set and Config.Sets[selected.Set] then -- 세트 띠
			local setDef = Config.Sets[selected.Set]
			local have = setCounts[selected.Set] or 0
			local band = create("Frame", { Size = UDim2.new(1, -12, 0, 24), Position = UDim2.new(0, 6, 0, 6), BackgroundColor3 = setDef.Color, BorderSizePixel = 0 }, detail)
			rounded(band, 8)
			create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.85) }) }, band)
			makeLabel({ Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 8, 0, 0), RichText = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
				Text = string.format("%s <b>%s</b> <b>Set</b>   %s %d/3", setDef.Icon or "★", setDef.Name, setPips(have), have) }, band)
			y = 34
		end
		makeLabel({ Size = UDim2.new(1, -16, 0, 36), Position = UDim2.new(0, 8, 0, y), RichText = true, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			Text = string.format("<font color='#%s'><b>[%s] %s</b></font> +%d\n<font color='#aaaacc' size='10'>%s · Score %d%s</font>", hex(color), Config.Gear.RarityNames[selected.Rarity], Config.ItemDisplayName(selected), selected.Level, slot.Name, selected.Score, selected.Equipped and " · Equipped" or "") }, detail)
		y += 40
		if selected.Equipped then
			if selected.Level < Config.Gear.MaxLevel then -- 강화 블록 (장착 중인 장비: 여기서 바로 강화. 마을에서만)
				local cost = Config.GetGearCost(selected.Slot, selected.Rarity, selected.Level)
				local chanceRaw = Config.GetGearEnhanceChance(selected.Level)
				local gold = player:GetAttribute("Gold") or 0
				local block = create("Frame", { Size = UDim2.new(1, -16, 0, 118), Position = UDim2.new(0, 8, 0, y), BackgroundColor3 = Color3.fromRGB(34, 30, 50), BorderSizePixel = 0 }, detail)
				rounded(block, 10)
				create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 1.5, Transparency = 0.35 }, block)
				makeLabel({ Size = UDim2.new(1, -16, 0, 24), Position = UDim2.new(0, 8, 0, 4), RichText = true, Font = Enum.Font.GothamBlack, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
					Text = string.format("<font color='#cfd6f0'>+%d</font>  <font color='#ffd966'>▶</font>  <font color='#78ff8c'>+%d</font>", selected.Level, selected.Level + 1) }, block)
				makeLabel({ Size = UDim2.new(1, -16, 0, 14), Position = UDim2.new(0, 8, 0, 29), RichText = true, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
					Text = string.format("%s  <font color='#78ff8c'>→ %s</font>", Config.FormatGearStat(selected.Slot, Config.GetGearStat(selected.Slot, selected.Rarity, selected.Level)), Config.FormatGearStat(selected.Slot, Config.GetGearStat(selected.Slot, selected.Rarity, selected.Level + 1))) }, block)
				local barBack = create("Frame", { Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 8, 0, 48), BackgroundColor3 = Color3.fromRGB(18, 18, 28), BorderSizePixel = 0 }, block)
				rounded(barBack, 8)
				local barFill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 90, 80):Lerp(Color3.fromRGB(110, 230, 120), math.clamp((chanceRaw - 0.35) / 0.65, 0, 1)), BorderSizePixel = 0 }, barBack)
				rounded(barFill, 8)
				TweenService:Create(barFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(chanceRaw, 0, 1, 0) }):Play()
				makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = string.format("Success %d%%", math.floor(chanceRaw * 100 + 0.5)), TextSize = 10, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.4, ZIndex = 3 }, barBack)
				local upgradeButton = makeButton({ Size = UDim2.new(0.62, -10, 0, 40), Position = UDim2.new(0, 8, 0, 70), Text = string.format("🔨 Upgrade\n💰 %d G", cost), TextSize = 11, Font = Enum.Font.GothamBlack,
					BackgroundColor3 = gold >= cost and GREEN or Color3.fromRGB(95, 60, 62) }, block, function()
					Remotes.Gear:FireServer("Enhance", selected.Slot)
				end)
				rounded(upgradeButton, 20)
				if gold >= cost then
					local glow = create("UIStroke", { Color = Color3.fromRGB(200, 255, 215), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, upgradeButton)
					TweenService:Create(glow, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.75 }):Play()
				end
				local tenButton = makeButton({ Size = UDim2.new(0.38, -6, 0, 40), Position = UDim2.new(0.62, 0, 0, 70), Text = "x10", TextSize = 13, Font = Enum.Font.GothamBlack, BackgroundColor3 = Color3.fromRGB(60, 120, 200) }, block, function()
					Remotes.Gear:FireServer("Enhance", selected.Slot, 10)
				end)
				rounded(tenButton, 20)
				upgradeAnchor = block
				y += 124
			else
				makeLabel({ Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 8, 0, y), Text = "✔ Max upgrade", TextSize = 12, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 217, 102) }, detail)
				y += 26
			end
		else
			local equipButton = makeButton({ Size = UDim2.new(0.62, -10, 0, 40), Position = UDim2.new(0, 8, 0, y), Text = "Equip", TextSize = 15, Font = Enum.Font.GothamBlack, BackgroundColor3 = GREEN }, detail, function()
				Remotes.Inventory:FireServer("Equip", selected.Id)
			end)
			rounded(equipButton, 20)
			local scrapButton = makeButton({ Size = UDim2.new(0.38, -6, 0, 40), Position = UDim2.new(0.62, 0, 0, y), Text = "Dismantle", TextSize = 11, Font = Enum.Font.GothamBold, BackgroundColor3 = RED }, detail, function()
				Remotes.Inventory:FireServer("Scrap", selected.Id)
			end)
			rounded(scrapButton, 20)
			y += 46
		end
		if selected.Unique or #selected.Affixes > 0 then -- 재굴림 줄
			if #selected.Affixes > 0 then
				makeButton({ Size = UDim2.new(0.5, -10, 0, 28), Position = UDim2.new(0, 8, 0, y), Text = string.format("Reroll ✨%d", Config.Inventory.RerollEssence[selected.Rarity]), TextSize = 10, BackgroundColor3 = Color3.fromRGB(70, 110, 220) }, detail, function()
					Remotes.Inventory:FireServer("Reroll", selected.Id)
				end)
			end
			if selected.Unique then
				makeButton({ Size = UDim2.new(0.5, -10, 0, 28), Position = UDim2.new(0.5, 2, 0, y), Text = string.format("★ 🎫%d", Config.Uniques.RerollTickets or 30), TextSize = 10, BackgroundColor3 = Color3.fromRGB(150, 90, 200) }, detail, function()
					Remotes.Inventory:FireServer("RerollUnique", selected.Id)
				end)
			end
			y += 34
		end
		-- 본문: 비교 / 끼면 바뀌는 것 / 능력치 (아래는 스크롤)
		local lines = {}
		if current and current.Id ~= selected.Id then
			local diff = selected.Score - current.Score
			table.insert(lines, diff >= 0 and string.format("<font color='#78ff8c'><b>vs. equipped ▲ +%d</b></font>", diff) or string.format("<font color='#ff8c8c'><b>vs. equipped ▼ %d</b></font>", diff))
		end
		-- 이걸 끼면 바뀌는 것: 세트 부위 수와 세트 효과 단계 (세트 효과는 세트 장비를 끼면 저절로 켜진다)
		if not selected.Equipped and (selected.Set or selected.AugBoost or (current and (current.Set or current.AugBoost))) then
			local changes = {}
			local cap = Config.Inventory.AugMaxLevel or 6
			local function augChange(zone, delta)
				local def = Config.Sets.ZoneKeys[zone] and Config.Sets[Config.Sets.ZoneKeys[zone]]
				local info = def and def.Aug and Config.AugInfo[def.Aug]
				if not info then return nil end
				local raw = (player:GetAttribute("AugLvZ_" .. zone) or 0) + (player:GetAttribute("AugGearZ_" .. zone) or 0)
				local before, after = math.min(cap, raw), math.clamp(raw + delta, 0, cap)
				if before == after then return nil end
				if before == 0 then return string.format("%s %s <font color='#78ff8c'>ON Lv.%d</font>", info.Icon, info.Name, after) end
				return string.format("%s %s Lv.%d→%d", info.Icon, info.Name, before, after)
			end
			local function setChange(setKey, delta)
				local def = setKey and Config.Sets[setKey]
				if not def then return end
				local before = setCounts[setKey] or 0
				local after = math.max(0, before + delta)
				local text = string.format("%s %s %d→%d/3", def.Icon or "★", def.Prefix or def.Name, math.min(3, before), math.min(3, after))
				if (before < 2 and after >= 2) or (before < 3 and after >= 3) then text ..= " <font color='#78ff8c'>(bonus ON)</font>" end
				if (before >= 2 and after < 2) or (before >= 3 and after < 3) then text ..= " <font color='#ff8c8c'>(bonus OFF)</font>" end
				table.insert(changes, text)
				if def.Zone and math.clamp(before, 0, 3) ~= math.clamp(after, 0, 3) then
					local a = augChange(def.Zone, math.clamp(after, 0, 3) - math.clamp(before, 0, 3))
					if a then table.insert(changes, a) end
				end
			end
			if not (current and current.Set == selected.Set) then
				setChange(selected.Set, 1)
				if current and current.Set then setChange(current.Set, -1) end
			end
			local gain, lose = selected.AugBoost, current and current.AugBoost
			if gain ~= lose then
				for _, pair in ipairs({ { gain, 1 }, { lose, -1 } }) do
					local zone = pair[1] and table.find(Config.Sets.ZoneAug, pair[1])
					local a = zone and augChange(zone, pair[2])
					if a then table.insert(changes, a) end
				end
			end
			if #changes > 0 then
				table.insert(lines, "<font color='#9ad7ff'><b>If equipped:</b></font>")
				for _, c in ipairs(changes) do table.insert(lines, "  " .. c) end
			end
		end
		table.insert(lines, "<font color='#ffffff'><b>Base</b>  " .. Config.FormatGearStat(selected.Slot, Config.GetGearStat(selected.Slot, selected.Rarity, selected.Level)) .. "</font>")
		for _, affix in ipairs(selected.Affixes) do
			local lo, hi = Config.AffixRange(affix.Stat, selected.Rarity)
			local pos = hi > lo and math.clamp((affix.Value - lo) / (hi - lo), 0, 1) or 1
			local posColor = pos >= 0.75 and "#78ff8c" or (pos >= 0.4 and "#ffd966" or "#ff9a6e")
			table.insert(lines, string.format("<font color='#9ad7ff'>◆ %s</font> <font size='10' color='%s'><b>%d%%</b></font>", Config.FormatAffix(affix.Stat, affix.Value), posColor, math.floor(pos * 100 + 0.5)))
		end
		if selected.Unique and Config.Uniques[selected.Unique] then
			table.insert(lines, "<font color='#ffb84d'>★ " .. Config.Uniques[selected.Unique].Name .. "</font> <font size='10' color='#d9b878'>" .. Config.Uniques[selected.Unique].Desc .. "</font>")
		end
		if selected.AugBoost and Config.AugInfo[selected.AugBoost] then
			local info = Config.AugInfo[selected.AugBoost]
			table.insert(lines, string.format("<font color='#9ad7ff'>%s %s +1 Lv</font>", info.Icon, info.Name))
		end
		if selected.Set and Config.Sets[selected.Set] then
			local setDef = Config.Sets[selected.Set]
			local have = setCounts[selected.Set] or 0
			for _, tier in ipairs({ 2, 3 }) do
				local parts = {}
				for _, b in ipairs(setDef.Bonuses[tier]) do table.insert(parts, "<font>" .. Config.FormatBonus(b.Stat, b.Value) .. "</font>") end
				local on = have >= tier
				table.insert(lines, string.format("<font size='10' color='%s'>%s %d pieces  %s</font>", on and ("#" .. hex(setDef.Color)) or "#6c7088", on and "✔" or "○", tier, table.concat(parts, ", ")))
			end
		end
		local body = create("ScrollingFrame", { Size = UDim2.new(1, -12, 1, -(y + 6)), Position = UDim2.new(0, 6, 0, y), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, detail)
		makeLabel({ Size = UDim2.new(1, -8, 0, 0), Position = UDim2.new(0, 4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = table.concat(lines, "\n"), TextSize = 12, RichText = true, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, body)
	elseif not showWeapons then
		makeLabel({ Size = UDim2.new(1, -20, 1, -20), Position = UDim2.new(0, 10, 0, 10), Text = "No gear yet.\nDefeat monsters in the field or use the gacha!", TextSize = 13, TextColor3 = Color3.fromRGB(150, 150, 170) }, detail)
	end
end

return buildInventoryTab -- buildInventoryTab(inventoryState)
end

return InventoryTab
