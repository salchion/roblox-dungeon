-- AugSlotsUI (StarterPlayer > StarterPlayerScripts 안의 ModuleScript, 이름: AugSlotsUI)
-- 🌟 세트 효과 창(Y) 안쪽 (11-26 목업 slots5 "게임 느낌"): 빛나는 원형 소켓 3개 + 소켓 아래 강화 보석 줄(● 10개, +5 / +10 은 ★) + 둥근 강화 버튼
--   아래 = 넣을 수 있는 효과를 동그란 보석으로 (⚔ 공격 줄 / 🛡 방어 줄, 탭 없음). 이미 칸에 든 효과는 목록에서 뺀다. 잠긴 효과는 작은 흑백 아이콘 한 줄.
--   AugClient 가 만든 panel 에 그린다: require(...).Build(panel) -> { Refresh, Focus }
--   값은 서버(AugService)가 채우는 Attribute 만 읽고, 바꾸는 것은 Remotes.Aug "Slot" / "SlotUp" / "Stone" 으로 보낸다.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local hoverPreview = not (UIS.TouchEnabled and not UIS.MouseEnabled) -- (마우스가 있는 기기에서만 마우스 올리기 미리 보기)
local S = Config.AugSlots
local ZONES = #Config.Sets.ZoneAug
local GOLD = Color3.fromRGB(201, 162, 74)
local GOLD_HI = Color3.fromRGB(255, 226, 122)
local CREAM = Color3.fromRGB(255, 233, 168)
local MUTED = Color3.fromRGB(184, 168, 208)
local DIM = Color3.fromRGB(122, 106, 144)
local ATK = Color3.fromRGB(201, 138, 58)
local DEF = Color3.fromRGB(106, 176, 232)

local UI = {}

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end
local function round(inst, r) make("UICorner", { CornerRadius = r and UDim.new(0, r) or UDim.new(1, 0) }, inst) return inst end
local function text(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextSize = props.TextSize or 13
	props.RichText = true
	props.ZIndex = props.ZIndex or 4
	return make("TextLabel", props, parent)
end
local function commas(n)
	return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function infoOf(z) return Config.AugInfo[Config.Sets.ZoneAug[z] or ""] end
local function isDefense(z) local i = infoOf(z) return i ~= nil and i.Defense == true end
local function setOf(z) local key = Config.Sets.ZoneKeys[z] return key and Config.Sets[key] end
local function attr(name) return player:GetAttribute(name) end
local function atTown() return attr("Zone") == "Lobby" or attr("TutorialActive") == true end
local function plusFive(z) return isDefense(z) and "effect value +20%" or "10% chance to fire again" end
local function tenText(z) return Config.AugSlotTen[Config.Sets.ZoneAug[z] or ""] or "bonus effect" end

-- 동그란 보석 (소켓 / 후보 공용): 바깥 금테 + 안쪽 색 + 가운데 아이콘
local function orb(parent, size, props)
	local o = make("Frame", { Size = UDim2.new(0, size, 0, size), BackgroundColor3 = Color3.fromRGB(42, 26, 16), BorderSizePixel = 0, ZIndex = 4 }, parent)
	for k, v in pairs(props or {}) do o[k] = v end
	round(o)
	local grad = make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 110, 130)) }, o)
	local stroke = make("UIStroke", { Color = GOLD, Thickness = math.max(2, size / 18) }, o)
	local icon = text({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = math.floor(size * 0.48), ZIndex = 5, TextXAlignment = Enum.TextXAlignment.Center }, o)
	return o, stroke, icon, grad
end
local function badge(parent, props)
	local strokeColor = props.Stroke
	props.Stroke = nil -- (TextLabel 에 없는 속성: 그대로 넣으면 오류로 창 전체가 안 만들어졌다)
	local b = text(props, parent)
	b.BackgroundTransparency = 0
	round(b, 9)
	make("UIStroke", { Color = strokeColor or GOLD, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b) -- (Border: 글자 칸의 UIStroke 기본값은 글자 테두리라 금색이 글자를 뭉개고 있었다)
	return b
end

function UI.Build(panel)
	local selectedSlot, showLocked, preview = 1, false, nil -- (preview: PC 마우스를 올린 보석 / 레벨 0 이라 못 넣는 보석의 설명을 설명 줄에. 누르면 바로 고른 칸에 들어간다)
	local W = panel.Size.X.Offset > 0 and panel.Size.X.Offset or 1000

	text({ Size = UDim2.new(0, 260, 0, 34), Position = UDim2.new(0, 20, 0, 10), Text = "🌟 Set Effects", TextSize = 22, Font = Enum.Font.GothamBlack, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	local resLabel = badge(panel, { Size = UDim2.new(0, 210, 0, 26), Position = UDim2.new(0, 196, 0, 14), Text = "", TextSize = 13, TextColor3 = Color3.fromRGB(143, 224, 255), BackgroundColor3 = Color3.fromRGB(16, 12, 22), Stroke = Color3.fromRGB(70, 60, 90) })
	local close = make("TextButton", { Size = UDim2.new(0, 76, 0, 32), Position = UDim2.new(1, -92, 0, 12), BackgroundColor3 = Color3.fromRGB(58, 42, 18), Text = "Close", TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = CREAM, ZIndex = 6 }, panel)
	round(close, 12)
	make("UIStroke", { Color = GOLD, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, close)
	close.Activated:Connect(function() panel.Visible = false end)
	text({ Size = UDim2.new(1, -40, 0, 16), Position = UDim2.new(0, 20, 0, 46), Text = "Only effects in a slot are on · pick a slot, then tap a gem below", TextSize = 12, TextColor3 = Color3.fromRGB(201, 184, 138) }, panel)

	-- 소켓 3개
	local sockets = {}
	local RING = 124
	for i = 1, S.Count do
		local cx = W / 2 + (i - 2) * 300
		local holder = make("Frame", { Size = UDim2.new(0, 260, 0, 270), Position = UDim2.new(0, cx - 130, 0, 70), BackgroundTransparency = 1, ZIndex = 3 }, panel)
		local glow = make("Frame", { Size = UDim2.new(0, RING + 26, 0, RING + 26), Position = UDim2.new(0.5, -(RING + 26) / 2, 0, -13), BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 3 }, holder) -- (소켓 뒤 은은한 빛)
		round(glow)
		local ring, ringStroke, ringIcon = orb(holder, RING, { Position = UDim2.new(0.5, -RING / 2, 0, 0) })
		local plus = badge(holder, { Size = UDim2.new(0, 46, 0, 26), Position = UDim2.new(0.5, RING / 2 - 34, 0, -4), Text = "+0", TextSize = 16, Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.fromRGB(58, 32, 0), BackgroundColor3 = GOLD_HI, Stroke = Color3.fromRGB(255, 243, 192), ZIndex = 8 })
		local lv = badge(holder, { Size = UDim2.new(0, 76, 0, 22), Position = UDim2.new(0.5, -38, 0, RING - 12), Text = "", TextSize = 12, Font = Enum.Font.GothamBlack,
			TextColor3 = CREAM, BackgroundColor3 = Color3.fromRGB(18, 14, 24), ZIndex = 8 })
		local pips = text({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, RING + 16), Text = "", TextSize = 13 }, holder)
		local name = text({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, RING + 36), Text = "", TextSize = 15, Font = Enum.Font.GothamBlack, TextTruncate = Enum.TextTruncate.AtEnd }, holder)
		local src = text({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, RING + 56), Text = "", TextSize = 11, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.AtEnd }, holder)
		local goal = text({ Size = UDim2.new(1, 10, 0, 16), Position = UDim2.new(0, -5, 0, RING + 73), Text = "", TextSize = 11, TextColor3 = Color3.fromRGB(255, 217, 102), TextTruncate = Enum.TextTruncate.AtEnd }, holder)
		local up = make("TextButton", { Size = UDim2.new(0, 160, 0, 32), Position = UDim2.new(0.5, -80, 0, RING + 96), BackgroundColor3 = Color3.fromRGB(70, 180, 82), Text = "", TextSize = 13,
			Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1), ZIndex = 7 }, holder)
		round(up, 16)
		local upStroke = make("UIStroke", { Color = Color3.fromRGB(184, 255, 191), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, up)
		up.Activated:Connect(function() Remotes.Aug:FireServer("SlotUp", i) end)
		local pick = make("TextButton", { Size = UDim2.new(0, RING, 0, RING), Position = UDim2.new(0.5, -RING / 2, 0, 0), BackgroundTransparency = 1, Text = "", ZIndex = 7 }, holder)
		pick.Activated:Connect(function() selectedSlot = i preview = nil UI.Refresh() end)
		local clear = make("TextButton", { Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(0.5, -RING / 2 - 4, 0, -2), BackgroundColor3 = Color3.fromRGB(122, 32, 48), Text = "X", TextSize = 12,
			Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1), ZIndex = 9 }, holder)
		round(clear)
		make("UIStroke", { Color = Color3.fromRGB(255, 154, 168), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, clear)
		clear.Activated:Connect(function() Remotes.Aug:FireServer("Slot", i, 0) end)
		sockets[i] = { Ring = ring, Stroke = ringStroke, Icon = ringIcon, Glow = glow, Plus = plus, Lv = lv, Pips = pips, Name = name, Src = src, Goal = goal, Up = up, UpStroke = upStroke, Clear = clear }
	end

	-- 설명 줄: 고른 소켓(또는 미리 보는 보석)의 효과 설명 + 👑 각성 설명
	local info = make("Frame", { Size = UDim2.new(1, -40, 0, 44), Position = UDim2.new(0, 20, 0, 326), BackgroundColor3 = Color3.fromRGB(16, 12, 22), BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 3 }, panel)
	round(info, 12)
	make("UIStroke", { Color = GOLD, Thickness = 1, Transparency = 0.5 }, info)
	local infoIcon = text({ Size = UDim2.new(0, 40, 1, 0), Position = UDim2.new(0, 4, 0, 0), Text = "", TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center }, info)
	local infoLine1 = text({ Size = UDim2.new(1, -60, 0, 20), Position = UDim2.new(0, 48, 0, 3), Text = "", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, info)
	local infoLine2 = text({ Size = UDim2.new(1, -60, 0, 18), Position = UDim2.new(0, 48, 0, 23), Text = "", TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, info)

	make("Frame", { Size = UDim2.new(1, -40, 0, 2), Position = UDim2.new(0, 20, 0, 376), BackgroundColor3 = GOLD, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 3 }, panel)

	-- 후보: 공격 줄 / 방어 줄 (보석) + 잠긴 효과 한 줄
	local rows = {}
	for k, key in ipairs({ "Attack", "Defense" }) do
		local y = 384 + (k - 1) * 88
		text({ Size = UDim2.new(0, 86, 0, 40), Position = UDim2.new(0, 20, 0, y + 6), Text = key == "Attack" and "⚔ Attack" or "🛡 Defense", TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Left }, panel)
		if key == "Defense" then -- (방어는 최대 2칸: 3번째를 넣으려 해야 알던 규칙을 화면에)
			text({ Size = UDim2.new(0, 86, 0, 16), Position = UDim2.new(0, 20, 0, y + 42), Text = "max 2 slots", TextSize = 11, TextColor3 = Color3.fromRGB(255, 184, 77), TextXAlignment = Enum.TextXAlignment.Left }, panel)
		end
		local row = make("Frame", { Size = UDim2.new(1, -130, 0, 86), Position = UDim2.new(0, 110, 0, y), BackgroundTransparency = 1, ZIndex = 3 }, panel)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		local empty = text({ Size = UDim2.new(0, 400, 0, 56), Text = "", TextSize = 12, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left, Visible = false }, row)
		rows[key] = { Row = row, Empty = empty }
	end
	local lockRow = make("TextButton", { Size = UDim2.new(1, -40, 0, 26), Position = UDim2.new(0, 20, 0, 564), BackgroundTransparency = 1, Text = "", ZIndex = 4 }, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, lockRow)
	lockRow.Activated:Connect(function() showLocked = not showLocked UI.Refresh() end)

	local function slotZone(i) return attr("AugSlotZ_" .. i) or 0 end
	local function inSlot(z) for i = 1, S.Count do if slotZone(i) == z then return i end end return nil end

	local refreshInfo -- (아래에서 정의: 보석 버튼이 부른다)
	local gemStrokes = {} -- [구역] = { Stroke, Base } (미리 보는 보석 금테: 보석을 다시 만들지 않고 테두리만 바꾼다)
	local GEM_THICK = math.max(2, 52 / 18) -- (orb 기본 두께와 같게)
	local function gem(parent, z, order)
		local info = infoOf(z)
		local level = attr("AugGearZ_" .. z) or 0
		local def = isDefense(z)
		local cell = make("Frame", { Size = UDim2.new(0, 82, 0, 86), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 4 }, parent)
		local o, stroke, icon, grad = orb(cell, 52, { Position = UDim2.new(0.5, -26, 0, 2) })
		icon.Text = info.Icon
		o.BackgroundColor3 = def and Color3.fromRGB(26, 52, 84) or Color3.fromRGB(96, 60, 30)
		stroke.Color = def and DEF or ATK
		if level <= 0 then
			o.BackgroundColor3 = Color3.fromRGB(40, 36, 52)
			stroke.Color = Color3.fromRGB(80, 72, 96)
			icon.TextTransparency = 0.55
		end
		if level > 0 then
			badge(cell, { Size = UDim2.new(0, 38, 0, 16), Position = UDim2.new(0.5, 6, 0, 42), Text = "Lv." .. level .. (attr("AugAwakeZ_" .. z) == true and "👑" or ""), TextSize = 10, Font = Enum.Font.GothamBlack,
				TextColor3 = CREAM, BackgroundColor3 = Color3.fromRGB(18, 14, 24), ZIndex = 7 })
		end
		text({ Size = UDim2.new(1, 4, 0, 14), Position = UDim2.new(0, -2, 0, 60), Text = info.Name, TextSize = 11, TextColor3 = level > 0 and Color3.new(1, 1, 1) or DIM, TextTruncate = Enum.TextTruncate.AtEnd }, cell)
		local sub
		if def then
			sub = string.format("Guard Stone %d/6", attr("AugStoneZ_" .. z) or 0)
		else
			local pieces = attr("AugSetZ_" .. z) or 0
			local setDef = setOf(z)
			sub = pieces < 2 and string.format("%d/6 · from 2 pieces", pieces) or string.format("%s %d/6", setDef and setDef.Prefix or "", pieces)
		end
		text({ Size = UDim2.new(1, 10, 0, 12), Position = UDim2.new(0, -5, 0, 75), Text = sub, TextSize = 9, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.AtEnd }, cell)
		local hit = make("TextButton", { Size = UDim2.new(0, 52, 0, 52), Position = UDim2.new(0.5, -26, 0, 2), BackgroundTransparency = 1, Text = "", ZIndex = 8 }, cell)
		gemStrokes[z] = { Stroke = stroke, Base = stroke.Color }
		hit.Activated:Connect(function() -- (11-28) 폰 / PC 모두 한 번 누르면 바로 고른 칸에. 못 넣는 효과(레벨 0)는 설명만 보여 준다
			preview = z
			if level > 0 then
				Remotes.Aug:FireServer("Slot", selectedSlot, z)
			elseif not def and attr("AugOpenZ_" .. z) == true then -- (아직 못 넣는 공격 효과: 그 세트 가장 좋은 조각을 끼우고 바로 칸에. 조각이 2개 안 되면 서버가 알려 준다)
				Remotes.Aug:FireServer("Wear", selectedSlot, z)
			end -- (들어가면 서버 속성이 바뀌어 전체 Refresh 가 따로 돈다: 그때 설명 줄은 칸에 든 그 효과)
			refreshInfo()
		end)
		if hoverPreview then -- (PC 만: 폰은 탭 시작 때 MouseEnter 가 먼저 와서, 여기서 다시 그리면 누르고 있는 버튼이 지워져 Activated 가 안 왔다)
			hit.MouseEnter:Connect(function()
				if preview ~= z then preview = z refreshInfo() end
			end)
		end
		if def then -- 🔷 수호석 단계 올리기 (마을)
			local need = Config.Guard.StoneCost[(attr("AugStoneZ_" .. z) or 0) + 1]
			if need then
				local ready = atTown() and (attr("GuardStones") or 0) >= need
				local sb = make("TextButton", { Size = UDim2.new(0, 36, 0, 18), Position = UDim2.new(0.5, 8, 0, -4), BackgroundColor3 = ready and Color3.fromRGB(47, 91, 214) or Color3.fromRGB(70, 66, 86),
					Text = "🔷" .. need, TextSize = 10, Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1), ZIndex = 9 }, cell)
				round(sb, 9)
				make("UIStroke", { Color = Color3.fromRGB(159, 192, 255), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, sb)
				sb.Activated:Connect(function() Remotes.Aug:FireServer("Stone", z) end)
			end
		end
	end

	-- 설명 줄만 다시 쓴다 (보석 / 소켓 버튼은 그대로 둔다: 누르고 있는 버튼을 지우지 않게)
	refreshInfo = function()
		if preview and inSlot(preview) then preview = nil end
		local z = preview or slotZone(selectedSlot)
		local zi = z > 0 and infoOf(z)
		if not zi then
			infoIcon.Text = "💡"
			infoLine1.Text = string.format("Tap a gem below to put it in Slot %d", selectedSlot)
			infoLine2.Text = ""
		else
			local level = attr("AugGearZ_" .. z) or 0
			local aw = attr("AugAwakeZ_" .. z) == true and Config.AugAwaken[Config.Sets.ZoneAug[z]]
			infoIcon.Text = zi.Icon
			infoLine1.Text = string.format("<b>%s</b>  <font color='#d8cce8'>%s</font>", zi.Name, zi.Desc or "")
			if aw then
				infoLine2.Text = "<font color='#ff9be6'>" .. string.format("👑 Awakening: %s", aw.Name) .. "</font>  " .. aw.Desc
			elseif level <= 0 then
				infoLine2.Text = isDefense(z) and "Collect Guard Stones" or "Tap: wear your best pieces of this set and put it in the slot"
			elseif preview then
				infoLine2.Text = string.format("Tap or click to put it in Slot %d", selectedSlot)
			elseif not isDefense(z) then
				infoLine2.Text = "<font color='#9a8ab8'>" .. "6 pieces 👑 awakening" .. "</font>"
			else
				infoLine2.Text = ""
			end
		end
		for gz, g in pairs(gemStrokes) do -- 미리 보는 보석만 금테, 나머지는 원래 색으로
			if g.Stroke.Parent then
				g.Stroke.Color = preview == gz and GOLD_HI or g.Base
				g.Stroke.Thickness = preview == gz and 4 or GEM_THICK
			end
		end
	end

	function UI.Refresh()
		gemStrokes = {} -- (아래에서 보석을 다시 만들며 새로 담는다: 지워진 보석의 테두리가 남지 않게)
		resLabel.Text = string.format("🔷 %d · 💰 %s", attr("GuardStones") or 0, commas(attr("Gold") or 0))
		for i, s in ipairs(sockets) do
			local z = slotZone(i)
			local lv = attr("AugSlotLv_" .. i) or 0
			local sel = i == selectedSlot
			local info = z > 0 and infoOf(z)
			local def = z > 0 and isDefense(z)
			s.Plus.Text = "+" .. lv
			s.Clear.Visible = z > 0
			s.Ring.BackgroundColor3 = not info and Color3.fromRGB(34, 28, 44) or (def and Color3.fromRGB(24, 48, 80) or Color3.fromRGB(80, 32, 34))
			s.Stroke.Color = sel and GOLD_HI or (not info and Color3.fromRGB(106, 96, 128) or (def and Color3.fromRGB(143, 208, 255) or GOLD))
			s.Stroke.Thickness = sel and 9 or 7
			s.Glow.BackgroundColor3 = not info and Color3.fromRGB(60, 50, 80) or (def and Color3.fromRGB(90, 176, 255) or Color3.fromRGB(255, 138, 58))
			s.Glow.BackgroundTransparency = sel and 0.45 or 0.75
			s.Icon.Text = info and info.Icon or "＋"
			s.Icon.TextTransparency = info and 0 or 0.5
			-- 강화 보석 줄: ● x10, +5 / +10 자리는 ★ (✦ / ◆ 는 게임 글꼴에 없어 네모 / 작은 점으로 나왔다)
			local p = {}
			for k = 1, S.MaxLevel do
				local mark = (k == 5 or k == 10) and "<font size='17'>★</font>" or "●"
				table.insert(p, string.format("<font color='%s'>%s</font>", k <= lv and "#ffd966" or "#4a4060", mark))
			end
			s.Pips.Text = table.concat(p, " ")
			if not info then
				s.Lv.Visible = false
				s.Name.Text = "<font color='#9a8ab8'>Empty slot</font>"
				s.Src.Text = "Pick one below"
				s.Goal.Text = ""
			else
				local level = attr("AugGearZ_" .. z) or 0
				s.Lv.Visible = true
				s.Lv.Text = string.format("Lv.%d", level) .. (attr("AugAwakeZ_" .. z) == true and " 👑" or (not def and level >= 4 and " ★" or ""))
				s.Name.Text = info.Name
				if def then
					local eff = attr("AugSlotEff_" .. i) or 1
					s.Src.Text = string.format("🔷 Guard Stone %d/6", attr("AugStoneZ_" .. z) or 0) .. (eff < 1 and string.format(" · <font color='#ffb84d'>2nd defense = %d%%</font>", math.floor(eff * 100 + 0.5)) or "")
				else
					local setDef = setOf(z)
					s.Src.Text = string.format("%s <font color='#d8cce8'>%s</font> <font color='#78ff8c'>%d/6</font>", setDef and setDef.Icon or "", setDef and setDef.Name or "", attr("AugSetZ_" .. z) or 0) -- (세트 이름은 따로 감싸야 통째로 번역된다: "사막 Sun" 처럼 반만 번역됐다)
				end
				if lv >= 10 then
					s.Goal.Text = "<font color='#78ff8c'>✔ +10 </font><font color='#78ff8c'>" .. tenText(z) .. "</font>"
				else
					local g = lv < 5 and 5 or 10
					s.Goal.Text = string.format("🎯 +%d <font color='#ffe9a8'>%s</font> · %d left", g, g == 5 and plusFive(z) or tenText(z), g - lv) -- (효과 문구를 따로 감싸야 번역된다)
				end
			end
			local cost = S.Cost[lv + 1]
			if not cost then
				s.Up.Text = "Max +10"
				s.Up.BackgroundColor3 = Color3.fromRGB(70, 66, 86)
				s.UpStroke.Color = Color3.fromRGB(120, 110, 140)
			elseif not atTown() then
				s.Up.Text = "🏘 Upgrade in town"
				s.Up.BackgroundColor3 = Color3.fromRGB(70, 66, 86)
				s.UpStroke.Color = Color3.fromRGB(120, 110, 140)
			else
				local ok = (attr("Gold") or 0) >= cost
				s.Up.Text = string.format("🔨 +%d · 💰 %s", lv + 1, commas(cost))
				s.Up.BackgroundColor3 = ok and Color3.fromRGB(70, 180, 82) or Color3.fromRGB(70, 74, 92)
				s.UpStroke.Color = ok and Color3.fromRGB(184, 255, 191) or Color3.fromRGB(120, 110, 140)
			end
		end
		-- 후보 보석
		local locked = {}
		for key, r in pairs(rows) do
			for _, child in ipairs(r.Row:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
			local n = 0
			for z = 1, ZONES do
				if (key == "Defense") == isDefense(z) and not inSlot(z) then
					if attr("AugOpenZ_" .. z) == true then
						n += 1
						gem(r.Row, z, z)
					else
						table.insert(locked, z)
					end
				end
			end
			r.Empty.Visible = n == 0
			r.Empty.Text = "—"
		end
		for _, child in ipairs(lockRow:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
		if #locked > 0 then
			text({ Size = UDim2.new(0, 120, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = "🔒 Locked effects", TextSize = 12, TextColor3 = DIM, LayoutOrder = 0 }, lockRow)
			for k, z in ipairs(locked) do
				local mini = make("Frame", { Size = UDim2.new(0, 24, 0, 24), BackgroundColor3 = Color3.fromRGB(42, 36, 54), LayoutOrder = k, ZIndex = 5 }, lockRow)
				round(mini)
				text({ Size = UDim2.new(1, 0, 1, 0), Text = infoOf(z).Icon, TextSize = 12, TextTransparency = 0.5, ZIndex = 6 }, mini)
			end
			text({ Size = UDim2.new(0, 200, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = "defeat zone lords to unlock", TextSize = 12, TextColor3 = DIM, LayoutOrder = 100 }, lockRow)
		end
		refreshInfo() -- (보석을 다 만든 뒤: 설명 줄 + 미리 보는 보석 금테)
	end

	function UI.Focus(zone) -- 장비 창 "내 세트" ✨: 그 효과가 든 칸을 고른다
		selectedSlot = inSlot(zone) or selectedSlot
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
