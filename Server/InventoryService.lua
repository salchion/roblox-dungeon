-- InventoryService (ServerScriptService > Modules 안의 ModuleScript, 이름: InventoryService)
-- 장비 아이템 / 가방.
--   * 아이템 = 부위(Slot) + 등급(Rarity 1~5) + 강화 레벨(Level) + 랜덤 옵션(Affixes)
--   * 드롭/뽑기로 얻으면 가방에 들어가고, 비어 있는 부위면 바로 장착된다
--   * 분해: 에센스 + 골드 / 재굴림: 에센스로 옵션 수치를 다시 뽑기 / 자동 분해: 설정한 등급 이하는 얻자마자 분해(숙제 방지)
--   * 장착한 아이템은 플레이어 Attribute(Gear_<부위>_R / _L / Gear_Rev)로 반영되고, GearService 가 능력치/외형으로 바꿔준다
--   * 가방 칸 수 = 기본 칸 + BagBonus Attribute (VIP / 가방 확장 상품 같은 BM 이 여기에 더해진다)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local I = Config.Inventory
local G = Config.Gear

local Inventory = {}

local states = {}       -- [player] = { Items = { [id] = item }, NextId, Equipped = { [slot] = id }, Essence, AutoScrap, Rev }
local pushQueued = {}

local function rAttr(key) return "Gear_" .. key .. "_R" end
local function lAttr(key) return "Gear_" .. key .. "_L" end

local function notify(player, text)
	Remotes.Notify:FireClient(player, text)
end

------------------------------------------------------------
-- 아이템 생성
------------------------------------------------------------
local function rollAffixValue(stat, rarity)
	return I.Affixes[stat].Base * I.AffixRarityScale[rarity] * (0.7 + 0.6 * math.random())
end

local function newAffixes(rarity)
	local pool = table.clone(I.AffixOrder)
	local list = {}
	for _ = 1, I.AffixCount[rarity] do
		local stat = table.remove(pool, math.random(#pool))
		table.insert(list, { Stat = stat, Value = rollAffixValue(stat, rarity) })
	end
	return list
end

function Inventory.NewItem(slotKey, rarity, level, zoneIndex, uniqueChance)
	local item = { Slot = slotKey, Rarity = rarity, Level = level or 0, Affixes = newAffixes(rarity) }
	-- 세트 / 유니크 (높은 등급에서만)
	if rarity == 5 and math.random() < (uniqueChance or Config.Uniques.Chance) then
		item.Unique = Config.Uniques.Order[math.random(#Config.Uniques.Order)]
	end
	local zoneSet = zoneIndex and Config.Sets.ZoneKeys[zoneIndex]
	if zoneSet and math.random() < Config.Sets.ZoneSetChance then
		item.Set = zoneSet -- 그 필드 구역에서만 나오는 구역 전용 세트 (뽑기 장비에는 세트가 붙지 않는다: 세트는 필드 파밍 / 각인으로만)
	end
	return item
end

function Inventory.ItemName(item)
	return Config.ItemDisplayName(item)
end

function Inventory.Capacity(player)
	return math.min(I.MaxSlots, I.BaseSlots + (player:GetAttribute("BagBonus") or 0))
end

local function bagCount(state)
	local count = 0
	for id in pairs(state.Items) do
		local equipped = false
		for _, equippedId in pairs(state.Equipped) do
			if equippedId == id then equipped = true end
		end
		if not equipped then
			count += 1
		end
	end
	return count
end

------------------------------------------------------------
-- 장착 상태를 Attribute 로 반영 (GearService 가 이걸 보고 능력치/외형 갱신)
------------------------------------------------------------
local function applyEquipAttributes(player, state)
	for _, slot in ipairs(G.Slots) do
		local item = state.Items[state.Equipped[slot.Key]]
		player:SetAttribute("Gear_" .. slot.Key .. "_Set", item and item.Set or "") -- 외형용 (GearService 가 세트 모양을 고른다)
		player:SetAttribute(rAttr(slot.Key), item and item.Rarity or 0)
		player:SetAttribute(lAttr(slot.Key), item and item.Level or 0)
	end
	state.Rev += 1
	player:SetAttribute("Gear_Rev", state.Rev) -- 옵션만 바뀌어도 능력치를 다시 계산하게 하는 신호
end

function Inventory.GetEquipped(player, slotKey)
	local state = states[player]
	return state and state.Items[state.Equipped[slotKey]] or nil
end

-- 장착 중인 아이템들의 랜덤 옵션 합계
function Inventory.GetTotals(player)
	local totals = { Health = 0, Crit = 0, Speed = 0, Damage = 0, Xp = 0, Luck = 0, Haste = 0, Shot = 0 }
	local state = states[player]
	if not state then return totals end
	local setCounts = {}
	for _, slot in ipairs(G.Slots) do
		local item = state.Items[state.Equipped[slot.Key]]
		if item then
			for _, affix in ipairs(item.Affixes) do
				totals[affix.Stat] += affix.Value
			end
			if item.Unique and Config.Uniques[item.Unique] then
				for _, effect in ipairs(Config.Uniques[item.Unique].Effects) do
					totals[effect.Stat] += effect.Value
				end
			end
			if item.Set then
				setCounts[item.Set] = (setCounts[item.Set] or 0) + 1
			end
		end
	end
	-- 세트 보너스: 2부위 / 3부위 (3부위면 2부위 보너스도 함께)
	for setKey, count in pairs(setCounts) do
		local def = Config.Sets[setKey]
		for pieces = 2, 3 do
			if count >= pieces and def.Bonuses[pieces] then
				for _, bonus in ipairs(def.Bonuses[pieces]) do
					totals[bonus.Stat] += bonus.Value
				end
			end
		end
	end
	totals.SetCounts = setCounts -- 세트별 장착 부위 수 (세트 효과 계산용)
	return totals
end

------------------------------------------------------------
-- 클라이언트로 상태 보내기
------------------------------------------------------------
local function buildPayload(player, state)
	local equippedIds = {}
	for _, id in pairs(state.Equipped) do
		equippedIds[id] = true
	end

	local items = {}
	for id, item in pairs(state.Items) do
		table.insert(items, {
			Id = id, Slot = item.Slot, Rarity = item.Rarity, Level = item.Level, Set = item.Set, Unique = item.Unique,
			Affixes = item.Affixes, Score = Config.GetItemScore(item), Equipped = equippedIds[id] == true,
		})
	end
	table.sort(items, function(a, b)
		if a.Equipped ~= b.Equipped then return a.Equipped end
		return a.Score > b.Score
	end)

	return {
		Items = items, Capacity = Inventory.Capacity(player), BagCount = bagCount(state),
		Essence = state.Essence, AutoScrap = state.AutoScrap, Shards = state.Shards,
	}
end

function Inventory.Push(player)
	local state = states[player]
	if not state or pushQueued[player] then return end
	pushQueued[player] = true
	task.delay(0.3, function()
		pushQueued[player] = nil
		if player.Parent and states[player] then
			Remotes.Inventory:FireClient(player, "State", buildPayload(player, states[player]))
		end
	end)
end

------------------------------------------------------------
-- 분해 / 장착 / 재굴림
------------------------------------------------------------
local function scrapValue(item)
	return I.ScrapEssence[item.Rarity], I.ScrapGold[item.Rarity]
end

local function giveScrap(player, state, item)
	local essence, gold = scrapValue(item)
	state.Essence += essence
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gold)
	return essence, gold
end

local function isEquipped(state, id)
	for _, equippedId in pairs(state.Equipped) do
		if equippedId == id then return true end
	end
	return false
end

-- 스마트 정리: "같은 부위에 이미 더 좋은 장비가 있는, 세트도 유니크도 아닌 장비"만 자동으로 분해한다.
--   * 순수 품질 = 점수에서 세트(+30) / 유니크(+80) 가산을 뺀 값 (등급 / 강화 / 옵션)
--   * 지키는 것: 유니크 / 구역 세트 조각(같은 부위 같은 세트에서 더 좋은 조각이 있을 때만 정리) / 장착 중인 장비 / 그 부위에서 가장 품질 좋은 장비
--   * 같은 부위에서 품질이 같으면 장착 중인 것, 그다음 먼저 얻은 것(Id 가 작은 것)이 남는다 -> 서로를 없애는 일이 없다
local SMART = 4
local function rawQuality(item)
	return Config.GetItemScore(item) - (item.Set and 30 or 0) - (item.Unique and 80 or 0)
end

local function beats(state, other, item) -- other 가 item 을 확실히 대신할 수 있는가
	local a, b = rawQuality(other), rawQuality(item)
	if a ~= b then return a > b end
	local otherEquipped, itemEquipped = isEquipped(state, other.Id), isEquipped(state, item.Id)
	if otherEquipped ~= itemEquipped then return otherEquipped end
	return other.Id < item.Id
end

local function isRedundant(state, item)
	if item.Unique or isEquipped(state, item.Id) then return false end
	for _, other in pairs(state.Items) do
		if other ~= item and other.Slot == item.Slot then
			if item.Set then
				if other.Set == item.Set and beats(state, other, item) then return true end -- 같은 세트 같은 부위의 더 좋은 조각
			elseif beats(state, other, item) then
				return true
			end
		end
	end
	return false
end

-- 한 부위(slotKey 가 없으면 전부)에서 대신할 수 있는 장비를 모두 분해. 반환: 개수, 에센스 합, 골드 합
local function smartPrune(player, state, slotKey)
	local count, essenceTotal, goldTotal = 0, 0, 0
	local changed = true
	while changed do
		changed = false
		for id, item in pairs(state.Items) do
			if (not slotKey or item.Slot == slotKey) and isRedundant(state, item) then
				state.Items[id] = nil
				local essence, gold = giveScrap(player, state, item)
				essenceTotal += essence
				goldTotal += gold
				count += 1
				changed = true
				break
			end
		end
	end
	return count, essenceTotal, goldTotal
end

-- 아이템을 가방에 넣는다. 반환: status ("Equipped" | "Bag" | "Scrapped" | "Full"), item, essence, gold
--   빈 부위면 자동 장착 / 자동 분해 등급 이하면 분해 / 가방이 가득하면 분해
-- 도감이 가방 / 장착 아이템을 훑을 때 쓴다
function Inventory.EachItem(player, fn)
	local state = states[player]
	if not state then return end
	for _, item in pairs(state.Items) do fn(item) end
end

function Inventory.Add(player, item)
	local state = states[player]
	if not state then return "None", item end

	state.NextId += 1
	item.Id = state.NextId
	item.Level = state.SlotLevels[item.Slot] or 0 -- 새 장비도 그 부위의 강화 단계를 바로 받는다
	do -- 도감(아이템): 이 부위 / 등급 / 유니크 효과를 얻어 봤다
		local okM, Meta = pcall(function() return require(script.Parent:WaitForChild("MetaService")) end)
		if okM and Meta.CodexItem then Meta.CodexItem(player, item.Slot, item.Rarity, item.Unique) end
	end
	if item.Set then -- 도감: 이 세트 장비를 얻어 봤다
		local okM, Meta = pcall(function() return require(script.Parent:WaitForChild("MetaService")) end)
		if okM and Meta.CodexSet then Meta.CodexSet(player, item.Set) end
	end

	if not state.Equipped[item.Slot] then
		state.Items[item.Id] = item
		state.Equipped[item.Slot] = item.Id
		applyEquipAttributes(player, state)
		Inventory.Push(player)
		return "Equipped", item
	end

	if state.AutoScrap == SMART then
		-- 스마트: 먼저 가방에 넣어 보고(가득 차면 정리부터), 같은 부위에서 대신할 수 있는 장비를 정리한다
		if bagCount(state) >= Inventory.Capacity(player) then
			smartPrune(player, state, nil)
		end
		if bagCount(state) >= Inventory.Capacity(player) then
			local essence, gold = giveScrap(player, state, item)
			Inventory.Push(player)
			return "Full", item, essence, gold
		end
		state.Items[item.Id] = item
		local mine = isRedundant(state, item)
		local count, essenceTotal, goldTotal = smartPrune(player, state, item.Slot)
		Inventory.Push(player)
		if mine then -- 방금 얻은 장비가 정리 대상이었다 (정리된 것 중 자기 몫만 알려 준다)
			local essence, gold = scrapValue(item)
			return "Scrapped", item, essence, gold
		end
		if count > 0 then
			notify(player, string.format("🧹 Auto-cleaned %d weaker gear (Essence +%d, %d G)", count, essenceTotal, goldTotal))
		end
		return "Bag", item
	end

	if item.Rarity <= state.AutoScrap and not item.Set and not item.Unique then
		local essence, gold = giveScrap(player, state, item)
		Inventory.Push(player)
		return "Scrapped", item, essence, gold
	end

	if bagCount(state) >= Inventory.Capacity(player) then
		local essence, gold = giveScrap(player, state, item)
		Inventory.Push(player)
		return "Full", item, essence, gold
	end

	state.Items[item.Id] = item
	Inventory.Push(player)
	return "Bag", item
end

function Inventory.Equip(player, id)
	local state = states[player]
	local item = state and state.Items[id]
	if not item then return false, "You don't have that item." end
	if player:GetAttribute("Zone") == "Dungeon" then return false, "You can't change gear in the dungeon." end
	if isEquipped(state, id) then return false, "Already equipped." end

	state.Equipped[item.Slot] = id
	applyEquipAttributes(player, state)
	Inventory.Push(player)
	return true, string.format("[%s] %s equipped!", G.RarityNames[item.Rarity], Inventory.ItemName(item))
end

-- 가방에 지금 끼고 있는 것보다 점수가 높은 아이템이 있는 부위 수 (뽑기 직후 "자동 장착" 팝업용)
function Inventory.CountUpgrades(player)
	local state = states[player]
	if not state then return 0 end
	local best = {}
	for id, item in pairs(state.Items) do
		if not isEquipped(state, id) then
			local score = Config.GetItemScore(item)
			if not best[item.Slot] or score > best[item.Slot] then best[item.Slot] = score end
		end
	end
	local count = 0
	for slotKey, score in pairs(best) do
		local equipped = state.Items[state.Equipped[slotKey]]
		if not equipped or score > Config.GetItemScore(equipped) then count += 1 end
	end
	return count
end

-- 부위마다 점수가 가장 높은 아이템을 자동으로 장착한다 (빈 칸 채우기 포함). 바뀐 부위 수를 돌려준다.
function Inventory.AutoEquipBest(player, emptyOnly)
	local state = states[player]
	if not state then return 0 end
	if player:GetAttribute("Zone") == "Dungeon" then
		return 0, "You can't change gear in the dungeon."
	end
	local best = {}      -- [slotKey] = { Id, Score }
	for id, item in pairs(state.Items) do
		local score = Config.GetItemScore(item)
		local current = best[item.Slot]
		if not current or score > current.Score then
			best[item.Slot] = { Id = id, Score = score }
		end
	end
	local changed = 0
	for slotKey, pick in pairs(best) do
		if state.Equipped[slotKey] ~= pick.Id and (not emptyOnly or not state.Equipped[slotKey]) then
			state.Equipped[slotKey] = pick.Id
			changed += 1
		end
	end
	if changed > 0 then
		applyEquipAttributes(player, state)
		Inventory.Push(player)
	end
	return changed
end

function Inventory.Scrap(player, id)
	local state = states[player]
	local item = state and state.Items[id]
	if not item then return false, "You don't have that item." end
	if isEquipped(state, id) then return false, "You can't dismantle equipped gear." end

	state.Items[id] = nil
	local essence, gold = giveScrap(player, state, item)
	Inventory.Push(player)
	return true, string.format("Dismantled! Essence +%d, %d G", essence, gold)
end

function Inventory.SmartClean(player)
	local state = states[player]
	if not state then return false, "" end
	local count, essenceTotal, goldTotal = smartPrune(player, state, nil)
	Inventory.Push(player)
	if count == 0 then return true, "No weak gear to clean up. (Set / Unique / best-in-slot gear is kept)" end
	return true, string.format("🧹 Cleaned up %d! Essence +%d, %d G", count, essenceTotal, goldTotal)
end

function Inventory.ScrapBelow(player, rarity)
	local state = states[player]
	if not state then return false, "" end
	rarity = math.clamp(math.floor(rarity), 1, 3) -- 영웅 이하까지만 일괄 분해 (전설/신화 보호)

	local count, essenceTotal, goldTotal = 0, 0, 0
	for id, item in pairs(state.Items) do
		if item.Rarity <= rarity and not isEquipped(state, id) then
			state.Items[id] = nil
			local essence, gold = giveScrap(player, state, item)
			essenceTotal += essence
			goldTotal += gold
			count += 1
		end
	end
	Inventory.Push(player)
	if count == 0 then
		return false, "No items to dismantle."
	end
	return true, string.format("Dismantled %d! Essence +%d, %d G", count, essenceTotal, goldTotal)
end

-- 옵션 재굴림: 옵션 종류는 그대로, 수치만 다시 뽑는다 (더 좋아질 수도 나빠질 수도 있어요)
function Inventory.Reroll(player, id)
	local state = states[player]
	local item = state and state.Items[id]
	if not item then return false, "You don't have that item." end
	if #item.Affixes == 0 then return false, "This item has no affixes." end

	local cost = I.RerollEssence[item.Rarity]
	if state.Essence < cost then
		return false, string.format("Not enough Essence. (%d needed)", cost)
	end
	state.Essence -= cost
	for _, affix in ipairs(item.Affixes) do
		affix.Value = rollAffixValue(affix.Stat, item.Rarity)
	end
	if isEquipped(state, id) then
		applyEquipAttributes(player, state)
	end
	Inventory.Push(player)
	return true, "Affix reroll complete!"
end

-- (세트 조각 / 세트 각인은 없어졌다: 세트 장비는 필드 드랍으로만 얻는다)

-- 강화 레벨 변경 (GearService 의 장비 강화가 호출)
function Inventory.SetLevel(player, slotKey, level)
	local state = states[player]
	if not state then return end
	state.SlotLevels[slotKey] = level
	for _, item in pairs(state.Items) do
		if item.Slot == slotKey then item.Level = level end
	end
	applyEquipAttributes(player, state)
	Inventory.Push(player)
end

function Inventory.GetSlotLevel(player, slotKey)
	local state = states[player]
	return state and state.SlotLevels[slotKey] or 0
end

function Inventory.SetAutoScrap(player, rarity)
	local state = states[player]
	if not state then return end
	state.AutoScrap = math.clamp(math.floor(rarity), 0, SMART)
	Inventory.Push(player)
end

function Inventory.AddEssence(player, amount)
	local state = states[player]
	if state then
		state.Essence += amount
		Inventory.Push(player)
	end
end

------------------------------------------------------------
-- 저장 / 불러오기
------------------------------------------------------------
-- saved: 저장된 Inventory 테이블. legacyGear: 예전 저장 형식({ Armor = { R, L }, ... })이면 아이템으로 바꿔서 이어받는다
function Inventory.Load(player, saved, legacyGear)
	local state = { Items = {}, NextId = 0, Equipped = {}, Essence = 0, AutoScrap = SMART, Rev = 0, Shards = {}, SlotLevels = {} }

	if typeof(saved) == "table" and typeof(saved.Items) == "table" then
		for _, entry in ipairs(saved.Items) do
			local slot = typeof(entry) == "table" and Config.GetGearSlot(entry.Slot)
			local rarity = typeof(entry) == "table" and math.floor(tonumber(entry.Rarity) or 0) or 0
			if slot and rarity >= 1 and rarity <= #G.RarityNames then
				local item = {
					Id = math.floor(tonumber(entry.Id) or 0), Slot = slot.Key, Rarity = rarity,
					Level = math.clamp(math.floor(tonumber(entry.Level) or 0), 0, G.MaxLevel), Affixes = {},
				}
				for _, affix in ipairs(typeof(entry.Affixes) == "table" and entry.Affixes or {}) do
					if typeof(affix) == "table" and I.Affixes[affix.S] and tonumber(affix.V) then
						table.insert(item.Affixes, { Stat = affix.S, Value = tonumber(affix.V) })
					end
				end
				if typeof(entry.Set) == "string" and entry.Set:sub(1, 4) == "Zone" and Config.Sets[entry.Set] and Config.Sets[entry.Set].Bonuses then item.Set = entry.Set end -- (옛 세트 4종은 없어졌다: 불러올 때 세트만 떼어 낸다)
				if Config.Uniques[entry.Unique] and entry.Unique ~= "Order" and Config.Uniques[entry.Unique].Effects then item.Unique = entry.Unique end
				if item.Id > 0 and not state.Items[item.Id] then
					state.Items[item.Id] = item
					state.NextId = math.max(state.NextId, item.Id)
				end
			end
		end
		if typeof(saved.Equipped) == "table" then
			for _, slot in ipairs(G.Slots) do
				local id = tonumber(saved.Equipped[slot.Key])
				local item = id and state.Items[id]
				if item and item.Slot == slot.Key then
					state.Equipped[slot.Key] = id
				end
			end
		end
		state.Essence = math.max(0, math.floor(tonumber(saved.Essence) or 0))
		local savedScrap = math.clamp(math.floor(tonumber(saved.AutoScrap) or 1), 0, SMART)
		state.AutoScrap = savedScrap == 1 and SMART or savedScrap -- (옛 기본값 "일반 이하" 는 새 기본값 "스마트"로)
		if typeof(saved.Shards) == "table" then
			for zone = 1, Config.Field.ZoneCount do
				state.Shards[zone] = math.max(0, math.floor(tonumber(saved.Shards[zone] or saved.Shards[tostring(zone)]) or 0))
			end
		end
	elseif typeof(legacyGear) == "table" then
		-- 예전 방식(부위당 장비 1개)에서 이어받기
		for _, slot in ipairs(G.Slots) do
			local entry = legacyGear[slot.Key]
			local rarity = entry and math.clamp(math.floor(tonumber(entry.R) or 0), 0, #G.RarityNames) or 0
			if rarity > 0 then
				local item = Inventory.NewItem(slot.Key, rarity, math.clamp(math.floor(tonumber(entry.L) or 0), 0, G.MaxLevel))
				state.NextId += 1
				item.Id = state.NextId
				state.Items[item.Id] = item
				state.Equipped[slot.Key] = item.Id
			end
		end
	end

	-- 강화는 아이템이 아니라 "부위(슬롯)"에 쌓인다: 어떤 장비를 끼든 그 부위의 강화 단계를 받는다. 모든 아이템의 Level 은 그 부위 단계를 그대로 따라간다.
	-- (옛 저장본: 저장된 슬롯 단계가 없으면 그 부위 아이템 중 가장 높은 강화 단계를 부위 단계로 이어받는다)
	local savedLevels = typeof(saved) == "table" and typeof(saved.SlotLevels) == "table" and saved.SlotLevels or nil
	for _, slot in ipairs(G.Slots) do
		local level = 0
		if savedLevels then
			level = math.clamp(math.floor(tonumber(savedLevels[slot.Key]) or 0), 0, G.MaxLevel)
		else
			for _, item in pairs(state.Items) do
				if item.Slot == slot.Key then level = math.max(level, item.Level) end
			end
		end
		state.SlotLevels[slot.Key] = level
	end
	for _, item in pairs(state.Items) do item.Level = state.SlotLevels[item.Slot] or 0 end

	states[player] = state
	Inventory.AutoEquipBest(player, true) -- 접속했을 때 빈 칸이 있고 가방에 맞는 장비가 있으면 자동으로 채운다
	applyEquipAttributes(player, state)
	Inventory.Push(player)
end

function Inventory.Serialize(player)
	local state = states[player]
	if not state then return nil end

	local items = {}
	for _, item in pairs(state.Items) do
		local affixes = {}
		for _, affix in ipairs(item.Affixes) do
			table.insert(affixes, { S = affix.Stat, V = affix.Value })
		end
		table.insert(items, { Id = item.Id, Slot = item.Slot, Rarity = item.Rarity, Level = item.Level, Affixes = affixes, Set = item.Set, Unique = item.Unique })
	end
	local shards = {}
	for zone = 1, Config.Field.ZoneCount do
		shards[tostring(zone)] = state.Shards[zone] or 0
	end
	return { Items = items, Equipped = state.Equipped, Essence = state.Essence, AutoScrap = state.AutoScrap, Shards = shards, SlotLevels = state.SlotLevels }
end

function Inventory.Forget(player)
	states[player] = nil
	pushQueued[player] = nil
end

------------------------------------------------------------
-- 클라이언트 요청
------------------------------------------------------------
local lastRequest = setmetatable({}, { __mode = "k" })

Remotes.Inventory.OnServerEvent:Connect(function(player, action, arg, arg2)
	if action == "Request" then
		Inventory.Push(player)
		return
	end

	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.15 then return end
	lastRequest[player] = now

	local ok, message
	if action == "Equip" and typeof(arg) == "number" then
		ok, message = Inventory.Equip(player, arg)
	elseif action == "Scrap" and typeof(arg) == "number" then
		ok, message = Inventory.Scrap(player, arg)
	elseif action == "Reroll" and typeof(arg) == "number" then
		ok, message = Inventory.Reroll(player, arg)
	elseif action == "SmartClean" then
		ok, message = Inventory.SmartClean(player)
	elseif action == "ScrapBelow" and typeof(arg) == "number" then
		ok, message = Inventory.ScrapBelow(player, arg)
	elseif action == "AutoEquip" then
		local changed, reason = Inventory.AutoEquipBest(player)
		if reason then
			ok, message = false, reason
		elseif changed > 0 then
			ok, message = true, string.format("Auto-equipped the best gear in %d slot(s)!", changed)
		else
			ok, message = true, "You're already wearing the best gear in every slot."
		end
	elseif action == "AutoScrap" and typeof(arg) == "number" then
		Inventory.SetAutoScrap(player, arg)
		return
	else
		return
	end
	notify(player, (ok and "✅ " or "⚠ ") .. message)
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)

return Inventory
