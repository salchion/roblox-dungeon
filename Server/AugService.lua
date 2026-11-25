-- AugService (ServerScriptService > Modules 안의 ModuleScript, 이름: AugService)
-- 세트 효과(미사일 / 낙뢰 / 유성 ...). 골드로 올리는 길도, 효과 칸(소켓)도 없다:
--   * 공격 효과(1~8) = 그 구역 세트 장비 부위 수로 단계 (Config.Sets.AugLevelByPieces: 1부위 꺼짐 / 2부위 Lv3 / 3부위 Lv6). 단계 > 0 이면 전부 자동으로 켜진다
--   * 방어 효과(9~14) = 그 구역 군주를 잡아 연 뒤 수호석으로 1~6단계 (Config.Guard.StoneCost). 한 번에 딱 1개만 켠다 (rift.AugDef = 구역 번호, 0 = 없음)
--   * "+1" 장비 옵션: 그 효과가 이미 자기 경로(세트 2부위 이상 / 수호석 1단계 이상)로 켜져 있을 때만 +1단계씩, 합계 상한 6. 옵션만으로는 켜지지 않는다
--   * 수호석 드롭: 3구역 이상(잡은 몬스터 구역 기준) 엘리트(확률) / 군주 · 월드 보스(확정) / 던전 보스(3구역 도달 뒤) -> Aug.GrantStones
--   * 저장: MetaService 의 Rift 표 안 AugBoss(군주를 잡은 구역) / AugStone(수호석 단계) / AugDef(켠 방어 효과). 키는 문자열 구역 번호.
--   * 던전 / 필드의 효과 코드는 Attribute(AugMissile 등 = 단계)를 읽는다. 이 모듈이 그 Attribute 를 채운다.
--   * 화면용 Attribute: AugGearZ_<구역>(단계), AugOnZ_<구역>(켬), AugOpenZ_<구역>(열림), AugDef(켠 방어 효과 구역)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Meta = require(script.Parent:WaitForChild("MetaService"))

local Aug = {}
local ZONES = #Config.Sets.ZoneAug -- (9~14 방어 기재 포함)
local function homeZone(z) return (Config.Sets.AugHomeZone and Config.Sets.AugHomeZone[z]) or z end -- (구역 세트가 없는 효과의 해금 기준 구역)
local function isDefense(z) local info = Config.AugInfo[Config.Sets.ZoneAug[z]] return info ~= nil and info.Defense == true end

local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

local function stateOf(player)
	local rift = Meta.GetRift(player)
	if not rift then return nil end
	rift.AugBoss = rift.AugBoss or {}
	rift.AugStone = rift.AugStone or {} -- [구역 번호 문자열] = 수호석으로 올린 단계 (방어 효과 1~6단계)
	rift.Stones = rift.Stones or 0 -- 🔷 수호석
	return rift
end

local function isOpen(player, rift, zone)
	local hz = homeZone(zone)
	return rift.AugBoss[tostring(hz)] == true or (player:GetAttribute("ClearedZone") or 0) >= hz -- 예전에 클리어한 구역도 열려 있다
end

-- 같은 구역 세트 장비 부위 수 -> 단계 (1부위 0 / 2부위 3 / 3부위 6)
local function gearBonus(player, zone, setCounts) -- (setCounts 를 주면 그 조합으로: 전투력 미리보기)
	local key = Config.Sets.ZoneKeys[zone]
	if not key then return 0 end
	local counts = setCounts
	if not counts then
		local okInv, Inventory = pcall(function() return require(script.Parent:WaitForChild("InventoryService")) end)
		if not okInv then return 0 end
		counts = Inventory.GetTotals(player).SetCounts or {}
	end
	return Config.Sets.AugLevelByPieces[math.clamp(counts[key] or 0, 0, 3)] or 0
end

-- 효과마다 단계: 자기 경로(공격 = 세트 부위 / 방어 = 수호석) + "+1" 옵션(자기 경로로 켜졌을 때만), 상한 6. 반환: levels, opts(옵션으로 더해진 단계)
local function levelsOf(player, rift, boosts, setCounts)
	local list, opts = {}, {}
	for z = 1, ZONES do
		local own = isDefense(z) and (rift.AugStone[tostring(z)] or 0) or gearBonus(player, z, setCounts)
		local opt = own > 0 and math.min(Config.Inventory.AugBoostCap or 3, boosts[Config.Sets.ZoneAug[z]] or 0) or 0
		list[z] = math.min(Config.Inventory.AugMaxLevel or 6, own + opt)
		opts[z] = list[z] - own
	end
	return list, opts
end

-- 켠 방어 효과 (구역 번호 또는 nil). 처음 한 번(rift.AugDef 가 nil)은 수호석이 가장 높은 방어 효과를 골라 저장한다
local function defenseZone(rift, levels, dryRun)
	if rift.AugDef == nil then
		local best, bestStone = nil, 0
		for z = 1, ZONES do
			local st = rift.AugStone[tostring(z)] or 0
			if isDefense(z) and st > bestStone then best, bestStone = z, st end
		end
		if not best then return nil end -- (수호석을 쓴 적이 없다: 아직 저장하지 않고 다음에 다시 고른다)
		if dryRun then return best end
		rift.AugDef = best
	end
	local z = rift.AugDef
	if typeof(z) == "number" and z >= 1 and z <= ZONES and isDefense(z) and (levels[z] or 0) > 0 then return z end
	return nil
end

-- 켜지는 효과: 단계 > 0 인 공격 효과 전부 + 고른 방어 효과 1개
local function activeList(rift, levels, dryRun)
	local list = {}
	for z = 1, ZONES do
		if not isDefense(z) and (levels[z] or 0) > 0 then table.insert(list, z) end
	end
	local dz = defenseZone(rift, levels, dryRun)
	if dz then table.insert(list, dz) end
	return list
end
local lastActive = setmetatable({}, { __mode = "k" }) -- [player] = { [구역] = true } (새로 켜진 효과 알림용)

local function sumLevels(list, levels)
	local atk, def = 0, 0
	for _, z in ipairs(list) do
		if isDefense(z) then def += levels[z] else atk += levels[z] end
	end
	return atk, def
end

-- ⚡ 전투력 미리보기: 이 장비 합계(totals: SetCounts / AugBoost)라면 켜지는 공격 / 방어 효과 단계 합 (Apply 와 같은 계산, 아무것도 저장하지 않는다)
function Aug.PowerLevelsFor(player, totals)
	local rift = stateOf(player)
	if not rift then return player:GetAttribute("AugAtkLv") or 0, player:GetAttribute("AugDefLv") or 0 end
	local zoneLevels = levelsOf(player, rift, totals.AugBoost or {}, totals.SetCounts or {})
	return sumLevels(activeList(rift, zoneLevels, true), zoneLevels)
end

-- Attribute 채우기 (효과 코드가 읽는 값 + 화면용 값)
function Aug.Apply(player)
	local rift = stateOf(player)
	if not rift then return end
	local levels, bestLevel, auraColor = {}, 0, nil
	local boosts, setPieces = {}, {} -- 장비 옵션 "세트 효과 +1" / 구역 세트 부위 수
	do
		local okInv, Inventory = pcall(function() return require(script.Parent:WaitForChild("InventoryService")) end)
		if okInv then
			local totals = Inventory.GetTotals(player)
			boosts, setPieces = totals.AugBoost or {}, totals.SetCounts or {}
		end
	end
	local zoneLevels, zoneOpts = levelsOf(player, rift, boosts, setPieces)
	local list = activeList(rift, zoneLevels)
	local nowActive = {}
	for _, z in ipairs(list) do
		local attr = Config.Sets.ZoneAug[z]
		local level = zoneLevels[z]
		levels[attr] = level
		nowActive[z] = true
		if level > bestLevel then bestLevel, auraColor = level, Config.AugInfo[attr].Color end
		if lastActive[player] and not lastActive[player][z] then -- 장비를 끼거나 수호석으로 올려서 새로 켜졌다
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
	player:SetAttribute("AugDef", typeof(rift.AugDef) == "number" and rift.AugDef or 0)
	if player:GetAttribute("AugBodyShown") ~= (levels.AugBody or 0) then -- ❤️ 강체가 바뀌면 최대 체력을 다시 잰다
		player:SetAttribute("AugBodyShown", levels.AugBody or 0)
		task.defer(function()
			local okD, Dungeon = pcall(function() return require(script.Parent:WaitForChild("DungeonService")) end)
			if okD and Dungeon.RefreshMaxHealth then pcall(Dungeon.RefreshMaxHealth, player) end
		end)
	end
	do -- 전투력용: 켜진 공격 / 방어 효과 단계 합 (Config.GetPower 의 PowerAug). PowerLevelsFor 와 같은 기준
		local atk, def = sumLevels(list, zoneLevels)
		player:SetAttribute("AugAtkLv", atk)
		player:SetAttribute("AugDefLv", def)
	end
	for z = 1, ZONES do
		player:SetAttribute("AugLvZ_" .. z, 0) -- (옛 골드 단계: 화면이 AugLvZ_ + AugGearZ_ 를 단계로 읽으므로 0)
		player:SetAttribute("AugGearZ_" .. z, zoneLevels[z]) -- 이 효과의 단계 (자기 경로 + 켜졌을 때만 "+1" 옵션, 상한 6)
		player:SetAttribute("AugStoneZ_" .. z, rift.AugStone[tostring(z)] or 0)
		local key = Config.Sets.ZoneKeys[z]
		player:SetAttribute("AugSetZ_" .. z, key and math.min(3, setPieces[key] or 0) or 0) -- (그 구역 세트 부위 수 0~3: 단계는 0 / 3 / 6)
		player:SetAttribute("AugOptZ_" .. z, zoneOpts[z]) -- ("+1" 옵션으로 실제로 더해진 단계: 효과가 꺼져 있으면 0)
		player:SetAttribute("AugOnZ_" .. z, table.find(list, z) ~= nil)
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
		notify(player, string.format("%s Set effect 『%s』 unlocked! Wear 2+ pieces of its set gear to turn it on (Y key)", info.Icon, info.Name))
		for extra, hz in pairs(Config.Sets.AugHomeZone or {}) do -- (같은 군주로 열리는 방어 효과도 알린다)
			if hz == zone then
				local xi = Config.AugInfo[Config.Sets.ZoneAug[extra]]
				if xi then
					-- (11-25 A-8) 방어 효과는 무엇으로 어떻게 켜는지 같이 알린다 (예전엔 "also unlocked" 한 줄뿐이라 Y 창을 열어 봐야 알 수 있었다)
					if xi.Defense then
						notify(player, string.format("%s %s (defense) also unlocked! Level it up with 🔷 Guard Stones in town, then pick 1 to keep on (Y key)", xi.Icon, xi.Name))
					else
						notify(player, string.format("%s %s also unlocked", xi.Icon, xi.Name))
					end
				end
			end
		end
	end
end

-- 수호석 강화는 마을에서만 (튜토리얼 중에는 필드에서도 가능)
local function townOnly(player)
	if player:GetAttribute("TutorialActive") == true or player:GetAttribute("Zone") == "Lobby" then return true end
	notify(player, "🏘 Upgrades can only be done in town")
	return false
end

Remotes.Aug.OnServerEvent:Connect(function(player, action, zone)
	local rift = stateOf(player)
	if not rift then return end
	if typeof(zone) ~= "number" then return end
	zone = math.floor(zone)
	if action == "Defense" and zone == 0 then -- 🛡 방어 효과 끄기 (어디서나)
		rift.AugDef = 0
		Aug.Apply(player)
		return
	end
	if zone < 1 or zone > ZONES then return end
	local key = tostring(zone)
	local attr = Config.Sets.ZoneAug[zone]
	local info = Config.AugInfo[attr]
	if action == "Stone" then -- 🔷 수호석으로 방어 효과 1~6단계 (마을에서)
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
	elseif action == "Defense" then -- 🛡 켤 방어 효과 고르기 (딱 1개, 어디서나). 이전 것은 꺼진다
		if not info.Defense or not isOpen(player, rift, zone) then return end
		rift.AugDef = zone
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
