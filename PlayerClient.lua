-- PlayerClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript)
-- 3인칭 시점. 마우스(또는 터치) 방향으로 공격하고, 상황에 따라 UI가 바뀐다.
--   로비   : 파티 패널(초대/수락/추방/나가기), 무기 강화창, 게이트 안내
--   던전   : 웨이브 정보, 보스 체력바, 스탯 분배 패널(숫자키 1/2/3), 결과 화면
-- UI 구역은 서버가 설정하는 플레이어 Attribute "Zone"("Lobby" / "Dungeon")으로 전환된다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- 무기는 서버가 장착해주므로 기본 툴바(숫자키 1/2/3 충돌)는 끈다
task.spawn(function()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
			break
		end
		task.wait(0.5)
	end
end)

------------------------------------------------------------
-- UI 헬퍼
------------------------------------------------------------
local function create(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function rounded(instance, radius)
	create("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, instance)
end

local function makePanel(props, parent)
	local base = {
		BackgroundColor3 = Color3.fromRGB(20, 20, 30),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local frame = create("Frame", base, parent)
	rounded(frame)
	return frame
end

local function makeLabel(props, parent)
	local base = {
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextWrapped = true,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	return create("TextLabel", base, parent)
end

local function makeButton(props, parent, onClick)
	local base = {
		BackgroundColor3 = Color3.fromRGB(70, 110, 220),
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		AutoButtonColor = true,
		BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local button = create("TextButton", base, parent)
	rounded(button, 6)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

local function clearChildren(container)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local GREEN = Color3.fromRGB(60, 170, 90)
local RED = Color3.fromRGB(200, 70, 70)
local GRAY = Color3.fromRGB(70, 70, 85)

local gui = create("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = true }, player:WaitForChild("PlayerGui"))

------------------------------------------------------------
-- 공통: 상단 좌측 정보, 알림
------------------------------------------------------------
local infoPanel = makePanel({ Size = UDim2.new(0, 230, 0, 78), Position = UDim2.new(0, 16, 0, 16) }, gui)
local infoLabel = makeLabel({
	Size = UDim2.new(1, -20, 1, -16),
	Position = UDim2.new(0, 10, 0, 8),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	RichText = true,
}, infoPanel)

local toastLabel = makeLabel({
	Size = UDim2.new(0, 460, 0, 40),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 110),
	BackgroundColor3 = Color3.fromRGB(20, 20, 30),
	BackgroundTransparency = 0.25,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	Visible = false,
}, gui)
rounded(toastLabel)

local toastToken = 0
local function toast(text)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.Visible = true
	task.delay(3.5, function()
		if token == toastToken then
			toastLabel.Visible = false
		end
	end)
end

Remotes.Notify.OnClientEvent:Connect(toast)

local function currentZone()
	return player:GetAttribute("Zone") or "Lobby"
end

local function weaponText(level)
	local tier = Config.GetWeaponTier(level)
	return string.format("+%d %s", level, tier.Name), tier.Color
end

------------------------------------------------------------
-- 로비: 무기 강화창
------------------------------------------------------------
local enhancePanel = makePanel({
	Size = UDim2.new(0, 380, 0, 330),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Visible = false,
}, gui)

makeLabel({
	Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8),
	Text = "🔨 무기 강화", Font = Enum.Font.GothamBlack, TextSize = 24,
}, enhancePanel)

local enhanceWeapon = makeLabel({
	Size = UDim2.new(1, -24, 0, 36), Position = UDim2.new(0, 12, 0, 50),
	Font = Enum.Font.GothamBlack, TextSize = 26,
}, enhancePanel)

local enhanceInfo = makeLabel({
	Size = UDim2.new(1, -40, 0, 130), Position = UDim2.new(0, 20, 0, 92),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	RichText = true,
}, enhancePanel)

local enhanceResult = makeLabel({
	Size = UDim2.new(1, -24, 0, 28), Position = UDim2.new(0, 12, 0, 226),
	Font = Enum.Font.GothamBold, TextSize = 17,
}, enhancePanel)

local enhanceButton = makeButton({
	Size = UDim2.new(0, 170, 0, 44), Position = UDim2.new(0, 20, 1, -58),
	Text = "강화하기", TextSize = 18, BackgroundColor3 = GREEN,
}, enhancePanel, function()
	Remotes.Enhance:FireServer()
end)

makeButton({
	Size = UDim2.new(0, 170, 0, 44), Position = UDim2.new(1, -190, 1, -58),
	Text = "닫기", TextSize = 18, BackgroundColor3 = GRAY,
}, enhancePanel, function()
	enhancePanel.Visible = false
end)

local function refreshEnhance()
	local level = player:GetAttribute("WeaponLevel") or 0
	local gold = player:GetAttribute("Gold") or 0
	local name, color = weaponText(level)
	enhanceWeapon.Text = name
	enhanceWeapon.TextColor3 = color

	local lines = {
		string.format("공격력 배율  x%.1f", Config.GetDamageMultiplier(level)),
		string.format("무기 크기      x%.2f", Config.GetWeaponScale(level)),
	}

	if level >= Config.Weapon.MaxLevel then
		table.insert(lines, "\n<font color='#ffd966'>최대 강화 단계입니다!</font>")
		enhanceButton.Text = "MAX"
		enhanceButton.BackgroundColor3 = GRAY
	else
		local cost = Config.GetEnhanceCost(level)
		table.insert(lines, string.format("공격력 배율 다음 단계  x%.1f", Config.GetDamageMultiplier(level + 1)))
		table.insert(lines, string.format("\n강화 비용  <font color='#ffd966'>%d G</font>  (보유 %d G)", cost, gold))
		table.insert(lines, string.format("성공 확률  %d%%  (실패해도 레벨은 유지)", math.floor(Config.GetEnhanceChance(level) * 100 + 0.5)))

		local tiers = Config.Weapon.Tiers
		for _, tier in ipairs(tiers) do
			if tier.MinLevel > level then
				table.insert(lines, string.format("다음 외형 변화: +%d %s", tier.MinLevel, tier.Name))
				break
			end
		end
		enhanceButton.Text = "강화하기"
		enhanceButton.BackgroundColor3 = gold >= cost and GREEN or GRAY
	end
	enhanceInfo.Text = table.concat(lines, "\n")
end

Remotes.Enhance.OnClientEvent:Connect(function(ok, message)
	enhanceResult.Text = message
	enhanceResult.TextColor3 = ok and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 130, 130)
	refreshEnhance()
end)

Remotes.OpenEnhance.OnClientEvent:Connect(function()
	enhanceResult.Text = ""
	refreshEnhance()
	enhancePanel.Visible = true
end)

------------------------------------------------------------
-- 로비: 파티 패널
------------------------------------------------------------
local lobbyFrame = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1 }, gui)

local partyPanel = makePanel({
	Size = UDim2.new(0, 270, 0, 420),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 16),
}, lobbyFrame)

local partyTitle = makeLabel({
	Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 10, 0, 8),
	Font = Enum.Font.GothamBlack, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
}, partyPanel)

local memberList = create("Frame", {
	Size = UDim2.new(1, -20, 0, 140), Position = UDim2.new(0, 10, 0, 40), BackgroundTransparency = 1,
}, partyPanel)
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, memberList)

local leaveButton = makeButton({
	Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 186),
	Text = "파티 나가기", BackgroundColor3 = RED,
}, partyPanel, function()
	Remotes.Party:FireServer("Leave")
end)

makeLabel({
	Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 0, 224),
	Text = "로비 플레이어 (초대)", Font = Enum.Font.GothamBold, TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(190, 190, 210),
}, partyPanel)

local playerList = create("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -256), Position = UDim2.new(0, 10, 0, 248),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 4,
}, partyPanel)
create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, playerList)

local partyData = nil -- 서버가 보내준 현재 파티 {Id, Leader, Members = {{UserId, Name}}}

local function isPartyLeaderOrSolo()
	return partyData == nil or partyData.Leader == player.UserId
end

local function refreshParty()
	local count = partyData and #partyData.Members or 1
	partyTitle.Text = string.format("파티 (%d/%d)", count, Config.Party.MaxSize)

	clearChildren(memberList)
	if partyData then
		for index, member in ipairs(partyData.Members) do
			local row = makePanel({ Size = UDim2.new(1, 0, 0, 30), LayoutOrder = index, BackgroundColor3 = Color3.fromRGB(45, 45, 65) }, memberList)
			local isLeader = member.UserId == partyData.Leader
			local target = Players:GetPlayerByUserId(member.UserId)
			local level = target and target:GetAttribute("WeaponLevel") or 0
			makeLabel({
				Size = UDim2.new(1, -60, 1, 0), Position = UDim2.new(0, 8, 0, 0),
				Text = string.format("%s%s  (+%d)", isLeader and "👑 " or "", member.Name, level),
				TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14,
			}, row)
			if partyData.Leader == player.UserId and member.UserId ~= player.UserId then
				makeButton({
					Size = UDim2.new(0, 48, 0, 22), Position = UDim2.new(1, -52, 0.5, -11),
					Text = "추방", TextSize = 12, BackgroundColor3 = RED,
				}, row, function()
					Remotes.Party:FireServer("Kick", member.UserId)
				end)
			end
		end
	else
		makeLabel({
			Size = UDim2.new(1, 0, 0, 40), Text = "파티가 없어요.\n아래에서 초대해보세요!",
			TextSize = 14, TextColor3 = Color3.fromRGB(190, 190, 210),
		}, memberList)
	end
	leaveButton.Visible = partyData ~= nil

	clearChildren(playerList)
	local canInvite = isPartyLeaderOrSolo() and (not partyData or #partyData.Members < Config.Party.MaxSize)
	local order = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other:GetAttribute("Zone") == "Lobby" then
			order += 1
			local inParty = (other:GetAttribute("PartyId") or 0) ~= 0
			local row = makePanel({ Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, BackgroundColor3 = Color3.fromRGB(45, 45, 65) }, playerList)
			makeLabel({
				Size = UDim2.new(1, -64, 1, 0), Position = UDim2.new(0, 8, 0, 0),
				Text = string.format("%s  (+%d)", other.DisplayName, other:GetAttribute("WeaponLevel") or 0),
				TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14,
			}, row)
			if inParty then
				makeLabel({
					Size = UDim2.new(0, 56, 1, 0), Position = UDim2.new(1, -60, 0, 0),
					Text = "파티중", TextSize = 12, TextColor3 = Color3.fromRGB(150, 150, 170),
				}, row)
			elseif canInvite then
				makeButton({
					Size = UDim2.new(0, 48, 0, 22), Position = UDim2.new(1, -52, 0.5, -11),
					Text = "초대", TextSize = 12, BackgroundColor3 = GREEN,
				}, row, function()
					Remotes.Party:FireServer("Invite", other.UserId)
				end)
			end
		end
	end
end

-- 여러 신호가 한꺼번에 와도 한 번만 다시 그리도록
local partyRefreshQueued = false
local function queuePartyRefresh()
	if partyRefreshQueued then return end
	partyRefreshQueued = true
	task.defer(function()
		partyRefreshQueued = false
		refreshParty()
	end)
end

local watched = {}
local function watchPlayer(other)
	if watched[other] then return end
	watched[other] = true
	other:GetAttributeChangedSignal("Zone"):Connect(queuePartyRefresh)
	other:GetAttributeChangedSignal("PartyId"):Connect(queuePartyRefresh)
	other:GetAttributeChangedSignal("WeaponLevel"):Connect(queuePartyRefresh)
end

for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end
Players.PlayerAdded:Connect(function(other)
	watchPlayer(other)
	queuePartyRefresh()
end)
Players.PlayerRemoving:Connect(function(other)
	watched[other] = nil
	queuePartyRefresh()
end)

-- 초대 팝업
local invitePanel = makePanel({
	Size = UDim2.new(0, 340, 0, 100),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 160),
	Visible = false,
}, gui)
local inviteLabel = makeLabel({
	Size = UDim2.new(1, -20, 0, 44), Position = UDim2.new(0, 10, 0, 6),
	Font = Enum.Font.GothamBold, TextSize = 17,
}, invitePanel)
local pendingInvite = nil

local function closeInvite(decline)
	if pendingInvite and decline then
		Remotes.Party:FireServer("Decline", pendingInvite.UserId)
	end
	pendingInvite = nil
	invitePanel.Visible = false
end

makeButton({
	Size = UDim2.new(0, 140, 0, 36), Position = UDim2.new(0, 20, 1, -46),
	Text = "수락", BackgroundColor3 = GREEN,
}, invitePanel, function()
	if pendingInvite then
		Remotes.Party:FireServer("Accept", pendingInvite.UserId)
	end
	closeInvite(false)
end)
makeButton({
	Size = UDim2.new(0, 140, 0, 36), Position = UDim2.new(1, -160, 1, -46),
	Text = "거절", BackgroundColor3 = RED,
}, invitePanel, function()
	closeInvite(true)
end)

Remotes.Party.OnClientEvent:Connect(function(action, a, b)
	if action == "State" then
		partyData = a
		queuePartyRefresh()
	elseif action == "Invite" then
		local invite = { UserId = a, Name = b }
		pendingInvite = invite
		inviteLabel.Text = string.format("%s 님이 파티에 초대했어요!", b)
		invitePanel.Visible = true
		task.delay(Config.Party.InviteTimeout, function()
			if pendingInvite == invite then
				closeInvite(false)
			end
		end)
	end
end)

-- 로비 하단: 무기 강화 버튼 + 안내
makeButton({
	Size = UDim2.new(0, 150, 0, 44), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -64),
	Text = "🔨 무기 강화", TextSize = 17, BackgroundColor3 = Color3.fromRGB(200, 130, 40),
}, lobbyFrame, function()
	enhanceResult.Text = ""
	refreshEnhance()
	enhancePanel.Visible = not enhancePanel.Visible
end)

makeLabel({
	Size = UDim2.new(0, 560, 0, 40), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16),
	Text = "던전 게이트에서 파티장이 입장하면 파티원이 함께 이동해요.  마우스 클릭으로 무기 이펙트를 뽐내보세요!",
	TextSize = 14, TextColor3 = Color3.fromRGB(220, 220, 235), TextStrokeTransparency = 0.5,
}, lobbyFrame)

------------------------------------------------------------
-- 던전: 웨이브 배너 / 보스 체력바 / 스탯 패널 / 결과
------------------------------------------------------------
local dungeonFrame = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false }, gui)

local banner = makePanel({
	Size = UDim2.new(0, 360, 0, 74), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16),
}, dungeonFrame)
local bannerTitle = makeLabel({
	Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 0, 6),
	Font = Enum.Font.GothamBlack, TextSize = 26,
}, banner)
local bannerSub = makeLabel({
	Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 44),
	TextSize = 16, TextColor3 = Color3.fromRGB(210, 210, 230),
}, banner)

local bossBar = makePanel({
	Size = UDim2.new(0, 460, 0, 26), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 100), Visible = false,
}, dungeonFrame)
local bossFill = create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(200, 40, 50), BorderSizePixel = 0 }, bossBar)
rounded(bossFill)
local bossName = makeLabel({
	Size = UDim2.new(1, 0, 1, 0), Font = Enum.Font.GothamBold, TextSize = 15, TextStrokeTransparency = 0.4,
}, bossBar)

-- 스탯 패널
local STATS = {
	{
		Key = "Crit", Attr = "CritPoints", Hotkey = Enum.KeyCode.One, Name = "치명타 확률",
		Describe = function(points) return string.format("%d%%", math.floor(points * Config.Player.CritPerPoint * 100 + 0.5)) end,
	},
	{
		Key = "Speed", Attr = "SpeedPoints", Hotkey = Enum.KeyCode.Two, Name = "공격 속도",
		Describe = function(points) return string.format("+%d%%", math.floor(points * Config.Player.SpeedPerPoint * 100 + 0.5)) end,
	},
	{
		Key = "Health", Attr = "HealthPoints", Hotkey = Enum.KeyCode.Three, Name = "최대 체력",
		Describe = function(points) return tostring(Config.Player.BaseHealth + points * Config.Player.HealthPerPoint) end,
	},
}

local statPanel = makePanel({
	Size = UDim2.new(0, 330, 0, 226), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16),
}, dungeonFrame)
local statStroke = create("UIStroke", { Color = Color3.fromRGB(255, 210, 90), Thickness = 0, Transparency = 0 }, statPanel)

local statPoints = makeLabel({
	Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 10, 0, 8),
	Font = Enum.Font.GothamBlack, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left,
}, statPanel)

local statRows = {}
for index, stat in ipairs(STATS) do
	local y = 42 + (index - 1) * 38
	local label = makeLabel({
		Size = UDim2.new(1, -70, 0, 32), Position = UDim2.new(0, 10, 0, y),
		TextXAlignment = Enum.TextXAlignment.Left, TextSize = 15,
	}, statPanel)
	makeButton({
		Size = UDim2.new(0, 44, 0, 32), Position = UDim2.new(1, -54, 0, y),
		Text = "+", TextSize = 22,
	}, statPanel, function()
		Remotes.Upgrade:FireServer(stat.Key)
	end)
	statRows[stat] = label
end

local readyButton = makeButton({
	Size = UDim2.new(1, -20, 0, 34), Position = UDim2.new(0, 10, 0, 160),
	Text = "준비 완료", BackgroundColor3 = GREEN, Visible = false,
}, statPanel, function()
	Remotes.Dungeon:FireServer("Ready")
end)

makeButton({
	Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 1, -30),
	Text = "던전 나가기", TextSize = 13, BackgroundColor3 = GRAY,
}, statPanel, function()
	Remotes.Dungeon:FireServer("Leave")
end)

local dungeonState = nil

local function refreshStats()
	local points = player:GetAttribute("StatPoints") or 0
	statPoints.Text = string.format("스탯 포인트: %d", points)
	statPoints.TextColor3 = points > 0 and Color3.fromRGB(255, 220, 90) or Color3.new(1, 1, 1)

	for stat, label in pairs(statRows) do
		local value = player:GetAttribute(stat.Attr) or 0
		label.Text = string.format("[%d] %s  Lv.%d  (%s)", table.find({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }, stat.Hotkey), stat.Name, value, stat.Describe(value))
	end

	local inStatPhase = dungeonState and dungeonState.Phase == "StatPhase"
	statStroke.Thickness = inStatPhase and 3 or 0
	readyButton.Visible = inStatPhase == true
	if inStatPhase then
		readyButton.Text = string.format("준비 완료 (%d/%d)", dungeonState.ReadyCount, dungeonState.MemberCount)
	end
end

local function refreshBanner()
	local state = dungeonState
	banner.Visible = state ~= nil and state.Phase ~= "Ended"
	bossBar.Visible = state ~= nil and state.BossRatio ~= nil
	if not state then return end

	if state.BossRatio then
		bossFill.Size = UDim2.new(math.clamp(state.BossRatio, 0, 1), 0, 1, 0)
		bossName.Text = state.BossName or "BOSS"
	end

	if state.Phase == "Starting" then
		bannerTitle.Text = "던전 입장!"
		bannerSub.Text = string.format("%d초 후 첫 웨이브 시작", state.TimeLeft)
	elseif state.Phase == "Wave" then
		bannerTitle.Text = string.format("웨이브 %d / %d", state.Wave, state.TotalWaves)
		bannerSub.Text = string.format("남은 몬스터: %d", state.MonstersLeft)
	elseif state.Phase == "StatPhase" then
		bannerTitle.Text = string.format("스탯 분배  %d초", state.TimeLeft)
		bannerSub.Text = state.Wave >= state.TotalWaves and "웨이브 클리어! 다음은 보스전!" or string.format("웨이브 %d 클리어! 스탯을 올리세요", state.Wave)
	elseif state.Phase == "Boss" then
		bannerTitle.Text = "BOSS"
		bannerSub.Text = string.format("남은 몬스터: %d", state.MonstersLeft)
	end
end

-- 결과 화면
local resultPanel = makePanel({
	Size = UDim2.new(0, 400, 0, 220), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0), Visible = false,
}, dungeonFrame)
local resultTitle = makeLabel({
	Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 0, 12), Font = Enum.Font.GothamBlack, TextSize = 36,
}, resultPanel)
local resultInfo = makeLabel({
	Size = UDim2.new(1, -20, 0, 70), Position = UDim2.new(0, 10, 0, 72), TextSize = 18,
}, resultPanel)
makeButton({
	Size = UDim2.new(0, 200, 0, 40), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	Text = "지금 로비로", TextSize = 17,
}, resultPanel, function()
	Remotes.Dungeon:FireServer("Leave")
end)

local resultToken = 0
local function showResult(result)
	resultToken += 1
	local token = resultToken
	resultPanel.Visible = true
	resultTitle.Text = result.Victory and "🏆 던전 클리어!" or "💀 던전 실패"
	resultTitle.TextColor3 = result.Victory and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(255, 110, 110)

	task.spawn(function()
		for remaining = result.ReturnDelay, 1, -1 do
			if token ~= resultToken or not resultPanel.Visible then return end
			resultInfo.Text = string.format(
				"도달 웨이브 %d / %d\n획득 골드  +%d G\n%d초 후 로비로 이동",
				result.Wave, result.TotalWaves, result.Gold, remaining
			)
			task.wait(1)
		end
	end)
end

Remotes.Dungeon.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		dungeonState = data
		refreshBanner()
		refreshStats()
	elseif action == "Result" then
		showResult(data)
	end
end)

------------------------------------------------------------
-- 구역 전환 / 정보 갱신
------------------------------------------------------------
local function refreshInfo()
	local level = player:GetAttribute("WeaponLevel") or 0
	local name, color = weaponText(level)
	infoLabel.Text = string.format(
		"💰 <font color='#ffd966'>%d G</font>\n⚔ <font color='#%s'>%s</font>\n📍 %s",
		player:GetAttribute("Gold") or 0,
		color:ToHex(),
		name,
		currentZone() == "Lobby" and "로비" or "던전"
	)
end

local function refreshZone()
	local zone = currentZone()
	lobbyFrame.Visible = zone == "Lobby"
	dungeonFrame.Visible = zone == "Dungeon"
	if zone == "Lobby" then
		dungeonState = nil
		resultToken += 1
		resultPanel.Visible = false
		bossBar.Visible = false
	else
		enhancePanel.Visible = false
		invitePanel.Visible = false
	end
	refreshInfo()
	refreshStats()
	refreshBanner()
	queuePartyRefresh()
end

player.AttributeChanged:Connect(function(attribute)
	if attribute == "Zone" then
		refreshZone()
		return
	end
	refreshInfo()
	refreshStats()
	if enhancePanel.Visible then
		refreshEnhance()
	end
end)

refreshZone()
refreshEnhance()

------------------------------------------------------------
-- 입력: 마우스 방향 공격 (누르고 있으면 연사), 숫자키 스탯 투자
------------------------------------------------------------
local holding = false
local nextAttack = 0

local function getAimPoint(screenPosition)
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	return result and result.Position or (ray.Origin + ray.Direction * 300)
end

local function attack(screenPosition)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local aimPoint = getAimPoint(screenPosition)

	-- 조준 방향으로 캐릭터를 돌려세움
	local flat = Vector3.new(aimPoint.X - root.Position.X, 0, aimPoint.Z - root.Position.Z)
	if flat.Magnitude > 1 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	end

	Remotes.Attack:FireServer(aimPoint)
end

local function attackCooldown()
	local speedPoints = player:GetAttribute("SpeedPoints") or 0
	return Config.Player.BaseCooldown / (1 + speedPoints * Config.Player.SpeedPerPoint)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = true
	elseif input.UserInputType == Enum.UserInputType.Touch then
		local inset = GuiService:GetGuiInset()
		attack(Vector2.new(input.Position.X, input.Position.Y) + inset)
	elseif currentZone() == "Dungeon" then
		for _, stat in ipairs(STATS) do
			if input.KeyCode == stat.Hotkey then
				Remotes.Upgrade:FireServer(stat.Key)
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = false
	end
end)

RunService.Heartbeat:Connect(function()
	if holding and os.clock() >= nextAttack then
		nextAttack = os.clock() + attackCooldown()
		attack(UserInputService:GetMouseLocation())
	end
end)
