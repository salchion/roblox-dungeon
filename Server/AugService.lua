-- AugService (ServerScriptService > Modules 안의 ModuleScript, 이름: AugService)
-- 세트 효과(미사일 / 낙뢰 / 유성 ...): 장비가 아니라 "골드로 활성화"하는 능력.
--   * 구역 군주를 잡으면 그 구역 효과가 열리고, 골드로 1~3단계까지 올린다 (Config.Sets.AugCost)
--   * 동시에 켤 수 있는 개수(슬롯)는 처음 1개, 4구역 / 7구역을 클리어하면 늘어난다 (Config.Sets.AugSlotZones)
--   * 저장: MetaService 의 Rift 표 안 AugBoss(군주를 잡은 구역) / AugLv(단계) / AugOn(켠 효과). 키는 문자열 구역 번호.
--   * 던전 / 필드의 효과 코드는 예전 그대로 Attribute(AugMissile 등 = 단계)를 읽는다. 이 모듈이 그 Attribute 를 채운다.
--   * 화면용 Attribute: AugSlots, AugLvZ_<구역>(단계), AugOnZ_<구역>(켬), AugOpenZ_<구역>(군주를 잡아 열림)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Meta = require(script.Parent:WaitForChild("MetaService"))

local Aug = {}
local ZONES = Config.Field.ZoneCount

local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

local function stateOf(player)
	local rift = Meta.GetRift(player)
	if not rift then return nil end
	rift.AugBoss = rift.AugBoss or {}
	rift.AugLv = rift.AugLv or {}
	rift.AugOn = rift.AugOn or {}
	return rift
end

local function isOpen(player, rift, zone)
	return rift.AugBoss[tostring(zone)] == true or (player:GetAttribute("ClearedZone") or 0) >= zone -- 예전에 클리어한 구역도 열려 있다
end

local function slotCount(player, rift)
	local cleared = player:GetAttribute("ClearedZone") or 0
	for z = 1, ZONES do
		if rift.AugBoss[tostring(z)] then cleared = math.max(cleared, z) end
	end
	local slots = 0
	for _, need in ipairs(Config.Sets.AugSlotZones) do
		if cleared >= need then slots += 1 end
	end
	return math.max(1, slots) + (player:GetAttribute("AugSlotBonus") or 0) -- 상품 / VIP 로 얻은 칸
end

-- 같은 구역 세트 장비를 끼면 단계가 오른다: 골드 단계(최대 3) + 장착 부위 수(최대 3) = 최대 6단계
local function gearBonus(player, zone)
	local okInv, Inventory = pcall(function() return require(script.Parent:WaitForChild("InventoryService")) end)
	if not okInv then return 0 end
	local counts = Inventory.GetTotals(player).SetCounts or {}
	return math.clamp(counts["Zone" .. zone] or 0, 0, 3)
end

-- 켜지는 세트 효과 고르기 (자동): 단계(골드 단계 + 낀 세트 부위 + "+1" 옵션)가 1 이상인 효과 중에서
--   📌 고정한 것 먼저, 그다음 단계가 높은 것부터 칸(1~3) 수만큼 켠다.
--   (예전: 골드로 1단계 이상 올리고 Y 창에서 직접 ON 을 눌러야 켜졌다 -> 세트 장비를 다 맞춰도 효과가 안 켜져서 헷갈렸다.
--    이제는 그 구역 세트 장비를 1부위만 껴도 효과가 저절로 켜진다. rift.AugOn 은 이제 "📌 고정" 표시로 쓴다)
local function levelsOf(player, rift, boosts)
	local list = {}
	for z = 1, ZONES do
		local attr = Config.Sets.ZoneAug[z]
		local level = (rift.AugLv[tostring(z)] or 0) + gearBonus(player, z) + math.min(Config.Inventory.AugBoostCap or 3, boosts[attr] or 0)
		list[z] = math.min(Config.Inventory.AugMaxLevel or 6, level)
	end
	return list
end
local function equipped(player, rift, slots, levels)
	local pinned, others = {}, {}
	for z = 1, ZONES do
		if (levels[z] or 0) > 0 then
			table.insert(rift.AugOn[tostring(z)] and pinned or others, z)
		end
	end
	local function byLevel(a, b)
		if levels[a] ~= levels[b] then return levels[a] > levels[b] end
		return a > b -- (같으면 뒤 구역 = 더 강한 효과 먼저)
	end
	table.sort(pinned, byLevel)
	table.sort(others, byLevel)
	local list = {}
	for _, group in ipairs({ pinned, others }) do
		for _, z in ipairs(group) do
			if #list < slots then table.insert(list, z) end
		end
	end
	return list
end
local lastActive = setmetatable({}, { __mode = "k" }) -- [player] = { [구역] = true } (새로 켜진 효과 알림용)

-- Attribute 채우기 (효과 코드가 읽는 값 + 화면용 값)
function Aug.Apply(player)
	local rift = stateOf(player)
	if not rift then return end
	local slots = slotCount(player, rift)
	local levels, bestLevel, auraColor = {}, 0, nil
	local boosts = {} -- 장비 옵션 "세트 효과 +1" (효과마다 최대 AugBoostCap)
	do
		local okInv, Inventory = pcall(function() return require(script.Parent:WaitForChild("InventoryService")) end)
		if okInv then boosts = Inventory.GetTotals(player).AugBoost or {} end
	end
	local function boostOf(attr) return math.min(Config.Inventory.AugBoostCap or 3, boosts[attr] or 0) end
	local zoneLevels = levelsOf(player, rift, boosts)
	local list = equipped(player, rift, slots, zoneLevels)
	local nowActive = {}
	for _, z in ipairs(list) do
		local attr = Config.Sets.ZoneAug[z]
		local level = zoneLevels[z] -- (골드 + 세트 부위 + 옵션, 합쳐서 최대 6)
		levels[attr] = level
		nowActive[z] = true
		if level > bestLevel then bestLevel, auraColor = level, Config.AugInfo[attr].Color end
		if lastActive[player] and not lastActive[player][z] then -- 장비를 끼거나 단계를 올려서 새로 켜졌다
			local info = Config.AugInfo[attr]
			notify(player, string.format("%s Set effect ON: 『%s』 Lv.%d", info.Icon, info.Name, level))
		end
	end
	lastActive[player] = nowActive
	for attr in pairs(Config.AugInfo) do
		player:SetAttribute(attr, levels[attr] or 0)
	end
	for _, synKey in ipairs(Config.AugSynergies.Order) do
		local syn = Config.AugSynergies[synKey]
		local active = true
		for _, need in ipairs(syn.Need) do
			local value = levels[need] or ((string.sub(need, 1, 4) == "Gear" or string.sub(need, 1, 4) == "Tal_") and player:GetAttribute(need)) or 0 -- (유니크 능력 / 특성은 플레이어 속성)
			if (tonumber(value) or 0) <= 0 then active = false end
		end
		local before = player:GetAttribute("AugSyn_" .. synKey)
		player:SetAttribute("AugSyn_" .. synKey, active)
		if active and before == false then
			notify(player, string.format("%s Set synergy activated! 『%s』 - %s", syn.Icon, syn.Name, syn.Desc))
		end
	end
	player:SetAttribute("AugAuraColor", auraColor)
	player:SetAttribute("AugSlots", slots)
	for z = 1, ZONES do
		player:SetAttribute("AugLvZ_" .. z, rift.AugLv[tostring(z)] or 0)
		player:SetAttribute("AugGearZ_" .. z, gearBonus(player, z) + boostOf(Config.Sets.ZoneAug[z])) -- 장비로 더해진 단계 (세트 부위 + "+1" 옵션: 골드 단계가 0 이어도 센다)
		player:SetAttribute("AugOnZ_" .. z, table.find(list, z) ~= nil)
		player:SetAttribute("AugPinZ_" .. z, rift.AugOn[tostring(z)] == true) -- 📌 고정
		player:SetAttribute("AugOpenZ_" .. z, isOpen(player, rift, z))
	end
end

-- 데이터가 적용된 뒤(Meta.Load 후) 호출
local watching = setmetatable({}, { __mode = "k" })
function Aug.Refresh(player)
	Aug.Apply(player)
	if not watching[player] then
		watching[player] = true
		player:GetAttributeChangedSignal("AugSlotBonus"):Connect(function() Aug.Apply(player) end) -- 칸 상품을 샀을 때
		for _, attr in ipairs({ "GearKillCdr", "GearShield", "GearSlaughter", "GearStar", "GearSunder", "Tal_Rush" }) do -- 유니크 / 특성을 바꾸면 조합 효과도 다시 계산
			player:GetAttributeChangedSignal(attr):Connect(function() Aug.Apply(player) end)
		end
	end
end

-- 구역 군주를 잡았다 (FieldService)
function Aug.NoteBoss(player, zone)
	local rift = stateOf(player)
	if not rift or typeof(zone) ~= "number" or zone < 1 or zone > ZONES then return end
	local key = tostring(zone)
	local wasOpen = isOpen(player, rift, zone)
	local before = slotCount(player, rift)
	rift.AugBoss[key] = true
	Aug.Apply(player)
	if not wasOpen then
		local attr = Config.Sets.ZoneAug[zone]
		local info = Config.AugInfo[attr]
		notify(player, string.format("%s Set effect 『%s』 unlocked! Equip its set gear to turn it on, or upgrade it with gold (Y key)", info.Icon, info.Name))
	end
	local after = slotCount(player, rift)
	if after > before then
		notify(player, string.format("🔓 You can now run %d set effects at once!", after))
	end
end

-- 업그레이드(골드를 쓰는 강화)는 모두 마을에서만 된다: 어떤 건 필드에서 되고 어떤 건 안 돼서 헷갈린다는 의견 (튜토리얼 중에는 필드에서도 가능)
local function townOnly(player)
	if player:GetAttribute("TutorialActive") == true or player:GetAttribute("Zone") == "Lobby" then return true end
	notify(player, "🏘 Upgrades can only be done in town")
	return false
end

Remotes.Aug.OnServerEvent:Connect(function(player, action, zone)
	local rift = stateOf(player)
	if not rift or typeof(zone) ~= "number" then return end
	zone = math.floor(zone)
	if zone < 1 or zone > ZONES then return end
	local key = tostring(zone)
	local attr = Config.Sets.ZoneAug[zone]
	local info = Config.AugInfo[attr]
	if action == "Buy" then
		if not townOnly(player) then return end
		if not isOpen(player, rift, zone) then
			notify(player, string.format("Defeat the Zone %d lord to unlock", zone))
			return
		end
		local level = rift.AugLv[key] or 0
		if level >= 3 then return end
		local cost = Config.Sets.AugCost(zone, level + 1)
		local gold = player:GetAttribute("Gold") or 0
		if gold < cost then
			notify(player, string.format("Not enough gold (need %d G)", cost))
			return
		end
		player:SetAttribute("Gold", gold - cost)
		rift.AugLv[key] = level + 1
		notify(player, string.format("%s 『%s』 %s done! (Lv.%d)", info.Icon, info.Name, level == 0 and "Activation" or "Upgrade", level + 1))
	elseif action == "Toggle" then -- 📌 고정 / 해제: 고정한 효과는 단계가 낮아도 먼저 켜진다 (칸 수까지)
		if rift.AugOn[key] then
			rift.AugOn[key] = nil
		else
			local slots = slotCount(player, rift)
			local pinned = 0
			for z = 1, ZONES do if rift.AugOn[tostring(z)] then pinned += 1 end end
			if pinned >= slots then
				notify(player, string.format("You can pin up to %d effects. Unpin another one first", slots))
				return
			end
			rift.AugOn[key] = true
		end
	end
	Aug.Apply(player)
end)

return Aug
