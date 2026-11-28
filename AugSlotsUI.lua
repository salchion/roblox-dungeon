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
-- 🔫 어울리는 무기 (Config.AugRoles): 지금 무기가 맞으면 초록 "✔ 🔫 이름 +40%", 아니면 "🔫 어울리는 무기: A / B"
local function weaponText(z)
	local attrName = Config.Sets.ZoneAug[z] or ""
	local role = Config.AugRoles and Config.AugRoles[attrName]
	if not role or not role.Weapons then return nil, false end
	local names = {}
	for _, key in ipairs(role.Weapons) do
		local w = Config.WeaponTypes[key]
		table.insert(names, "<font>" .. (w and w.Name or key) .. "</font>") -- (이름마다 따로 감싸야 각각 번역된다)
	end
	local match = Config.AugWeaponMatch(player, attrName) == true
	local bonus = math.floor(((Config.AugWeaponBonus or 1.4) - 1) * 100 + 0.5)
	if match then
		return "<font color='#78ff8c'>✔ 🔫 </font>" .. table.concat(names, " / ") .. string.format("<font color='#78ff8c'> +%d%%</font>", bonus), true
	end
	return "<font color='#ffcf8a'>🔫 Best with </font>" .. table.concat(names, " / ") .. string.format("<font color='#9a8ab8'> (+%d%%)</font>", bonus), false
end
-- 🔷 지금(마을에서) 수호석으로 바로 올릴 수 있나: 다음 단계 비용 (아니면 nil). 메뉴 "세트" 버튼 빨간 점(MenuDockClient)과 같은 규칙
local function stoneReadyCost(z)
	if not isDefense(z) or attr("AugOpenZ_" .. z) ~= true or not atTown() then return nil end
	local stone = attr("AugStoneZ_" .. z) or 0
	local need = Config.Guard.StoneCost[stone + 1]
	if need and (attr("GuardStones") or 0) >= need then return need, stone + 1 end
	return nil
end
-- 지금 단계에서 실제로 하는 일 한 줄 (Config.AugLevelLine 의 단계 문장, "★추가 효과" 꼬리는 뺀다)
local function levelLine(z, level)
	if level <= 0 then return nil end
	local text = Config.AugLevelLine(Config.Sets.ZoneAug[z], math.min(6, level))
	text = string.split(text, " · ★")[1]
	return text ~= "" and text or nil
end
-- 아래 보석의 짧은 역할 (무슨 효과인지 한눈에)
local ROLE = {
	AugPulse = "Blast shells at nearby foes", AugOrbit = "Bouncing blades", AugStorm = "Lightning strikes", AugMissile = "Missiles on crit",
	AugNova = "Kill explosions", AugFlame = "Stacking burn", AugExecute = "Finishes weak foes", AugMeteor = "Meteors on crowds",
	AugWard = "Less damage taken", AugBody = "More max HP", AugBuffer = "Spread damage over 3s", AugEvade = "Dodge hits",
	AugGrit = "Tougher at low HP", AugRegen = "Heal in combat",
}
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
	local selectedSlot, showLocked, preview, picked = 1, false, nil, nil -- (picked: 눌러서 고른 보석 = 위 소켓 중 넣을 칸을 고르는 중. 칸을 누를 때만 서버에 보낸다)
	local refreshTargets, refreshInfo -- (아래에서 정의: 소켓 / 보석 / 빈 곳 버튼이 부른다) -- (preview: PC 마우스를 올린 보석 / 레벨 0 이라 못 넣는 보석의 설명을 설명 줄에. 누르면 바로 고른 칸에 들어간다)
	local W = panel.Size.X.Offset > 0 and panel.Size.X.Offset or 1000

	text({ Size = UDim2.new(0, 260, 0, 34), Position = UDim2.new(0, 20, 0, 10), Text = "🌟 Set Effects", TextSize = 22, Font = Enum.Font.GothamBlack, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Left }, panel)
	local resLabel = badge(panel, { Size = UDim2.new(0, 210, 0, 26), Position = UDim2.new(0, 196, 0, 14), Text = "", TextSize = 13, TextColor3 = Color3.fromRGB(143, 224, 255), BackgroundColor3 = Color3.fromRGB(16, 12, 22), Stroke = Color3.fromRGB(70, 60, 90) })
	local close = make("TextButton", { Size = UDim2.new(0, 76, 0, 32), Position = UDim2.new(1, -92, 0, 12), BackgroundColor3 = Color3.fromRGB(58, 42, 18), Text = "Close", TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = CREAM, ZIndex = 6 }, panel)
	round(close, 12)
	make("UIStroke", { Color = GOLD, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, close)
	close.Activated:Connect(function() panel.Visible = false end)
	local subtitle = text({ Size = UDim2.new(1, -40, 0, 16), Position = UDim2.new(0, 20, 0, 46), Text = "Only effects in a slot are on · tap a gem below, then tap a slot above", TextSize = 12, TextColor3 = Color3.fromRGB(201, 184, 138) }, panel)

	-- 빈 곳을 누르면 고르기 취소 (다른 버튼들보다 아래 ZIndex: 버튼이 먼저 받는다)
	local catcher = make("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 1 }, panel)
	catcher.Activated:Connect(function() if picked then picked = nil refreshTargets() refreshInfo() end end)

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
		local gunBadge = badge(holder, { Size = UDim2.new(0, 30, 0, 22), Position = UDim2.new(0.5, -RING / 2 - 2, 0, RING - 30), Text = "🔫", TextSize = 13, -- (지금 무기가 이 효과와 어울리면 초록)
			TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = Color3.fromRGB(46, 150, 80), Stroke = Color3.fromRGB(120, 255, 140), ZIndex = 8 })
		gunBadge.Visible = false
		local lv = badge(holder, { Size = UDim2.new(0, 76, 0, 22), Position = UDim2.new(0.5, -38, 0, RING - 12), Text = "", TextSize = 12, Font = Enum.Font.GothamBlack,
			TextColor3 = CREAM, BackgroundColor3 = Color3.fromRGB(18, 14, 24), ZIndex = 8 })
		local pips = text({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, RING + 16), Text = "", TextSize = 13 }, holder)
		local name = text({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, RING + 36), Text = "", TextSize = 15, Font = Enum.Font.GothamBlack, TextTruncate = Enum.TextTruncate.AtEnd }, holder)
		local src = text({ Size = UDim2.new(1, 10, 0, 18), Position = UDim2.new(0, -5, 0, RING + 55), Text = "", TextSize = 12, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(120, 255, 140),
			TextTruncate = Enum.TextTruncate.AtEnd }, holder) -- (11-30: 지금 단계 효과 한 줄 · 세트 이름 / 부위는 이름 옆에 작게)
		src.BackgroundTransparency, src.BackgroundColor3 = 0.45, Color3.fromRGB(0, 0, 0)
		round(src, 8)
		local goal = text({ Size = UDim2.new(1, 10, 0, 16), Position = UDim2.new(0, -5, 0, RING + 73), Text = "", TextSize = 11, TextColor3 = Color3.fromRGB(255, 217, 102), TextTruncate = Enum.TextTruncate.AtEnd }, holder)
		local up = make("TextButton", { Size = UDim2.new(0, 160, 0, 32), Position = UDim2.new(0.5, -80, 0, RING + 96), BackgroundColor3 = Color3.fromRGB(70, 180, 82), Text = "", TextSize = 13,
			Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1), ZIndex = 7 }, holder)
		round(up, 16)
		local upStroke = make("UIStroke", { Color = Color3.fromRGB(184, 255, 191), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, up)
		up.Activated:Connect(function() Remotes.Aug:FireServer("SlotUp", i) end)
		local pick = make("TextButton", { Size = UDim2.new(0, RING, 0, RING), Position = UDim2.new(0.5, -RING / 2, 0, 0), BackgroundTransparency = 1, Text = "", ZIndex = 7 }, holder)
		-- 고르는 중 표시: 초록 고리 + 위쪽 꼬리표 ("⬇ 여기에 넣기" / "⚠ … 빠져요" / "🔒 방어 2칸 제한" / "바꿔 넣기")
		local target = make("Frame", { Size = UDim2.new(0, RING + 24, 0, RING + 24), Position = UDim2.new(0.5, -(RING + 24) / 2, 0, -12), BackgroundTransparency = 1, Visible = false, ZIndex = 6 }, holder)
		round(target)
		local targetStroke = make("UIStroke", { Color = Color3.fromRGB(120, 255, 140), Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, target)
		local tag = badge(holder, { Size = UDim2.new(0, 190, 0, 22), Position = UDim2.new(0.5, -95, 0, -30), Text = "", TextSize = 12, Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = Color3.fromRGB(31, 90, 42), Stroke = Color3.fromRGB(120, 255, 140), ZIndex = 10 })
		tag.Visible = false
		pick.Activated:Connect(function()
			if picked then -- 칸 확정: 이때만 보낸다
				local allowed, _, wear = UI.TargetState(i)
				if not allowed then return end
				local z = picked
				picked = nil
				Remotes.Aug:FireServer(wear and "Wear" or "Slot", i, z)
				selectedSlot = i
				refreshTargets()
				refreshInfo()
				return
			end
			selectedSlot = i preview = nil UI.Refresh()
		end)
		local clear = make("TextButton", { Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(0.5, -RING / 2 - 4, 0, -2), BackgroundColor3 = Color3.fromRGB(122, 32, 48), Text = "X", TextSize = 12,
			Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1), ZIndex = 9 }, holder)
		round(clear)
		make("UIStroke", { Color = Color3.fromRGB(255, 154, 168), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, clear)
		clear.Activated:Connect(function() Remotes.Aug:FireServer("Slot", i, 0) end)
		sockets[i] = { Ring = ring, Stroke = ringStroke, Icon = ringIcon, Glow = glow, Plus = plus, Lv = lv, Pips = pips, Name = name, Src = src, Goal = goal, Gun = gunBadge, Target = target, TargetStroke = targetStroke, Tag = tag, Up = up, UpStroke = upStroke, Clear = clear }
	end

	-- 설명 줄: 고른 소켓(또는 미리 보는 보석)의 효과 설명 + 👑 각성 설명
	local info = make("Frame", { Size = UDim2.new(1, -40, 0, 44), Position = UDim2.new(0, 20, 0, 326), BackgroundColor3 = Color3.fromRGB(16, 12, 22), BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 3 }, panel)
	round(info, 12)
	make("UIStroke", { Color = GOLD, Thickness = 1, Transparency = 0.5 }, info)
	local infoIcon = text({ Size = UDim2.new(0, 40, 1, 0), Position = UDim2.new(0, 4, 0, 0), Text = "", TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center }, info)
	local infoLine1 = text({ Size = UDim2.new(1, -60, 0, 20), Position = UDim2.new(0, 48, 0, 3), Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, info)
	local cancelBtn = make("TextButton", { Size = UDim2.new(0, 96, 0, 30), Position = UDim2.new(1, -104, 0.5, -15), BackgroundColor3 = Color3.fromRGB(90, 32, 48), Text = "✖ Cancel", TextSize = 13,
		Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1), Visible = false, ZIndex = 6 }, info)
	round(cancelBtn, 15)
	cancelBtn.Activated:Connect(function() picked = nil refreshTargets() refreshInfo() end)
	local infoStroke = info:FindFirstChildOfClass("UIStroke")
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

	local gemStrokes = {} -- [구역] = { Stroke, Base } (미리 보는 보석 금테: 보석을 다시 만들지 않고 테두리만 바꾼다)
	local GEM_THICK = math.max(2, 52 / 18) -- (orb 기본 두께와 같게)
	local function gem(parent, z, order)
		local info = infoOf(z)
		local level = attr("AugGearZ_" .. z) or 0
		local def = isDefense(z)
		local cell = make("Frame", { Size = UDim2.new(0, 98, 0, 86), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 4 }, parent)
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
		local sub = "<font color='" .. (def and "#8fe0ff" or "#ffb86b") .. "'>" .. (ROLE[Config.Sets.ZoneAug[z]] or "") .. "</font>" -- (11-30: 부위 수 대신 짧은 역할. 부위 수는 설명 줄에)
		text({ Size = UDim2.new(1, 10, 0, 12), Position = UDim2.new(0, -5, 0, 75), Text = sub, TextSize = 10, Font = Enum.Font.GothamBold, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.AtEnd }, cell)
		local hit = make("TextButton", { Size = UDim2.new(0, 52, 0, 52), Position = UDim2.new(0.5, -26, 0, 2), BackgroundTransparency = 1, Text = "", ZIndex = 8 }, cell)
		gemStrokes[z] = { Stroke = stroke, Base = stroke.Color }
		hit.Activated:Connect(function() -- (11-28 B안) 보석 = 고르기만 (아무것도 안 보낸다) → 위 소켓을 눌러 칸 확정. 같은 보석을 다시 누르면 취소
			preview = z
			if picked == z then
				picked = nil
			elseif level > 0 or (not def and attr("AugOpenZ_" .. z) == true) then -- (레벨 0 공격 = 칸을 고르면 그 세트 장비를 끼우고 넣는다)
				picked = z
			else
				picked = nil -- (레벨 0 방어: 수호석이 있어야 넣을 수 있다 → 설명만)
			end
			refreshTargets()
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
				if ready then -- (빨간 점의 이유: 지금 올릴 수 있는 🔷 버튼이 숨 쉬듯 커졌다 작아진다)
					local scale = make("UIScale", { Scale = 1 }, sb)
					game:GetService("TweenService"):Create(scale, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.25 }):Play()
				end
			end
		end
	end

	-- 설명 줄만 다시 쓴다 (보석 / 소켓 버튼은 그대로 둔다: 누르고 있는 버튼을 지우지 않게)
	refreshInfo = function()
		if preview and inSlot(preview) and not stoneReadyCost(preview) then preview = nil end -- (수호석으로 올릴 수 있는 방어 효과는 칸에 들어 있어도 설명 줄에 남긴다)
		if picked and inSlot(picked) then picked = nil end
		cancelBtn.Visible = picked ~= nil
		info.BackgroundColor3 = picked and Color3.fromRGB(20, 44, 26) or Color3.fromRGB(16, 12, 22)
		if infoStroke then infoStroke.Color = picked and Color3.fromRGB(120, 255, 140) or GOLD end
		infoLine1.Size = UDim2.new(1, picked and -160 or -60, 0, 20)
		infoLine2.Size = UDim2.new(1, picked and -160 or -60, 0, 18)
		subtitle.Visible = picked == nil -- (소켓 위 꼬리표와 겹치지 않게)
		local z = preview or slotZone(selectedSlot)
		local zi = z > 0 and infoOf(z)
		if picked then -- 고르는 중: 안내 막대
			local pz = infoOf(picked)
			local wear = (attr("AugGearZ_" .. picked) or 0) <= 0
			infoIcon.Text = pz.Icon
			infoLine1.Text = string.format("<b>%s</b>  ", pz.Name) .. "<font color='#ffd966'>" .. (wear and "Pick a slot: this set's gear goes on and it goes in" or "Pick a slot above to put it in") .. "</font>"
			infoLine2.Text = (wear and attr("Zone") == "Dungeon") and "<font color='#ff9a8a'>You can't change gear in the dungeon</font>" or "<font color='#9a8ab8'>Tap the same gem or an empty spot to cancel</font>"
		elseif not zi then
			infoIcon.Text = "💡"
			infoLine1.Text = "Tap a gem below, then tap a slot above"
			infoLine2.Text = ""
		else
			local level = attr("AugGearZ_" .. z) or 0
			local aw = attr("AugAwakeZ_" .. z) == true and Config.AugAwaken[Config.Sets.ZoneAug[z]]
			infoIcon.Text = zi.Icon
			local now = levelLine(z, level)
			local where = isDefense(z) and string.format("🔷 %d/6", attr("AugStoneZ_" .. z) or 0) or string.format("%d/6", attr("AugSetZ_" .. z) or 0)
			infoLine1.Text = string.format("<b>%s</b> <font size='11' color='#b8a8d0'>%s</font>  <font color='#d8cce8'>%s</font>", zi.Name, where, zi.Desc or "")
				.. (now and ("  <font color='#78ff8c'>" .. string.format("· Lv.%d now: ", math.min(6, level)) .. "</font><font color='#78ff8c'>" .. now .. "</font>") or "")
			local wtext = not isDefense(z) and weaponText(z)
			if wtext then -- 공격 효과: 어울리는 무기를 맨 앞에 (예전 창의 "무기 궁합" 띠)
				infoLine2.Text = wtext .. (aw and ("  <font color='#ff9be6'>" .. string.format("👑 Awakening: %s", aw.Name) .. "</font>") or (level <= 0 and "  <font color='#9a8ab8'>· tap it, then a slot</font>" or ""))
			elseif stoneReadyCost(z) then -- 🔷 지금 수호석으로 올릴 수 있다 (메뉴 빨간 점의 이유)
				local cost, nextLv = stoneReadyCost(z)
				infoLine2.Text = "<font color='#8fe0ff'>" .. string.format("🔷 You can raise %s to Lv.%d with %d Guard Stones (🔷 button on the gem)", zi.Name, nextLv, cost) .. "</font>"
			elseif aw then
				infoLine2.Text = "<font color='#ff9be6'>" .. string.format("👑 Awakening: %s", aw.Name) .. "</font>  " .. aw.Desc
			elseif level <= 0 then
				infoLine2.Text = isDefense(z) and "Collect Guard Stones" or "Tap it, then a slot: this set's gear goes on and it goes in"
			elseif preview then
				infoLine2.Text = "Tap it, then tap a slot above"
			elseif not isDefense(z) then
				infoLine2.Text = "<font color='#9a8ab8'>" .. "6 pieces 👑 awakening" .. "</font>"
			else
				infoLine2.Text = ""
			end
		end
		for gz, g in pairs(gemStrokes) do -- 미리 보는 보석만 금테, 나머지는 원래 색으로
			if g.Stroke.Parent then
				local on = (picked or preview) == gz
				g.Stroke.Color = on and GOLD_HI or g.Base
				g.Stroke.Thickness = on and 4 or GEM_THICK
			end
		end
	end

	-- 고른 보석을 칸 i 에 넣을 수 있나: allowed, 꼬리표 종류, wear(레벨 0 공격 = 장비를 끼우고 넣기)
	function UI.TargetState(i)
		local z = picked
		if not z then return false, nil, false end
		local cur = slotZone(i)
		local wear = not isDefense(z) and (attr("AugGearZ_" .. z) or 0) <= 0
		if wear and attr("Zone") == "Dungeon" then return false, "dungeon", wear end -- (서버 EquipSetKeep 과 같은 규칙: 던전 안 장비 교체 불가)
		if cur == z then return false, "same", wear end
		if isDefense(z) then
			if cur > 0 and isDefense(cur) then return true, "swap", wear end
			local defs = 0 -- (서버 AugService "Slot" 과 같은 규칙: 이 칸을 빼고 방어가 이미 MaxDefense 개면 막는다)
			for k = 1, S.Count do
				local other = slotZone(k)
				if k ~= i and other ~= z and other > 0 and isDefense(other) then defs += 1 end
			end
			if defs >= S.MaxDefense then return false, "defmax", wear end
			return true, "put", wear
		end
		if cur > 0 and isDefense(cur) then return true, "warn", wear end
		return true, "put", wear
	end
	refreshTargets = function()
		for i, s in ipairs(sockets) do
			local allowed, kind = UI.TargetState(i)
			local show = picked ~= nil and kind ~= "same"
			s.Target.Visible = show
			s.Tag.Visible = show
			if show then
				local cur = slotZone(i)
				local curInfo = cur > 0 and infoOf(cur)
				if kind == "warn" then
					s.Tag.Text = string.format("⚠ %s will be removed", curInfo and curInfo.Name or "")
					s.Tag.BackgroundColor3, s.TargetStroke.Color = Color3.fromRGB(90, 58, 16), Color3.fromRGB(255, 184, 77)
				elseif kind == "swap" then
					s.Tag.Text = "🔄 Swap in"
					s.Tag.BackgroundColor3, s.TargetStroke.Color = Color3.fromRGB(31, 90, 42), Color3.fromRGB(120, 255, 140)
				elseif kind == "defmax" then
					s.Tag.Text = "🔒 Defense max 2"
					s.Tag.BackgroundColor3, s.TargetStroke.Color = Color3.fromRGB(51, 51, 58), Color3.fromRGB(110, 110, 120)
				elseif kind == "dungeon" then
					s.Tag.Text = "🔒 Not in the dungeon"
					s.Tag.BackgroundColor3, s.TargetStroke.Color = Color3.fromRGB(51, 51, 58), Color3.fromRGB(110, 110, 120)
				else
					s.Tag.Text = "⬇ Put here"
					s.Tag.BackgroundColor3, s.TargetStroke.Color = Color3.fromRGB(31, 90, 42), Color3.fromRGB(120, 255, 140)
				end
				s.Ring.BackgroundTransparency = allowed and 0 or 0.5
			else
				s.Ring.BackgroundTransparency = 0
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
				s.Gun.Visible = false
				s.Name.Text = "<font color='#9a8ab8'>Empty slot</font>"
				s.Src.Text = "Pick one below"
				s.Src.BackgroundTransparency = 1
				s.Goal.Text = ""
			else
				local level = attr("AugGearZ_" .. z) or 0
				s.Lv.Visible = true
				local _, gunMatch = weaponText(z)
				s.Gun.Visible = not def and gunMatch
				s.Lv.Text = string.format("Lv.%d", level) .. (attr("AugAwakeZ_" .. z) == true and " 👑" or (not def and level >= 4 and " ★" or ""))
				local small
				if def then
					local eff = attr("AugSlotEff_" .. i) or 1
					small = string.format("🔷 %d/6", attr("AugStoneZ_" .. z) or 0) .. (eff < 1 and string.format(" · <font color='#ffb84d'>2nd defense = %d%%</font>", math.floor(eff * 100 + 0.5)) or "")
				else
					local setDef = setOf(z)
					small = string.format("%s <font color='#d8cce8'>%s</font> <font color='#78ff8c'>%d/6</font>", setDef and setDef.Icon or "", setDef and setDef.Name or "", attr("AugSetZ_" .. z) or 0) -- (세트 이름은 따로 감싸야 통째로 번역된다)
				end
				s.Name.Text = "<b>" .. info.Name .. "</b>  <font size='11' color='#b8a8d0'>" .. small .. "</font>"
				local line = levelLine(z, level)
				s.Src.Text = line and line or "<font color='#9a8ab8'>off · " .. (def and "collect Guard Stones" or "wear 2 set pieces") .. "</font>"
				s.Src.BackgroundTransparency = 0.45
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
		if picked and (inSlot(picked) or attr("AugOpenZ_" .. picked) ~= true) then picked = nil end
		refreshTargets()
		refreshInfo() -- (보석을 다 만든 뒤: 설명 줄 + 미리 보는 보석 금테)
	end

	function UI.Focus(zone) -- 장비 창 "내 세트" ✨: 그 효과가 든 칸을 고른다
		selectedSlot = inSlot(zone) or selectedSlot
		UI.Refresh()
	end

	local watch = { "Gold", "TutorialActive", "Zone", "GuardStones", "WeaponType", "WeaponLevel" } -- (무기를 바꾸면 🔫 표시도)
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
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.Visible then return end
		if not picked then -- (빨간 점을 보고 열었을 때: 수호석으로 올릴 수 있는 방어 효과를 설명 줄에 먼저 보여 준다)
			preview = nil
			for z = 1, ZONES do if stoneReadyCost(z) then preview = z break end end
		end
		UI.Refresh()
	end)
	UI.Refresh()
	return UI
end

return UI
