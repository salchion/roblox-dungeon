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

-- ---------- 캐릭터 미리보기 모델 캐시 ----------
-- (M-12) 장비 탭은 열려 있는 동안 1초마다 다시 그려진다. 그때마다 캐릭터를 통째로 복제하면(스크립트·장식·파티클까지)
-- 탭이 열려 있는 내내 복제 비용이 반복된다. 그래서
--   1) 캐릭터 복제는 외형(장비 등급/강화/세트·무기)이 실제로 바뀌었을 때만 한다.
--   2) 그 결과는 화면 밖에 "실루엣 모델"로 한 번만 만들어 두고, 다시 그릴 때는 그것을 복제해 뷰포트에 넣는다(파트 몇 개라 아주 싸다).
-- (오프닝/로딩 화면과는 무관하다: 미리보기는 메뉴 > 장비 탭을 그릴 때만 만들어지고, 로딩 중에는 메뉴 자체가 꺼져 있다.)
local ghostTemplate, ghostSig
local function appearanceSig(character)
	local children = character:GetChildren()
	local parts = { #children }
	for _, child in ipairs(children) do parts[#parts + 1] = child.Name end
	for _, slot in ipairs(Config.Gear.Slots) do
		local rarity = player:GetAttribute("Gear_" .. slot.Key .. "_R") or 0
		local level = player:GetAttribute("Gear_" .. slot.Key .. "_L") or 0
		local setKey = player:GetAttribute("Gear_" .. slot.Key .. "_Set") or ""
		if rarity ~= 0 or level ~= 0 or setKey ~= "" then
			parts[#parts + 1] = slot.Key .. rarity .. level .. setKey
		end
	end
	parts[#parts + 1] = tostring(player:GetAttribute("WeaponLevel") or 0) .. tostring(player:GetAttribute("WeaponType") or "")
	return table.concat(parts, ",")
end

local function buildGhostTemplate(character)
	character.Archivable = true
	local clone = character:Clone()
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("BillboardGui") or descendant:IsA("ForceField") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	clone.Parent = nil -- (화면 밖에 둔다: 뷰포트에 넣을 때 복제해서 쓴다)
	return clone
end

local function ghostModel()
	local character = player.Character
	if not character then return nil end
	local sig = appearanceSig(character)
	if not ghostTemplate or ghostSig ~= sig then -- 외형이 바뀐 때만 캐릭터를 복제한다
		if ghostTemplate then ghostTemplate:Destroy() end
		ghostTemplate = buildGhostTemplate(character)
		ghostSig = sig
	end
	return ghostTemplate:Clone()
end

player.CharacterAdded:Connect(function() -- 캐릭터가 새로 생기면(사망/리스폰) 다음에 그릴 때 새로 만든다
	if ghostTemplate then ghostTemplate:Destroy() end
	ghostTemplate, ghostSig = nil, nil
end)

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

-- ⚡ 전투력 미리보기 (서버 InventoryService PowerPreview): "이걸 끼면 전투력" 을 가방 장비 묶음으로 한 번에 받아 둔다
--   preview = { Key = 이 값을 받을 때의 장비 조합, Base = 지금 전투력, Of = { [id 문자열] = 끼면 전투력 } }. 응답 전에는 점수 비율 근사("≈")
local preview = { Key = nil, Base = nil, Of = {} }
local previewAsked, previewAskedAt = nil, 0
local function requestPreview(key, ids)
	if previewAsked == key and os.clock() - previewAskedAt < 2 then return end -- (같은 조합은 2초에 한 번만: 서버 제한 0.5초에 막혀 응답이 없으면 다시 묻는다)
	previewAsked, previewAskedAt = key, os.clock()
	Remotes.Inventory:FireServer("PowerPreview", ids)
end
Remotes.Inventory.OnClientEvent:Connect(function(action, data)
	if action ~= "PowerPreview" or type(data) ~= "table" then return end
	preview = { Key = previewAsked, Base = data.Base, Of = data.Of or {} }
	if menuContent.Parent and menuContent:IsDescendantOf(game) and menuContent:FindFirstAncestorWhichIsA("GuiObject") and menuContent:FindFirstAncestorWhichIsA("GuiObject").Visible then
		refreshMenu() -- (근사 "≈" 를 정확한 숫자로 바꾼다. 조합이 같으니 다시 묻지 않는다)
	end
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

-- ---------- 등급 이하 일괄 분해 (서버 InventoryService.ScrapBelow) ----------
-- 가방 화면은 1초마다 통째로 다시 그려지므로(menuContent 를 비운다) 확인 창은 메뉴 패널에 따로 붙인다.
-- 실수 방지: 등급을 고르고 "무엇이 몇 개 지워지는지"를 본 뒤에야 분해 버튼이 켜진다. 착용 / 세트 / 유니크 장비는 서버가 지킨다.
local bulkRoot, bulkHooked, bulkPick = nil, false, 1
local function scrapBelowCount(rarity)
	local n = 0
	for _, item in ipairs(infoState and infoState.Items or {}) do
		if not item.Equipped and (item.Rarity or 0) <= rarity and not item.Set and not item.Unique then n += 1 end
	end
	return n
end
local function closeBulk()
	if bulkRoot and bulkRoot.Parent then bulkRoot:Destroy() end
	bulkRoot = nil
end
local function openBulk()
	local host = menuContent.Parent
	if not host then return end
	closeBulk()
	bulkRoot = create("Frame", { Name = "BagBulkScrap", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, ZIndex = 60 }, host)
	local scrim = makeButton({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 1, BackgroundColor3 = Color3.fromRGB(6, 7, 12), BackgroundTransparency = 0.42, AutoButtonColor = false, ZIndex = 60 }, bulkRoot, function() closeBulk() end)
	scrim.Text = "" -- (창 밖을 누르면 닫힌다)
	local card = create("Frame", { Size = UDim2.new(0, 420, 0, 200), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = Color3.fromRGB(28, 26, 44), BorderSizePixel = 0, Active = true, ZIndex = 61 }, bulkRoot)
	rounded(card, 16)
	create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 1.5, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	makeLabel({ Size = UDim2.new(1, -32, 0, 26), Position = UDim2.new(0, 16, 0, 12), Text = "Dismantle by rarity", TextSize = 17, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 62 }, card)
	makeLabel({ Size = UDim2.new(1, -32, 0, 18), Position = UDim2.new(0, 16, 0, 40), Text = "Equipped, set, and unique gear is kept.", TextSize = 11, TextColor3 = Color3.fromRGB(170, 176, 204), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 62 }, card)
	local optionButtons, optionCounts = {}, {}
	local confirm
	local function refreshBulk()
		local picked = scrapBelowCount(bulkPick)
		for r, button in ipairs(optionButtons) do
			button.BackgroundColor3 = r == bulkPick and Color3.fromRGB(96, 74, 30) or Color3.fromRGB(36, 38, 58)
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = r == bulkPick and Color3.fromRGB(255, 217, 102) or Color3.fromRGB(90, 96, 130)
				stroke.Thickness = r == bulkPick and 2 or 1
				stroke.Transparency = r == bulkPick and 0 or 0.45
			end
			local count = scrapBelowCount(r)
			optionCounts[r].Text = "x" .. count
			optionCounts[r].TextColor3 = count > 0 and Color3.fromRGB(255, 236, 180) or Color3.fromRGB(130, 134, 158)
		end
		confirm.Text = string.format("Dismantle %d", picked)
		confirm.BackgroundColor3 = picked > 0 and RED or Color3.fromRGB(70, 62, 72)
	end
	for r = 1, math.min(3, #Config.Gear.RarityNames) do
		local button = makeButton({ Size = UDim2.new(0, 120, 0, 48), Position = UDim2.new(0, 16 + (r - 1) * 126, 0, 66), Text = "", BackgroundColor3 = Color3.fromRGB(36, 38, 58), ZIndex = 62 }, card, function()
			bulkPick = r
			refreshBulk()
		end)
		rounded(button, 12)
		create("UIStroke", { Color = Color3.fromRGB(90, 96, 130), Thickness = 1, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
		makeLabel({ Size = UDim2.new(1, -12, 0, 18), Position = UDim2.new(0, 8, 0, 6), TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 63,
			Text = Config.Gear.RarityNames[r] .. " & below", TextColor3 = Config.Gear.RarityColors[r] or Color3.new(1, 1, 1) }, button)
		optionCounts[r] = makeLabel({ Size = UDim2.new(1, -12, 0, 16), Position = UDim2.new(0, 8, 0, 25), TextSize = 11, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, Text = "x0", ZIndex = 63 }, button)
		optionButtons[r] = button
	end
	confirm = makeButton({ Size = UDim2.new(0, 240, 0, 40), Position = UDim2.new(0, 16, 0, 136), Text = "Dismantle", TextSize = 14, Font = Enum.Font.GothamBlack, BackgroundColor3 = RED, ZIndex = 62 }, card, function()
		if scrapBelowCount(bulkPick) == 0 then return end
		Remotes.Inventory:FireServer("ScrapBelow", bulkPick)
		closeBulk()
	end)
	rounded(confirm, 20)
	makeButton({ Size = UDim2.new(0, 148, 0, 40), Position = UDim2.new(0, 264, 0, 136), Text = "Cancel", TextSize = 13, BackgroundColor3 = Color3.fromRGB(54, 58, 82), ZIndex = 62 }, card, function() closeBulk() end)
	refreshBulk()
	if not bulkHooked then -- 메뉴가 닫히면 같이 닫는다 (남아 있으면 다음에 메뉴를 열 때 창이 겹친다)
		bulkHooked = true
		host:GetPropertyChangedSignal("Visible"):Connect(function()
			if not host.Visible then closeBulk() end
		end)
	end
end

-- 빌드 이름: 가장 많이 낀 세트 = 이름(직업), 두 번째 세트 = 꾸밈말
local BUILD_ADJ = { "Galeborn", "Wildwood", "Ancient", "Scorching", "Frostbound", "Molten", "Shadowed", "Abyssal" }
local BUILD_NOUN = { "Guardian", "Hunter", "Warrior", "Marksman", "Mage", "Destroyer", "Rogue", "Lord" }
local function commas(n)
	local s = tostring(math.floor(n or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function itemStatText(item)
	local parts = { Config.FormatGearStat(item.Slot, Config.GetGearStat(item.Slot, item.Rarity, item.Level)) }
	for _, affix in ipairs(item.Affixes or {}) do table.insert(parts, Config.FormatAffix(affix.Stat, affix.Value)) end
	return parts
end

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
	local previewKey, previewIds = nil, {}
	do -- 조합 키 = 장착 id + 가방 id (바뀌면 다시 묻는다)
		local parts = {}
		for _, item in ipairs(state.Items) do table.insert(parts, (item.Equipped and "E" or "") .. item.Id .. ":" .. item.Level) end
		table.sort(parts)
		-- 장비가 그대로여도 전투력 입력(세트 효과 단계 / 레벨 / 스탯 / 훈련 / 펫 / 무기)이 바뀌면 다시 묻는다 (낡은 값을 "정확한 값"으로 보여 주지 않게)
		for _, name in ipairs({ "Power", "Level", "CritPoints", "SpeedPoints", "WeaponLevel", "GearHealth", "GearCrit", "GearDamage", "TrainHealth", "TrainCrit", "TrainDamage", "PetDamage", "AugAtkLv", "AugDefLv" }) do
			table.insert(parts, tostring(player:GetAttribute(name) or 0))
		end
		previewKey = table.concat(parts, ",")
		local sorted = table.clone(bag)
		table.sort(sorted, function(a, b) return (a.Score or 0) > (b.Score or 0) end)
		for i = 1, math.min(50, #sorted) do previewIds[i] = sorted[i].Id end
		if preview.Key ~= previewKey and #previewIds > 0 then requestPreview(previewKey, previewIds) end
	end
	local function powerIf(item) -- 끼면 전투력, 정확한 값이면 true 도 함께 (아니면 점수 비율 근사)
		local now = player:GetAttribute("Power") or 0
		-- "현재" 는 언제나 지금 ⚡ 전투력. 서버 Base 와 다르면(입력이 막 바뀌어 다시 묻는 중) 정확한 값으로 치지 않는다
		if preview.Key == previewKey and preview.Of[tostring(item.Id)] and preview.Base == now then return preview.Of[tostring(item.Id)], now, true end
		local cur = equipped[item.Slot]
		local function value(map)
			local total, counts = 0, {}
			for _, it in pairs(map) do
				total += it.Score or 0
				if it.Set then counts[it.Set] = (counts[it.Set] or 0) + 1 end
			end
			for _, n in pairs(counts) do total += (n >= 2 and 150 or 0) + (n >= 3 and 220 or 0) + 60 * math.min(3, n) end
			return total
		end
		local trial = table.clone(equipped)
		trial[item.Slot] = item
		local before = math.max(1, value(equipped))
		return math.floor(now * value(trial) / before + 0.5), now, false
	end
	local selectedId = menuContent:GetAttribute("SelectedItem")
	local selected = selectedId and byId[selectedId]
	if not selected then
		selected = equipped.Armor or equipped.Helmet or equipped.Gloves or equipped.Boots or equipped.Ring or equipped.Necklace or bag[1]
	end

	local function rarityOutline(frame, rarity, thick)
		local color = Config.Gear.RarityColors[rarity]
		-- (다크 포지: 움직이지 않는 테두리. 일반~에픽 2px / 전설 · 신화 3px. 예전의 깜빡임 / 무지개 회전은 칸마다 Tween 이 붙어 뺐다)
		local stroke = create("UIStroke", { Color = color, Thickness = thick or (rarity >= 4 and 3 or 2), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
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
		local z = math.max(6, (tile.ZIndex or 1) + 5) -- (칸보다 위에: 장착 칸은 ZIndex 9 + 메달 10~13 이라 예전 고정값 6 이면 배지가 칸 뒤로 숨어 초록 귀퉁이만 보였다)
		local badge = create("Frame", { Size = UDim2.new(0, 20, 0, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -3, 0, 3), BackgroundColor3 = def.Color, BorderSizePixel = 0, ZIndex = z, Active = false }, tile)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
		local stroke = create("UIStroke", { Color = active and Color3.new(1, 1, 1) or Color3.fromRGB(22, 18, 44), Thickness = active and 2 or 1.8, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)
		makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = def.Icon or "★", TextSize = 12, TextWrapped = false, AutoLocalize = false, ZIndex = z + 1 }, badge)
	end

	local SLOT_ICONS = { Armor = "🛡", Gloves = "🧤", Boots = "👢", Weapon = "🔫", Helmet = "⛑", Ring = "💍", Necklace = "📿" }
	-- 가방 묶기 기준: 부위 / 등급 / 강화 / 세트 / 유니크 / "+1" 옵션이 같으면 같은 칸 (랜덤 옵션 값은 묶음 안에서 다를 수 있다)
	local function gearGroupKey(it)
		return table.concat({ tostring(it.Slot), tostring(it.Rarity), tostring(it.Level), tostring(it.Set), tostring(it.Unique), tostring(it.AugBoost) }, "|")
	end

	-- ===== 한 화면 장비 셋팅 (스크롤 없이) =====
	--   왼쪽: 지금 낀 칸 + 내 세트(모으는 중: 빠진 부위를 누르면 가방이 그 부위 / 세트로 걸러진다)
	--   가운데: 가방 (부위 / 세트 칩으로 거르기 + 정렬, 안에서만 스크롤) + 합성
	--   오른쪽: 고른 장비의 상세 / 비교 / 강화 / 장착
	-- (예전: 장비 칸 -> 바꿔 끼기 줄 -> 가방이 위아래로 길게 이어져서 계속 스크롤해야 했다)
	local MAIN_H, LEFT_W, RIGHT_W = 424, 208, 294 -- (다크 포지 시안 A: 208 + 308 + 294 + 간격 16 = 826. 가방 타일 52px 5열)
	-- 다음에 할 일 한 줄: 무엇을 하면 좋은지 바로 알려 주고 버튼 하나로 한다 (화면이 복잡해서 뭘 해야 할지 몰랐다)
	do
		local tip, tipItem, tipColor -- (긴 문장 대신 짧은 배지 + [끼기] 하나)
		local function slotName(key) return Config.GetGearSlot(key) and Config.GetGearSlot(key).Name or key end
		-- (11-23) 배지도 상세 창 · [⚡ 최강 장착] 과 같은 기준 하나: 점수 비교가 아니라 그 장비를 끼면 실제로 오르는 ⚡ 전투력(서버 PowerPreview).
		--   정확한 미리보기가 아직 없으면(로딩 중 · 상위 50 밖) 점수로 어림해 "더 강하다" 고 말하지 않는다. 그때는 서버가 계산한 state.Better 만 말한다.
		local bestUp, bestGain = nil, 0
		local setPick, setTier = nil, 0
		for _, item in ipairs(bag) do
			local current = equipped[item.Slot]
			if not current then
				if not tip then
					tip = string.format("Empty %s slot", slotName(item.Slot))
					tipItem, tipColor = item, Color3.fromRGB(255, 196, 90)
				end
			else
				local after, base, exact = powerIf(item)
				local gain = after - base
				if exact and gain > bestGain then bestUp, bestGain = item, gain end
				if item.Set and Config.Sets[item.Set] and current.Set ~= item.Set and gain >= 0 then -- (세트 안내도 ⚡ 가 떨어지지 않을 때만: [⚡ 최강 장착] 과 모순 없이)
					local afterPieces = (setCounts[item.Set] or 0) + 1
					local tierNow = (afterPieces >= 3 and 3) or (afterPieces >= 2 and 2) or 0
					if tierNow > 0 and tierNow > setTier then setPick, setTier = item, tierNow end
				end
			end
		end
		if not tip and bestUp then
			tip = string.format("▲ Stronger %s", slotName(bestUp.Slot))
			tipItem, tipColor = bestUp, Color3.fromRGB(120, 255, 140)
		elseif not tip and setPick then
			local def = Config.Sets[setPick.Set]
			tip = string.format("🧩 %s %d/3", def.Name, setTier)
			tipItem, tipColor = setPick, def.Color
		elseif not tip then -- 한 부위 교체로는 안 오르지만 서버가 더 좋은 조합을 찾았을 때: [⚡ 최강 장착] 이 초록이면 이 배지도 같이 말한다
			tip = state.Better and "🌟 Better combo" or "✔ Best gear"
			tipColor = state.Better and Color3.fromRGB(255, 210, 100) or nil
		end
		-- 지금 빌드 띠: 세트 조합 이름 + 켜진 세트 + 전투력 + 추천 한 가지 (버튼 하나)
		local ranked = {}
		for key, n in pairs(setCounts) do if Config.Sets[key] and n >= 1 then table.insert(ranked, { key, n }) end end
		table.sort(ranked, function(a, b)
			if a[2] ~= b[2] then return a[2] > b[2] end
			return (Config.Sets[a[1]].Zone or 0) > (Config.Sets[b[1]].Zone or 0)
		end)
		local first, second = ranked[1] and Config.Sets[ranked[1][1]], ranked[2] and Config.Sets[ranked[2][1]]
		local buildName, buildIcon, buildColor = "<font>Wanderer</font>", "🧭", Color3.fromRGB(150, 156, 190)
		if first and first.Zone then
			local adj = BUILD_ADJ[(second and second.Zone) or first.Zone]
			buildName = string.format("<font>%s</font> <font>%s</font>", adj, BUILD_NOUN[first.Zone])
			buildIcon, buildColor = first.Icon or "★", first.Color
		end
		local setsLine = {}
		for _, r in ipairs(ranked) do
			local def = Config.Sets[r[1]]
			table.insert(setsLine, string.format("%s <font color='#%s'><b>%d/3</b></font>", def.Icon or "★", r[2] >= 2 and "78ff8c" or "aab0cc", math.min(3, r[2])))
		end
		-- 한 줄로 합친 위 띠: 빌드 이름 + 세트 + 추천 한 가지 | ⚡ 전투력 · [⚡ 최강 장착] · [🧹 정리 ▼]
		--   (예전: "장착 방식" 줄(칩 3개 + 분해 버튼 3개)과 이 띠가 두 줄로 따로 있어 글자가 작고 눈이 갈 곳이 많았다)
		-- 다크 포지 띠 (높이 54): 빌드 이름 + 세트 | [배지] [끼기] | ⚡ 전투력 상자 · [⚡ 최강 장착] · [🧹 정리 ▼]
		local guide = newRow(54, Color3.fromRGB(22, 24, 38))
		create("UIGradient", { Rotation = 0, Color = ColorSequence.new(buildColor:Lerp(Color3.fromRGB(22, 24, 38), 0.55), Color3.fromRGB(22, 24, 38)) }, guide)
		create("UIStroke", { Color = Color3.fromRGB(225, 196, 118), Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, guide)
		local disc = create("Frame", { Size = UDim2.new(0, 38, 0, 38), Position = UDim2.new(0, 10, 0.5, -19), BackgroundColor3 = buildColor:Lerp(Color3.fromRGB(16, 18, 30), 0.55), BorderSizePixel = 0 }, guide)
		create("UICorner", { CornerRadius = UDim.new(1, 0) }, disc)
		create("UIStroke", { Color = buildColor, Thickness = 2 }, disc)
		makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = buildIcon, TextSize = 20 }, disc)
		makeLabel({ Size = UDim2.new(0, 200, 0, 22), Position = UDim2.new(0, 56, 0, 6), RichText = true, Text = buildName, TextSize = 17, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left }, guide)
		makeLabel({ Size = UDim2.new(0, 200, 0, 18), Position = UDim2.new(0, 56, 0, 29), RichText = true, Text = #setsLine > 0 and table.concat(setsLine, " · ") or "", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(205, 225, 240) }, guide)
		do -- 배지 + [끼기]
			local holder = create("Frame", { Size = UDim2.new(0, 220, 0, 30), Position = UDim2.new(0, 262, 0.5, -15), BackgroundTransparency = 1 }, guide)
			create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, holder)
			local color = tipColor or Color3.fromRGB(150, 210, 160)
			local badge = makeLabel({ Size = UDim2.new(0, 0, 0, 26), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, RichText = true, Text = tip or "✔ Best gear", TextSize = 13, Font = Enum.Font.GothamBlack,
				TextColor3 = color, BackgroundTransparency = 0, BackgroundColor3 = color:Lerp(Color3.fromRGB(16, 18, 30), 0.8) }, holder)
			rounded(badge, 13)
			create("UIStroke", { Color = color, Thickness = 1.5, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)
			create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, badge)
			if tipItem then
				local go = makeButton({ Size = UDim2.new(0, 60, 0, 26), LayoutOrder = 2, Text = "Equip it", TextSize = 13, Font = Enum.Font.GothamBlack, BackgroundColor3 = GREEN }, holder, function()
					Remotes.Inventory:FireServer("Equip", tipItem.Id)
				end)
				rounded(go, 13)
			end
		end
		do -- ⚡ 전투력 상자 (금테)
			local box = create("Frame", { Size = UDim2.new(0, 150, 0, 40), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -216, 0.5, 0), BackgroundColor3 = Color3.fromRGB(34, 30, 22), BorderSizePixel = 0 }, guide)
			rounded(box, 10)
			create("UIStroke", { Color = Color3.fromRGB(225, 180, 80), Thickness = 1.5 }, box)
			makeLabel({ Size = UDim2.new(1, -54, 1, 0), Position = UDim2.new(0, 8, 0, 0), Text = "⚡ " .. commas(player:GetAttribute("Power") or 0), TextSize = 20, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 217, 102) }, box)
			makeLabel({ Size = UDim2.new(0, 46, 1, 0), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Text = "Power", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(210, 190, 150) }, box)
		end
		local drop = menuContent:GetAttribute("GearDrop") -- (펼칠 수 있는 줄은 [🧹 정리] 하나뿐이다)
		local function dropButton(key, text, x, width)
			local open = drop == key
			local b = makeButton({ Size = UDim2.new(0, width, 0, 34), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0), RichText = true, TextSize = 13, Font = Enum.Font.GothamBlack,
				Text = text .. (open and " ▲" or " ▼"), BackgroundColor3 = open and Color3.fromRGB(70, 64, 110) or Color3.fromRGB(44, 46, 68) }, guide, function()
				menuContent:SetAttribute("GearDrop", open and nil or key)
				refreshMenu()
			end)
			rounded(b, 12)
		end
		do -- [⚡ 최강 장착] 하나: 실제 ⚡ 전투력이 가장 높은 조합 (세트 효과 단계 포함). 끼면 ⚡ 가 오르는 장비가 가방에 있으면("!") 초록으로 빛난다
			local better = state.Better == true
			local b = makeButton({ Size = UDim2.new(0, 110, 0, 34), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -98, 0.5, 0), Text = "⚡ Best gear", TextSize = 13, Font = Enum.Font.GothamBlack,
				BackgroundColor3 = better and GREEN or Color3.fromRGB(56, 110, 220) }, guide, function()
				Remotes.Inventory:FireServer("AutoEquip")
			end)
			rounded(b, 12)
			if better then
				local glow = create("UIStroke", { Color = Color3.fromRGB(200, 255, 215), Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
				TweenService:Create(glow, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.7 }):Play()
			end
		end
		dropButton("Clean", "🧹 Clean", -8, 84)
	end
	-- 정리 줄: 위 띠의 [🧹 정리 ▼] 를 누르면 그 아래에 자동 분해 규칙 · 등급 이하 일괄 분해 · 스마트 정리가 펼쳐진다
	-- (예전 "장착 방식" 칩 줄은 11-23 에 없앴다: 장착은 [⚡ 최강 장착] 하나, 세트 맞추기는 왼쪽 내 세트 카드 [장착])
	do
		local drop = menuContent:GetAttribute("GearDrop") -- ([🧹 정리 ▼] 를 누르면 그 아래에 이 줄이 펼쳐진다)
		local setRow = drop and newRow(44, Color3.fromRGB(24, 26, 40)) or create("Frame", { Visible = false })
		makeLabel({ Size = UDim2.new(0, 84, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = "🧹 Clean", TextSize = 13, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(225, 196, 118), TextXAlignment = Enum.TextXAlignment.Left }, setRow)
		-- 오른쪽 세 칸: 자동 분해 규칙 / 등급 이하 일괄 분해 / 스마트 정리
		local scrapButton = makeButton({ Size = UDim2.new(0, 170, 0, 32), Position = UDim2.new(0, 96, 0.5, -16), RichText = true, TextWrapped = true, Text = "♻ <font size='11' color='#cfe0ff'>Auto-salvage</font>\n" .. Config.Inventory.AutoScrapNames[state.AutoScrap], TextSize = 11, BackgroundColor3 = Color3.fromRGB(70, 110, 220) }, setRow, function() -- (자동 분해 규칙이 버튼에 바로 보인다. 누르면 다음 규칙)
			Remotes.Inventory:FireServer("AutoScrap", (state.AutoScrap + 1) % 5)
		end)
		rounded(scrapButton, 14)
		local belowButton = makeButton({ Size = UDim2.new(0, 130, 0, 32), Position = UDim2.new(0, 276, 0.5, -16), Text = "♻ Rarity ▼", TextSize = 12, BackgroundColor3 = Color3.fromRGB(86, 74, 160) }, setRow, function() -- (누르면 등급 선택 + 확인 창: 실수로 지우지 않게 한 번 더 본다)
			openBulk()
		end)
		rounded(belowButton, 14)
		local cleanButton = makeButton({ Size = UDim2.new(0, 130, 0, 32), Position = UDim2.new(0, 416, 0.5, -16), Text = "🧹 Smart Clean", TextSize = 12, BackgroundColor3 = Color3.fromRGB(176, 76, 84) }, setRow, function()
			Remotes.Inventory:FireServer("SmartClean")
		end)
		rounded(cleanButton, 14)
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
	local sortDir = menuContent:GetAttribute("BagSortDir") or "Desc" -- (▼ 높은 것부터 / ▲ 낮은 것부터)
	local onlyUnique = menuContent:GetAttribute("BagUnique") == true
	local onlyAug = menuContent:GetAttribute("BagAug") == true
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
		for index, spec in ipairs({ { 88, 0.88 }, { 64, 0.78 } }) do
			local halo = create("Frame", { Size = UDim2.new(0, spec[1], 0, spec[1]), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, LEFT_W / 2, 0, 118), BackgroundColor3 = glow, BackgroundTransparency = spec[2], BorderSizePixel = 0, ZIndex = 1 + index }, left)
			create("UICorner", { CornerRadius = UDim.new(1, 0) }, halo)
		end
		local viewport = create("ViewportFrame", {
			Size = UDim2.new(0, 84, 0, 132), Position = UDim2.new(0, LEFT_W / 2 - 42, 0, 50), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4,
			Ambient = Color3.fromRGB(190, 190, 200), LightColor = Color3.new(1, 1, 1),
		}, left)
		local cam = create("Camera", { FieldOfView = 38 }, viewport)
		viewport.CurrentCamera = cam
		local model = ghostModel() -- (M-12) 캐시된 실루엣을 복제해서 넣는다 (캐릭터 통복제는 외형이 바뀔 때만)
		if model then
			model.Parent = viewport
			local pivot = model:GetPivot()
			local spin = settings.InvSpin or 0
			local connection
			connection = RunService.RenderStepped:Connect(function(dt)
				if not viewport:IsDescendantOf(game) then
					connection:Disconnect()
					return
				end
				spin += dt * 0.9
				settings.InvSpin = spin
				model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, spin, 0))
				cam.CFrame = CFrame.lookAt(pivot.Position + Vector3.new(0, 1.2, 12.5), pivot.Position + Vector3.new(0, 0.4, 0))
			end)
		end
		makeLabel({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 4), Text = "⚡ " .. commas(player:GetAttribute("Power") or 0), TextSize = 14, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 225, 110), ZIndex = 5 }, left)
	end
	local function slotBox(slotKey, x, y)
		local item = equipped[slotKey]
		local rarity = item and item.Rarity or 0
		local box = makeButton({
			Size = UDim2.new(0, 52, 0, 54), Position = UDim2.new(0, x, 0, y), Text = "",
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
			makeLabel({ Size = UDim2.new(1, -6, 0, 14), Position = UDim2.new(0, 3, 1, -17), Text = Config.WeaponTypes[tier.Class].Name, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = tier.Color, Font = Enum.Font.GothamBold, ZIndex = 10 }, box)
		elseif item then
			if filterSlot ~= slotKey then rarityOutline(box, rarity, rarity >= 4 and 2 or 1.5) end
			iconDisc(Config.Gear.RarityColors[rarity], SLOT_ICONS[slotKey], rarity)
			local canUp = item.Level < Config.Gear.MaxLevel and (player:GetAttribute("Gold") or 0) >= Config.GetGearCost(item.Slot, item.Rarity, item.Level)
			makeLabel({ Size = UDim2.new(1, -6, 0, 14), Position = UDim2.new(0, 3, 1, -17), RichText = true, TextSize = 11, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 220, 120), ZIndex = 10,
				Text = canUp and string.format("+%d <font color='#78ff8c'>▲</font>", item.Level) or (item.Level > 0 and string.format("+%d", item.Level) or "") }, box) -- (+0 은 강화할 수 있을 때만 적는다)
			if item.Set then setDecor(box, item.Set, setCounts[item.Set]) end
			if item.Unique then
				makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 3, 0, 3), Text = "★", TextSize = 11, TextColor3 = Color3.fromRGB(255, 184, 77), ZIndex = 11 }, box)
			end
		else
			create("UIStroke", { Color = Color3.fromRGB(70, 74, 96), Thickness = 1, Transparency = 0.3 }, box)
			iconDisc(Color3.fromRGB(110, 114, 140), SLOT_ICONS[slotKey])
			makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -17), Text = "Empty", TextSize = 11, TextColor3 = Color3.fromRGB(120, 120, 140), ZIndex = 10 }, box)
		end
		return box
	end
	slotBox("Helmet", 6, 28) -- (칸 52px 두 줄: 6~58 / 150~202, 가운데 92px 에 미리보기 84px)
	slotBox("Armor", 6, 86)
	slotBox("Gloves", 6, 144)
	slotBox("Necklace", LEFT_W - 58, 28)
	slotBox("Ring", LEFT_W - 58, 86)
	slotBox("Boots", LEFT_W - 58, 144)
	slotBox("Weapon", LEFT_W - 58, 202)
	do -- 펫 칸 (왼쪽 아래)
		local petLevel = player:GetAttribute("PetLevel") or 0
		local look = Config.Pet.Looks[player:GetAttribute("PetLook") or "Orb"] or Config.Pet.Looks.Orb
		local box = makeButton({ Size = UDim2.new(0, 52, 0, 54), Position = UDim2.new(0, 6, 0, 202), Text = "", BackgroundColor3 = petLevel > 0 and Color3.fromRGB(46, 48, 68) or Color3.fromRGB(34, 34, 48), AutoButtonColor = true, ZIndex = 9 }, left, function()
			player:SetAttribute("OpenPet", os.clock())
		end)
		rounded(box, 12)
		create("UIStroke", { Color = petLevel > 0 and Color3.fromRGB(255, 200, 90) or Color3.fromRGB(70, 70, 90), Thickness = petLevel > 0 and 2 or 1.5 }, box)
		makeLabel({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 2), Text = petLevel > 0 and look.Icon or "🐾", TextSize = 18, TextTransparency = petLevel > 0 and 0 or 0.6, ZIndex = 10 }, box)
		makeLabel({ Size = UDim2.new(1, -4, 0, 22), Position = UDim2.new(0, 2, 0, 30), Text = petLevel > 0 and string.format("Lv.%d", petLevel) or "Unlock\nPet (P)", TextSize = 11, TextWrapped = true, Font = Enum.Font.GothamBlack,
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
			makeLabel({ Size = UDim2.new(1, -8, 0, 54), Text = "Set gear drops in the field (each zone has its own set). Wear 2–3 pieces of one set for bonuses — and its set effect turns on.", TextSize = 12, TextWrapped = true, TextColor3 = Color3.fromRGB(140, 144, 170) }, list)
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
			do -- [끼기]: 이 세트로 맞추기 (예전 "장착 방식 > 세트 장비" 를 여기로 옮겼다)
				local wear = makeButton({ Size = UDim2.new(0, 40, 0, 18), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, def.Zone and -28 or 0, 0, 0), Text = "Equip", TextSize = 11, BackgroundColor3 = Color3.fromRGB(56, 110, 220), ZIndex = 4 }, setButton, function()
					Remotes.Inventory:FireServer("EquipSet", key)
				end)
				rounded(wear, 9)
			end
			if def.Zone then -- ✨: 세트 효과 창에서 이 효과 보기 (메뉴를 닫고 연다)
				local jump = makeButton({ Size = UDim2.new(0, 24, 0, 18), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Text = "✨", TextSize = 11, BackgroundColor3 = Color3.fromRGB(70, 60, 110), ZIndex = 4 }, setButton, function()
					player:SetAttribute("OpenMenuTab", "Character:Gear|" .. tostring(os.clock())) -- (같은 탭 신호 = 메뉴 닫기)
					player:SetAttribute("AugFocusZone", def.Zone)
				end)
				rounded(jump, 9)
			end
			makeLabel({ Size = UDim2.new(1, -72, 1, 0), RichText = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBlack, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = string.format("%s %s  %s%s", def.Icon or "★", def.Name, table.concat(pips, ""), worn >= 2 and "  <font color='#78ff8c' size='11'>ON</font>" or "") }, setButton)
			for _, tier in ipairs({ 2, 3 }) do
				local parts = {}
				for _, b in ipairs(def.Bonuses[tier] or {}) do table.insert(parts, "<font>" .. Config.FormatBonus(b.Stat, b.Value) .. "</font>") end
				makeLabel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, RichText = true, TextWrapped = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 + tier,
					TextColor3 = worn >= tier and Color3.fromRGB(200, 240, 210) or Color3.fromRGB(130, 134, 160),
					Text = string.format("%s %d · %s", worn >= tier and "✔" or "○", tier, table.concat(parts, " · ")) }, card)
			end
			if aug then
				makeLabel({ Size = UDim2.new(1, 0, 0, 14), RichText = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 5, TextColor3 = effectOn and Color3.fromRGB(150, 230, 255) or Color3.fromRGB(130, 134, 160),
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
			if worn < 3 and def.Zone then -- 빠진 부위가 어디서 나오는지
				makeLabel({ Size = UDim2.new(1, 0, 0, 14), RichText = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 7, TextColor3 = Color3.fromRGB(154, 215, 255),
					Text = string.format("📍 <font>Zone %d</font> · <font>drops from field monsters and bosses</font>", def.Zone) }, card)
			end
		end
	end

	-- ---------- 가운데: 가방 ----------
	do
		local filtered = {}
		for _, item in ipairs(bag) do
			if (not filterSlot or item.Slot == filterSlot) and (not filterSet or item.Set == filterSet)
				and (not onlyUnique or item.Unique == true) and (not onlyAug or (item.AugBoost or 0) >= 1) then
				local current = equipped[item.Slot]
				local setGain = 0
				if item.Set and Config.Sets[item.Set] and not (current and current.Set == item.Set) then setGain = (setCounts[item.Set] or 0) + 1 end
				table.insert(filtered, { Item = item, SetGain = setGain, Diff = current and (item.Score - current.Score) or item.Score })
			end
		end
		local function sortBefore(x, y) -- (x 가 앞에 오는가)
			if sortMode == "Rarity" and x.Item.Rarity ~= y.Item.Rarity then return x.Item.Rarity > y.Item.Rarity end
			if sortMode == "Set" then
				local xs, ys = x.SetGain >= 2 and 1 or 0, y.SetGain >= 2 and 1 or 0
				if xs ~= ys then return xs > ys end
			end
			if x.Item.Score ~= y.Item.Score then return x.Item.Score > y.Item.Score end
			return (x.Item.Id or 0) < (y.Item.Id or 0) -- (같은 점수는 항상 같은 순서: 뒤집어도 목록이 흔들리지 않게)
		end
		local ascending = sortDir == "Asc"
		table.sort(filtered, function(x, y)
			if ascending then return sortBefore(y, x) end
			return sortBefore(x, y)
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
		-- 정렬 / 필터는 [⇅ 정렬 ▼] 하나로: 누르면 둘째 줄(세트 칩) 자리에 정렬 · 방향 · 유니크만 · 세트 +1만이 펼쳐진다 (칩이 넘쳐 오른쪽이 잘렸다)
		local sortOpen = menuContent:GetAttribute("BagSortOpen") == true
		local filtering = onlyUnique or onlyAug
		chip(slotRow, 99, "⇅ Sort" .. (filtering and " ●" or "") .. (sortOpen and " ▲" or " ▼"), sortOpen, function()
			menuContent:SetAttribute("BagSortOpen", not sortOpen)
			refreshMenu()
		end)
		local setRow = chipRow(56)
		if not sortOpen then
			chip(setRow, 0, "All sets", filterSet == nil, function() setFilter(filterSlot, nil) end)
			for i, key in ipairs(Config.Sets.ZoneKeys) do
				local def = Config.Sets[key]
				local has = false
				for _, item in ipairs(bag) do if item.Set == key then has = true break end end
				if has then chip(setRow, i, def.Icon or "★", filterSet == key, function() setFilter(filterSlot, filterSet == key and nil or key) end, def.Color) end
			end
		else
			local SORTS = { Score = "Sort: Score", Rarity = "Sort: Rarity", Set = "Sort: Set first" }
			for i, key in ipairs({ "Score", "Set", "Rarity" }) do
				chip(setRow, i, SORTS[key], sortMode == key, function()
					menuContent:SetAttribute("BagSort", key)
					refreshMenu()
				end)
			end
			-- 정렬 방향 (누를 때마다 ▲ 약한 것부터 / ▼ 강한 것부터)
			chip(setRow, 10, ascending and "▲ Low first" or "▼ High first", false, function()
				menuContent:SetAttribute("BagSortDir", ascending and "Desc" or "Asc")
				refreshMenu()
			end)
			-- 필터 칩: 유니크만 / 세트 효과 +1만 (둘 다 켜면 두 조건 모두). 다시 누르면 풀린다.
			chip(setRow, 20, "★ Uniques only", onlyUnique, function()
				menuContent:SetAttribute("BagUnique", not onlyUnique)
				refreshMenu()
			end, Color3.fromRGB(255, 184, 77))
			chip(setRow, 21, "🚀 Set +1 only", onlyAug, function()
				menuContent:SetAttribute("BagAug", not onlyAug)
				refreshMenu()
			end, Color3.fromRGB(255, 140, 90))
		end
		if (filterSlot or filterSet) and not (filterSlot and not filterSet and menuContent:GetAttribute("FuseOpen") ~= true) then
			local caption = {}
			if filterSlot then table.insert(caption, (SLOT_ICONS[filterSlot] or "") .. " " .. (Config.GetGearSlot(filterSlot) and Config.GetGearSlot(filterSlot).Name or filterSlot)) end
			if filterSet and Config.Sets[filterSet] then table.insert(caption, (Config.Sets[filterSet].Icon or "") .. " " .. Config.Sets[filterSet].Name) end
			makeLabel({ Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 10, 0, 84), RichText = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(154, 215, 255),
				Text = string.format("%s · %d", table.concat(caption, " · "), #filtered) }, middle)
		end
		-- 칸을 고르면: 가방 자리에 "그 칸 바꿔 끼기" 목록 (실제 ⚡ 전투력 변화 큰 순 · 추천 · 세트 변화 · 끼기 버튼 · 마우스 올리면 비교)
		local swapMode = filterSlot ~= nil and not filterSet and menuContent:GetAttribute("FuseOpen") ~= true
		if swapMode then
			local current = equipped[filterSlot]
			local rows = {}
			for _, entry in ipairs(filtered) do -- (11-23) 점수 비율이 아니라 상세 창 · [⚡ 최강 장착] 과 같은 powerIf(서버 PowerPreview): 끼면 실제 ⚡ 가 얼마나 오르는가
				local item = entry.Item
				local after, base, exact = powerIf(item)
				local pieces = item.Set and ((setCounts[item.Set] or 0) + ((current and current.Set == item.Set) and 0 or 1)) or 0
				table.insert(rows, { Item = item, Gain = after - base, Base = base, AfterPower = after, Exact = exact, After = pieces })
			end
			table.sort(rows, function(a, b)
				if a.Gain ~= b.Gain then return a.Gain > b.Gain end
				return (a.Item.Score or 0) > (b.Item.Score or 0) -- (변화량이 같으면 점수 높은 것부터: 순서가 흔들리지 않게)
			end)
			local head = makeLabel({ Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 10, 0, 84), RichText = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(154, 215, 255),
				Text = "Hover to compare · ⚡ = power change (set bonus + set effect counted)" }, middle)
			local list = create("ScrollingFrame", { Size = UDim2.new(1, -8, 1, -156), Position = UDim2.new(0, 4, 0, 102), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
				CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, middle)
			create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
			create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8) }, list)
			if #rows == 0 then
				makeLabel({ Size = UDim2.new(1, 0, 0, 40), Text = "No other gear for this slot yet", TextSize = 12, TextColor3 = Color3.fromRGB(130, 130, 150) }, list)
			end
			local nowText = current and table.concat(itemStatText(current), " · ") or "—"
			for order, r in ipairs(rows) do
				local item, best = r.Item, order == 1 and r.Gain > 0
				local good = r.Gain >= 0
				local row = create("Frame", { Size = UDim2.new(1, 0, 0, 62), LayoutOrder = order, BackgroundColor3 = best and Color3.fromRGB(30, 58, 38) or Color3.fromRGB(34, 36, 56), BorderSizePixel = 0, Active = true }, list)
				rounded(row, 12)
				local stroke = create("UIStroke", { Color = best and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(58, 60, 86), Thickness = best and 1.6 or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row)
				local tile = create("Frame", { Size = UDim2.new(0, 50, 0, 50), Position = UDim2.new(0, 6, 0, 6), BackgroundColor3 = Config.Gear.RarityColors[item.Rarity]:Lerp(Color3.fromRGB(20, 22, 36), 0.78), BorderSizePixel = 0 }, row)
				rounded(tile, 10)
				create("UIStroke", { Color = Config.Gear.RarityColors[item.Rarity], Thickness = 1.5 }, tile)
				makeLabel({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 2), Text = SLOT_ICONS[item.Slot] or "?", TextSize = 18 }, tile)
				if item.Level > 0 then makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -16), Text = string.format("+%d", item.Level), TextSize = 12, Font = Enum.Font.GothamBlack }, tile) end
				if item.Set and Config.Sets[item.Set] then
					local dot = create("Frame", { Size = UDim2.new(0, 9, 0, 9), Position = UDim2.new(1, -12, 0, 3), BackgroundColor3 = Config.Sets[item.Set].Color, BorderSizePixel = 0 }, tile)
					create("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
				end
				local lines = { string.format("<font size='15' color='#%s'><b>⚡ %s%s%s</b></font>%s", good and "78ff8c" or "ff8c8c", r.Exact and "" or "≈ ", r.Gain >= 0 and "+" or "-", commas(math.abs(r.Gain)), best and "  <font size='11' color='#78ff8c'><b>★ Best pick</b></font>" or "") }
				if item.Set and Config.Sets[item.Set] and not (current and current.Set == item.Set) then
					local def, after = Config.Sets[item.Set], math.min(3, r.After or 1)
					table.insert(lines, string.format("<font color='#cfeeff'>%s %d→%d/3</font>%s", def.Icon or "★", after - 1, after, after >= 2 and " <font color='#78ff8c'>· Set ON!</font>" or ""))
				elseif current and current.Set and current.Set ~= item.Set and Config.Sets[current.Set] then
					local def, n = Config.Sets[current.Set], math.min(3, setCounts[current.Set] or 1)
					table.insert(lines, string.format("<font color='#ff9a8a'>%s %d→%d/3</font>", def.Icon or "★", n, n - 1))
				end
				local statText = table.concat(itemStatText(item), " · ")
				table.insert(lines, "<font color='#aab0cc' size='11'>" .. statText .. "</font>")
				makeLabel({ Size = UDim2.new(1, -150, 1, -4), Position = UDim2.new(0, 64, 0, 2), RichText = true, TextWrapped = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
					Text = table.concat(lines, "\n") }, row)
				local equipBtn = makeButton({ Size = UDim2.new(0, 70, 0, 34), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Text = "Equip", TextSize = 13, Font = Enum.Font.GothamBlack,
					BackgroundColor3 = good and GREEN or Color3.fromRGB(58, 60, 82) }, row, function()
					Remotes.Inventory:FireServer("Equip", item.Id)
				end)
				rounded(equipBtn, 17)
				local function hover(on)
					stroke.Color = on and Color3.new(1, 1, 1) or (best and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(58, 60, 86))
					if not on then
						head.Text = "Hover to compare · ⚡ = power change (set bonus + set effect counted)"
					else
						head.Text = string.format("⚡ %s%s → <b>%s</b>  ·  Now: <font color='#cfd6f0'>%s</font>", r.Exact and "" or "≈ ", commas(r.Base), commas(r.AfterPower), nowText)
					end
				end
				row.MouseEnter:Connect(function() hover(true) end)
				row.MouseLeave:Connect(function() hover(false) end)
				row.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.Touch then hover(true) end
				end)
			end
		end
		local grid = create("ScrollingFrame", { Size = UDim2.new(1, -8, 1, -156), Position = UDim2.new(0, 4, 0, 102), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, middle)
		create("UIGridLayout", { CellSize = UDim2.new(0, 52, 0, 52), CellPadding = UDim2.new(0, 6, 0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, grid) -- (가운데 308 - 8 - 12 = 288 >= 52 x 5 + 6 x 4 = 284)
		if #filtered == 0 and not swapMode then
			makeLabel({ Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 0, 110), Text = #bag == 0 and "Your bag is empty" or "Nothing matches this filter", TextSize = 12, TextColor3 = Color3.fromRGB(130, 130, 150) }, middle)
		end
		-- 같은 장비 묶기: 부위 / 등급 / 강화 / 세트 / 유니크 / "+1" 옵션이 같으면 한 칸 + "x개수" (정렬상 앞선 것 = 대표)
		local shownList, groupCount, groupOf, groupSel = {}, {}, {}, {}
		for _, entry in ipairs(swapMode and {} or filtered) do
			local it = entry.Item
			local key = gearGroupKey(it)
			if groupOf[key] then
				local idx = groupOf[key]
				groupCount[idx] += 1
				if selected and selected.Id == it.Id then -- (고른 장비가 묶음 안이면 그걸 대표로)
					shownList[idx], groupSel[idx] = entry, true
				elseif not groupSel[idx] and (ascending and it.Score < shownList[idx].Item.Score or (not ascending and it.Score > shownList[idx].Item.Score)) then -- (대표 = 정렬 방향 끝의 것: ▼는 제일 강한 것, ▲는 제일 약한 것)
					shownList[idx] = entry
				end
			else
				table.insert(shownList, entry)
				groupOf[key] = #shownList
				groupCount[#shownList] = 1
				if selected and selected.Id == it.Id then groupSel[#shownList] = true end
			end
		end
		-- 가방 타일 (다크 포지): 등급 테두리 2~3px + 위 3px 등급색 띠 + 등급색 12% 배경 + 전설 이상 뒤쪽 광채(정적)
		--   배지 6자리 고정: ★ 유니크 좌상 / x개수 상단 가운데 / 세트 점 우상 / "+1" 효과 아이콘 좌하 / +N 하단 가운데 / ▲▼ 우하
		local BASE = Color3.fromRGB(24, 26, 40)
		-- 보이는 만큼만 그리기: 처음 25칸(약 5줄 = 한 화면)만 바로 그리고, 나머지는 빈 자리(Frame 1개)만 잡아 두었다가 스크롤해서 보일 때 채운다
		--   (가방 40~50개면 창을 열 때마다 타일 요소 600개 가까이를 만들어 [창 측정] 69~96ms 였다)
		local FIRST = 25
		local function fillCell(cell, order, entry)
			local item = entry.Item
			local isSel = selected and selected.Id == item.Id
			local rarityColor = Config.Gear.RarityColors[item.Rarity] or Color3.fromRGB(190, 190, 190)
			if item.Rarity >= 4 then
				local glow = create("Frame", { Size = UDim2.new(1, 6, 1, 6), Position = UDim2.new(0, -3, 0, -3), BackgroundColor3 = rarityColor, BackgroundTransparency = 0.72, BorderSizePixel = 0 }, cell)
				rounded(glow, 12)
			end
			local tile = create("TextButton", { Size = UDim2.new(1, 0, 1, 0), Text = "", BackgroundColor3 = Color3.new(1, 1, 1), AutoButtonColor = true, BorderSizePixel = 0 }, cell) -- (makeButton 의 광택 / 검은 테두리 없이: 등급 그라데이션이 그대로 보이게)
			tile.Activated:Connect(function()
				menuContent:SetAttribute("ShowWeapons", nil)
				menuContent:SetAttribute("SelectedItem", item.Id)
				refreshMenu()
			end)
			rounded(tile, 10)
			create("UIGradient", { Rotation = 90, Color = ColorSequence.new(BASE:Lerp(rarityColor, isSel and 0.22 or 0.12), BASE) }, tile)
			local stroke = create("UIStroke", { Color = isSel and Color3.new(1, 1, 1) or rarityColor, Thickness = (isSel or item.Rarity >= 4) and 3 or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tile)
			if isSel then -- (반짝임은 고른 칸 하나에만)
				TweenService:Create(stroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.45 }):Play()
			end
			local band = create("Frame", { Size = UDim2.new(1, -14, 0, 3), Position = UDim2.new(0, 7, 0, 2), BackgroundColor3 = rarityColor, BorderSizePixel = 0, ZIndex = 3 }, tile)
			rounded(band, 2)
			makeLabel({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 9), Text = SLOT_ICONS[item.Slot], TextSize = 20, ZIndex = 3 }, tile)
			if (item.Level or 0) > 0 then -- 하단 가운데: +N (+0 은 안 적는다)
				makeLabel({ Size = UDim2.new(0, 30, 0, 14), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Text = string.format("+%d", item.Level), TextSize = 11, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, ZIndex = 4 }, tile)
			end
			if groupCount[order] > 1 then -- 상단 가운데: x개수
				local cnt = makeLabel({ Size = UDim2.new(0, 26, 0, 15), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0), Text = "x" .. groupCount[order], TextSize = 11, Font = Enum.Font.GothamBlack,
					TextColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(70, 66, 110), ZIndex = 8 }, tile)
				rounded(cnt, 7)
			end
			if entry.Diff ~= 0 then -- 우하: ▲▼
				makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(1, -15, 1, -15), Text = entry.Diff > 0 and "▲" or "▼", TextSize = 11, Font = Enum.Font.GothamBlack, ZIndex = 4,
					TextColor3 = entry.Diff > 0 and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 120, 120) }, tile)
			end
			if item.Unique then -- 좌상: ★
				makeLabel({ Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 2, 0, 3), Text = "★", TextSize = 11, TextColor3 = Color3.fromRGB(255, 184, 77), ZIndex = 4 }, tile)
			end
			if item.AugBoost and Config.AugInfo[item.AugBoost] then -- 좌하: "+1" 효과 아이콘
				makeLabel({ Size = UDim2.new(0, 16, 0, 14), Position = UDim2.new(0, 2, 1, -15), Text = Config.AugInfo[item.AugBoost].Icon, TextSize = 11, ZIndex = 4 }, tile)
			end
			if item.Set and Config.Sets[item.Set] then -- 우상: 세트 점 (끼면 세트가 이어지면 초록 테두리. 예전 "▲n/3" 띠는 뺐다)
				local dot = create("Frame", { Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(1, -13, 0, 4), BackgroundColor3 = Config.Sets[item.Set].Color, BorderSizePixel = 0, ZIndex = 5, Active = false }, tile)
				create("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
				if entry.SetGain >= 2 then create("UIStroke", { Color = Color3.fromRGB(120, 255, 140), Thickness = 2 }, dot) end
			end
		end
		local pending = {}
		for order, entry in ipairs(shownList) do
			local cell = create("Frame", { BackgroundTransparency = 1, LayoutOrder = order }, grid)
			if order <= FIRST or (selected and selected.Id == entry.Item.Id) then
				fillCell(cell, order, entry)
			else
				table.insert(pending, { cell, order, entry })
			end
		end
		if #pending > 0 then
			local function fillVisible()
				local bottom = grid.AbsolutePosition.Y + grid.AbsoluteSize.Y + 80 -- (한 줄 미리)
				for i = #pending, 1, -1 do
					local p = pending[i]
					if p[1].Parent and p[1].AbsolutePosition.Y < bottom then
						fillCell(p[1], p[2], p[3])
						table.remove(pending, i)
					end
				end
			end
			local conn
			conn = grid:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
				if not grid.Parent then conn:Disconnect() return end
				fillVisible()
				if #pending == 0 then conn:Disconnect() end
			end)
			task.defer(fillVisible) -- (배치가 끝난 다음 한 번: 가방 칸이 화면에 걸쳐 있는데 스크롤 값이 그대로일 때도 채운다)
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
			Text = string.format("<font size='14'><b>🔫 Weapons</b></font>  <font color='#aab0cc'>%s · +%d</font>\n<font size='11' color='#9aa4cc'>A new weapon unlocks every 15 levels. Tap one to use it.</font>", Config.GetEraName(eraTier.Era), weaponLevel),
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
				Size = UDim2.new(1, -90, 1, 0), Position = UDim2.new(0, 8, 0, 0), RichText = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
				Text = string.format("<font size='12' color='#%s'><b>%s</b></font>\n<font color='#8f94b0'>%s</font>", open and hex(look.Color) or "777788", info.Name, info.Trait),
			}, row)
			makeLabel({
				Size = UDim2.new(0, 78, 1, 0), Position = UDim2.new(1, -82, 0, 0), TextSize = 12, Font = Enum.Font.GothamBold,
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
		local y = 6
		if not selected.Equipped then -- 비교 배너 (가방 장비를 골랐을 때): 장착 중 → 이 장비, 큰 "▲ +N 전투력", "지금 → 끼면"
			local after, base, exact = powerIf(selected)
			local delta = after - base
			local up = delta >= 0
			local tone = up and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 120, 120)
			local banner = create("Frame", { Size = UDim2.new(1, -12, 0, 100), Position = UDim2.new(0, 6, 0, y), BackgroundColor3 = Color3.fromRGB(20, 30, 26):Lerp(Color3.fromRGB(36, 20, 24), up and 0 or 1), BorderSizePixel = 0 }, detail)
			rounded(banner, 12)
			create("UIStroke", { Color = tone, Thickness = 1.5, Transparency = 0.35 }, banner)
			makeLabel({ Size = UDim2.new(1, -90, 0, 16), Position = UDim2.new(0, 10, 0, 5), Text = "Equipped vs this", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(200, 205, 225) }, banner)
			local pill = makeLabel({ Size = UDim2.new(0, 64, 0, 18), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 4), Text = up and "▲ Gain" or "▼ Loss", TextSize = 11, Font = Enum.Font.GothamBlack,
				TextColor3 = tone, BackgroundTransparency = 0, BackgroundColor3 = tone:Lerp(Color3.fromRGB(16, 18, 30), 0.8) }, banner)
			rounded(pill, 9)
			local function mini(item, x, w)
				local card = create("Frame", { Size = UDim2.new(0, w, 0, 30), Position = UDim2.new(0, x, 0, 24), BackgroundColor3 = Color3.fromRGB(26, 28, 42), BorderSizePixel = 0 }, banner)
				rounded(card, 8)
				local c = item and Config.Gear.RarityColors[item.Rarity] or Color3.fromRGB(90, 94, 120)
				create("UIStroke", { Color = c, Thickness = item and item.Rarity >= 4 and 2 or 1.5 }, card)
				makeLabel({ Size = UDim2.new(1, -8, 0, 15), Position = UDim2.new(0, 6, 0, 1), Text = item and (Config.ItemDisplayName(item) .. (item.Level > 0 and (" +" .. item.Level) or "")) or "Empty", TextSize = 11, Font = Enum.Font.GothamBold,
					TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = c }, card)
				makeLabel({ Size = UDim2.new(1, -8, 0, 13), Position = UDim2.new(0, 6, 0, 15), Text = item and string.format("Score %d", item.Score or 0) or "", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(160, 165, 190) }, card)
			end
			mini(current, 8, 124)
			makeLabel({ Size = UDim2.new(0, 18, 0, 30), Position = UDim2.new(0, 134, 0, 24), Text = "▶", TextSize = 12, TextColor3 = Color3.fromRGB(225, 196, 118) }, banner)
			mini(selected, 154, 124)
			makeLabel({ Size = UDim2.new(0, 150, 0, 34), Position = UDim2.new(0, 10, 0, 58), RichText = true, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBlack, TextSize = 21, TextColor3 = tone,
				TextTransparency = exact and 0 or 0.35,
				Text = string.format("%s%s%s <font size='11' color='#d8dcef'>Power</font>", exact and "" or "≈ ", up and "+" or "-", commas(math.abs(delta))) }, banner)
			makeLabel({ Size = UDim2.new(0, 120, 0, 34), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 58), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(225, 230, 245),
				TextTransparency = exact and 0 or 0.35, Text = string.format("%s → %s", commas(base), commas(after)) }, banner)
			y += 106
		end
		if selected.Set and Config.Sets[selected.Set] then -- 세트 띠
			local setDef = Config.Sets[selected.Set]
			local have = setCounts[selected.Set] or 0
			local band = create("Frame", { Size = UDim2.new(1, -12, 0, 24), Position = UDim2.new(0, 6, 0, y), BackgroundColor3 = setDef.Color, BorderSizePixel = 0 }, detail)
			rounded(band, 8)
			create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.85) }) }, band)
			makeLabel({ Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 8, 0, 0), RichText = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
				Text = string.format("%s <b>%s</b> <b>Set</b>   %s %d/3", setDef.Icon or "★", setDef.Name, setPips(have), have) }, band)
			y += 28
		end
		makeLabel({ Size = UDim2.new(1, -16, 0, 36), Position = UDim2.new(0, 8, 0, y), RichText = true, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			Text = string.format("<font color='#%s'><b>[%s] %s</b></font> +%d\n<font color='#aaaacc' size='11'>%s · Score %d%s</font>", hex(color), Config.Gear.RarityNames[selected.Rarity], Config.ItemDisplayName(selected), selected.Level, slot.Name, selected.Score, selected.Equipped and " · Equipped" or "") }, detail)
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
				makeLabel({ Size = UDim2.new(1, -16, 0, 14), Position = UDim2.new(0, 8, 0, 29), RichText = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
					Text = string.format("%s  <font color='#78ff8c'>→ %s</font>", Config.FormatGearStat(selected.Slot, Config.GetGearStat(selected.Slot, selected.Rarity, selected.Level)), Config.FormatGearStat(selected.Slot, Config.GetGearStat(selected.Slot, selected.Rarity, selected.Level + 1))) }, block)
				local barBack = create("Frame", { Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 8, 0, 48), BackgroundColor3 = Color3.fromRGB(18, 18, 28), BorderSizePixel = 0 }, block)
				rounded(barBack, 8)
				local barFill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 90, 80):Lerp(Color3.fromRGB(110, 230, 120), math.clamp((chanceRaw - 0.35) / 0.65, 0, 1)), BorderSizePixel = 0 }, barBack)
				rounded(barFill, 8)
				TweenService:Create(barFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(chanceRaw, 0, 1, 0) }):Play()
				makeLabel({ Size = UDim2.new(1, 0, 1, 0), Text = string.format("Success %d%%", math.floor(chanceRaw * 100 + 0.5)), TextSize = 12, Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.4, ZIndex = 3 }, barBack)
				local upgradeButton = makeButton({ Size = UDim2.new(0.62, -10, 0, 40), Position = UDim2.new(0, 8, 0, 70), Text = string.format("🔨 Upgrade\n💰 %s G", commas(cost)), TextSize = 13, Font = Enum.Font.GothamBlack,
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
			-- 묶인 장비면 몇 개 중 제일 약한 것을 지우는지 버튼에 적는다 (예전엔 대표만 지워 약한 복사본이 남았다)
			local groupN, groupKey = 0, gearGroupKey(selected)
			for _, it in ipairs(bag) do
				if not it.Equipped and gearGroupKey(it) == groupKey then groupN += 1 end
			end
			local scrapButton = makeButton({ Size = UDim2.new(0.38, -6, 0, 40), Position = UDim2.new(0.62, 0, 0, y), Text = groupN > 1 and "" or "Dismantle", TextSize = 13, Font = Enum.Font.GothamBold, BackgroundColor3 = RED }, detail, function()
				-- 묶인 장비면 묶음에서 점수가 제일 낮은 것을 분해한다 (대표 = 제일 좋은 것이라 그대로 분해하면 약한 복사본이 남았다)
				local target, key = selected, gearGroupKey(selected)
				for _, it in ipairs(bag) do
					if not it.Equipped and it.Id ~= selected.Id and gearGroupKey(it) == key and it.Score < target.Score then target = it end
				end
				Remotes.Inventory:FireServer("Scrap", target.Id)
			end)
			rounded(scrapButton, 20)
			if groupN > 1 then -- (버튼 글자를 비우고 두 줄 라벨: 줄마다 번역표 문장으로 찾을 수 있게)
				makeLabel({ Size = UDim2.new(1, 0, 0, 15), Position = UDim2.new(0, 0, 0, 5), Text = "Dismantle", TextSize = 11, Font = Enum.Font.GothamBold }, scrapButton)
				makeLabel({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 0, 21), Text = string.format("x%d · weakest", groupN), TextSize = 11, TextColor3 = Color3.fromRGB(255, 226, 226) }, scrapButton)
			end
			y += 46
		end
		if selected.Unique or #selected.Affixes > 0 then -- 재굴림 줄
			if #selected.Affixes > 0 then
				makeButton({ Size = UDim2.new(0.5, -10, 0, 28), Position = UDim2.new(0, 8, 0, y), Text = string.format("Reroll ✨%d", Config.Inventory.RerollEssence[selected.Rarity]), TextSize = 13, BackgroundColor3 = Color3.fromRGB(58, 60, 84) }, detail, function()
					Remotes.Inventory:FireServer("Reroll", selected.Id)
				end)
			end
			if selected.Unique then
				makeButton({ Size = UDim2.new(0.5, -10, 0, 28), Position = UDim2.new(0.5, 2, 0, y), Text = string.format("★ 🎫%d", Config.Uniques.RerollTickets or 30), TextSize = 13, BackgroundColor3 = Color3.fromRGB(58, 60, 84) }, detail, function()
					Remotes.Inventory:FireServer("RerollUnique", selected.Id)
				end)
			end
			y += 34
		end
		-- 본문: 비교 / 끼면 바뀌는 것 / 능력치 (아래는 스크롤)
		local lines = {}
		-- 이걸 끼면 바뀌는 것: 세트 부위 수와 세트 효과 단계 (세트 효과는 세트 장비를 끼면 저절로 켜진다)
		if not selected.Equipped and (selected.Set or selected.AugBoost or (current and (current.Set or current.AugBoost))) then
			local changes = {}
			local cap = Config.Inventory.AugMaxLevel or 6
			local function augChange(zone, delta)
				local def = Config.Sets.ZoneKeys[zone] and Config.Sets[Config.Sets.ZoneKeys[zone]]
				local info = (def and def.Aug and Config.AugInfo[def.Aug]) or Config.AugInfo[Config.Sets.ZoneAug[zone] or ""] -- (구역 세트가 없는 효과(폭풍의 방벽)는 효과 이름에서)
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
			local diffText = "" -- 장착 중 장비 대비 (가방 장비를 골랐을 때): 같은 옵션 수치 차이
			if not selected.Equipped and current then
				local cv = 0
				for _, ca in ipairs(current.Affixes or {}) do if ca.Stat == affix.Stat then cv += ca.Value end end
				local d = affix.Value - cv
				local def = Config.Inventory.Affixes[affix.Stat]
				if math.abs(d) > 1e-6 and def then
					local num = def.Percent and string.format("%.1f%%", math.abs(d) * 100) or (affix.Stat == "Health" and tostring(math.floor(math.abs(d) + 0.5)) or string.format("%.1f", math.abs(d)))
					diffText = string.format("  <font color='%s'>%s %s</font>", d > 0 and "#78ff8c" or "#ff8c8c", d > 0 and "▲ +" or "▼ -", num)
				end
			end
			table.insert(lines, string.format("<font color='#9ad7ff'>◆ %s</font> <font size='11' color='%s'><b>%d%%</b></font>%s", Config.FormatAffix(affix.Stat, affix.Value), posColor, math.floor(pos * 100 + 0.5), diffText))
		end
		if selected.Unique and Config.Uniques[selected.Unique] then
			table.insert(lines, "<font color='#ffb84d'>★ " .. Config.Uniques[selected.Unique].Name .. "</font> <font size='11' color='#d9b878'>" .. Config.Uniques[selected.Unique].Desc .. "</font>")
		end
		if selected.AugBoost and Config.AugInfo[selected.AugBoost] then
			local info = Config.AugInfo[selected.AugBoost]
			table.insert(lines, string.format("<font color='#9ad7ff'>%s %s +1 Lv</font>", info.Icon, info.Name))
		end
		local more = {} -- (긴 설명 줄은 [▼ 자세히] 안으로: 강화 블록과 핵심 능력치가 먼저 보이게)
		if selected.Set and Config.Sets[selected.Set] then
			local setDef = Config.Sets[selected.Set]
			local have = setCounts[selected.Set] or 0
			for _, tier in ipairs({ 2, 3 }) do
				local parts = {}
				for _, b in ipairs(setDef.Bonuses[tier]) do table.insert(parts, "<font>" .. Config.FormatBonus(b.Stat, b.Value) .. "</font>") end
				local on = have >= tier
				table.insert(more, string.format("<font size='11' color='%s'>%s %d pieces  %s</font>", on and ("#" .. hex(setDef.Color)) or "#6c7088", on and "✔" or "○", tier, table.concat(parts, ", ")))
			end
		end
		local alertH = 0
		if selected.Equipped then -- 장착 중 장비를 골랐을 때: 맨 아래 "가방에 더 좋은 장갑 +N ⚡" (누르면 그 장비를 고른다)
			local bestItem, bestGain = nil, 0
			for _, it in ipairs(bag) do
				if it.Slot == selected.Slot then
					local after, base = powerIf(it)
					if after - base > bestGain then bestItem, bestGain = it, after - base end
				end
			end
			if bestItem then
				alertH = 36
				local alert = makeButton({ Size = UDim2.new(1, -12, 0, 30), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 6, 1, -6), RichText = true, TextSize = 12, Font = Enum.Font.GothamBlack,
					BackgroundColor3 = Color3.fromRGB(34, 70, 46), Text = string.format("▲ Better %s in bag  <font color='#ffd966'>+%s ⚡</font>", slot.Name, commas(bestGain)) }, detail, function()
					menuContent:SetAttribute("SelectedItem", bestItem.Id)
					refreshMenu()
				end)
				rounded(alert, 12)
			end
		end
		local body = create("ScrollingFrame", { Size = UDim2.new(1, -12, 1, -(y + 6 + alertH)), Position = UDim2.new(0, 6, 0, y), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, detail)
		create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, body)
		local showMore = menuContent:GetAttribute("DetailMore") == true
		makeLabel({ Size = UDim2.new(1, -8, 0, 0), LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.Y, Text = table.concat(lines, "\n"), TextSize = 12, RichText = true, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, body)
		if #more > 0 then
			local toggle = makeButton({ Size = UDim2.new(0, 120, 0, 24), LayoutOrder = 2, Text = showMore and "▲ Less" or "▼ Details", TextSize = 12, Font = Enum.Font.GothamBold, BackgroundColor3 = Color3.fromRGB(44, 46, 68) }, body, function()
				menuContent:SetAttribute("DetailMore", not showMore)
				refreshMenu()
			end)
			rounded(toggle, 12)
			if showMore then
				makeLabel({ Size = UDim2.new(1, -8, 0, 0), LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.Y, Text = table.concat(more, "\n"), TextSize = 12, RichText = true, TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, body)
			end
		end
	elseif not showWeapons then
		makeLabel({ Size = UDim2.new(1, -20, 1, -20), Position = UDim2.new(0, 10, 0, 10), Text = "No gear yet.\nDefeat monsters in the field or use the gacha!", TextSize = 13, TextColor3 = Color3.fromRGB(150, 150, 170) }, detail)
	end
end

return buildInventoryTab -- buildInventoryTab(inventoryState)
end

return InventoryTab
