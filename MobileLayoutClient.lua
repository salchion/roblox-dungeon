-- MobileLayoutClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: MobileLayoutClient)
-- 작은 화면(폰 가로 896x414, 740x360, 640x360 / 세로 414x896)에서 UI 가 겹치지 않게 한 곳에서 정리한다.
-- 데스크톱(화면 900x560 이상)에서는 아무것도 바꾸지 않는다: 작은 화면일 때만 적용하고, 커지면 원래대로 되돌린다.
--
-- 하는 일
--  1) 모든 HUD ScreenGui 의 UIScale 을 같은 값(0.7~1)으로 맞춘다. (예전에는 HUD / Goal / Rift / Tutorial 은 0.55 까지 줄고
--     HudClient / LevelStat / Pet 은 1 이라서 서로 다른 크기로 겹쳤다.) 글씨가 읽히도록 0.7 아래로는 줄이지 않는다.
--  2) 왼쪽 위 = HudClient 카드(줄인 모양) + 메뉴 / 설정 / 스탯 버튼 줄. 미션 카드는 위쪽 가운데로 (GoalClient / TutorialClient 가
--     PlayerGui 의 Ui* 속성을 읽어서 스스로 놓는다).
--  3) 오른쪽 위 = 작은 버튼(랭킹 / 파티, 던전에서는 특성) 으로 접어 둔 패널 + 작게 줄인 레이더.
--  4) 아래 가운데 = 스킬 바 + 자동 공격(R) 버튼 한 줄. 왼쪽 아래(조이스틱) / 오른쪽 아래(점프) 200x200 은 비워 둔다.
--  5) 키 안내 줄(ControlsHint) 숨김, 토스트 / 튜토리얼 안내 카드는 아래 가운데로, 큰 창(메뉴 등)은 화면에 맞게 줄임.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local THUMB = 200       -- 모바일 조이스틱 / 점프 버튼 영역 (실제 픽셀)
local MIN_SCALE = 0.7   -- 이보다 작게 줄이면 12px 글씨가 8px 아래로 내려간다
local PILL_Y = 6
local PANEL_Y = 52      -- 접이식 패널 / 레이더 시작 높이 (버튼 줄 아래)

-- UIScale 을 직접 가진 화면(자기 fit() 이 있다) / 가지고 있지 않은 화면
local THEIRS = { HUD = true, ShopGui = true, GoalHUD = true, RiftHUD = true, TutorialHUD = true }
local OWN = { HudGui = true, LevelStatGui = true, PetGui = true, HUDFx = true, EvolveFx = true }

local st = { compact = false, s = 1 }
local saved = {}      -- [객체] = { [속성] = { 원래 값 } }
local cache = {}
local driven = {}     -- 이미 감시 중인 UIScale
local guarded = {}    -- 이미 감시 중인 객체 (보이면 안 되는 것)
local fitScales = {}  -- 큰 창에 붙인 UIScale
local open = nil      -- 펼쳐진 접이식 패널: "party" | "rank" | "stat" | nil
local ui, scaleObj, pillRank, pillParty, pillStat, pillShop
local layoutCompact, layoutCalm

local function make(class, props, parent)
	local instance = Instance.new(class)
	for key, value in pairs(props) do instance[key] = value end
	instance.Parent = parent
	return instance
end

local function set(obj, prop, value)
	if not obj or not obj.Parent then return end
	local rec = saved[obj]
	if not rec then
		rec = {}
		saved[obj] = rec
	end
	if rec[prop] == nil then rec[prop] = { obj[prop] } end
	if obj[prop] ~= value then obj[prop] = value end
end

local function restoreAll()
	for obj, rec in pairs(saved) do
		if obj.Parent then
			for prop, box in pairs(rec) do obj[prop] = box[1] end
		end
	end
	saved = {}
end

local function find(root, name)
	local found = cache[name]
	if found and found:IsDescendantOf(playerGui) then return found end
	cache[name] = nil
	if not root then return nil end
	found = root:FindFirstChild(name, true)
	cache[name] = found
	return found
end

local function desktopScale(viewport)
	return math.clamp(math.min(viewport.X / 1100, viewport.Y / 720), 0.55, 1) -- 다른 스크립트들의 fit() 과 같은 식
end

------------------------------------------------------------
-- 접이식 버튼 (오른쪽 위)
------------------------------------------------------------
local function pill(name, text, width, onClick)
	local button = make("TextButton", {
		Name = name, Size = UDim2.new(0, width, 0, 40), AnchorPoint = Vector2.new(1, 0), Text = text,
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.fromRGB(240, 242, 250),
		BackgroundColor3 = Color3.fromRGB(34, 40, 70), BackgroundTransparency = 0.05, BorderSizePixel = 0, AutoButtonColor = true, Visible = false,
	}, ui)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, button)
	make("UIStroke", { Color = Color3.fromRGB(110, 130, 220), Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	button.Activated:Connect(onClick)
	return button
end

local function ensureUi()
	if ui and ui.Parent then return end
	ui = make("ScreenGui", { Name = "MobileUi", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = -1, Enabled = false }, playerGui)
	scaleObj = make("UIScale", { Name = "MobileScale" }, ui)
	local function toggle(which)
		open = open ~= which and which or nil
		task.defer(function()
			local vp = workspace.CurrentCamera.ViewportSize
			if st.compact then layoutCompact(vp) else layoutCalm(vp) end
		end)
	end
	pillRank = pill("RankPill", "🏆 랭킹", 92, function() toggle("rank") end)
	pillParty = pill("PartyPill", "👥 파티", 116, function() toggle("party") end)
	pillStat = pill("StatPill", "✨ 특성 / 나가기", 150, function() toggle("stat") end)
	pillShop = pill("ShopPill", "🎁 상점", 96, function() player:SetAttribute("OpenShop", os.clock()) end) -- PlayerClient 가 신호를 받아 상점 창을 연다
	pillShop.BackgroundColor3 = Color3.fromRGB(86, 52, 40)
end

------------------------------------------------------------
-- 큰 창(메뉴 / 강화 / 장비 / 던전 선택 / 펫 / 스탯 ...)을 화면 안에 맞춘다
------------------------------------------------------------
local function isModal(f)
	return f:IsA("Frame") and f.AnchorPoint == Vector2.new(0.5, 0.5) and f.Size.X.Scale == 0 and f.Size.Y.Scale == 0
		and f.Size.Y.Offset >= 300 and math.abs(f.Position.X.Scale - 0.5) < 0.01 and f.Position.X.Offset == 0
end

local function fitModal(f, vw, vh)
	local own = f:FindFirstChild("FitScale")
	if not own and f:FindFirstChildOfClass("UIScale") then return end -- 스스로 크기를 쓰는 창(튜토리얼 안내 등)은 건드리지 않는다
	local m = math.min(1, (vh - 12) / f.Size.Y.Offset, (vw - 12) / f.Size.X.Offset)
	if m >= 1 and not own then return end
	if not own then
		own = make("UIScale", { Name = "FitScale" }, f)
		table.insert(fitScales, own)
	end
	own.Scale = m
	if m < 1 then set(f, "Position", UDim2.new(0.5, 0, 0.5, 0)) end
end

local function scanModals(vw, vh)
	for _, g in ipairs(playerGui:GetChildren()) do
		if g:IsA("ScreenGui") and (THEIRS[g.Name] or OWN[g.Name]) then
			for _, child in ipairs(g:GetChildren()) do
				if isModal(child) then
					fitModal(child, vw, vh)
				elseif child.Name == "LobbyFrame" or child.Name == "DungeonFrame" then
					for _, inner in ipairs(child:GetChildren()) do
						if isModal(inner) then fitModal(inner, vw, vh) end
					end
				end
			end
		end
	end
end

------------------------------------------------------------
-- UIScale 맞추기
------------------------------------------------------------
local function applyScales(viewport)
	for _, g in ipairs(playerGui:GetChildren()) do
		if g:IsA("ScreenGui") then
			if THEIRS[g.Name] then
				local sc = g:FindFirstChildOfClass("UIScale")
				if sc then
					if not driven[sc] then
						driven[sc] = true
						sc:GetPropertyChangedSignal("Scale"):Connect(function()
							if st.compact and sc.Scale ~= st.s then sc.Scale = st.s end -- 각 스크립트의 fit() 이 덮어써도 바로 되돌린다
						end)
					end
					local want = st.compact and st.s or desktopScale(viewport)
					if sc.Scale ~= want then sc.Scale = want end
				end
			elseif OWN[g.Name] then
				local sc = g:FindFirstChild("MobileScale") or make("UIScale", { Name = "MobileScale" }, g)
				local want = st.compact and st.s or 1
				if sc.Scale ~= want then sc.Scale = want end
			end
		end
	end
end

local function guardHidden(obj)
	if not obj or guarded[obj] then return end
	guarded[obj] = true
	obj:GetPropertyChangedSignal("Visible"):Connect(function()
		if st.compact and obj.Visible then obj.Visible = false end
	end)
end

------------------------------------------------------------
-- 배치 (가상 좌표 = 실제 픽셀 / s)
------------------------------------------------------------
function layoutCompact(viewport)
	local s = st.s
	local vw, vh = viewport.X / s, viewport.Y / s
	local zone = THUMB / s
	local narrow = viewport.Y > viewport.X
	local raised = vw - 2 * zone < 300         -- 스킬 줄이 양쪽 엄지 영역 사이에 안 들어가면 위로 올린다
	local topY = math.ceil(52 / s)            -- Roblox 왼쪽 위 아이콘(실제 약 48px) 아래
	local btnY = topY + 118
	local missionY = narrow and (btnY + 40) or 8
	local barBottom = raised and (math.ceil(zone) + 10) or 14
	local barTop = barBottom + 64

	-- 다른 스크립트가 읽는 값
	playerGui:SetAttribute("UiS", s)
	playerGui:SetAttribute("UiNarrow", narrow)
	playerGui:SetAttribute("UiMissionY", missionY)
	playerGui:SetAttribute("UiToastX", math.floor(vw / 2 - 160))
	playerGui:SetAttribute("UiToastY", -(barTop + 8))
	playerGui:SetAttribute("UiToastYUp", -(barTop + 8 + 104 + 8))
	playerGui:SetAttribute("UiPromptY", -(barTop + 8))
	playerGui:SetAttribute("UiCompact", true)

	local hud = playerGui:FindFirstChild("HUD")
	local hudGui = playerGui:FindFirstChild("HudGui")
	local statGui = playerGui:FindFirstChild("LevelStatGui")
	local riftGui = playerGui:FindFirstChild("RiftHUD")

	-- 왼쪽 위: 카드 (무기 / 위치 줄은 접는다) + 버튼 줄
	local card = find(hudGui, "HudCard")
	set(card, "Position", UDim2.new(0, 12, 0, topY))
	set(card, "Size", UDim2.new(0, 244, 0, 116))
	set(find(hudGui, "HudWeaponRow"), "Visible", false)
	set(find(hudGui, "HudZoneRow"), "Visible", false)
	set(find(hudGui, "HudSep"), "Visible", false)
	set(find(hud, "MenuButton"), "Position", UDim2.new(0, 12, 0, btnY))
	set(find(hud, "HelpButton"), "Position", UDim2.new(0, 94, 0, btnY))
	if statGui then
		for _, child in ipairs(statGui:GetChildren()) do
			if child:IsA("TextButton") then set(child, "Position", UDim2.new(0, 176, 0, btnY)) end
		end
	end

	-- 오른쪽 위: 접이식 패널 + 레이더
	local lobbyFrame, dungeonFrame = find(hud, "LobbyFrame"), find(hud, "DungeonFrame")
	local partyPanel, rankMini, statPanel = find(hud, "PartyPanel"), find(hud, "RankMini"), find(hud, "StatPanel")
	local lobbyOn = lobbyFrame ~= nil and lobbyFrame.Visible
	local dungeonOn = dungeonFrame ~= nil and dungeonFrame.Visible
	if (open == "party" or open == "rank") and not lobbyOn then open = nil end
	if open == "stat" and not dungeonOn then open = nil end

	ensureUi()
	ui.Enabled = true
	scaleObj.Scale = s
	pillRank.Position = UDim2.new(1, -(12 + 116 + 6), 0, PILL_Y)
	pillParty.Position = UDim2.new(1, -12, 0, PILL_Y)
	pillStat.Position = UDim2.new(1, -12, 0, PILL_Y)
	pillRank.Visible, pillParty.Visible, pillStat.Visible = lobbyOn, lobbyOn, dungeonOn
	pillShop.Size = UDim2.new(0, 96, 0, 40)
	pillShop.Position = UDim2.new(1, -(12 + 116 + 6 + 92 + 6), 0, PILL_Y) -- 랭킹 버튼 왼쪽 (위 줄)
	pillShop.Visible = lobbyOn
	local partyTitle = partyPanel and partyPanel:FindFirstChildOfClass("TextLabel")
	pillParty.Text = partyTitle and partyTitle.Text ~= "" and ("👥 " .. partyTitle.Text) or "👥 파티"
	local function tint(button, on)
		button.BackgroundColor3 = on and Color3.fromRGB(62, 96, 196) or Color3.fromRGB(34, 40, 70)
	end
	tint(pillRank, open == "rank")
	tint(pillParty, open == "party")
	tint(pillStat, open == "stat")

	if partyPanel then
		set(partyPanel, "Position", UDim2.new(1, -12, 0, PANEL_Y))
		partyPanel.Visible = open == "party"
	end
	if rankMini then
		set(rankMini, "Position", UDim2.new(1, -12, 0, PANEL_Y))
		rankMini.Visible = open == "rank"
	end
	if statPanel then
		set(statPanel, "AnchorPoint", Vector2.new(1, 0))
		set(statPanel, "Position", UDim2.new(1, -12, 0, PANEL_Y))
		statPanel.Visible = open == "stat"
	end

	local radar = find(hud, "RadarFrame")
	if radar then
		set(radar, "AnchorPoint", Vector2.new(1, 0))
		set(radar, "Position", UDim2.new(1, -12, 0, open and -600 or PANEL_Y)) -- 패널이 펼쳐져 있는 동안은 레이더를 치운다
		local rs = radar:FindFirstChild("MobileRadarScale") or make("UIScale", { Name = "MobileRadarScale" }, radar)
		rs.Scale = 0.66
	end

	-- 아래 가운데: 스킬 바 + 자동 공격 버튼 (양쪽 엄지 영역 밖)
	local bar, auto = find(hud, "SkillBar"), find(hud, "AutoButton")
	if bar and auto then
		local barW, autoW, gap = bar.Size.X.Offset, 64, 8
		local total = barW + gap + autoW
		set(bar, "AnchorPoint", Vector2.new(0.5, 1))
		set(bar, "Position", UDim2.new(0.5, -total / 2 + barW / 2, 1, -barBottom))
		set(auto, "AnchorPoint", Vector2.new(0, 1))
		set(auto, "Position", UDim2.new(0.5, -total / 2 + barW + gap, 1, -barBottom))
		set(auto, "Size", UDim2.new(0, autoW, 0, 54))
		for _, child in ipairs(auto:GetChildren()) do
			if child:IsA("Frame") then
				set(child, "Position", UDim2.new(0.5, -17, 0.5, -17))
			elseif child:IsA("TextLabel") then
				set(child, "Visible", false) -- 켜짐 / 꺼짐은 테두리 색(초록)으로 이미 보인다
			end
		end
	end

	-- 키 안내 줄은 터치 화면에서 필요 없다
	local hint = find(hud, "ControlsHint")
	if hint then
		guardHidden(hint)
		if hint.Visible then hint.Visible = false end
	end

	-- 토스트: 아래 가운데 (스킬 바 위)
	set(find(hud, "ToastLabel"), "Size", UDim2.new(0, 320, 0, 74))

	-- 던전 위쪽 가운데: 배너 / 막대 (왼쪽 카드와 오른쪽 버튼 사이)
	local bw = narrow and math.min(360, vw - 24) or 360
	local by = missionY
	set(find(hud, "WaveBanner"), "Size", UDim2.new(0, bw, 0, 96))
	set(find(hud, "WaveBanner"), "Position", UDim2.new(0.5, 0, 0, by))
	set(find(hud, "BonusBar"), "Size", UDim2.new(0, bw, 0, 22))
	set(find(hud, "BonusBar"), "Position", UDim2.new(0.5, 0, 0, by + 100))
	set(find(hud, "LimitBar"), "Size", UDim2.new(0, bw, 0, 22))
	set(find(hud, "LimitBar"), "Position", UDim2.new(0.5, 0, 0, by + 126))
	set(find(hud, "BossBar"), "Size", UDim2.new(0, bw, 0, 26))
	set(find(hud, "BossBar"), "Position", UDim2.new(0.5, 0, 0, by + 102))
	set(find(riftGui, "RiftScore"), "Position", UDim2.new(0.5, 0, 0, by + 156))

	scanModals(vw, vh)
end

local function layoutDesktop()
	for _, key in ipairs({ "UiS", "UiNarrow", "UiMissionY", "UiToastX", "UiToastY", "UiToastYUp", "UiPromptY" }) do
		playerGui:SetAttribute(key, nil)
	end
	playerGui:SetAttribute("UiCompact", false)
	restoreAll()
	for _, sc in ipairs(fitScales) do
		if sc.Parent then sc:Destroy() end
	end
	fitScales = {}
	local hud = playerGui:FindFirstChild("HUD")
	local radar = find(hud, "RadarFrame")
	local rs = radar and radar:FindFirstChild("MobileRadarScale")
	if rs then rs:Destroy() end
	-- 접어 두었던 패널은 원래대로 항상 보이게
	for _, name in ipairs({ "PartyPanel", "RankMini", "StatPanel" }) do
		local obj = find(hud, name)
		if obj then obj.Visible = true end
	end
	local hint = find(hud, "ControlsHint")
	if hint then hint.Visible = (player:GetAttribute("Zone") or "Lobby") == "Lobby" end
	if ui and ui.Parent then ui.Enabled = false end
	open = nil
end

------------------------------------------------------------
-- 첫 화면 정리 (데스크톱 포함): 처음 6초는 HUD 카드 + 미션만, 나머지는 서서히 / 필요할 때만
--  - 마을 월드 글자(간판 / NPC 이름 등)는 처음 6초 숨겼다가 가까운 것부터 켠다
--  - 내 머리 위 이름표(Nameplate)는 내 화면에서만 숨긴다 (다른 사람 것은 그대로)
--  - 키 안내 줄은 intro 가 끝나면 나타났다가 12초 뒤 사라진다 (H 를 누르면 8초 다시 보인다)
--  - 파티 패널: 파티가 없으면 작은 "파티" 버튼 하나 (누르면 펼침) / 랭킹: 3줄, 내용 높이만큼
------------------------------------------------------------
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local calm = { t0 = nil, hidden = {}, wave2 = false, rehid = false, hintState = nil, hintInit = false, hintReq = nil, hintOff = 0, hintStroke = 0.5 }
local scriptStart = os.clock()
local INTRO = 6

local function introOver()
	return calm.t0 == false or (calm.t0 ~= nil and os.clock() - calm.t0 >= INTRO)
end

local function hideWorldLabels(root)
	for _, name in ipairs({ "Lobby", "LobbyDecor", "Dummies", "Npcs" }) do
		local folder = workspace:FindFirstChild(name)
		if folder then
			for _, d in ipairs(folder:GetDescendants()) do
				if d:IsA("BillboardGui") and d.Enabled and d.Name ~= "SealGui" and d.Parent and d.Parent.Name ~= "FieldGateSign" then
					local p = d.Parent
					local dist = p:IsA("BasePart") and (p.Position - root.Position).Magnitude or 0
					calm.hidden[d] = dist
					d.Enabled = false
				end
			end
		end
	end
end

local function revealWorldLabels(near)
	for d, dist in pairs(calm.hidden) do
		if (dist < 70) == near then
			if d.Parent then d.Enabled = true end
			calm.hidden[d] = nil
		end
	end
end

local function calmTick(hud)
	local now = os.clock()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	-- 내 이름표 숨김
	local head = character and character:FindFirstChild("Head")
	local nameplate = head and head:FindFirstChild("Nameplate")
	if nameplate and nameplate.Enabled then nameplate.Enabled = false end
	-- intro 시작
	if calm.t0 == nil then
		if root and player:GetAttribute("DataReady") then
			if player:GetAttribute("Zone") == "Lobby" then
				calm.t0 = now
				hideWorldLabels(root)
			else
				calm.t0 = false
			end
		elseif now - scriptStart > 25 then
			calm.t0 = false
		end
	elseif calm.t0 then
		if not calm.rehid and now - calm.t0 > 1.5 then
			calm.rehid = true
			if root then hideWorldLabels(root) end -- 늦게 생긴 글자도 함께
		end
		if not calm.near and now - calm.t0 >= INTRO then
			calm.near = true
			revealWorldLabels(true)
		end
		if not calm.far and now - calm.t0 >= INTRO + 2 then
			calm.far = true
			revealWorldLabels(false)
		end
	end
	-- 키 안내 줄
	local hint = find(hud, "ControlsHint")
	if hint then
		if not calm.hintState then
			calm.hintState = "hidden"
			calm.hintStroke = hint.TextStrokeTransparency
			hint.TextTransparency = 1
			hint.TextStrokeTransparency = 1
		end
		if introOver() and not calm.hintInit then
			calm.hintInit = true
			calm.hintReq = now + 12
		end
		if calm.hintReq then
			calm.hintOff = calm.hintReq
			calm.hintReq = nil
			if calm.hintState == "hidden" then
				calm.hintState = "shown"
				TweenService:Create(hint, TweenInfo.new(0.8), { TextTransparency = 0, TextStrokeTransparency = calm.hintStroke }):Play()
			end
		elseif calm.hintState == "shown" and now > calm.hintOff then
			calm.hintState = "hidden"
			TweenService:Create(hint, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.H then calm.hintReq = os.clock() + 8 end
end)

-- 데스크톱: 파티가 없으면 작은 버튼, 랭킹은 3줄짜리 작은 상자
function layoutCalm(viewport)
	local hud = playerGui:FindFirstChild("HUD")
	local partyPanel, rankMini = find(hud, "PartyPanel"), find(hud, "RankMini")
	local lobbyFrame = find(hud, "LobbyFrame")
	if not (partyPanel and rankMini) then return end
	local lobbyOn = lobbyFrame ~= nil and lobbyFrame.Visible and introOver()
	local hasParty = (player:GetAttribute("PartyId") or 0) ~= 0
	if hasParty or not lobbyOn then open = nil end
	if open == "rank" or open == "stat" then open = nil end
	ensureUi()
	local showPill = lobbyOn and not hasParty
	ui.Enabled = lobbyOn
	scaleObj.Scale = desktopScale(viewport)
	pillRank.Visible, pillStat.Visible = false, false
	pillParty.Visible = showPill
	pillParty.Text = "👥 파티"
	pillParty.Position = UDim2.new(1, -16, 0, 16)
	pillParty.BackgroundColor3 = open == "party" and Color3.fromRGB(62, 96, 196) or Color3.fromRGB(34, 40, 70)

	local partyShown = lobbyOn and (hasParty or open == "party")
	local panelY = showPill and 62 or 16
	set(partyPanel, "Position", UDim2.new(1, -16, 0, panelY))
	partyPanel.Visible = partyShown

	-- 랭킹: 최대 3줄, 내용 높이만큼
	local body = calm.rankBody
	if not body or not body.Parent then
		body = nil
		for _, child in ipairs(rankMini:GetChildren()) do
			if child:IsA("TextLabel") and child.RichText then body = child end
		end
		calm.rankBody = body
		if body then
			local function trim()
				local lines = string.split(body.Text, "\n")
				if #lines > 3 then body.Text = table.concat(lines, "\n", 1, 3) end
			end
			body:GetPropertyChangedSignal("Text"):Connect(trim)
			trim()
		end
	end
	local rows = body and math.min(3, #string.split(body.Text, "\n")) or 3
	local rankY = partyShown and (panelY + partyPanel.Size.Y.Offset + 8) or panelY
	set(rankMini, "Size", UDim2.new(0, 220, 0, 36 + 16 * rows))
	set(rankMini, "Position", UDim2.new(1, -16, 0, rankY))
	rankMini.Visible = lobbyOn

	-- 🎁 상점 버튼: 랭킹 카드 바로 아래 (DPS 패널과 겹칠 것 같으면 랭킹 카드 왼쪽)
	local rankH = 36 + 16 * rows
	local scale = scaleObj.Scale
	local dpsGui = playerGui:FindFirstChild("DpsPanelGui")
	local dps = dpsGui and dpsGui:FindFirstChild("DpsPanel")
	local shopY = rankY + rankH + 8
	local beside = dps ~= nil and dps.Visible and (shopY + 40 + 6) * scale > dps.AbsolutePosition.Y
	pillShop.Size = UDim2.new(0, beside and 96 or 130, 0, 40)
	pillShop.Position = beside and UDim2.new(1, -(16 + 220 + 8), 0, rankY) or UDim2.new(1, -16, 0, shopY)
	pillShop.Visible = lobbyOn
end

local function update()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local viewport = camera.ViewportSize
	if viewport.X < 1 or viewport.Y < 1 then return end
	local compact = viewport.Y < 560 or viewport.X < 900
	if compact then
		st.s = math.clamp(math.min(viewport.Y / 560, viewport.X / 820), MIN_SCALE, 1)
	end
	local was = st.compact
	if compact and not was then restoreAll() end -- 데스크톱 정리에서 바꾼 크기 / 위치를 되돌린 뒤 작은 화면 배치를 적용
	st.compact = compact
	applyScales(viewport)
	calmTick(playerGui:FindFirstChild("HUD"))
	if compact then
		layoutCompact(viewport)
	else
		if was then layoutDesktop() end
		layoutCalm(viewport)
	end
end

local function hook()
	local camera = workspace.CurrentCamera
	if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(update) end
end
hook()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	hook()
	update()
end)
playerGui.ChildAdded:Connect(function() task.defer(update) end)

update()
-- 다른 스크립트가 늦게 만든 위젯 / 다시 열린 패널도 따라가도록 가볍게 계속 맞춘다 (모두 값이 같으면 아무 일도 안 한다)
task.spawn(function()
	while true do
		task.wait(0.3)
		update()
	end
end)
