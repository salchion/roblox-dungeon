-- WeaponBarClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: WeaponBarClient)
-- 화면 아래의 "무기 슬롯 바": 무기 종류 10개를 번호 1~0 으로 바로 바꾼다 (폰은 칸을 누른다).
--   * 열린 종류만 켜지고, 지금 쓰는 무기는 테두리가 강조된다. 잠긴 칸은 🔒 이고, 누르면 "+N 단계에서 열려요 (몇 단계 남음)" 이 뜬다.
--   (강화 버튼은 두지 않는다: 무기 강화는 대장간 / 메뉴(B)에서만 한다.)
--   * 새 무기 종류가 열리면 그 칸이 반짝이고 "새 총: ○○ — 숫자 N 을 누르세요" 가 뜬다 (무기를 올리면 새 총이 열린다는 걸 자연스럽게 알려 준다).
--   * 위치는 자동: 화면의 다른 UI 와 겹치지 않는 빈 자리를 찾는다 (아래 가운데부터). 메뉴 / 큰 창이 열려 있으면 숨는다.
--   무기 바꾸기 / 강화는 서버가 다시 검사한다 (이 스크립트는 요청만 보낸다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Kit = require(ReplicatedStorage:WaitForChild("ClientKit"))
local create, rounded = Kit.create, Kit.rounded

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local COMPACT = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local ORDER = Config.WeaponTypes.Order
local ICONS = { Pistol = "🔫", Smg = "💨", Revolver = "💣", Rifle = "🏹", Shotgun = "✴", Flamer = "📖", Cannon = "🧨", Sniper = "🎯", Rocket = "🚀", Rail = "🪄" }
local KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine, Enum.KeyCode.Zero,
}
local KEY_TO_SLOT = {}
for index, code in ipairs(KEYS) do KEY_TO_SLOT[code] = index end

local SLOT = COMPACT and 26 or 32 -- (칸 아이콘이 너무 크다는 의견: 40 -> 32 / 폰 32 -> 26)
local GAP = 4
local BAR_W = #ORDER * SLOT + (#ORDER - 1) * GAP
local INFO_H = 20
local HOLDER_H = INFO_H + 2 + SLOT

local GOLD = Color3.fromRGB(255, 210, 90)
local attached = false -- 스킬 바에 붙었는지 (아래 attachToSkillBar)

print("[WeaponBar] version: center-77 (fixed)") -- 출력창에서 어떤 버전이 돌고 있는지 바로 확인용
local gui = create("ScreenGui", { Name = "WeaponBarGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 3, Enabled = false }, playerGui)
local holder = create("Frame", { Size = UDim2.new(0, BAR_W, 0, HOLDER_H), BackgroundTransparency = 1 }, gui)

local info = create("TextLabel", {
	Size = UDim2.new(1, 0, 0, INFO_H), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.fromRGB(225, 230, 250), TextTruncate = Enum.TextTruncate.AtEnd,
	TextStrokeTransparency = 0.5, Text = "", ZIndex = 2,
}, holder)

local slots = {}
for index, key in ipairs(ORDER) do
	local button = create("TextButton", {
		Name = "Slot" .. index, Size = UDim2.new(0, SLOT, 0, SLOT), Position = UDim2.new(0, (index - 1) * (SLOT + GAP), 0, INFO_H + 2),
		BackgroundColor3 = Color3.fromRGB(26, 28, 44), BackgroundTransparency = 0.12, BorderSizePixel = 0, AutoButtonColor = true,
		Font = Enum.Font.GothamBold, TextSize = COMPACT and 12 or 15, Text = ICONS[key] or "?", TextColor3 = Color3.new(1, 1, 1), ZIndex = 2,
	}, holder)
	rounded(button, 8)
	local stroke = create("UIStroke", { Color = Color3.fromRGB(90, 96, 130), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	create("TextLabel", {
		Size = UDim2.new(0, 12, 0, 10), Position = UDim2.new(0, 2, 0, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextSize = 9, TextColor3 = Color3.fromRGB(190, 195, 220), Text = tostring(index % 10), ZIndex = 3,
	}, button)
	slots[index] = { Button = button, Stroke = stroke, Key = key }
end

local function weaponName(key)
	local entry = Config.WeaponTypes[key]
	return entry and entry.Name or tostring(key)
end

-- 위쪽 글자: 잠깐 보여 주는 안내(say) 가 없으면 지금 무기 + 다음에 열릴 총
local sayUntil = 0
local sayToken = 0
local function idleText()
	local level = player:GetAttribute("WeaponLevel") or 0
	local current = player:GetAttribute("WeaponType") or "Pistol"
	local milestone = Config.GetNextMilestone(level)
	local text = string.format("%s", weaponName(current))
	if milestone and milestone.Kind == "Form" then
		text = text .. string.format("  ·  next gun: %s at +%d", milestone.Name, milestone.Level)
	elseif not COMPACT then
		text = text .. "  ·  keys 1-0 switch guns"
	end
	return text
end
local function say(text, seconds)
	sayToken += 1
	local mine = sayToken
	info.Text = text
	sayUntil = os.clock() + seconds
	task.delay(seconds, function()
		if sayToken == mine then info.Text = idleText() end
	end)
end

local lastUnlocked = nil
local function flash(index)
	local slot = slots[index]
	if not slot then return end
	slot.Stroke.Color = GOLD
	slot.Stroke.Thickness = 5
	TweenService:Create(slot.Stroke, TweenInfo.new(1.2), { Thickness = 2 }):Play()
end

local function refresh()
	local level = player:GetAttribute("WeaponLevel") or 0
	local current = player:GetAttribute("WeaponType") or "Pistol"
	local count = Config.GetUnlockedCount(level)
	if lastUnlocked and count > lastUnlocked then
		flash(count)
		say(string.format("🆕 New gun: %s - press %d!", weaponName(ORDER[count]), count % 10), 6)
	end
	lastUnlocked = count

	for index, slot in ipairs(slots) do
		local unlocked = Config.IsWeaponUnlocked(level, slot.Key)
		local isCurrent = slot.Key == current
		slot.Button.Text = unlocked and (ICONS[slot.Key] or "?") or "🔒"
		slot.Button.TextTransparency = unlocked and 0 or 0.35
		slot.Button.BackgroundColor3 = unlocked and Color3.fromRGB(26, 28, 44) or Color3.fromRGB(18, 19, 30)
		if isCurrent and unlocked then
			slot.Stroke.Color = GOLD
			slot.Stroke.Thickness = 2.5
		else
			slot.Stroke.Color = Color3.fromRGB(90, 96, 130)
			slot.Stroke.Thickness = 1
		end
	end

	if os.clock() >= sayUntil then info.Text = idleText() end
end

local function equip(index)
	local slot = slots[index]
	if not slot then return end
	local level = player:GetAttribute("WeaponLevel") or 0
	if Config.IsWeaponUnlocked(level, slot.Key) then
		if player:GetAttribute("WeaponType") ~= slot.Key then
			Remotes.Weapon:FireServer("Equip", slot.Key)
		end
	else
		local need = Config.GetUnlockLevel(slot.Key)
		say(string.format("🔒 %s unlocks at +%d (%d to go) - upgrade your weapon at the Forge or in the Menu (B)", weaponName(slot.Key), need, math.max(0, need - level)), 4)
	end
end
for index, slot in ipairs(slots) do
	slot.Button.Activated:Connect(function() equip(index) end)
end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not holder.Visible or not holder:IsDescendantOf(playerGui) or not (gui.Enabled or attached) then return end
	local index = KEY_TO_SLOT[input.KeyCode]
	if index then equip(index) end
end)

------------------------------------------------------------
-- 자동 배치 (OnlineClient 와 같은 방식): 다른 UI 와 겹치지 않는 빈 자리를 찾는다
------------------------------------------------------------
local spot = nil
local collideSince = nil -- 지금 자리가 다른 UI 와 겹치기 시작한 시각
local function visibleChain(instance)
	local current = instance
	while current and current ~= playerGui do
		if current:IsA("GuiObject") and not current.Visible then return false end
		if current:IsA("ScreenGui") and not current.Enabled then return false end
		current = current.Parent
	end
	return true
end

local seen = {} -- 화면 요소가 처음 보인 시각 (오래 있던 요소 = 고정 UI, 방금 생긴 요소 = 잠깐 뜨는 알림)
local function collectRects(screen)
	local rects = {}
	local present = {}
	local now = os.clock()
	local inset = GuiService:GetGuiInset().Y
	for _, instance in ipairs(playerGui:GetDescendants()) do
		if instance:IsA("GuiObject") and not instance:IsDescendantOf(gui) then
			local size = instance.AbsoluteSize
			if size.X > 4 and size.Y > 4 and size.X < screen.X * 0.7 and size.Y < screen.Y * 0.7 then
				local visibleContent = instance.BackgroundTransparency < 0.9
					or ((instance:IsA("TextLabel") or instance:IsA("TextButton")) and instance.Text ~= "" and instance.TextTransparency < 0.9)
					or ((instance:IsA("ImageLabel") or instance:IsA("ImageButton")) and instance.ImageTransparency < 0.9)
				if visibleContent and visibleChain(instance) then
					local screenGui = instance:FindFirstAncestorOfClass("ScreenGui")
					local offsetY = (screenGui and not screenGui.IgnoreGuiInset) and inset or 0
					present[instance] = true
					seen[instance] = seen[instance] or now
					local young = now - seen[instance] < 6
					-- AbsolutePosition 에 상단 여백이 들어가는지 환경마다 헷갈리므로, 두 경우를 모두 막는다 (조금 넉넉하게 피한다)
					table.insert(rects, { X = instance.AbsolutePosition.X, Y = instance.AbsolutePosition.Y, W = size.X, H = size.Y + offsetY, Young = young })
				end
			end
		end
	end
	for instance in pairs(seen) do
		if not present[instance] then seen[instance] = nil end
	end
	return rects
end

local function hits(rects, x, y, w, h, stableOnly)
	local pad = 4
	for _, r in ipairs(rects) do
		if not (stableOnly and r.Young) and x < r.X + r.W + pad and x + w + pad > r.X and y < r.Y + r.H + pad and y + h + pad > r.Y then return true end
	end
	return false
end

local function findSpot()
	local screen = gui.AbsoluteSize
	local w, h = BAR_W, HOLDER_H
	local rects = collectRects(screen)
	local margin = 10
	local columns = { (screen.X - w) / 2, screen.X - w - margin, margin } -- 가운데 -> 오른쪽 -> 왼쪽
	local bottom = screen.Y - h - margin
	for _, x in ipairs(columns) do
		for y = bottom, screen.Y * 0.45, -8 do -- 아래에서 위로 올라가며 첫 빈 자리
			if not hits(rects, x, y, w, h) then return Vector2.new(x, y) end
		end
	end
	return Vector2.new(columns[1], bottom)
end

-- 스킬 바 위에 붙이기: 화면 좌표를 계산하지 않고 스킬 바(SkillBar)의 자식으로 넣어서 항상 바로 위에 따라다니게 한다 (폰 배치가 바뀌어도 같이 움직인다)
local function attachToSkillBar()
	local bar = nil
	for _, instance in ipairs(playerGui:GetDescendants()) do
		if instance.Name == "SkillBar" and instance:IsA("GuiObject") then bar = instance break end
	end
	if not bar then return false end
	bar.ClipsDescendants = false
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 0, -8)
	holder.Parent = bar
	attached = true
	return true
end

local FIXED = true -- 항상 같은 자리 (계산 없음): 가로 가운데, 캐릭터와 스킬 바 사이에서 살짝 아래쪽
local function place(force)
	if FIXED then
		local zone = player:GetAttribute("Zone")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.new(0.5, 0, 0.77, 0)
		gui.Enabled = (zone == "Lobby" or zone == "Field" or zone == "Dungeon")
			and not player:GetAttribute("ModalOpen") and not player:GetAttribute("ChestOpening")
		return
	end
	if attached then
		local zone = player:GetAttribute("Zone")
		holder.Visible = (zone == "Lobby" or zone == "Field" or zone == "Dungeon")
			and not player:GetAttribute("ModalOpen") and not player:GetAttribute("ChestOpening")
		return
	end
	local zone = player:GetAttribute("Zone")
	local show = (zone == "Lobby" or zone == "Field" or zone == "Dungeon")
		and not player:GetAttribute("ModalOpen") and not player:GetAttribute("ChestOpening")
	gui.Enabled = show
	if not show then return end
	if gui.AbsoluteSize.X < 50 then return end
	-- 자리는 "계속 겹칠 때만" 옮긴다 (알림 카드 같은 잠깐의 UI 때문에 바가 튀지 않게): force 면 겹칠 때 바로, 아니면 5초 넘게 계속 겹칠 때 / 화면 밖이면 바로
	if spot then
		local screen = gui.AbsoluteSize
		local outside = spot.X < 0 or spot.Y < 0 or spot.X + BAR_W > screen.X or spot.Y + HOLDER_H > screen.Y
		local rects = collectRects(screen)
		if not outside and not hits(rects, spot.X, spot.Y, BAR_W, HOLDER_H) then
			collideSince = nil
			return
		end
		-- 오래 있던 고정 UI(스킬 바 등)와 겹치면 바로 옮기고, 방금 뜬 알림과만 겹치면 5초 기다린다
		if not outside and not hits(rects, spot.X, spot.Y, BAR_W, HOLDER_H, true) then
			collideSince = collideSince or os.clock()
			if not force and os.clock() - collideSince < 5 then return end
		end
	end
	collideSince = nil
	spot = findSpot()
	holder.Position = UDim2.fromOffset(spot.X, spot.Y)
end

for _, name in ipairs({ "WeaponLevel", "WeaponType", "Gold" }) do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
for _, name in ipairs({ "Zone", "ModalOpen", "TutorialActive", "ChestOpening" }) do
	player:GetAttributeChangedSignal(name):Connect(function()
		place(true)
		task.delay(1.5, function() place(true) end) -- 화면 UI 가 다시 짜인 뒤에 한 번 더
	end)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() place(true) end)
refresh()
place(true)
task.delay(2, function() place(true) end)
task.spawn(function()
	if FIXED then return end
	for _ = 1, 40 do -- 스킬 바가 만들어질 때까지 (최대 20초) 기다렸다가 붙인다. 못 찾으면 예전 자동 배치를 쓴다
		if attachToSkillBar() then place(true) return end
		task.wait(0.5)
	end
end)
task.spawn(function()
	while true do
		task.wait(1)
		place(false) -- 지금 자리가 다른 UI 와 겹치게 되었으면 다시 찾는다
	end
end)
