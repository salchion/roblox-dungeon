-- InventoryTabUI (StarterPlayer > StarterPlayerScripts 안의 ModuleScript, 이름: InventoryTabUI)
-- 메뉴(B) > Character > Gear 탭: 장비 칸 6개 + 가방 목록 + 상세 창을 그린다.
-- PlayerClient 가 너무 커져서(Studio 스크립트 한도 200KB) 이 부분만 따로 뺐다. 필요한 것은 Init(env) 로 넘겨 받는다.
--   env: player, create, rounded, makeLabel, makeButton, GREEN, RED, GRAY, settings, menuContent, newRow, rowText, hex, refreshMenu(함수)

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local InventoryTab = {}

function InventoryTab.Init(env)
local player, create, rounded = env.player, env.create, env.rounded
local makeLabel, makeButton = env.makeLabel, env.makeButton
local GREEN, RED, GRAY = env.GREEN, env.RED, env.GRAY
local settings, menuContent = env.settings, env.menuContent
local newRow, rowText, hex = env.newRow, env.rowText, env.hex
local function refreshMenu() env.refreshMenu() end

local function buildInventoryTab(state)
	if not state then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>Loading bag...</font>")
		return
	end

	if settings.MenuInfo then
		settings.MenuInfo.Text = string.format("🎒 Bag <b>%d / %d</b>    ✨ Essence <font color='#9ad7ff'><b>%d</b></font>", state.BagCount, state.Capacity, state.Essence)
	end

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

	local top = newRow(470, Color3.fromRGB(30, 32, 46))

	local viewport = create("ViewportFrame", {
		Size = UDim2.new(0, 230, 0, 330), Position = UDim2.new(0, 108, 0, 12), BackgroundColor3 = Color3.fromRGB(20, 22, 34), BorderSizePixel = 0,
		Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1),
	}, top)
	rounded(viewport, 10)
	create("UIStroke", { Color = Color3.fromRGB(90, 110, 170), Thickness = 2 }, viewport)
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
	makeLabel({ Size = UDim2.new(0, 230, 0, 22), Position = UDim2.new(0, 108, 0, 350), Text = string.format("⚡ Power %d", player:GetAttribute("Power") or 0), TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110) }, top)

	do
		local rowsShown = 0
		for _, key in ipairs(Config.Sets.ZoneKeys) do
			local count = setCounts[key] or 0
			if count >= 2 then
				local def = Config.Sets[key]
				local bar = create("Frame", { Size = UDim2.new(0, 230, 0, 26), Position = UDim2.new(0, 108, 0, 378 + rowsShown * 30), BackgroundColor3 = def.Color, BorderSizePixel = 0 }, top)
				rounded(bar, 8)
				create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.9) }) }, bar)
				local glow = create("UIStroke", { Color = def.Color, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, bar)
				TweenService:Create(glow, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 }):Play()
				makeLabel({
					Size = UDim2.new(1, -10, 1, 0), Position = UDim2.new(0, 5, 0, 0), RichText = true, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
					Text = string.format("%s <b>%s</b>  <font color='#%s'>%s</font> %d/3", def.Icon or "✦", def.Name, hex(def.Color), setPips(count), count),
				}, bar)
				rowsShown += 1
			end
		end
		if rowsShown == 0 then
			makeLabel({ Size = UDim2.new(0, 230, 0, 30), Position = UDim2.new(0, 108, 0, 378), Text = "Wear 1·2·3 pieces of the same zone set → set effect tiers 4·5·6 (Set window: Y)", TextSize = 10, TextWrapped = true, TextColor3 = Color3.fromRGB(120, 124, 150) }, top)
		end
	end
	local function slotBox(slotKey, x, y)
		local item = equipped[slotKey]
		local rarity = item and item.Rarity or 0
		local box = makeButton({
			Size = UDim2.new(0, 88, 0, 88), Position = UDim2.new(0, x, 0, y), Text = "",
			BackgroundColor3 = item and Color3.fromRGB(46, 48, 68) or Color3.fromRGB(34, 34, 48), AutoButtonColor = true,
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
		rounded(box, 10)
		if slotKey == "Weapon" then
			local weaponLevel = player:GetAttribute("WeaponLevel") or 0
			local tier = Config.GetLookTier(weaponLevel, Config.ResolveWeaponType(weaponLevel, player:GetAttribute("WeaponType")))
			rarityOutline(box, 4, 3.5).Color = tier.Color
			makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 6), Text = "🔫", TextSize = 27 }, box)
			makeLabel({ Size = UDim2.new(1, -6, 0, 36), Position = UDim2.new(0, 3, 0, 46), Text = Config.WeaponTypes[tier.Class].Name, TextSize = 10, TextWrapped = true, TextColor3 = tier.Color, Font = Enum.Font.GothamBold }, box)
		elseif item then
			rarityOutline(box, rarity)
			setDecor(box, item.Set, setCounts[item.Set], UDim2.new(0, 4, 0, 4), UDim2.new(0, 44, 0, 16), 10)
			makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 4), Text = SLOT_ICONS[slotKey], TextSize = 27 }, box)
			makeLabel({ Size = UDim2.new(1, -6, 0, 16), Position = UDim2.new(0, 3, 0, 44), Text = Config.ItemDisplayName(item), TextSize = 9, TextWrapped = true, TextColor3 = Config.Gear.RarityColors[rarity], Font = Enum.Font.GothamBold }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 64), Text = string.format("+%d", item.Level), TextSize = 11, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack }, box)
			if item.Unique then
				makeLabel({ Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(1, -18, 0, 2), Text = "✦", TextSize = 12, TextColor3 = Color3.fromRGB(255, 184, 77) }, box)
			end
		else
			create("UIStroke", { Color = Color3.fromRGB(70, 70, 90), Thickness = 1.5 }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 10), Text = SLOT_ICONS[slotKey], TextSize = 26, TextTransparency = 0.6 }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 56), Text = "Empty", TextSize = 10, TextColor3 = Color3.fromRGB(120, 120, 140) }, box)
		end
		return box
	end
	slotBox("Helmet", 10, 12)
	slotBox("Armor", 10, 108)
	slotBox("Gloves", 10, 204)
	slotBox("Necklace", 350, 12)
	slotBox("Ring", 350, 108)
	slotBox("Boots", 350, 204)
	slotBox("Weapon", 350, 300)
	do
		local petLevel = player:GetAttribute("PetLevel") or 0
		local look = Config.Pet.Looks[player:GetAttribute("PetLook") or "Orb"] or Config.Pet.Looks.Orb
		local box = makeButton({ Size = UDim2.new(0, 88, 0, 88), Position = UDim2.new(0, 10, 0, 300), Text = "", BackgroundColor3 = petLevel > 0 and Color3.fromRGB(46, 48, 68) or Color3.fromRGB(34, 34, 48), AutoButtonColor = true }, top, function()
			player:SetAttribute("OpenPet", os.clock())
		end)
		rounded(box, 10)
		if petLevel > 0 then
			create("UIStroke", { Color = Color3.fromRGB(255, 200, 90), Thickness = 2.5 }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 4), Text = look.Icon, TextSize = 26 }, box)
			local nextFn
			for _, fn in ipairs(Config.Pet.Functions) do
				if fn.Level > petLevel then nextFn = fn break end
			end
			makeLabel({ Size = UDim2.new(1, -6, 0, 16), Position = UDim2.new(0, 3, 0, 42), Text = nextFn and string.format("▶ %s Lv.%d", nextFn.Icon, nextFn.Level) or "Max!", TextSize = 9, TextWrapped = true, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(190, 220, 255) }, box) -- 다음에 열리는 펫 기능
			makeLabel({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 62), Text = string.format("Lv.%d", petLevel), TextSize = 11, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110) }, box)
		else
			create("UIStroke", { Color = Color3.fromRGB(70, 70, 90), Thickness = 1.5 }, box)
			makeLabel({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 8), Text = "🐾", TextSize = 26, TextTransparency = 0.6 }, box)
			makeLabel({ Size = UDim2.new(1, -4, 0, 30), Position = UDim2.new(0, 2, 0, 52), Text = "Unlock\nPet (P)", TextSize = 9, TextWrapped = true, TextColor3 = Color3.fromRGB(150, 150, 175) }, box)
		end
	end
	local detail = create("Frame", { Size = UDim2.new(1, -462, 1, -24), Position = UDim2.new(0, 450, 0, 12), BackgroundColor3 = Color3.fromRGB(24, 26, 38), BorderSizePixel = 0 }, top)
	rounded(detail, 10)
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
		rarityOutline(detail, selected.Rarity)
		local slot = Config.GetGearSlot(selected.Slot)
		local lines = {
			string.format("<font color='#%s' size='15'><b>[%s] %s</b></font>  +%d", hex(color), Config.Gear.RarityNames[selected.Rarity], Config.ItemDisplayName(selected), selected.Level),
			string.format("<font color='#aaaacc' size='10'>%s · Score %d%s</font>", slot.Name, selected.Score, selected.Equipped and " · Equipped" or ""),
			"<font size='11' color='#ddddee'>Base  " .. Config.FormatGearStat(selected.Slot, Config.GetGearStat(selected.Slot, selected.Rarity, selected.Level)) .. "</font>"
				.. (Config.StatDesc[slot.Stat] and ("\n<font size='9' color='#8a8aa8'>   → " .. Config.StatDesc[slot.Stat].Desc .. "</font>") or ""),
		}
		for _, affix in ipairs(selected.Affixes) do
			local info = Config.StatDesc[affix.Stat]
			local lo, hi = Config.AffixRange(affix.Stat, selected.Rarity)
			local pos = hi > lo and math.clamp((affix.Value - lo) / (hi - lo), 0, 1) or 1
			local posColor = pos >= 0.75 and "#78ff8c" or (pos >= 0.4 and "#ffd966" or "#ff9a6e")
			table.insert(lines, "<font size='11' color='#9ad7ff'>◆ " .. Config.FormatAffix(affix.Stat, affix.Value) .. "</font>"
				.. string.format(" <font size='9' color='#8a8aa8'>Range %s</font> <font size='9' color='%s'><b>(%d%%)</b></font>", Config.FormatAffixRange(affix.Stat, selected.Rarity), posColor, math.floor(pos * 100 + 0.5))
				.. (info and ("\n<font size='9' color='#8a8aa8'>   → " .. info.Desc .. "</font>") or ""))
		end
		if #selected.Affixes > 0 then
			table.insert(lines, "<font size='9' color='#7f86a8'>🎲 Reroll: re-rolls affix values within the range above (brackets = position in range, 100% is best). Can get better or worse</font>")
		end
		if selected.Unique and Config.Uniques[selected.Unique] then
			table.insert(lines, "<font size='11' color='#ffb84d'>✦ Unique: " .. Config.Uniques[selected.Unique].Desc .. "</font>")
		end
		if selected.Set and Config.Sets[selected.Set] then
			local setDef = Config.Sets[selected.Set]
			local have = setCounts[selected.Set] or 0
			local lit, dim = "#" .. hex(setDef.Color), "#6c7088"
			if setDef.Zone then
				table.insert(lines, string.format("<font size='10' color='%s'>📍 Zone %d %s · Drops in that zone · Dungeon chests (deeper = better odds)</font>", lit, setDef.Zone, Config.Field.ZoneNames[setDef.Zone]))
			end
			for _, tier in ipairs({ 2, 3 }) do
				local parts = {}
				for _, b in ipairs(setDef.Bonuses[tier]) do table.insert(parts, Config.FormatBonus(b.Stat, b.Value)) end
				local on = have >= tier
				table.insert(lines, string.format("<font size='10' color='%s'>%s <b>%d pieces</b>  %s</font>", on and lit or dim, on and "✔" or "○", tier, table.concat(parts, ", ")))
			end
			local augInfo = setDef.Aug and Config.AugInfo[setDef.Aug]
			if augInfo then
				local lv = player:GetAttribute("AugLvZ_" .. setDef.Zone) or 0
				local ac = lv > 0 and ("#" .. hex(augInfo.Color)) or dim
				table.insert(lines, string.format("<font size='10' color='%s'><b>%s %s</b> %s</font>\n  <font color='%s'>%s</font>", ac, augInfo.Icon, augInfo.Name, lv > 0 and ("✔ Tier " .. lv) or "○ Gold Tier 3 + 1·2·3 gear pieces = Tier 4·5·6 (Y)", lv > 0 and "#cfd6f0" or dim, augInfo.Desc))
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
				Text = string.format("%s <b>%s Set</b>   %s %d/3 <font size='9'>worn</font>", setDef.Icon or "✦", setDef.Name, setPips(have), have),
			}, band)
		end
		makeLabel({
			Size = UDim2.new(1, -20, 1, -52 - bandH), Position = UDim2.new(0, 10, 0, 46 + bandH), Text = table.concat(lines, "\n"), TextSize = 12, RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		}, detail)
		-- (강화 / 재굴림 / 장착 버튼은 상세 창 맨 위로 올렸다: 아래에 두면 메뉴 아래쪽에 가려졌다)
		if selected.Equipped then
			-- 장착 중인 장비는 여기서도 바로 강화 (뽑기 창의 강화와 같다: 로비에서만)
			if selected.Level < Config.Gear.MaxLevel then
				local cost = Config.GetGearCost(selected.Slot, selected.Rarity, selected.Level, player:GetAttribute("WeaponLevel") or 0)
				local chance = math.floor(Config.GetGearEnhanceChance(selected.Level) * 100 + 0.5)
				local gold = player:GetAttribute("Gold") or 0
				makeButton({
					Size = UDim2.new(0, 190, 0, 30), Position = UDim2.new(0, 10, 0, bandH + 6),
					Text = string.format("💰 %d G Slot Upgrade (%d%% success)", cost, chance), TextSize = 11, BackgroundColor3 = gold >= cost and GREEN or Color3.fromRGB(95, 60, 62),
				}, detail, function()
					Remotes.Gear:FireServer("Enhance", selected.Slot)
				end)
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
		if #selected.Affixes > 0 then
			makeButton({
				Size = UDim2.new(0, 120, 0, 30), Position = UDim2.new(1, -130, 0, bandH + 6),
				Text = string.format("Reroll ✨%d", Config.Inventory.RerollEssence[selected.Rarity]), TextSize = 10, BackgroundColor3 = Color3.fromRGB(70, 110, 220),
			}, detail, function()
				Remotes.Inventory:FireServer("Reroll", selected.Id)
			end)
		end
	elseif not showWeapons then
		makeLabel({ Size = UDim2.new(1, -20, 1, -20), Position = UDim2.new(0, 10, 0, 10), Text = "No gear yet.\nDefeat monsters in the field or use the gacha!", TextSize = 13, TextColor3 = Color3.fromRGB(150, 150, 170) }, detail)
	end

	-- 가방 줄: 제목 + 자동 장착 / 자동 분해 / 정리 버튼 (장비 화면 위쪽 공간을 비우려고 이쪽으로 옮겼다)
	local bagHeader = newRow(34, Color3.fromRGB(26, 28, 42))
	rowText(bagHeader, "<font color='#e1c476'><b>🎒 Bag — tap a slot to see details above</b></font>", 14)
	makeButton({ Size = UDim2.new(0, 132, 0, 26), Position = UDim2.new(1, -140, 0.5, -13), Text = "🧹 Smart Clean", TextSize = 10, BackgroundColor3 = RED }, bagHeader, function()
		Remotes.Inventory:FireServer("SmartClean")
	end)
	makeButton({ Size = UDim2.new(0, 172, 0, 26), Position = UDim2.new(1, -318, 0.5, -13), Text = "Auto-Dismantle: " .. Config.Inventory.AutoScrapNames[state.AutoScrap], TextSize = 10, BackgroundColor3 = Color3.fromRGB(70, 110, 220) }, bagHeader, function()
		Remotes.Inventory:FireServer("AutoScrap", (state.AutoScrap + 1) % 5)
	end)
	makeButton({ Size = UDim2.new(0, 160, 0, 26), Position = UDim2.new(1, -486, 0.5, -13), Text = "⚡ Auto-equip best gear", TextSize = 10, BackgroundColor3 = GREEN }, bagHeader, function()
		Remotes.Inventory:FireServer("AutoEquip")
	end)
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
			makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 2, 0, 3), Text = "✦", TextSize = 10, TextColor3 = Color3.fromRGB(255, 184, 77) }, tile)
		end
		if item.Set then
			setDecor(tile, item.Set, setCounts[item.Set], UDim2.new(0, 5, 1, -17), UDim2.new(1, -10, 0, 14), 8)
		end
	end
end

return buildInventoryTab -- buildInventoryTab(inventoryState)
end

return InventoryTab
