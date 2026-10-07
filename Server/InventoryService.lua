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

function Inventory.NewItem(slotKey, rarity, level)
	return { Slot = slotKey, Rarity = rarity, Level = level or 0, Affixes = newAffixes(rarity) }
end

function Inventory.ItemName(item)
	return Config.GetGearSlot(item.Slot).Names[item.Rarity]
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
	local totals = { Health = 0, Crit = 0, Speed = 0, Damage = 0, Xp = 0, Luck = 0 }
	local state = states[player]
	if not state then return totals end
	for _, slot in ipairs(G.Slots) do
		local item = state.Items[state.Equipped[slot.Key]]
		if item then
			for _, affix in ipairs(item.Affixes) do
				totals[affix.Stat] += affix.Value
			end
		end
	end
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
			Id = id, Slot = item.Slot, Rarity = item.Rarity, Level = item.Level,
			Affixes = item.Affixes, Score = Config.GetItemScore(item), Equipped = equippedIds[id] == true,
		})
	end
	table.sort(items, function(a, b)
		if a.Equipped ~= b.Equipped then return a.Equipped end
		return a.Score > b.Score
	end)

	return {
		Items = items, Capacity = Inventory.Capacity(player), BagCount = bagCount(state),
		Essence = state.Essence, AutoScrap = state.AutoScrap,
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

-- 아이템을 가방에 넣는다. 반환: status ("Equipped" | "Bag" | "Scrapped" | "Full"), item, essence, gold
--   빈 부위면 자동 장착 / 자동 분해 등급 이하면 분해 / 가방이 가득하면 분해
function Inventory.Add(player, item)
	local state = states[player]
	if not state then return "None", item end

	state.NextId += 1
	item.Id = state.NextId

	if not state.Equipped[item.Slot] then
		state.Items[item.Id] = item
		state.Equipped[item.Slot] = item.Id
		applyEquipAttributes(player, state)
		Inventory.Push(player)
		return "Equipped", item
	end

	if item.Rarity <= state.AutoScrap then
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
	if not item then return false, "그 아이템이 없어요." end
	if player:GetAttribute("Zone") == "Dungeon" then return false, "던전 안에서는 장비를 바꿀 수 없어요." end
	if isEquipped(state, id) then return false, "이미 장착 중이에요." end

	state.Equipped[item.Slot] = id
	applyEquipAttributes(player, state)
	Inventory.Push(player)
	return true, string.format("[%s] %s 장착!", G.RarityNames[item.Rarity], Inventory.ItemName(item))
end

function Inventory.Scrap(player, id)
	local state = states[player]
	local item = state and state.Items[id]
	if not item then return false, "그 아이템이 없어요." end
	if isEquipped(state, id) then return false, "장착 중인 장비는 분해할 수 없어요." end

	state.Items[id] = nil
	local essence, gold = giveScrap(player, state, item)
	Inventory.Push(player)
	return true, string.format("분해! 에센스 +%d, %d G", essence, gold)
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
		return false, "분해할 아이템이 없어요."
	end
	return true, string.format("%d개 분해! 에센스 +%d, %d G", count, essenceTotal, goldTotal)
end

-- 옵션 재굴림: 옵션 종류는 그대로, 수치만 다시 뽑는다 (더 좋아질 수도 나빠질 수도 있어요)
function Inventory.Reroll(player, id)
	local state = states[player]
	local item = state and state.Items[id]
	if not item then return false, "그 아이템이 없어요." end
	if #item.Affixes == 0 then return false, "옵션이 없는 아이템이에요." end

	local cost = I.RerollEssence[item.Rarity]
	if state.Essence < cost then
		return false, string.format("에센스가 부족해요. (%d 필요)", cost)
	end
	state.Essence -= cost
	for _, affix in ipairs(item.Affixes) do
		affix.Value = rollAffixValue(affix.Stat, item.Rarity)
	end
	if isEquipped(state, id) then
		applyEquipAttributes(player, state)
	end
	Inventory.Push(player)
	return true, "옵션 재굴림 완료!"
end

-- 강화 레벨 변경 (GearService 의 장비 강화가 호출)
function Inventory.SetLevel(player, slotKey, level)
	local state = states[player]
	local item = state and state.Items[state.Equipped[slotKey]]
	if not item then return end
	item.Level = level
	applyEquipAttributes(player, state)
	Inventory.Push(player)
end

function Inventory.SetAutoScrap(player, rarity)
	local state = states[player]
	if not state then return end
	state.AutoScrap = math.clamp(math.floor(rarity), 0, 3)
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
	local state = { Items = {}, NextId = 0, Equipped = {}, Essence = 0, AutoScrap = 1, Rev = 0 }

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
		state.AutoScrap = math.clamp(math.floor(tonumber(saved.AutoScrap) or 1), 0, 3)
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

	states[player] = state
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
		table.insert(items, { Id = item.Id, Slot = item.Slot, Rarity = item.Rarity, Level = item.Level, Affixes = affixes })
	end
	return { Items = items, Equipped = state.Equipped, Essence = state.Essence, AutoScrap = state.AutoScrap }
end

function Inventory.Forget(player)
	states[player] = nil
	pushQueued[player] = nil
end

------------------------------------------------------------
-- 클라이언트 요청
------------------------------------------------------------
local lastRequest = {}

Remotes.Inventory.OnServerEvent:Connect(function(player, action, arg)
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
	elseif action == "ScrapBelow" and typeof(arg) == "number" then
		ok, message = Inventory.ScrapBelow(player, arg)
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
