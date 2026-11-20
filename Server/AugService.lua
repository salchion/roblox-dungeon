-- AugService (ServerScriptService > Modules 안의 ModuleScript, 이름: AugService)
-- 세트 효과(미사일 / 낙뢰 / 유성 ...): 장비가 아니라 "골드로 활성화"하는 능력.
--   * 구역 군주를 잡으면 그 구역 효과가 열리고, 골드로 1~3단계까지 올린다 (Config.Sets.AugCost)
--   * 동시에 켤 수 있는 개수(슬롯)는 처음 1개, 2구역 / 4구역을 클리어하면 늘어난다 (Config.Sets.AugSlotZones)
--   * 저장: MetaService 의 Rift 표 안 AugBoss(군주를 잡은 구역) / AugLv(단계) / AugOn(켠 효과). 키는 문자열 구역 번호.
--   * 던전 / 필드의 효과 코드는 예전 그대로 Attribute(AugMissile 등 = 단계)를 읽는다. 이 모듈이 그 Attribute 를 채운다.
--   * 화면용 Attribute: AugSlots, AugLvZ_<구역>(단계), AugOnZ_<구역>(켬), AugOpenZ_<구역>(군주를 잡아 열림)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Meta = require(script.Parent:WaitForChild("MetaService"))

local Aug = {}
local ZONES = #Config.Sets.ZoneAug -- (9번째 폭풍의 방벽 포함)
local function homeZone(z) return (Config.Sets.AugHomeZone and Config.Sets.AugHomeZone[z]) or z end -- (구역 세트가 없는 효과의 해금 / 가격 기준 구역)

local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

local function stateOf(player)
	local rift = Meta.GetRift(player)
	if not rift then return nil end
	rift.AugBoss = rift.AugBoss or {}
	rift.AugLv = rift.AugLv or {}
	rift.AugOn = rift.AugOn or {}
	rift.AugStone = rift.AugStone or {} -- [구역 번호 문자열] = 수호석으로 올린 단계 (방어 기재 4~6단계)
	rift.Stones = rift.Stones or 0 -- 🔷 수호석
	rift.AugLoad = rift.AugLoad or 1 -- 지금 쓰는 세팅 (1 = 사냥용, 2 = 보스용)
	return rift
end

local function isOpen(player, rift, zone)
	local hz = homeZone(zone)
	return rift.AugBoss[tostring(hz)] == true or (player:GetAttribute("ClearedZone") or 0) >= hz -- 예전에 클리어한 구역도 열려 있다
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
		local level = (rift.AugLv[tostring(z)] or 0) + gearBonus(player, z) + (rift.AugStone[tostring(z)] or 0) + math.min(Config.Inventory.AugBoostCap or 3, boosts[attr] or 0)
		list[z] = math.min(Config.Inventory.AugMaxLevel or 6, level)
	end
	return list
end
-- 켜지는 효과 = 내가 칸에 끼운 것만 (지금 세팅 rift.AugEquip[AugLoad]). 단계가 높다고 저절로 바뀌지 않는다
--   딱 한 가지 자동: 한 번도 세팅을 만든 적이 없으면(신규 / 업데이트 직후) 칸을 한 번 채워 준다
local function equipped(player, rift, slots, levels)
	rift.AugEquip = rift.AugEquip or {}
	local load = rift.AugEquip[rift.AugLoad]
	if load == nil then -- (처음 한 번: 예전 자동 규칙 그대로 채워 둔다 = 📌 고정했던 것 먼저, 그다음 단계 높은 순. 기존 유저가 업데이트 뒤 효과가 꺼지지 않게)
		load = {}
		local order = {}
		for z = 1, ZONES do if (levels[z] or 0) > 0 then table.insert(order, z) end end
		table.sort(order, function(a, b)
			local pa, pb = rift.AugOn[tostring(a)] and 1 or 0, rift.AugOn[tostring(b)] and 1 or 0
			if pa ~= pb then return pa > pb end
			if levels[a] ~= levels[b] then return levels[a] > levels[b] end
			return a > b
		end)
		for i = 1, math.min(slots, #order) do table.insert(load, order[i]) end
		if #load > 0 then rift.AugEquip[rift.AugLoad] = load end
	end
	local list, seen = {}, {}
	for _, z in ipairs(load) do
		if #list < slots and not seen[z] and (levels[z] or 0) > 0 then
			table.insert(list, z)
			seen[z] = true
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
	player:SetAttribute("GuardStones", rift.Stones or 0)
	player:SetAttribute("AugLoad", rift.AugLoad)
	if player:GetAttribute("AugBodyShown") ~= (levels.AugBody or 0) then -- ❤️ 강체가 바뀌면 최대 체력을 다시 잰다
		player:SetAttribute("AugBodyShown", levels.AugBody or 0)
		task.defer(function()
			local okD, Dungeon = pcall(function() return require(script.Parent:WaitForChild("DungeonService")) end)
			if okD and Dungeon.RefreshMaxHealth then pcall(Dungeon.RefreshMaxHealth, player) end
		end)
	end
	player:SetAttribute("AugSlots", slots)
	do -- 전투력용: 켜진 공격 / 방어 효과 단계 합 (Config.GetPower 의 PowerAug)
		local atk, def = 0, 0
		for attr, lv in pairs(levels) do
			if Config.AugInfo[attr] and Config.AugInfo[attr].Defense then def += lv else atk += lv end
		end
		player:SetAttribute("AugAtkLv", atk)
		player:SetAttribute("AugDefLv", def)
	end
	for z = 1, ZONES do
		player:SetAttribute("AugLvZ_" .. z, rift.AugLv[tostring(z)] or 0)
		player:SetAttribute("AugGearZ_" .. z, gearBonus(player, z) + (rift.AugStone[tostring(z)] or 0) + boostOf(Config.Sets.ZoneAug[z])) -- 장비 / 수호석으로 더해진 단계 (세트 부위 / 수호석 + "+1" 옵션: 골드 단계가 0 이어도 센다)
		player:SetAttribute("AugStoneZ_" .. z, rift.AugStone[tostring(z)] or 0)
		player:SetAttribute("AugSetZ_" .. z, gearBonus(player, z)) -- (세트 장비 부위로 오른 단계: 창의 "더 세지는 길")
		player:SetAttribute("AugOptZ_" .. z, boostOf(Config.Sets.ZoneAug[z])) -- ("+1" 장비 옵션으로 오른 단계)
		player:SetAttribute("AugOnZ_" .. z, table.find(list, z) ~= nil)
		player:SetAttribute("AugSlotOf_" .. z, (function() local load = rift.AugEquip and rift.AugEquip[rift.AugLoad] or {} return table.find(load, z) or 0 end)()) -- (몇 번 칸에 끼웠나: 0 = 안 끼움)
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
		for extra, hz in pairs(Config.Sets.AugHomeZone or {}) do -- (같은 군주로 열리는 구역 세트 없는 효과도 알린다)
			if hz == zone then
				local xi = Config.AugInfo[Config.Sets.ZoneAug[extra]]
				if xi then notify(player, string.format("%s %s also unlocked", xi.Icon, xi.Name)) end
			end
		end
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

Remotes.Aug.OnServerEvent:Connect(function(player, action, zone, slotIndex)
	local rift = stateOf(player)
	if not rift then return end
	if action == "Loadout" then -- 🗡 사냥용 / 👑 보스용 세팅 바꾸기 (어디서나)
		if zone == 1 or zone == 2 then
			rift.AugLoad = zone
			rift.AugEquip = rift.AugEquip or {}
			rift.AugEquip[zone] = rift.AugEquip[zone] or {}
			Aug.Apply(player)
			-- 장착 방식이 "세트 효과 맞춤"이면 장비도 새 세팅 칸에 맞춘다 (최강 장비 / 세트 방식은 그대로). 던전 안 / 빈 칸 / 바꿀 게 없으면 조용히 넘어가고, 실제로 바꿨을 때만 알린다
			if player:GetAttribute("Zone") ~= "Dungeon" and Aug.AutoGear then
				local okInv, Inventory = pcall(function() return require(script.Parent:WaitForChild("InventoryService")) end)
				if okInv and Inventory.GetEquipMode and Inventory.GetEquipMode(player) == "Augs" then
					local ok, message, changed = Aug.AutoGear(player)
					if ok and (changed or 0) > 0 and message then notify(player, message) end
				end
			end
		end
		return
	end
	if typeof(zone) ~= "number" then return end
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
		local cost = Config.Sets.AugCost(homeZone(zone), level + 1, player:GetAttribute("MaxZone") or 0)
		local gold = player:GetAttribute("Gold") or 0
		if gold < cost then
			notify(player, string.format("Not enough gold (need %d G)", cost))
			return
		end
		player:SetAttribute("Gold", gold - cost)
		rift.AugLv[key] = level + 1
		notify(player, string.format("%s 『%s』 %s done! (Lv.%d)", info.Icon, info.Name, level == 0 and "Activation" or "Upgrade", level + 1))
	elseif action == "Stone" then -- 🔷 수호석으로 방어 기재 4~6단계 (골드 3단계를 다 올린 뒤, 마을에서)
		if not townOnly(player) then return end
		if not info.Defense or (rift.AugLv[key] or 0) < 3 then return end
		local stone = rift.AugStone[key] or 0
		if stone >= 3 then return end
		local cost = Config.Guard.StoneCost[stone + 1]
		if (rift.Stones or 0) < cost then
			notify(player, string.format("Not enough Guard Stones (need %d)", cost))
			return
		end
		rift.Stones -= cost
		rift.AugStone[key] = stone + 1
		notify(player, string.format("%s 『%s』 Lv.%d", info.Icon, info.Name, 3 + stone + 1))
	elseif action == "Equip" then -- 칸에 끼우기 (어디서나). slotIndex 가 있으면 그 칸과 바꾼다
		if not isOpen(player, rift, zone) then return end
		rift.AugEquip = rift.AugEquip or {}
		local load = rift.AugEquip[rift.AugLoad] or {}
		rift.AugEquip[rift.AugLoad] = load
		if table.find(load, zone) then return end
		local slots = slotCount(player, rift)
		while #load > slots do table.remove(load) end
		if typeof(slotIndex) == "number" and slotIndex >= 1 and slotIndex <= #load then
			load[math.floor(slotIndex)] = zone
		elseif #load < slots then
			table.insert(load, zone)
		else
			notify(player, "All slots are full — choose a slot to swap")
			return
		end
	elseif action == "Unequip" then
		local load = rift.AugEquip and rift.AugEquip[rift.AugLoad]
		local at = load and table.find(load, zone)
		if at then table.remove(load, at) end
	end
	Aug.Apply(player)
end)

-- 🔷 수호석 얻기: 4구역부터 엘리트(확률) / 군주 · 던전 보스(확정). 퀘스트 카운터를 듣는다 (필드 / 던전 코드를 고치지 않는다)
task.spawn(function()
	local okQ, Quest = pcall(function() return require(script.Parent:WaitForChild("QuestService")) end)
	if not okQ or not Quest.Listeners then return end
	table.insert(Quest.Listeners, function(player, stat, amount)
		if stat ~= "EliteKills" and stat ~= "BossKills" then return end
		if (player:GetAttribute("ClearedZone") or 0) < Config.Guard.FromCleared then return end
		local rift = stateOf(player)
		if not rift then return end
		local gain = 0
		if stat == "BossKills" then
			gain = Config.Guard.BossStones * (amount or 1)
		else
			for _ = 1, (amount or 1) do if math.random() < Config.Guard.EliteChance then gain += 1 end end
		end
		if gain > 0 then
			rift.Stones = (rift.Stones or 0) + gain
			player:SetAttribute("GuardStones", rift.Stones)
			notify(player, string.format("🔷 Guard Stone +%d", gain))
		end
	end)
end)

-- 세트 효과 맞춤 장착 (Y 창 버튼 / 장비 창 칩): 지금 세팅(사냥용 / 보스용)의 칸에 끼운 효과들의 단계 합이 가장 높아지도록 장비를 바꿔 낀다
--   계산은 Inventory.EquipForAugs. 효과마다 Base = 골드 단계 + 수호석 단계 (세트 부위 / "+1" 옵션은 장비 조합에 따라 바뀐다)
local function augTargets(player)
	local rift = stateOf(player)
	if not rift then return nil end
	local load = rift.AugEquip and rift.AugEquip[rift.AugLoad] or {}
	local list = {}
	for _, z in ipairs(load) do
		if typeof(z) == "number" and z >= 1 and z <= ZONES and isOpen(player, rift, z) then
			table.insert(list, { Zone = z, Set = Config.Sets.ZoneKeys[z], Attr = Config.Sets.ZoneAug[z], Base = (rift.AugLv[tostring(z)] or 0) + (rift.AugStone[tostring(z)] or 0) })
		end
	end
	return list
end
local function levelOf(player, z)
	return math.min(Config.Inventory.AugMaxLevel or 6, (player:GetAttribute("AugLvZ_" .. z) or 0) + (player:GetAttribute("AugGearZ_" .. z) or 0))
end
function Aug.AutoGear(player)
	local targets = augTargets(player)
	if not targets or #targets == 0 then return false, "No set effects in this setup's slots. Put effects in slots in the Set Effects window (Y) first." end
	local okInv, Inventory = pcall(function() return require(script.Parent:WaitForChild("InventoryService")) end)
	if not okInv then return false, "Try again in a moment." end
	local before, powerBefore = {}, player:GetAttribute("Power") or 0
	for _, t in ipairs(targets) do before[t.Zone] = levelOf(player, t.Zone) end
	local changed, reason = Inventory.EquipForAugs(player, targets)
	if reason then return false, reason end
	Aug.Apply(player)
	if changed == 0 then return true, "🌟 Already the best gear for this setup's set effects.", 0 end
	task.delay(0.5, function() -- (장비 Attribute / 전투력이 다시 계산된 뒤에 알린다)
		if not player.Parent then return end
		for _, t in ipairs(targets) do
			local info = Config.AugInfo[t.Attr]
			local now = levelOf(player, t.Zone)
			if info and now ~= before[t.Zone] then notify(player, string.format("%s 『%s』 Lv.%d → Lv.%d", info.Icon, info.Name, before[t.Zone], now)) end
		end
		local powerNow = player:GetAttribute("Power") or 0
		if powerNow ~= powerBefore then notify(player, string.format("⚡ Power %d → %d", powerBefore, powerNow)) end
	end)
	return true, string.format("🌟 Set-effect gear equipped: %d slot(s) swapped", changed), changed
end
task.spawn(function() -- 장비 "!" 표시가 세트 효과 맞춤 기준으로 볼 수 있게 (서로 require 하지 않으려고 나중에 넣는다)
	local okInv, Inventory = pcall(function() return require(script.Parent:WaitForChild("InventoryService")) end)
	if okInv and Inventory.SetAugTargets then Inventory.SetAugTargets(augTargets) end
end)
Remotes.Aug.OnServerEvent:Connect(function(player, action)
	if action ~= "AutoGear" then return end
	local ok, message = Aug.AutoGear(player)
	if message then notify(player, (ok == false and "⚠ " or "") .. message) end
end)

return Aug
