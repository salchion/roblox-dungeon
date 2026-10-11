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

local function equipped(rift, slots)
	local list = {}
	for z = 1, ZONES do
		if rift.AugOn[tostring(z)] and (rift.AugLv[tostring(z)] or 0) > 0 and #list < slots then
			table.insert(list, z)
		end
	end
	return list
end

-- 같은 구역 세트 장비를 끼면 단계가 오른다: 골드 단계(최대 3) + 장착 부위 수(최대 3) = 최대 6단계 (1부위 4단계 / 2부위 5단계 / 3부위 6단계)
local function gearBonus(player, zone)
	local okInv, Inventory = pcall(function() return require(script.Parent:WaitForChild("InventoryService")) end)
	if not okInv then return 0 end
	local counts = Inventory.GetTotals(player).SetCounts or {}
	return math.clamp(counts["Zone" .. zone] or 0, 0, 3)
end

-- Attribute 채우기 (효과 코드가 읽는 값 + 화면용 값)
function Aug.Apply(player)
	local rift = stateOf(player)
	if not rift then return end
	local slots = slotCount(player, rift)
	local list = equipped(rift, slots)
	local levels, bestLevel, auraColor = {}, 0, nil
	for _, z in ipairs(list) do
		local attr = Config.Sets.ZoneAug[z]
		local level = rift.AugLv[tostring(z)] + gearBonus(player, z)
		levels[attr] = level
		if level > bestLevel then bestLevel, auraColor = level, Config.AugInfo[attr].Color end
	end
	for attr in pairs(Config.AugInfo) do
		player:SetAttribute(attr, levels[attr] or 0)
	end
	for _, synKey in ipairs(Config.AugSynergies.Order) do
		local syn = Config.AugSynergies[synKey]
		local active = true
		for _, need in ipairs(syn.Need) do
			if (levels[need] or 0) <= 0 then active = false end
		end
		local before = player:GetAttribute("AugSyn_" .. synKey)
		player:SetAttribute("AugSyn_" .. synKey, active)
		if active and before == false then
			notify(player, string.format("%s 세트 시너지 발동! 『%s』 — %s", syn.Icon, syn.Name, syn.Desc))
		end
	end
	player:SetAttribute("AugAuraColor", auraColor)
	player:SetAttribute("AugSlots", slots)
	for z = 1, ZONES do
		player:SetAttribute("AugLvZ_" .. z, rift.AugLv[tostring(z)] or 0)
		player:SetAttribute("AugGearZ_" .. z, (rift.AugLv[tostring(z)] or 0) > 0 and gearBonus(player, z) or 0) -- 장비로 더해진 단계
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
		player:GetAttributeChangedSignal("AugSlotBonus"):Connect(function() Aug.Apply(player) end) -- 칸 상품을 샀을 때
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
		notify(player, string.format("%s 세트 효과 『%s』가 열렸어요! 골드로 활성화하세요 (Y 키 / ✨ 세트 버튼)", info.Icon, info.Name))
	end
	local after = slotCount(player, rift)
	if after > before then
		notify(player, string.format("🔓 세트 효과를 동시에 켤 수 있는 칸이 %d개로 늘었어요!", after))
	end
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
		if not isOpen(player, rift, zone) then
			notify(player, string.format("%d구역 군주를 잡으면 열려요", zone))
			return
		end
		local level = rift.AugLv[key] or 0
		if level >= 3 then return end
		local cost = Config.Sets.AugCost(zone, level + 1)
		local gold = player:GetAttribute("Gold") or 0
		if gold < cost then
			notify(player, string.format("골드가 부족해요 (필요 %d G)", cost))
			return
		end
		player:SetAttribute("Gold", gold - cost)
		rift.AugLv[key] = level + 1
		local slots = slotCount(player, rift)
		if level == 0 and #equipped(rift, slots) < slots then
			rift.AugOn[key] = true -- 첫 활성화는 빈 칸이 있으면 바로 켠다
		end
		notify(player, string.format("%s 『%s』 %s 완료! (%d단계)", info.Icon, info.Name, level == 0 and "활성화" or "강화", level + 1))
	elseif action == "Toggle" then
		if (rift.AugLv[key] or 0) <= 0 then return end
		if rift.AugOn[key] then
			rift.AugOn[key] = nil
		else
			local slots = slotCount(player, rift)
			if #equipped(rift, slots) >= slots then
				notify(player, string.format("동시에 켤 수 있는 칸이 %d개예요. 다른 효과를 먼저 끄세요", slots))
				return
			end
			rift.AugOn[key] = true
		end
	end
	Aug.Apply(player)
end)

return Aug
