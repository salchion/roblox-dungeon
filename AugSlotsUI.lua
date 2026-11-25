-- AugSlotsUI (StarterPlayer > StarterPlayerScripts 안의 ModuleScript, 이름: AugSlotsUI)
-- 🌟 세트 효과 창(Y) 안쪽: 칸 3개 + 후보 목록(공격 / 방어 탭) + 칸 강화 + 조합 비교 카드 (11-25 확정 목업 slots3)
--   AugClient 가 만든 panel 에 그린다: require(...).Build(panel) -> { Refresh, Focus }
--   값은 서버(AugService)가 채우는 Attribute 만 읽고, 바꾸는 것은 Remotes.Aug "Slot" / "SlotUp" / "Stone" 으로 보낸다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local S = Config.AugSlots
local ZONES = #Config.Sets.ZoneAug
local GOLD = Color3.fromRGB(255, 217, 102)
local GREEN = Color3.fromRGB(120, 255, 140)
local MUTED = Color3.fromRGB(154, 152, 191)
local ATK = Color3.fromRGB(255, 184, 77)
local DEF = Color3.fromRGB(143, 224, 255)

local UI = {}

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end
local function corner(inst, r) make("UICorner", { CornerRadius = UDim.new(0, r or 10) }, inst) return inst end
local function text(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextSize = props.TextSize or 13
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.RichText = true
	props.ZIndex = props.ZIndex or 4
	return make("TextLabel", props, parent)
end
local function button(props, parent, onClick)
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextSize = props.TextSize or 13
	props.AutoButtonColor = true
	props.ZIndex = props.ZIndex or 5
	local b = make("TextButton", props, parent)
	corner(b, 10)
	b.Activated:Connect(onClick)
	return b
end
local function commas(n)
	return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function infoOf(z) return Config.AugInfo[Config.Sets.ZoneAug[z] or ""] end
local function isDefense(z) local i = infoOf(z) return i ~= nil and i.Defense == true end
local function homeZone(z) return (Config.Sets.AugHomeZone and Config.Sets.AugHomeZone[z]) or z end
local function setOf(z) local key = Config.Sets.ZoneKeys[z] return key and Config.Sets[key] end
local function dots(n) return string.rep("●", math.min(6, n)) .. string.rep("○", math.max(0, 6 - n)) end
local function attr(name) return player:GetAttribute(name) end
local function atTown() return attr("Zone") == "Lobby" or attr("TutorialActive") == true end
local function plusFive(z) return isDefense(z) and "effect value +20%" or "10% chance to fire again" end

function UI.Build(panel)
	local selectedSlot, tab, showLocked = 1, "Attack", false

	text({ Size = UDim2.new(0, 420, 0, 30), Position = UDim2.new(0, 16, 0, 8), Text = "🌟 Set Effects · 3 slots", TextSize = 20, Font = Enum.Font.GothamBlack }, panel)
	local resLabel = text({ Size = UDim2.new(0, 360, 0, 30), Position = UDim2.new(0, 330, 0, 8), Text = "", TextSize = 14, TextColor3 = DEF }, panel)
	button({ Size = UDim2.new(0, 72, 0, 30), Position = UDim2.new(1, -84, 0, 10), BackgroundColor3 = Color3.fromRGB(54, 58, 82), Text = "Close", TextSize = 12 }, panel, function() panel.Visible = false end)
	text({ Size = UDim2.new(1, -32, 0, 18), Position = UDim2.new(0, 16, 0, 40), TextSize = 11, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "<font color='#ffd966'><b>Only effects in a slot are on.</b></font> Attack: 2 set pieces Lv.3 · 3 pieces Lv.6 · 6 pieces Lv.6 + 👑 awakening · Defense: 🔷 Guard Stone level (max 2 slots) · slot upgrades stay with the slot" }, panel)

	-- 칸 3개
	local cards = {}
	for i = 1, S.Count do
		local card = make("Frame", { Size = UDim2.new(0, 312, 0, 150), Position = UDim2.new(0, 16 + (i - 1) * 324, 0, 68), BackgroundColor3 = Color3.fromRGB(29, 27, 45), BorderSizePixel = 0, ZIndex = 3 }, panel)
		corner(card, 14)
		local stroke = make("UIStroke", { Color = Color3.fromRGB(58, 52, 86), Thickness = 2 }, card)
		local chip = text({ Size = UDim2.new(0, 52, 0, 18), Position = UDim2.new(0, 10, 0, -9), BackgroundTransparency = 0, BackgroundColor3 = GOLD, TextColor3 = Color3.fromRGB(42, 26, 0),
			Text = string.format("Slot %d", i), TextSize = 11, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, card)
		corner(chip, 9)
		local plus = text({ Size = UDim2.new(0, 60, 0, 26), Position = UDim2.new(1, -68, 0, 8), Text = "", TextSize = 20, Font = Enum.Font.GothamBlack, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right }, card)
		local name = text({ Size = UDim2.new(1, -80, 0, 24), Position = UDim2.new(0, 12, 0, 12), Text = "", TextSize = 16, Font = Enum.Font.GothamBlack, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		local src = text({ Size = UDim2.new(1, -24, 0, 16), Position = UDim2.new(0, 12, 0, 38), Text = "", TextSize = 11, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		local tags = text({ Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 0, 58), Text = "", TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		local m5 = text({ Size = UDim2.new(0.5, -16, 0, 34), Position = UDim2.new(0, 12, 0, 82), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(38, 36, 58), Text = "", TextSize = 10, TextWrapped = true, TextColor3 = MUTED }, card)
		local m10 = text({ Size = UDim2.new(0.5, -16, 0, 34), Position = UDim2.new(0.5, 4, 0, 82), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(38, 36, 58), Text = "", TextSize = 10, TextWrapped = true, TextColor3 = MUTED }, card)
		corner(m5, 8) corner(m10, 8)
		make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 4) }, m5)
		make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 4) }, m10)
		local barBack = make("Frame", { Size = UDim2.new(1, -24, 0, 7), Position = UDim2.new(0, 12, 0, 128), BackgroundColor3 = Color3.fromRGB(43, 42, 68), BorderSizePixel = 0, ZIndex = 4 }, card)
		corner(barBack, 4)
		local bar = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 5 }, barBack)
		corner(bar, 4)
		local hit = make("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 7 }, card)
		hit.Activated:Connect(function() selectedSlot = i UI.Refresh() end)
		local clear = button({ Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(1, -16, 0, -8), BackgroundColor3 = Color3.fromRGB(150, 50, 70), Text = "✕", TextSize = 11, ZIndex = 9 }, card, function()
			Remotes.Aug:FireServer("Slot", i, 0)
		end)
		cards[i] = { Card = card, Stroke = stroke, Plus = plus, Name = name, Src = src, Tags = tags, M5 = m5, M10 = m10, Bar = bar, Clear = clear }
	end

	-- 후보 목록
	local list = make("Frame", { Size = UDim2.new(0, 620, 0, 262), Position = UDim2.new(0, 16, 0, 230), BackgroundColor3 = Color3.fromRGB(27, 26, 42), BorderSizePixel = 0, ZIndex = 3 }, panel)
	corner(list, 14)
	local tabs = {}
	for k, key in ipairs({ "Attack", "Defense" }) do
		tabs[key] = button({ Size = UDim2.new(0, 110, 0, 28), Position = UDim2.new(0, 10 + (k - 1) * 118, 0, 10), BackgroundColor3 = Color3.fromRGB(34, 33, 58),
			Text = key == "Attack" and "⚔ Attack" or "🛡 Defense", TextSize = 13 }, list, function() tab = key UI.Refresh() end)
	end
	local pickHint = text({ Size = UDim2.new(0, 360, 0, 28), Position = UDim2.new(1, -370, 0, 10), Text = "", TextSize = 11, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right }, list)
	local grid = make("ScrollingFrame", { Size = UDim2.new(1, -20, 0, 188), Position = UDim2.new(0, 10, 0, 46), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 4 }, list)
	make("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 52), CellPadding = UDim2.new(0, 8, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local note = text({ Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 1, -24), Text = "", TextSize = 11, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.AtEnd }, list)

	-- 칸 강화
	local enh = make("Frame", { Size = UDim2.new(0, 340, 0, 262), Position = UDim2.new(0, 644, 0, 230), BackgroundColor3 = Color3.fromRGB(27, 26, 42), BorderSizePixel = 0, ZIndex = 3 }, panel)
	corner(enh, 14)
	local enhTitle = text({ Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 12, 0, 10), Text = "", TextSize = 15, Font = Enum.Font.GothamBlack }, enh)
	text({ Size = UDim2.new(1, -20, 0, 14), Position = UDim2.new(0, 12, 0, 32), Text = "(stays with the slot, whatever you put in it)", TextSize = 10, TextColor3 = MUTED }, enh)
	local enhLv = text({ Size = UDim2.new(1, -20, 0, 34), Position = UDim2.new(0, 12, 0, 52), Text = "", TextSize = 26, Font = Enum.Font.GothamBlack }, enh)
	local enhStat = text({ Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 12, 0, 92), Text = "", TextSize = 12, TextColor3 = Color3.fromRGB(220, 218, 245) }, enh)
	local enhGoal = text({ Size = UDim2.new(1, -20, 0, 36), Position = UDim2.new(0, 12, 0, 114), Text = "", TextSize = 12, TextWrapped = true }, enh)
	local enhButton = button({ Size = UDim2.new(1, -24, 0, 44), Position = UDim2.new(0, 12, 0, 160), BackgroundColor3 = Color3.fromRGB(59, 180, 74), Text = "", TextSize = 16, Font = Enum.Font.GothamBlack }, enh, function()
		Remotes.Aug:FireServer("SlotUp", selectedSlot)
	end)
	local enhNote = text({ Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 12, 0, 212), Text = "", TextSize = 11, TextWrapped = true, TextColor3 = MUTED }, enh)

	-- 조합 비교 카드 (고정 예시: 정답이 하나가 아니라는 안내)
	local examples = {
		{ "⚔3 + ⚔3 + 🛡1 · wide", "⚔ Lv6 · ⚔ Lv6 · 🛡 Lv6", "⚡ x2.74 · damage taken −45% (EHP 1.82×)" },
		{ "⚔6 + 🛡2 · sturdy", "⚔ Lv6 👑 · 🛡 Lv6 · 🛡 Lv6 (60%)", "⚡ x2.68 · EHP 1.82 × 1.24 = 2.25×" },
		{ "⚔3 + 🛡2 · a unique in the spare piece", "⚔ Lv6 · 🛡 Lv6 · 🛡 Lv6 (60%)", "⚡ x2.20 · survival 2.25× · 2-piece Lv3 → no slot · set bonus only" },
	}
	for k, ex in ipairs(examples) do
		local c = make("Frame", { Size = UDim2.new(0, 314, 0, 128), Position = UDim2.new(0, 16 + (k - 1) * 323, 0, 502), BackgroundColor3 = Color3.fromRGB(27, 26, 42), BorderSizePixel = 0, ZIndex = 3 }, panel)
		corner(c, 14)
		text({ Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 0, 8), Text = "<b>" .. ex[1] .. "</b>", TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd }, c)
		text({ Size = UDim2.new(1, -20, 0, 26), Position = UDim2.new(0, 10, 0, 34), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(38, 36, 58), Text = ex[2], TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center }, c).ZIndex = 5
		text({ Size = UDim2.new(1, -20, 0, 54), Position = UDim2.new(0, 10, 0, 66), Text = ex[3], TextSize = 11, TextWrapped = true, TextColor3 = Color3.fromRGB(220, 218, 245), TextYAlignment = Enum.TextYAlignment.Top }, c)
	end

	local function slotZone(i) return attr("AugSlotZ_" .. i) or 0 end
	local function slotOf(z) for i = 1, S.Count do if slotZone(i) == z then return i end end return nil end

	local function candidate(z, order)
		local info = infoOf(z)
		local level = attr("AugGearZ_" .. z) or 0
		local inSlot = slotOf(z)
		local row = make("TextButton", { BackgroundColor3 = Color3.fromRGB(34, 33, 58), Text = "", AutoButtonColor = true, LayoutOrder = order, ZIndex = 5 }, grid)
		corner(row, 10)
		if inSlot then make("UIStroke", { Color = GOLD, Thickness = 2 }, row) end
		text({ Size = UDim2.new(0, 34, 1, 0), Position = UDim2.new(0, 6, 0, 0), Text = info.Icon, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, row)
		local sub
		if isDefense(z) then
			sub = string.format("🔷 Guard Stone %d/6", attr("AugStoneZ_" .. z) or 0)
		else
			local def = setOf(z)
			local pieces = attr("AugSetZ_" .. z) or 0
			sub = string.format("%s %d/6", def and def.Name or "", pieces) .. (pieces < 2 and " · 2 pieces needed" or "")
		end
		if inSlot then sub = string.format("In slot %d", inSlot) end
		text({ Size = UDim2.new(1, -120, 0, 18), Position = UDim2.new(0, 44, 0, 7), Text = "<b>" .. info.Name .. "</b>", TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6 }, row)
		text({ Size = UDim2.new(1, -120, 0, 16), Position = UDim2.new(0, 44, 0, 27), Text = sub, TextSize = 10, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6 }, row)
		local awake = attr("AugAwakeZ_" .. z) == true
		text({ Size = UDim2.new(0, 66, 1, 0), Position = UDim2.new(1, -72, 0, 0), Text = level > 0 and (string.format("Lv.%d", level) .. (awake and " 👑" or "")) or "—", TextSize = 13, Font = Enum.Font.GothamBlack,
			TextColor3 = awake and Color3.fromRGB(255, 155, 230) or (level > 0 and Color3.new(1, 1, 1) or MUTED), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6 }, row)
		row.Activated:Connect(function()
			if level <= 0 then return end
			Remotes.Aug:FireServer("Slot", selectedSlot, z)
		end)
		if isDefense(z) then -- 🔷 수호석 단계 올리기 (마을)
			local stone = attr("AugStoneZ_" .. z) or 0
			local need = Config.Guard.StoneCost[stone + 1]
			if need then
				local ready = atTown() and (attr("GuardStones") or 0) >= need
				local up = button({ Size = UDim2.new(0, 64, 0, 20), Position = UDim2.new(1, -140, 0, 16), BackgroundColor3 = ready and Color3.fromRGB(50, 120, 190) or Color3.fromRGB(60, 62, 80),
					Text = string.format("🔷 %d", need), TextSize = 11, ZIndex = 8 }, row, function() Remotes.Aug:FireServer("Stone", z) end)
				up.AutoButtonColor = ready
			end
		end
	end

	function UI.Refresh()
		resLabel.Text = string.format("🔷 Guard Stone %d · 💰 %s", attr("GuardStones") or 0, commas(attr("Gold") or 0))
		for i, c in ipairs(cards) do
			local z = slotZone(i)
			local lv = attr("AugSlotLv_" .. i) or 0
			local on = z > 0 and attr("AugOnZ_" .. z) == true
			c.Plus.Text = "+" .. lv
			c.Bar.Size = UDim2.new(lv / S.MaxLevel, 0, 1, 0)
			c.Stroke.Color = i == selectedSlot and GOLD or (z > 0 and (isDefense(z) and DEF or ATK) or Color3.fromRGB(58, 52, 86))
			c.Stroke.Thickness = i == selectedSlot and 3 or 2
			c.Clear.Visible = z > 0
			if z == 0 then
				c.Name.Text = "<font color='#9a98bf'>Empty</font>"
				c.Src.Text = "Pick an effect below"
				c.Tags.Text = ""
				c.M5.Text = "<b>+5</b> " .. "bonus effect"
				c.M10.Text = "<b>+10</b> " .. "bonus effect"
			else
				local info = infoOf(z)
				local level = attr("AugGearZ_" .. z) or 0
				c.Name.Text = string.format("%s %s Lv.%d", info.Icon, info.Name, level)
				if isDefense(z) then
					local eff = attr("AugSlotEff_" .. i) or 1
					c.Src.Text = string.format("🔷 Guard Stone %d/6", attr("AugStoneZ_" .. z) or 0) .. (eff < 1 and string.format(" · <font color='#ffb84d'>2nd defense = %d%%</font>", math.floor(eff * 100 + 0.5)) or "")
					c.Tags.Text = on and ("<font color='#78ff8c'>" .. select(1, Config.AugLevelLine(Config.Sets.ZoneAug[z], level)) .. "</font>") or "<font color='#9a98bf'>off</font>"
				else
					local def = setOf(z)
					local pieces = attr("AugSetZ_" .. z) or 0
					c.Src.Text = string.format("%s %s <font color='#78ff8c'>%s %d/6</font>", def and def.Icon or "", def and def.Name or "", dots(pieces), pieces)
					local awake = attr("AugAwakeZ_" .. z) == true and Config.AugAwaken[Config.Sets.ZoneAug[z]]
					c.Tags.Text = (level >= 4 and string.format("<font color='#78ff8c'>★ Lv.%d</font>", level) or string.format("<font color='#9a98bf'>Lv.%d · no ★</font>", level))
						.. (awake and ("  <font color='#ff9be6'>👑 Awakening: " .. awake.Name .. "</font>") or "")
				end
				local ten = Config.AugSlotTen[Config.Sets.ZoneAug[z]] or ""
				c.M5.Text = (lv >= 5 and "<font color='#78ff8c'><b>+5 ✔</b></font> " or "<b>+5</b> ") .. plusFive(z)
				c.M10.Text = (lv >= 10 and "<font color='#78ff8c'><b>+10 ✔</b></font> " or "<b>+10</b> ") .. ten
			end
			c.M5.BackgroundColor3 = lv >= 5 and Color3.fromRGB(31, 58, 36) or Color3.fromRGB(38, 36, 58)
			c.M10.BackgroundColor3 = lv >= 10 and Color3.fromRGB(31, 58, 36) or Color3.fromRGB(38, 36, 58)
		end
		-- 후보
		for key, b in pairs(tabs) do
			b.BackgroundColor3 = key == tab and Color3.fromRGB(90, 74, 30) or Color3.fromRGB(34, 33, 58)
		end
		pickHint.Text = string.format("Tap to put it in Slot %d", selectedSlot)
		for _, child in ipairs(grid:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
		local order, locked = 0, 0
		for z = 1, ZONES do
			if (tab == "Defense") == isDefense(z) then
				if attr("AugOpenZ_" .. z) == true then
					order += 1
					candidate(z, order)
				else
					locked += 1
				end
			end
		end
		if locked > 0 then
			local more = button({ BackgroundColor3 = Color3.fromRGB(30, 29, 46), Text = string.format(showLocked and "▾ 🔒 Locked effects %d (hide)" or "▸ 🔒 Locked effects %d (show)", locked),
				TextSize = 11, TextColor3 = MUTED, LayoutOrder = 100 }, grid, function() showLocked = not showLocked UI.Refresh() end)
			more.Name = "Locked"
			if showLocked then
				for z = 1, ZONES do
					if (tab == "Defense") == isDefense(z) and attr("AugOpenZ_" .. z) ~= true then
						local info = infoOf(z)
						text({ BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(30, 29, 46), Text = string.format("  %s %s · <font color='#6c6a88'>🔒 Zone %d lord</font>", info.Icon, info.Name, homeZone(z)),
							TextSize = 12, TextColor3 = MUTED, LayoutOrder = 100 + z, ZIndex = 5 }, grid)
					end
				end
			end
		end
		note.Text = tab == "Attack" and "2 pieces Lv.3 = no ★ bonus · a +1 option making it Lv.4–5 turns on ★4·★5 · 3+ pieces Lv.6 · 6 pieces 👑 awakening"
			or "Defense: up to 2 slots · the lower one works at 60% · set defense cuts damage taken by at most 55%"
		-- 강화
		local lv = attr("AugSlotLv_" .. selectedSlot) or 0
		local z = slotZone(selectedSlot)
		enhTitle.Text = string.format("🔨 Slot %d upgrade", selectedSlot)
		local cost = S.Cost[lv + 1]
		if cost then
			enhLv.Text = string.format("+%d ▸ <font color='#78ff8c'>+%d</font>", lv, lv + 1)
			enhStat.Text = string.format("Slot power +%d%% → +%d%% · ⚡ +0.1 level", math.floor(S.StepMult * lv * 100 + 0.5), math.floor(S.StepMult * (lv + 1) * 100 + 0.5))
			local goal = lv < 5 and 5 or 10
			local goalText = goal == 5 and (z > 0 and plusFive(z) or "bonus effect") or (z > 0 and Config.AugSlotTen[Config.Sets.ZoneAug[z]] or "bonus effect")
			enhGoal.Text = string.format("🎯 Next goal +%d · %s (%d left)", goal, goalText, goal - lv)
			local gold = attr("Gold") or 0
			if not atTown() then
				enhButton.Text = "🏘 Upgrade in town"
				enhButton.BackgroundColor3 = Color3.fromRGB(60, 62, 80)
			else
				enhButton.Text = string.format("+%d upgrade 💰 %s", lv + 1, commas(cost))
				enhButton.BackgroundColor3 = gold >= cost and Color3.fromRGB(59, 180, 74) or Color3.fromRGB(70, 74, 92)
			end
		else
			enhLv.Text = string.format("<font color='#78ff8c'>+%d</font>", lv)
			enhStat.Text = string.format("Slot power +%d%%", math.floor(S.StepMult * lv * 100 + 0.5))
			enhGoal.Text = "<font color='#78ff8c'>+5 ✔ · +10 ✔</font>"
			enhButton.Text = "Max +10"
			enhButton.BackgroundColor3 = Color3.fromRGB(60, 62, 80)
		end
		enhNote.Text = "Gold only · fixed price per step (same for every slot)"
	end

	function UI.Focus(zone) -- 장비 창 "내 세트" ✨: 그 효과가 든 칸을 고르고 그 탭을 연다
		tab = isDefense(zone) and "Defense" or "Attack"
		selectedSlot = slotOf(zone) or selectedSlot
		UI.Refresh()
	end

	local watch = { "Gold", "TutorialActive", "Zone", "GuardStones" }
	for i = 1, S.Count do
		table.insert(watch, "AugSlotZ_" .. i) table.insert(watch, "AugSlotLv_" .. i) table.insert(watch, "AugSlotEff_" .. i)
	end
	for z = 1, ZONES do
		for _, prefix in ipairs({ "AugOpenZ_", "AugOnZ_", "AugGearZ_", "AugStoneZ_", "AugSetZ_", "AugAwakeZ_" }) do table.insert(watch, prefix .. z) end
	end
	local queued = false
	for _, name in ipairs(watch) do
		player:GetAttributeChangedSignal(name):Connect(function()
			if queued then return end
			queued = true
			task.defer(function() queued = false if panel.Visible then UI.Refresh() end end)
		end)
	end
	panel:GetPropertyChangedSignal("Visible"):Connect(function() if panel.Visible then UI.Refresh() end end)
	UI.Refresh()
	return UI
end

return UI
