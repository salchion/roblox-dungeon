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
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

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
local infoPanel = makePanel({ Size = UDim2.new(0, 240, 0, 126), Position = UDim2.new(0, 16, 0, 16) }, gui)
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
	local typeKey = player:GetAttribute("WeaponType") or "Pistol"
	return string.format("+%d %s", level, Config.GetWeaponName(typeKey, level)), tier.Color
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
-- 로비: 장비창 (갑옷 / 장갑 / 신발 강화 + 보스 티켓 뽑기)
------------------------------------------------------------
local gearPanel = makePanel({
	Size = UDim2.new(0, 540, 0, 500),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Visible = false,
}, gui)

makeLabel({
	Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8),
	Text = "🛡 장비 · 뽑기", Font = Enum.Font.GothamBlack, TextSize = 24,
}, gearPanel)

local gearMessage = makeLabel({
	Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0, 12, 0, 50),
	Font = Enum.Font.GothamBold, TextSize = 16, RichText = true,
}, gearPanel)

local gearRows = {}
for index, slot in ipairs(Config.Gear.Slots) do
	local card = makePanel({
		Size = UDim2.new(1, -24, 0, 88), Position = UDim2.new(0, 12, 0, 98 + (index - 1) * 96),
		BackgroundColor3 = Color3.fromRGB(40, 40, 58),
	}, gearPanel)
	local nameLabel = makeLabel({
		Size = UDim2.new(1, -150, 0, 26), Position = UDim2.new(0, 12, 0, 6),
		Font = Enum.Font.GothamBlack, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, RichText = true,
	}, card)
	local statLabel = makeLabel({
		Size = UDim2.new(1, -150, 0, 22), Position = UDim2.new(0, 12, 0, 34),
		TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, RichText = true,
	}, card)
	local costLabel = makeLabel({
		Size = UDim2.new(1, -150, 0, 22), Position = UDim2.new(0, 12, 0, 58),
		TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, RichText = true,
		TextColor3 = Color3.fromRGB(200, 200, 215),
	}, card)
	local button = makeButton({
		Size = UDim2.new(0, 120, 0, 34), Position = UDim2.new(1, -132, 0.5, -17), Text = "강화",
	}, card, function()
		Remotes.Gear:FireServer("Enhance", slot.Key)
	end)
	gearRows[slot.Key] = { Name = nameLabel, Stat = statLabel, Cost = costLabel, Button = button }
end

local gachaCard = makePanel({
	Size = UDim2.new(1, -24, 0, 100), Position = UDim2.new(0, 12, 0, 390),
	BackgroundColor3 = Color3.fromRGB(55, 40, 80),
}, gearPanel)
local ticketLabel = makeLabel({
	Size = UDim2.new(0.5, -12, 0, 30), Position = UDim2.new(0, 12, 0, 8),
	Font = Enum.Font.GothamBlack, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left,
}, gachaCard)
local rateParts = {}
for index, rate in ipairs(Config.Gacha.Rates) do
	table.insert(rateParts, string.format("%s %d%%", Config.Gear.RarityNames[index], rate))
end
makeLabel({
	Size = UDim2.new(1, -24, 0, 46), Position = UDim2.new(0, 12, 0, 44),
	Text = table.concat(rateParts, " · ") .. "\n같은 부위의 같거나 낮은 등급은 골드로 교환돼요. 티켓은 던전 보스 / 필드 보스에게서 나와요.",
	TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(205, 200, 225),
}, gachaCard)
local rollButton = makeButton({
	Size = UDim2.new(0, 180, 0, 34), Position = UDim2.new(1, -192, 0, 8),
	Text = "🎫 뽑기 (티켓 1장)", BackgroundColor3 = Color3.fromRGB(150, 70, 230),
}, gachaCard, function()
	Remotes.Gear:FireServer("Roll")
end)

makeButton({
	Size = UDim2.new(0, 64, 0, 28), Position = UDim2.new(1, -76, 0, 10), Text = "닫기", TextSize = 14, BackgroundColor3 = GRAY,
}, gearPanel, function()
	gearPanel.Visible = false
end)

local function refreshGear()
	local gold = player:GetAttribute("Gold") or 0
	local tickets = player:GetAttribute("Tickets") or 0
	local maxLevel = Config.Gear.MaxLevel

	for _, slot in ipairs(Config.Gear.Slots) do
		local row = gearRows[slot.Key]
		local rarity = player:GetAttribute("Gear_" .. slot.Key .. "_R") or 0
		local level = player:GetAttribute("Gear_" .. slot.Key .. "_L") or 0

		if rarity <= 0 then
			row.Name.Text = slot.Name .. " — 비어 있음"
			row.Stat.Text = slot.StatName .. " 효과 · 뽑기로 얻을 수 있어요"
			row.Cost.Text = ""
			row.Button.Text = "—"
			row.Button.BackgroundColor3 = GRAY
		else
			local color = Config.Gear.RarityColors[rarity]
			row.Name.Text = string.format("<font color='#%s'>[%s] %s</font>  +%d", color:ToHex(), Config.Gear.RarityNames[rarity], slot.Names[rarity], level)
			local statText = Config.FormatGearStat(slot.Key, Config.GetGearStat(slot.Key, rarity, level))
			if level < maxLevel then
				statText ..= "   →   " .. Config.FormatGearStat(slot.Key, Config.GetGearStat(slot.Key, rarity, level + 1))
				local cost = Config.GetGearCost(slot.Key, rarity, level)
				row.Cost.Text = string.format("강화 비용 <font color='#ffd966'>%d G</font> · 성공 %d%%", cost, math.floor(Config.GetGearEnhanceChance(level) * 100 + 0.5))
				row.Button.Text = "강화"
				row.Button.BackgroundColor3 = gold >= cost and GREEN or GRAY
			else
				row.Cost.Text = "최대 강화 단계!"
				row.Button.Text = "MAX"
				row.Button.BackgroundColor3 = GRAY
			end
			row.Stat.Text = statText
		end
	end

	ticketLabel.Text = string.format("🎫 티켓 %d장", tickets)
	rollButton.BackgroundColor3 = tickets > 0 and Color3.fromRGB(150, 70, 230) or GRAY
end

Remotes.Gear.OnClientEvent:Connect(function(action, result)
	if action ~= "Result" then return end
	local color
	if result.Roll then
		color = Config.Gear.RarityColors[result.Roll.Rarity]
	else
		color = result.Ok and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 130, 130)
	end
	gearMessage.Text = result.Message
	gearMessage.TextColor3 = color
	refreshGear()
end)

Remotes.OpenGear.OnClientEvent:Connect(function()
	gearMessage.Text = ""
	refreshGear()
	gearPanel.Visible = true
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
	Size = UDim2.new(0, 150, 0, 44), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, -80, 1, -64),
	Text = "🔨 무기 강화", TextSize = 17, BackgroundColor3 = Color3.fromRGB(200, 130, 40),
}, lobbyFrame, function()
	enhanceResult.Text = ""
	refreshEnhance()
	enhancePanel.Visible = not enhancePanel.Visible
end)

makeButton({
	Size = UDim2.new(0, 150, 0, 44), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 80, 1, -64),
	Text = "🛡 장비 · 뽑기", TextSize = 17, BackgroundColor3 = Color3.fromRGB(150, 70, 230),
}, lobbyFrame, function()
	gearMessage.Text = ""
	refreshGear()
	gearPanel.Visible = not gearPanel.Visible
end)

makeLabel({
	Size = UDim2.new(0, 560, 0, 40), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16),
	Text = "북쪽 던전 게이트 · 서쪽 허수아비 훈련장 · 동쪽 끝 사냥 필드   |   Shift 달리기 · Q 슬라이딩 · R 자동공격 · I 메뉴",
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
local openDungeonSelect -- 던전 선택창 (아래에서 정의)

------------------------------------------------------------
-- 배경음악: Config.Audio.Music 에 소리 ID를 넣으면 로비 / 던전 / 보스전마다 부드럽게 바뀐다
------------------------------------------------------------
local tracks = {}
for name, id in pairs(Config.Audio.Music) do
	if id ~= 0 then
		local sound = Instance.new("Sound")
		sound.Name = "Music_" .. name
		sound.SoundId = "rbxassetid://" .. id
		sound.Looped = true
		sound.Volume = 0
		sound.Parent = SoundService
		tracks[name] = sound
	end
end

local currentMusic = nil
local function playMusic(name)
	if name == currentMusic then return end
	currentMusic = name
	for trackName, sound in pairs(tracks) do
		if trackName == name then
			if not sound.IsPlaying then
				sound:Play()
			end
			TweenService:Create(sound, TweenInfo.new(1.5), { Volume = Config.Audio.MusicVolume }):Play()
		else
			local fade = TweenService:Create(sound, TweenInfo.new(1.5), { Volume = 0 })
			fade.Completed:Connect(function()
				if currentMusic ~= trackName then
					sound:Pause()
				end
			end)
			fade:Play()
		end
	end
end

local function updateMusic()
	local zone = currentZone()
	if zone == "Lobby" then
		playMusic("Lobby")
	elseif zone == "Field" then
		playMusic(tracks.Field and "Field" or "Lobby")
	elseif dungeonState and dungeonState.Phase == "Boss" then
		playMusic("Boss")
	else
		playMusic("Dungeon")
	end
end

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
		bannerTitle.Text = string.format("%s 입장!", state.TypeName or "던전")
		bannerSub.Text = string.format("[%s] %d초 후 첫 웨이브 시작", state.DifficultyName or "", state.TimeLeft)
	elseif state.Phase == "Wave" then
		bannerTitle.Text = string.format("웨이브 %d / %d", state.Wave, state.TotalWaves)
		bannerSub.Text = string.format("%s · %s · 남은 몬스터 %d", state.TypeName or "", state.DifficultyName or "", state.MonstersLeft)
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
				"도달 웨이브 %d / %d\n획득 골드  +%d G   🎫 티켓 +%d\n%d초 후 로비로 이동",
				result.Wave, result.TotalWaves, result.Gold, result.Tickets or 0, remaining
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
		updateMusic()
	elseif action == "Result" then
		showResult(data)
	elseif action == "OpenSelect" then
		openDungeonSelect()
	end
end)

------------------------------------------------------------
-- 구역 전환 / 정보 갱신
------------------------------------------------------------
local function refreshInfo()
	local level = player:GetAttribute("WeaponLevel") or 0
	local name, color = weaponText(level)
	local zone = currentZone()
	local zoneText = zone == "Lobby" and "로비" or zone == "Dungeon" and "던전" or string.format("필드 (최고 %d구역)", player:GetAttribute("MaxZone") or 0)
	infoLabel.Text = string.format(
		"💰 <font color='#ffd966'>%d G</font>   🎫 <font color='#d9a6ff'>%d</font>\n⚡ 전투력 <font color='#ffe16e'>%d</font>\n⚔ <font color='#%s'>%s</font>\n📍 %s",
		player:GetAttribute("Gold") or 0,
		player:GetAttribute("Tickets") or 0,
		player:GetAttribute("Power") or 0,
		color:ToHex(),
		name,
		zoneText
	)
end

local function refreshZone()
	local zone = currentZone()
	lobbyFrame.Visible = zone ~= "Dungeon"
	dungeonFrame.Visible = zone == "Dungeon"
	if zone ~= "Dungeon" then
		dungeonState = nil
		resultToken += 1
		resultPanel.Visible = false
		bossBar.Visible = false
	else
		enhancePanel.Visible = false
		gearPanel.Visible = false
		invitePanel.Visible = false
	end
	refreshInfo()
	refreshStats()
	refreshBanner()
	queuePartyRefresh()
	updateMusic()
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
	if gearPanel.Visible then
		refreshGear()
	end
end)

refreshZone()
refreshEnhance()

------------------------------------------------------------
-- 입력: 마우스 방향 공격 (누르고 있으면 연사), 숫자키 스탯 투자
------------------------------------------------------------
local holding = false
local nextAttack = 0

------------------------------------------------------------
-- Shift 달리기 / Q 슬라이딩
------------------------------------------------------------
local sprinting = false
local sliding = false

local function applySpeed()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local bonus = player:GetAttribute("GearSpeed") or 0 -- 신발 장비 효과
		humanoid.WalkSpeed = (sprinting and Config.Player.RunSpeed or Config.Player.WalkSpeed) + bonus
	end
end

player:GetAttributeChangedSignal("GearSpeed"):Connect(applySpeed)

-- Q: 슬라이딩. 이동 방향(가만히 있으면 바라보는 방향)으로 빠르게 미끄러지다가 점점 느려진다.
-- 발밑에 먼지가 일고 몸에서 꼬리가 남는다.
local lastSlide = 0
local function slide()
	if sliding then return end
	local now = os.clock()
	if now - lastSlide < Config.Player.DashCooldown then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end
	lastSlide = now
	sliding = true

	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z).Unit

	local attachment = Instance.new("Attachment")
	attachment.Parent = root

	-- 수평으로만 속도를 주고 세로(중력)는 그대로 둔다
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	velocity.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
	velocity.VectorVelocity = direction * Config.Player.DashSpeed
	velocity.Parent = root

	-- 먼지 + 꼬리 (내 화면에서만 보임)
	local dustAttachment = Instance.new("Attachment")
	dustAttachment.Position = Vector3.new(0, -2.6, 0)
	dustAttachment.Parent = root
	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 90
	dust.Lifetime = NumberRange.new(0.3, 0.6)
	dust.Speed = NumberRange.new(2, 6)
	dust.SpreadAngle = Vector2.new(60, 60)
	dust.Color = ColorSequence.new(Color3.fromRGB(220, 215, 200))
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3) })
	dust.Parent = dustAttachment

	local trailTop = Instance.new("Attachment")
	trailTop.Position = Vector3.new(0, 1.4, 0)
	trailTop.Parent = root
	local trailBottom = Instance.new("Attachment")
	trailBottom.Position = Vector3.new(0, -2.4, 0)
	trailBottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = trailTop
	trail.Attachment1 = trailBottom
	trail.Lifetime = 0.3
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new(Color3.fromRGB(190, 225, 255))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = root

	local autoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)

	local started = os.clock()
	local connection
	local function finish()
		connection:Disconnect()
		velocity:Destroy()
		attachment:Destroy()
		dust.Enabled = false
		trail.Enabled = false
		if humanoid.Parent then
			humanoid.AutoRotate = autoRotate
		end
		sliding = false
		task.delay(0.7, function()
			dustAttachment:Destroy()
			trail:Destroy()
			trailTop:Destroy()
			trailBottom:Destroy()
		end)
	end
	connection = RunService.Heartbeat:Connect(function()
		local t = (os.clock() - started) / Config.Player.DashTime
		if t >= 1 or not root.Parent or humanoid.Health <= 0 then
			finish()
			return
		end
		-- 처음엔 빠르게, 갈수록 느려지며 미끄러지는 느낌
		velocity.VectorVelocity = direction * (Config.Player.DashSpeed * (1 - t) ^ 1.6 + 6)
	end)
end

player.CharacterAdded:Connect(function(character)
	character:WaitForChild("Humanoid")
	applySpeed()
	sliding = false
end)

RunService.RenderStepped:Connect(function(dt)
	local target = sliding and 92 or sprinting and 80 or 70
	camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 8)
end)

------------------------------------------------------------
-- 조준 / 공격 / 자동 공격(락온, R)
------------------------------------------------------------
local autoMode = false
local lockTarget = nil     -- { Kind = "Dummy" | "Monster", Instance, Part }
local nextSearch = 0

local autoLabel = makeLabel({
	Size = UDim2.new(0, 460, 0, 30), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -128),
	BackgroundColor3 = Color3.fromRGB(20, 20, 30), BackgroundTransparency = 0.25,
	Font = Enum.Font.GothamBold, TextSize = 16, Visible = false, RichText = true,
}, gui)
rounded(autoLabel)

local lockHighlight = Instance.new("Highlight")
lockHighlight.FillTransparency = 1
lockHighlight.OutlineColor = Color3.fromRGB(255, 220, 80)
lockHighlight.OutlineTransparency = 0
lockHighlight.Enabled = false
lockHighlight.Parent = workspace

local function targetName(target)
	if not target then return "대상 찾는 중..." end
	if target.Kind == "Dummy" then
		local index = tonumber(string.sub(target.Instance.Name, 6))
		local info = index and Config.Dummy.List[index]
		return info and string.format("x%s 허수아비", tostring(info.Multiplier)) or "허수아비"
	end
	return "몬스터"
end

local function updateLockVisual()
	autoLabel.Visible = autoMode
	if autoMode then
		autoLabel.Text = string.format("🔒 자동 공격 <font color='#ffe16e'>ON</font> (R) · %s", targetName(lockTarget))
	end
	if autoMode and lockTarget and lockTarget.Instance.Parent then
		lockHighlight.Adornee = lockTarget.Instance
		lockHighlight.Enabled = true
	else
		lockHighlight.Adornee = nil
		lockHighlight.Enabled = false
	end
end

local function weaponRange()
	return Config.GetPlayerWeapon(player).Range
end

-- 이 허수아비를 지금 무기 레벨로 때려서 골드를 받을 수 있는가?
local function dummyUsable(model)
	local index = tonumber(string.sub(model.Name, 6))
	local info = index and Config.Dummy.List[index]
	return info ~= nil and (player:GetAttribute("WeaponLevel") or 0) >= info.RequiredLevel
end

-- 맞은 Instance 가 락온할 수 있는 대상(허수아비 / 필드 몬스터 / 던전 몬스터)이면 대상 정보를 만든다
local function resolveTarget(instance)
	if not instance then return nil end

	local dummies = workspace:FindFirstChild("Dummies")
	if dummies and instance:IsDescendantOf(dummies) then
		local model = instance:FindFirstAncestorOfClass("Model")
		if model and model.PrimaryPart and string.sub(model.Name, 1, 5) == "Dummy" then
			return { Kind = "Dummy", Instance = model, Part = model.PrimaryPart }
		end
		return nil
	end

	local parent = instance.Parent
	if parent and parent.Name == "FieldMonsters" and parent.Parent == workspace then
		return { Kind = "Monster", Instance = instance, Part = instance }
	end
	if parent and parent.Name == "Monsters" and parent.Parent and string.sub(parent.Parent.Name, 1, 8) == "Dungeon_" then
		return { Kind = "Monster", Instance = instance, Part = instance }
	end
	return nil
end

local function isTargetValid(target, root)
	if not target or not target.Instance.Parent or not target.Part.Parent then return false end
	if target.Kind == "Dummy" and not dummyUsable(target.Instance) then return false end
	return (target.Part.Position - root.Position).Magnitude <= weaponRange() * 0.95
end

-- 지금 구역에서 때릴 수 있는 가장 가까운 대상
local function findNearestTarget(root)
	local zone = currentZone()
	local best, bestDistance = nil, math.huge

	local function consider(target)
		if isTargetValid(target, root) then
			local distance = (target.Part.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = target, distance
			end
		end
	end

	if zone == "Lobby" then
		local dummies = workspace:FindFirstChild("Dummies")
		if dummies then
			for _, model in ipairs(dummies:GetChildren()) do
				if model:IsA("Model") and model.PrimaryPart then
					consider({ Kind = "Dummy", Instance = model, Part = model.PrimaryPart })
				end
			end
		end
	elseif zone == "Field" then
		local folder = workspace:FindFirstChild("FieldMonsters")
		if folder then
			for _, part in ipairs(folder:GetChildren()) do
				consider({ Kind = "Monster", Instance = part, Part = part })
			end
		end
	elseif zone == "Dungeon" then
		for _, child in ipairs(workspace:GetChildren()) do
			if string.sub(child.Name, 1, 8) == "Dungeon_" then
				local monsters = child:FindFirstChild("Monsters")
				if monsters then
					for _, part in ipairs(monsters:GetChildren()) do
						consider({ Kind = "Monster", Instance = part, Part = part })
					end
				end
			end
		end
	end
	return best
end

local function getAimPoint(screenPosition)
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if result then
		return result.Position, result.Instance
	end
	return ray.Origin + ray.Direction * 300, nil
end

local crosshairKick = 0 -- 쏠 때마다 조준점이 벌어졌다 돌아오는 연출용

-- 월드 좌표를 향해 캐릭터를 돌려세우고 서버에 공격 요청
local function fireAt(worldPoint)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	if not sliding then
		local flat = Vector3.new(worldPoint.X - root.Position.X, 0, worldPoint.Z - root.Position.Z)
		if flat.Magnitude > 1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end
	crosshairKick = 10
	Remotes.Attack:FireServer(worldPoint)
end

local function attack(screenPosition)
	local point, instance = getAimPoint(screenPosition)

	-- 자동 공격 중에 대상을 직접 클릭하면 그 대상으로 락온을 바꾼다 (배율이 다른 허수아비를 고를 수 있음)
	if autoMode then
		local target = resolveTarget(instance)
		if target then
			if target.Kind == "Dummy" and not dummyUsable(target.Instance) then
				toast("🔒 이 허수아비는 무기 레벨이 더 필요해요")
			else
				lockTarget = target
				updateLockVisual()
			end
		end
	end
	fireAt(point)
end

local function toggleAuto()
	autoMode = not autoMode
	lockTarget = nil
	nextSearch = 0
	updateLockVisual()
	toast(autoMode and "🔒 자동 공격 ON — 허수아비/몬스터를 직접 클릭하면 그 대상으로 고정돼요 (R로 끄기)" or "자동 공격 OFF")
end

local function attackCooldown()
	local speedPoints = player:GetAttribute("SpeedPoints") or 0
	return Config.Player.BaseCooldown * Config.GetPlayerWeapon(player).Cooldown / (1 + speedPoints * Config.Player.SpeedPerPoint)
end

------------------------------------------------------------
-- 메뉴 (I): 캐릭터 / 무기 / 퀘스트 / 업적 / 랭킹
------------------------------------------------------------
local questState = nil   -- 서버가 보내준 퀘스트/업적/칭호 상태
local rankList = {}      -- 서버가 보내준 전투력 랭킹

local menuPanel = makePanel({
	Size = UDim2.new(0, 680, 0, 560),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Visible = false,
}, gui)

makeLabel({
	Size = UDim2.new(1, -90, 0, 36), Position = UDim2.new(0, 16, 0, 8),
	Text = "📋 메뉴", Font = Enum.Font.GothamBlack, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left,
}, menuPanel)

makeButton({
	Size = UDim2.new(0, 64, 0, 28), Position = UDim2.new(1, -76, 0, 10), Text = "닫기 (I)", TextSize = 13, BackgroundColor3 = GRAY,
}, menuPanel, function()
	menuPanel.Visible = false
end)

local TABS = {
	{ Key = "Character", Name = "캐릭터" },
	{ Key = "Weapon", Name = "무기" },
	{ Key = "Quest", Name = "퀘스트" },
	{ Key = "Ach", Name = "업적" },
	{ Key = "Rank", Name = "랭킹" },
}
local currentTab = "Character"
local tabButtons = {}

local menuContent = create("ScrollingFrame", {
	Size = UDim2.new(1, -24, 1, -108), Position = UDim2.new(0, 12, 0, 96),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6,
	CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, menuPanel)
create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, menuContent)

local rowOrder = 0
local function newRow(height, color)
	rowOrder += 1
	return makePanel({
		Size = UDim2.new(1, -10, 0, height), LayoutOrder = rowOrder,
		BackgroundColor3 = color or Color3.fromRGB(40, 40, 58),
	}, menuContent)
end

local function rowText(row, text, size, rightMargin)
	return makeLabel({
		Size = UDim2.new(1, -(rightMargin or 24), 1, -10), Position = UDim2.new(0, 12, 0, 5),
		Text = text, TextSize = size or 15, RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
	}, row)
end

local function sectionTitle(text)
	local row = newRow(26, Color3.fromRGB(30, 30, 44))
	rowText(row, text, 14)
end

local function hex(color)
	return color:ToHex()
end

local function buildCharacterTab()
	local weaponType = Config.GetPlayerWeapon(player)
	local health = Config.Player.BaseHealth + (player:GetAttribute("HealthPoints") or 0) * Config.Player.HealthPerPoint + (player:GetAttribute("GearHealth") or 0)
	local crit = ((player:GetAttribute("CritPoints") or 0) * Config.Player.CritPerPoint + (player:GetAttribute("GearCrit") or 0) + (weaponType.CritBonus or 0)) * 100
	local speed = Config.Player.WalkSpeed + (player:GetAttribute("GearSpeed") or 0)

	local summary = newRow(118)
	rowText(summary, string.format(
		"⚡ 전투력 <font color='#ffe16e'>%d</font>\n❤ 최대 체력 %d    🎯 치명타 확률 %.1f%%    💨 이동속도 %.1f\n💰 %d G    🎫 티켓 %d장\n🏔 필드 최고 %d구역 돌파    🏰 던전 클리어 %d회",
		player:GetAttribute("Power") or 0, health, crit, speed,
		player:GetAttribute("Gold") or 0, player:GetAttribute("Tickets") or 0,
		player:GetAttribute("MaxZone") or 0, questState and questState.Stats and questState.Stats.DungeonClears or 0
	), 16)

	sectionTitle("장착 중인 장비")
	local level = player:GetAttribute("WeaponLevel") or 0
	local weaponName, weaponColor = weaponText(level)
	local weaponRow = newRow(40)
	rowText(weaponRow, string.format("🔫 무기   <font color='#%s'>%s</font>", hex(weaponColor), weaponName))

	for _, slot in ipairs(Config.Gear.Slots) do
		local rarity = player:GetAttribute("Gear_" .. slot.Key .. "_R") or 0
		local gearLevel = player:GetAttribute("Gear_" .. slot.Key .. "_L") or 0
		local row = newRow(40)
		if rarity <= 0 then
			rowText(row, string.format("🛡 %s   <font color='#888888'>비어 있음 (보스 티켓으로 뽑기)</font>", slot.Name))
		else
			local color = Config.Gear.RarityColors[rarity]
			rowText(row, string.format("🛡 %s   <font color='#%s'>[%s] %s +%d</font>   %s", slot.Name, hex(color),
				Config.Gear.RarityNames[rarity], slot.Names[rarity], gearLevel,
				Config.FormatGearStat(slot.Key, Config.GetGearStat(slot.Key, rarity, gearLevel))))
		end
	end

	sectionTitle("칭호 (업적을 달성하면 해금, 머리 위 이름표에 표시)")
	local titles = questState and questState.Titles or {}
	local equipped = questState and questState.Equipped
	if #titles == 0 then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>아직 해금한 칭호가 없어요. 업적 탭에서 도전해보세요!</font>")
	end
	for _, title in ipairs(titles) do
		local row = newRow(40)
		rowText(row, string.format("『%s』", title), 16, 150)
		local isEquipped = title == equipped
		makeButton({
			Size = UDim2.new(0, 110, 0, 28), Position = UDim2.new(1, -122, 0.5, -14),
			Text = isEquipped and "해제" or "장착", BackgroundColor3 = isEquipped and RED or GREEN,
		}, row, function()
			Remotes.Quest:FireServer("Title", isEquipped and "" or title)
		end)
	end
end

local function buildWeaponTab()
	sectionTitle("무기 종류 — 종류마다 강화 레벨이 따로 있어요. 구매/교체는 로비에서만 가능해요.")
	local active = player:GetAttribute("WeaponType") or "Pistol"
	for _, key in ipairs(Config.WeaponTypes.Order) do
		local weaponType = Config.WeaponTypes[key]
		local unlocked = key == "Pistol" or player:GetAttribute("WUnlock_" .. key) == true
		local level = player:GetAttribute("WLvl_" .. key) or 0
		local tier = Config.GetWeaponTier(level)

		local row = newRow(84)
		rowText(row, string.format(
			"<font size='18'><b>%s</b></font>  <font color='#%s'>+%d %s</font>\n<font color='#bbbbcc'>%s</font>\n<font color='#bbbbcc'>한 발 x%.1f · 발사 간격 x%.1f · 탄 %d발 · 사거리 %d</font>",
			weaponType.Name, hex(tier.Color), level, Config.GetWeaponName(key, level),
			weaponType.Desc, weaponType.DamageMult, weaponType.Cooldown, weaponType.Pellets, weaponType.Range
		), 14, 170)

		local label, color, action
		if key == active then
			label, color = "장착 중", GRAY
		elseif unlocked then
			label, color, action = "장착", GREEN, "Equip"
		else
			label, color, action = string.format("구매 %d G", weaponType.UnlockCost), Color3.fromRGB(200, 130, 40), "Buy"
		end
		makeButton({
			Size = UDim2.new(0, 130, 0, 34), Position = UDim2.new(1, -142, 0.5, -17), Text = label, BackgroundColor3 = color,
		}, row, function()
			if action then
				Remotes.Weapon:FireServer(action, key)
			end
		end)
	end
end

local function buildProgressRows(entries, remoteAction, showTitle)
	if not entries then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>불러오는 중...</font>")
		return
	end
	for _, entry in ipairs(entries) do
		local done = entry.Progress >= entry.Goal
		local row = newRow(66, entry.Claimed and Color3.fromRGB(32, 38, 36) or Color3.fromRGB(40, 40, 58))
		local titleText = showTitle and entry.Title and string.format("   <font color='#9ad7ff'>칭호 『%s』</font>", entry.Title) or ""
		rowText(row, string.format(
			"<font size='16'><b>%s</b></font>%s\n<font color='#bbbbcc'>%s</font>\n<font color='#%s'>%d / %d</font>   <font color='#ffd966'>보상 %s</font>",
			entry.Name, titleText, entry.Desc, done and "78ff8c" or "ffffff", entry.Progress, entry.Goal, entry.Reward
		), 14, 160)

		local label, color, enabled
		if entry.Claimed then
			label, color = "완료", GRAY
		elseif done then
			label, color, enabled = "보상 받기", GREEN, true
		else
			label, color = "진행 중", GRAY
		end
		makeButton({
			Size = UDim2.new(0, 120, 0, 32), Position = UDim2.new(1, -132, 0.5, -16), Text = label, BackgroundColor3 = color,
		}, row, function()
			if enabled then
				Remotes.Quest:FireServer(remoteAction, entry.Id)
			end
		end)
	end
end

local function buildRankTab()
	sectionTitle("🏆 전투력 랭킹 TOP 10 (광장의 랭킹판과 같아요)")
	if #rankList == 0 then
		local row = newRow(36)
		rowText(row, "<font color='#888888'>집계 중이에요...</font>")
	end
	for index, entry in ipairs(rankList) do
		local row = newRow(36, entry.Name == player.DisplayName and Color3.fromRGB(60, 52, 28) or nil)
		local medal = index == 1 and "🥇" or index == 2 and "🥈" or index == 3 and "🥉" or string.format("%d.", index)
		rowText(row, string.format("%s  <b>%s</b>   ⚡ %d", medal, entry.Name, entry.Power), 16)
	end
end

local function refreshMenu()
	for _, tab in ipairs(TABS) do
		tabButtons[tab.Key].BackgroundColor3 = tab.Key == currentTab and Color3.fromRGB(70, 110, 220) or GRAY
	end

	clearChildren(menuContent)
	rowOrder = 0
	if currentTab == "Character" then
		buildCharacterTab()
	elseif currentTab == "Weapon" then
		buildWeaponTab()
	elseif currentTab == "Quest" then
		sectionTitle("📅 오늘의 일일 퀘스트 (매일 바뀌어요)")
		buildProgressRows(questState and questState.Daily, "Claim", false)
	elseif currentTab == "Ach" then
		sectionTitle("🏅 업적 — 달성하면 보상과 칭호를 받아요")
		buildProgressRows(questState and questState.Achievements, "ClaimAch", true)
	elseif currentTab == "Rank" then
		buildRankTab()
	end
end

local function selectTab(key)
	currentTab = key
	if key == "Quest" or key == "Ach" or key == "Character" then
		Remotes.Quest:FireServer("Request")
	elseif key == "Rank" then
		Remotes.Rank:FireServer("Request")
	end
	refreshMenu()
end

for index, tab in ipairs(TABS) do
	tabButtons[tab.Key] = makeButton({
		Size = UDim2.new(0, 124, 0, 34), Position = UDim2.new(0, 14 + (index - 1) * 130, 0, 52), Text = tab.Name, TextSize = 16,
	}, menuPanel, function()
		selectTab(tab.Key)
	end)
end

local function toggleMenu()
	menuPanel.Visible = not menuPanel.Visible
	if menuPanel.Visible then
		selectTab(currentTab)
	end
end

makeButton({
	Size = UDim2.new(0, 110, 0, 32), Position = UDim2.new(0, 16, 0, 150), Text = "📋 메뉴 (I)", TextSize = 14,
	BackgroundColor3 = Color3.fromRGB(60, 70, 120),
}, gui, toggleMenu)

Remotes.Quest.OnClientEvent:Connect(function(action, data)
	if action == "State" then
		questState = data
		if menuPanel.Visible then
			refreshMenu()
		end
	end
end)

Remotes.Rank.OnClientEvent:Connect(function(action, data)
	if action == "List" then
		rankList = data
		if menuPanel.Visible and currentTab == "Rank" then
			refreshMenu()
		end
	end
end)

-- 골드/장비/무기 등이 바뀌면 열려 있는 메뉴도 갱신 (한꺼번에 여러 번 와도 한 번만)
local menuRefreshQueued = false
player.AttributeChanged:Connect(function()
	if not menuPanel.Visible or menuRefreshQueued then return end
	menuRefreshQueued = true
	task.defer(function()
		menuRefreshQueued = false
		if menuPanel.Visible then
			refreshMenu()
		end
	end)
end)

------------------------------------------------------------
-- 던전 선택창 (게이트): 종류 + 난이도
------------------------------------------------------------
local refreshSelect
local selectedType = "Cave"
local selectedDifficulty = "Normal"

local selectPanel = makePanel({
	Size = UDim2.new(0, 660, 0, 500),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Visible = false,
}, gui)

makeLabel({
	Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 0, 8),
	Text = "⚔ 던전 선택", Font = Enum.Font.GothamBlack, TextSize = 24,
}, selectPanel)

local typeCards = {}
for index, key in ipairs(Config.Dungeon.Types.Order) do
	local info = Config.Dungeon.Types[key]
	local card = makeButton({
		Size = UDim2.new(0, 200, 0, 170), Position = UDim2.new(0, 14 + (index - 1) * 212, 0, 54),
		Text = "", BackgroundColor3 = Color3.fromRGB(40, 40, 58), AutoButtonColor = true,
	}, selectPanel, function()
		selectedType = key
		refreshSelect()
	end)
	create("UIStroke", { Color = info.Torch, Thickness = 0, Name = "Stroke" }, card)
	makeLabel({
		Size = UDim2.new(1, -16, 1, -12), Position = UDim2.new(0, 8, 0, 6), RichText = true,
		Text = string.format("<font size='20'><b>%s</b></font>\n\n<font color='#bbbbcc' size='13'>%s</font>\n\n웨이브 %d + 보스\n권장 전투력 %d",
			info.Name, info.Desc, info.Waves, info.RecommendedPower),
		TextSize = 15, TextYAlignment = Enum.TextYAlignment.Top,
	}, card)
	typeCards[key] = card
end

makeLabel({
	Size = UDim2.new(1, -28, 0, 22), Position = UDim2.new(0, 14, 0, 236),
	Text = "난이도", Font = Enum.Font.GothamBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
}, selectPanel)

local difficultyButtons = {}
for index, key in ipairs(Config.Dungeon.Difficulties.Order) do
	local info = Config.Dungeon.Difficulties[key]
	difficultyButtons[key] = makeButton({
		Size = UDim2.new(0, 200, 0, 40), Position = UDim2.new(0, 14 + (index - 1) * 212, 0, 262),
		Text = info.Name, TextSize = 18, BackgroundColor3 = GRAY,
	}, selectPanel, function()
		selectedDifficulty = key
		refreshSelect()
	end)
end

local summaryLabel = makeLabel({
	Size = UDim2.new(1, -28, 0, 110), Position = UDim2.new(0, 14, 0, 314), RichText = true,
	TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, selectPanel)

function refreshSelect()
	for key, card in pairs(typeCards) do
		card.Stroke.Thickness = key == selectedType and 3 or 0
	end
	for key, button in pairs(difficultyButtons) do
		local info = Config.Dungeon.Difficulties[key]
		button.BackgroundColor3 = key == selectedDifficulty and info.Color:Lerp(Color3.fromRGB(30, 30, 40), 0.35) or GRAY
	end

	local dungeonType = Config.Dungeon.Types[selectedType]
	local difficulty = Config.Dungeon.Difficulties[selectedDifficulty]
	summaryLabel.Text = string.format(
		"<b>%s · %s</b>\n웨이브 %d개 → 보스 <font color='#ff9a9a'>%s</font>\n권장 전투력 <font color='#ffe16e'>%d</font>  (내 전투력 %d)\n골드 보상 x%.1f    보스 처치 시 🎫 티켓 %d장",
		dungeonType.Name, difficulty.Name, dungeonType.Waves, dungeonType.Boss.Name,
		dungeonType.RecommendedPower, player:GetAttribute("Power") or 0,
		dungeonType.GoldMult * difficulty.GoldMult, difficulty.Tickets
	)
end

makeButton({
	Size = UDim2.new(0, 280, 0, 46), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14),
	Text = "입장하기", TextSize = 20, BackgroundColor3 = GREEN,
}, selectPanel, function()
	selectPanel.Visible = false
	Remotes.Dungeon:FireServer("Start", selectedType, selectedDifficulty)
end)

makeButton({
	Size = UDim2.new(0, 280, 0, 46), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14),
	Text = "닫기", TextSize = 20, BackgroundColor3 = GRAY,
}, selectPanel, function()
	selectPanel.Visible = false
end)

openDungeonSelect = function()
	refreshSelect()
	selectPanel.Visible = true
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	if currentZone() == "Dungeon" then
		selectPanel.Visible = false
	end
	lockTarget = nil
	updateLockVisual()
end)

------------------------------------------------------------
-- 입력
--   마우스: 조준 방향 공격(누르고 있으면 연사) / R: 자동 공격(락온) / Q: 슬라이딩 / Shift: 달리기
--   I: 메뉴 / 던전 안: 숫자키 1 2 3 스탯 투자
------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = true
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = true
		applySpeed()
	elseif input.KeyCode == Enum.KeyCode.Q then
		slide()
	elseif input.KeyCode == Enum.KeyCode.R then
		toggleAuto()
	elseif input.KeyCode == Enum.KeyCode.I then
		toggleMenu()
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
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = false
		applySpeed()
	end
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now < nextAttack then return end

	if holding then
		nextAttack = now + attackCooldown()
		attack(UserInputService:GetMouseLocation())
	elseif autoMode then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then return end

		if not isTargetValid(lockTarget, root) and now >= nextSearch then
			nextSearch = now + 0.4 -- 대상 탐색은 0.4초에 한 번만
			lockTarget = findNearestTarget(root)
			updateLockVisual()
		end
		if lockTarget and isTargetValid(lockTarget, root) then
			nextAttack = now + attackCooldown()
			fireAt(lockTarget.Part.Position)
		end
	end
end)

------------------------------------------------------------
-- 조준점: 마우스 화살표 대신 십자 격자 조준점이 마우스를 따라다닌다.
--   쏠 때마다 살짝 벌어졌다 돌아오고, 자동 공격으로 대상을 잡으면 노란색이 된다.
--   메뉴 창이 열려 있거나 버튼 위에 있을 땐 원래 화살표 마우스로 돌아온다.
------------------------------------------------------------
local hasMouse = UserInputService.MouseEnabled
local playerGui = player:WaitForChild("PlayerGui")

local crosshair = create("Frame", {
	Name = "Crosshair", Size = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 100,
}, gui)

local function makeCrosshairPart(width, height)
	local part = create("Frame", {
		Size = UDim2.new(0, width, 0, height), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 100,
	}, crosshair)
	create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, part)
	return part
end

local barUp = makeCrosshairPart(2, 11)
local barDown = makeCrosshairPart(2, 11)
local barLeft = makeCrosshairPart(11, 2)
local barRight = makeCrosshairPart(11, 2)
local centerDot = makeCrosshairPart(3, 3)

local function isMouseOverButton(position)
	for _, object in ipairs(playerGui:GetGuiObjectsAtPosition(position.X, position.Y)) do
		if object:IsA("GuiButton") and object.Visible then
			return true
		end
	end
	return false
end

RunService.RenderStepped:Connect(function(dt)
	local modalOpen = menuPanel.Visible or enhancePanel.Visible or gearPanel.Visible or selectPanel.Visible
	local position = UserInputService:GetMouseLocation()
	local show = hasMouse and not modalOpen and player.Character ~= nil and not isMouseOverButton(position)

	UserInputService.MouseIconEnabled = not show
	crosshair.Visible = show
	if not show then return end

	crosshairKick = math.max(0, crosshairKick - dt * 55)
	local gap = 7 + crosshairKick + (holding and 2 or 0)
	local color = (autoMode and lockTarget) and Color3.fromRGB(255, 225, 90) or Color3.new(1, 1, 1)

	crosshair.Position = UDim2.fromOffset(position.X, position.Y)
	barUp.Position = UDim2.fromOffset(0, -gap - 5)
	barDown.Position = UDim2.fromOffset(0, gap + 5)
	barLeft.Position = UDim2.fromOffset(-gap - 5, 0)
	barRight.Position = UDim2.fromOffset(gap + 5, 0)
	for _, part in ipairs({ barUp, barDown, barLeft, barRight, centerDot }) do
		part.BackgroundColor3 = color
	end
end)
