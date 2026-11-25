-- AugService (ServerScriptService > Modules 안의 ModuleScript, 이름: AugService)
-- 세트 효과(미사일 / 낙뢰 / 유성 ...) · 🌟 칸 3개 (11-25 확정, Config.AugSlots):
--   * 칸 3개에 공격 / 방어 효과를 자유롭게 넣는다 (rift.AugSlot = { 구역, 구역, 구역 }, 0 = 빈 칸). 칸에 넣은 효과만 켜진다. 방어는 최대 2칸
--   * 공격 효과(1~8) 단계 = 그 구역 세트 장비 부위 수 (2부위 Lv3 / 3~5부위 Lv6 / 6부위 Lv6 + 👑 각성). 칸에 넣을 자격 = 단계 > 0
--   * 방어 효과(9~14) 단계 = 그 구역 군주를 잡아 연 뒤 수호석 1~6단계. 방어 2개면 단계가 낮은 쪽은 60% 효율, 받는 피해 감소(방벽 + 불굴) 총합 상한 55%
--   * "+1" 장비 옵션: 그 효과가 이미 자기 경로로 켜질 수 있을 때만 +1단계씩, 합계 상한 6
--   * 칸 강화(rift.AugSlotLv, +1~+10, 칸 자체 고정 골드표): 단계마다 그 칸 효과 +3%, +5 공통(공격 10% 한 번 더 / 방어 수치 +20%), +10 효과 전용 (AugFx)
--   * 효과 코드가 읽는 값: Attribute AugMissile 등(단계) + AugMul_<효과>(위력 / 수치 배율) + AugEcho_<효과>(+5) + AugTen_<효과>(+10) + AugAwake_<효과>(6부위 각성)
--   * 화면용: AugSlotZ_<칸>, AugSlotLv_<칸>, AugGearZ_<구역>(단계), AugOnZ_ / AugOpenZ_ / AugSetZ_(부위 0~6) / AugOptZ_ / AugStoneZ_ / AugAwakeZ_, AugPrefSet
--   * 수호석 드롭: 3구역 이상(잡은 몬스터 구역 기준) -> Aug.GrantStones

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Meta = require(script.Parent:WaitForChild("MetaService"))

local Aug = {}
local S = Config.AugSlots
local ZONES = #Config.Sets.ZoneAug -- (9~14 방어 기재 포함)
local function homeZone(z) return (Config.Sets.AugHomeZone and Config.Sets.AugHomeZone[z]) or z end -- (구역 세트가 없는 효과의 해금 기준 구역)
local function isDefense(z) local info = Config.AugInfo[Config.Sets.ZoneAug[z]] return info ~= nil and info.Defense == true end

local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end
local function inventory()
	local ok, Inventory = pcall(function() return require(script.Parent:WaitForChild("InventoryService")) end)
	return ok and Inventory or nil
end

local function stateOf(player)
	local rift = Meta.GetRift(player)
	if not rift then return nil end
	rift.AugBoss = rift.AugBoss or {}
	rift.AugStone = rift.AugStone or {} -- [구역 번호 문자열] = 수호석으로 올린 단계 (방어 효과 1~6단계)
	rift.Stones = rift.Stones or 0 -- 🔷 수호석
	rift.AugSlotLv = rift.AugSlotLv or { 0, 0, 0 }
	return rift
end

local function isOpen(player, rift, zone)
	local hz = homeZone(zone)
	return rift.AugBoss[tostring(hz)] == true or (player:GetAttribute("ClearedZone") or 0) >= hz -- 예전에 클리어한 구역도 열려 있다
end

local function piecesOf(zone, setCounts)
	local key = Config.Sets.ZoneKeys[zone]
	return key and math.clamp((setCounts or {})[key] or 0, 0, 6) or 0
end

-- 효과마다 단계: 자기 경로(공격 = 세트 부위 / 방어 = 수호석) + "+1" 옵션(자기 경로로 켜졌을 때만), 상한 6. 반환: levels, opts(옵션으로 더해진 단계)
local function levelsOf(rift, boosts, setCounts)
	local list, opts = {}, {}
	for z = 1, ZONES do
		local own = isDefense(z) and (rift.AugStone[tostring(z)] or 0) or (Config.Sets.AugLevelByPieces[piecesOf(z, setCounts)] or 0)
		local opt = own > 0 and math.min(Config.Inventory.AugBoostCap or 3, boosts[Config.Sets.ZoneAug[z]] or 0) or 0
		list[z] = math.min(Config.Inventory.AugMaxLevel or 6, own + opt)
		opts[z] = list[z] - own
	end
	return list, opts
end

-- 처음 한 번(rift.AugSlot 이 아예 없을 때만): 공격은 단계 높은 순 2개 + 지금 켜 둔 방어(rift.AugDef) 1개로 칸을 채운다
--   (장비가 아직 안 불러와졌으면 건너뛴다: 빈 칸을 저장해 버리지 않게)
local function migrate(player, rift)
	if rift.AugSlot ~= nil then return end
	local Inventory = inventory()
	if not Inventory or not Inventory.Loaded or not Inventory.Loaded(player) then return end
	local totals = Inventory.GetTotals(player)
	local levels = levelsOf(rift, totals.AugBoost or {}, totals.SetCounts or {})
	local order = {}
	for z = 1, ZONES do if not isDefense(z) and levels[z] > 0 then table.insert(order, z) end end
	table.sort(order, function(a, b) if levels[a] ~= levels[b] then return levels[a] > levels[b] end return a > b end)
	local slots = { order[1] or 0, order[2] or 0, 0 }
	local def = tonumber(rift.AugDef)
	if def and def >= 1 and def <= ZONES and isDefense(def) and levels[def] > 0 then
		for i = 1, S.Count do if slots[i] == 0 then slots[i] = def break end end
	end
	rift.AugSlot = slots
	print(string.format("[AugSlot] migrate %d -> %d,%d,%d", player.UserId, slots[1], slots[2], slots[3]))
end

-- 칸에 넣은 효과 중 켜지는 것: { { Slot, Zone, Level, Eff(방어 효율), SlotLv } }
local function activeOf(rift, levels)
	local list, seen, defs = {}, {}, {}
	for i = 1, S.Count do
		local z = rift.AugSlot and tonumber(rift.AugSlot[i]) or 0
		if z >= 1 and z <= ZONES and not seen[z] and (levels[z] or 0) > 0 then
			seen[z] = true
			local e = { Slot = i, Zone = z, Level = levels[z], Eff = 1, SlotLv = rift.AugSlotLv[i] or 0 }
			table.insert(list, e)
			if isDefense(z) then table.insert(defs, e) end
		end
	end
	if #defs >= 2 then -- 방어 2개: 단계가 낮은 쪽(같으면 뒤 칸)은 60%
		local low = (defs[2].Level <= defs[1].Level) and defs[2] or defs[1]
		low.Eff = S.SecondDefense
	end
	return list
end
local function slotPower(lv)
	return S.PowerPerStep * lv + (lv >= 5 and S.PowerMilestone or 0) + (lv >= 10 and S.PowerMilestone or 0)
end
-- 전투력용 단계 합 (공격: 단계 + 각성 4 + 칸 강화 / 방어: 단계 x 효율 + 칸 강화)
local function sumLevels(list, setCounts)
	local atk, def = 0, 0
	for _, e in ipairs(list) do
		if isDefense(e.Zone) then
			def += e.Level * e.Eff + slotPower(e.SlotLv)
		else
			atk += e.Level + slotPower(e.SlotLv) + (piecesOf(e.Zone, setCounts) >= Config.Sets.AwakenPieces and S.AwakenPower or 0)
		end
	end
	return atk, def
end
local lastActive = setmetatable({}, { __mode = "k" }) -- [player] = { [구역] = true } (새로 켜진 효과 알림용)

-- ⚡ 전투력 미리보기: 이 장비 합계(totals: SetCounts / AugBoost)라면 켜지는 공격 / 방어 효과 단계 합 (Apply 와 같은 계산, 아무것도 저장하지 않는다)
function Aug.PowerLevelsFor(player, totals)
	local rift = stateOf(player)
	if not rift then return player:GetAttribute("AugAtkLv") or 0, player:GetAttribute("AugDefLv") or 0 end
	local zoneLevels = levelsOf(rift, totals.AugBoost or {}, totals.SetCounts or {})
	return sumLevels(activeOf(rift, zoneLevels), totals.SetCounts or {})
end

-- Attribute 채우기 (효과 코드가 읽는 값 + 화면용 값)
function Aug.Apply(player)
	local rift = stateOf(player)
	if not rift then return end
	migrate(player, rift)
	local levels, bestLevel, auraColor = {}, 0, nil
	local boosts, setPieces = {}, {} -- 장비 옵션 "세트 효과 +1" / 구역 세트 부위 수
	local Inventory = inventory()
	if Inventory then
		local totals = Inventory.GetTotals(player)
		boosts, setPieces = totals.AugBoost or {}, totals.SetCounts or {}
	end
	local zoneLevels, zoneOpts = levelsOf(rift, boosts, setPieces)
	local list = activeOf(rift, zoneLevels)
	local nowActive, mul, echo, ten, awake = {}, {}, {}, {}, {}
	for _, e in ipairs(list) do
		local z = e.Zone
		local attr = Config.Sets.ZoneAug[z]
		levels[attr] = e.Level
		nowActive[z] = true
		local m = (1 + S.StepMult * e.SlotLv) * e.Eff
		if isDefense(z) then
			if e.SlotLv >= 5 then m *= 1 + S.DefBoost end
		else
			echo[attr] = e.SlotLv >= 5
			awake[attr] = piecesOf(z, setPieces) >= Config.Sets.AwakenPieces
		end
		mul[attr], ten[attr] = m, e.SlotLv >= 10
		if e.Level > bestLevel then bestLevel, auraColor = e.Level, Config.AugInfo[attr].Color end
		if lastActive[player] and not lastActive[player][z] then -- 칸에 넣거나 장비를 맞춰서 새로 켜졌다
			local info = Config.AugInfo[attr]
			notify(player, string.format("%s Set effect ON: 『%s』 Lv.%d", info.Icon, info.Name, e.Level))
		end
	end
	lastActive[player] = nowActive
	for attr in pairs(Config.AugInfo) do
		player:SetAttribute(attr, levels[attr] or 0)
		player:SetAttribute("AugMul_" .. attr, mul[attr] or 1)
		player:SetAttribute("AugEcho_" .. attr, echo[attr] == true)
		player:SetAttribute("AugTen_" .. attr, ten[attr] == true)
		player:SetAttribute("AugAwake_" .. attr, awake[attr] == true)
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
	player:SetAttribute("AugPrefSet", tonumber(rift.PrefSet) or 0)
	if player:GetAttribute("AugBodyShown") ~= (levels.AugBody or 0) * (mul.AugBody or 1) then -- ❤️ 강체가 바뀌면 최대 체력을 다시 잰다
		player:SetAttribute("AugBodyShown", (levels.AugBody or 0) * (mul.AugBody or 1))
		task.defer(function()
			local okD, Dungeon = pcall(function() return require(script.Parent:WaitForChild("DungeonService")) end)
			if okD and Dungeon.RefreshMaxHealth then pcall(Dungeon.RefreshMaxHealth, player) end
		end)
	end
	do -- 전투력용 (Config.GetPower 의 PowerAug). PowerLevelsFor 와 같은 기준
		local atk, def = sumLevels(list, setPieces)
		player:SetAttribute("AugAtkLv", atk)
		player:SetAttribute("AugDefLv", def)
	end
	for i = 1, S.Count do
		player:SetAttribute("AugSlotZ_" .. i, rift.AugSlot and tonumber(rift.AugSlot[i]) or 0)
		player:SetAttribute("AugSlotLv_" .. i, rift.AugSlotLv[i] or 0)
		local eff = 1
		for _, e in ipairs(list) do if e.Slot == i then eff = e.Eff end end
		player:SetAttribute("AugSlotEff_" .. i, eff)
	end
	for z = 1, ZONES do
		player:SetAttribute("AugLvZ_" .. z, 0) -- (옛 골드 단계: 화면이 AugLvZ_ + AugGearZ_ 를 단계로 읽으므로 0)
		player:SetAttribute("AugGearZ_" .. z, zoneLevels[z]) -- 이 효과의 단계 (칸에 넣으면 이 단계로 켜진다)
		player:SetAttribute("AugStoneZ_" .. z, rift.AugStone[tostring(z)] or 0)
		player:SetAttribute("AugSetZ_" .. z, piecesOf(z, setPieces)) -- (그 구역 세트 부위 수 0~6)
		player:SetAttribute("AugAwakeZ_" .. z, not isDefense(z) and piecesOf(z, setPieces) >= Config.Sets.AwakenPieces)
		player:SetAttribute("AugOptZ_" .. z, zoneOpts[z])
		player:SetAttribute("AugOnZ_" .. z, nowActive[z] == true)
		player:SetAttribute("AugOpenZ_" .. z, isOpen(player, rift, z))
	end
end

-- 데이터가 적용된 뒤(Meta.Load 후) 호출
local watching = setmetatable({}, { __mode = "k" })
function Aug.Refresh(player)
	Aug.Apply(player)
	if not watching[player] then
		watching[player] = true
		for _, attr in ipairs({ "GearKillCdr", "GearShield", "GearSlaughter", "GearStar", "GearSunder", "Tal_Rush" }) do -- 유니크 / 특성을 바꾸면 조합 효과도 다시 계산
			player:GetAttributeChangedSignal(attr):Connect(function() Aug.Apply(player) end)
		end
	end
end

-- 구역 군주를 잡았다 (FieldService)
function Aug.NoteBoss(player, zone)
	local rift = stateOf(player)
	if not rift or typeof(zone) ~= "number" or zone < 1 or zone > ZONES then return end
	local wasOpen = isOpen(player, rift, zone)
	rift.AugBoss[tostring(zone)] = true
	Aug.Apply(player)
	if not wasOpen then
		local attr = Config.Sets.ZoneAug[zone]
		local info = Config.AugInfo[attr]
		notify(player, string.format("%s Set effect 『%s』 unlocked! Wear 2+ pieces of its set gear, then put it in a slot (Y key)", info.Icon, info.Name))
		for extra, hz in pairs(Config.Sets.AugHomeZone or {}) do -- (같은 군주로 열리는 방어 효과도 알린다)
			if hz == zone then
				local xi = Config.AugInfo[Config.Sets.ZoneAug[extra]]
				if xi then notify(player, string.format("%s %s also unlocked", xi.Icon, xi.Name)) end
			end
		end
	end
end

-- 던전 상자 "선호 세트" (DungeonService / LootService 가 읽는다). 0 = 없음
function Aug.PrefSet(player)
	local rift = Meta.GetRift(player)
	local z = rift and tonumber(rift.PrefSet) or 0
	return (z >= 1 and z <= Config.Field.ZoneCount and z <= (player:GetAttribute("ClearedZone") or 0)) and z or 0
end

-- 강화(수호석 / 칸 강화)는 마을에서만 (튜토리얼 중에는 필드에서도 가능)
local function townOnly(player)
	if player:GetAttribute("TutorialActive") == true or player:GetAttribute("Zone") == "Lobby" then return true end
	notify(player, "🏘 Upgrades can only be done in town")
	return false
end

Remotes.Aug.OnServerEvent:Connect(function(player, action, a, b)
	local rift = stateOf(player)
	if not rift then return end
	if action == "PrefSet" then -- 🎯 던전 선호 세트 (0 = 없음 = 지금처럼 무작위)
		local z = tonumber(a) and math.floor(a) or 0
		if z ~= 0 and (z < 1 or z > Config.Field.ZoneCount or z > (player:GetAttribute("ClearedZone") or 0)) then return end
		rift.PrefSet = z
		player:SetAttribute("AugPrefSet", z)
		return
	end
	if action == "Slot" then -- 칸 a 에 효과 b 넣기 (b = 0 이면 비우기). 다른 칸에 있던 같은 효과는 그 칸에서 빠진다
		local i, z = tonumber(a), tonumber(b)
		if not i or not z then return end
		i, z = math.floor(i), math.floor(z)
		if i < 1 or i > S.Count or z < 0 or z > ZONES then return end
		migrate(player, rift)
		rift.AugSlot = rift.AugSlot or { 0, 0, 0 }
		if z > 0 then
			local Inventory = inventory()
			local totals = Inventory and Inventory.GetTotals(player) or {}
			local levels = levelsOf(rift, totals.AugBoost or {}, totals.SetCounts or {})
			if not isOpen(player, rift, z) or (levels[z] or 0) <= 0 then return end
			if isDefense(z) then
				local defs = 0
				for k = 1, S.Count do
					local other = tonumber(rift.AugSlot[k]) or 0
					if k ~= i and other ~= z and other > 0 and isDefense(other) then defs += 1 end
				end
				if defs >= S.MaxDefense then notify(player, "🛡 Up to 2 defense effects") return end
			end
			for k = 1, S.Count do if rift.AugSlot[k] == z then rift.AugSlot[k] = 0 end end
		end
		rift.AugSlot[i] = z
	elseif action == "SlotUp" then -- 🔨 칸 강화 (칸 자체 고정 골드표)
		local i = tonumber(a)
		if not i then return end
		i = math.floor(i)
		if i < 1 or i > S.Count or not townOnly(player) then return end
		local lv = rift.AugSlotLv[i] or 0
		local cost = S.Cost[lv + 1]
		if not cost then return end
		local gold = player:GetAttribute("Gold") or 0
		if gold < cost then notify(player, string.format("Not enough gold (need %d G)", cost)) return end
		player:SetAttribute("Gold", gold - cost)
		rift.AugSlotLv[i] = lv + 1
		notify(player, string.format("🔨 Slot %d → +%d", i, lv + 1))
	elseif action == "Stone" then -- 🔷 수호석으로 방어 효과 1~6단계 (마을에서)
		local zone = tonumber(a)
		if not zone then return end
		zone = math.floor(zone)
		if zone < 1 or zone > ZONES then return end
		local key = tostring(zone)
		local info = Config.AugInfo[Config.Sets.ZoneAug[zone]]
		if not townOnly(player) then return end
		if not info.Defense or not isOpen(player, rift, zone) then return end
		local stone = rift.AugStone[key] or 0
		if stone >= #Config.Guard.StoneCost then return end
		local cost = Config.Guard.StoneCost[stone + 1]
		if (rift.Stones or 0) < cost then
			notify(player, string.format("Not enough Guard Stones (need %d)", cost))
			return
		end
		rift.Stones -= cost
		rift.AugStone[key] = stone + 1
		notify(player, string.format("%s 『%s』 Lv.%d", info.Icon, info.Name, stone + 1))
	else
		return
	end
	Aug.Apply(player)
end)

-- 🔷 수호석 드롭: 처치한 그 순간에 직접 부른다 (FieldService / DungeonService). zone = 잡은 몬스터의 구역, kind = "Elite" / "Boss"
--   (예전: QuestService 의 처치 수 신호를 듣고 "내가 깬 구역"으로 판정 -> 깬 뒤에는 1~2구역 정예 / 군주로도 모여 약한 군주 반복 사냥이 됐다)
function Aug.GrantStones(player, zone, kind)
	local G = Config.Guard
	if not player or not player.Parent or (tonumber(zone) or 0) < (G.FromZone or 3) then return end
	local rift = stateOf(player)
	if not rift then return end
	local gain = 0
	if kind == "Boss" then
		gain = G.BossStones
	elseif kind == "Elite" and math.random() < G.EliteChance then
		gain = 1
	end
	if gain > 0 then
		rift.Stones = (rift.Stones or 0) + gain
		player:SetAttribute("GuardStones", rift.Stones)
		notify(player, string.format("🔷 Guard Stone +%d", gain))
	end
end

return Aug
