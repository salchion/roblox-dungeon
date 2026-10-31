-- LootService (ServerScriptService > Modules 안의 ModuleScript, 이름: LootService)
-- 전리품. 필드에서 몬스터를 잡으면 장비 아이템이 떨어진다.
--   * 개인 전리품: 드롭은 처치한 본인(이벤트는 참여자 각자)에게만 보이고 본인만 주울 수 있다 -> 뺏기/경쟁 스트레스 없음
--   * 자동 줍기: 가까이 가기만 하면 주워진다 (가방/자동 분해 설정은 InventoryService 가 처리)
--   * 구역이 깊을수록 높은 등급, 엘리트/보스는 더 좋은 등급, 행운 옵션/부스터는 높은 등급 확률을 올려준다
--   * 전설 이상은 서버 전체에 알려서 뽐낼 수 있다
--   * 던전 보스 상자: 던전 종류/난이도에 따라 등급이 정해진 아이템을 바로 가방으로

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Inventory = require(script.Parent:WaitForChild("InventoryService"))
local Odds = require(ReplicatedStorage:WaitForChild("Odds"))

local L = Config.Loot
local G = Config.Gear

local Loot = {}

local drops = {}      -- [player] = { [dropId] = { Item, Position, Expire } }
local nextDropId = 0

local function luckOf(player)
	local luck = player:GetAttribute("GearLuck") or 0
	if (player:GetAttribute("LuckBoostUntil") or 0) > os.time() then
		luck += Config.Shop.LuckBoostBonus
	end
	return luck
end

-- 구역 줄(row)의 가중치로 등급을 뽑는다. 가중치 계산은 화면에 보여 주는 확률과 같은 모듈(Odds)을 쓴다.
local function rollRarity(row, luck, kindMult)
	local weights = Odds.Weights(row, luck, kindMult)
	local total = 0
	for _, weight in ipairs(weights) do total += weight end
	local roll = math.random() * total
	for index, weight in ipairs(weights) do
		roll -= weight
		if roll <= 0 then
			return index
		end
	end
	return 1
end

local function kindMultiplier(kind)
	if kind == "Elite" then
		return L.EliteBonus
	elseif kind == "DungeonBoss" then
		return L.DungeonBossBonus or L.BossBonus
	elseif kind == "Boss" or kind == "Event" then
		return L.BossBonus
	end
	return 1
end

-- extraMult: 높은 등급 추가 배율(던전 깊이가 표의 끝을 넘었을 때) / uniqueChance: 신화 장비의 유니크 확률(던전 깊이)
function Loot.RollItem(player, row, kind, zoneIndex, extraMult, uniqueChance)
	local rarity = rollRarity(row, luckOf(player), kindMultiplier(kind) * (extraMult or 1))
	local slot = G.Slots[math.random(#G.Slots)]
	return Inventory.NewItem(slot.Key, rarity, 0, zoneIndex, uniqueChance)
end

local function itemLabel(item)
	return string.format("[%s] %s", G.RarityNames[item.Rarity], Inventory.ItemName(item))
end

------------------------------------------------------------
-- 필드 드롭
------------------------------------------------------------
-- kind: "Normal" | "Elite" | "Boss" | "Event". zoneIndex: 구역 번호(등급 표의 줄)
function Loot.DropFor(player, position, kind, zoneIndex)
	local chance = L.DropChance[kind] or 0
	local count = L.Counts[kind] or 1
	local row = math.clamp(zoneIndex, 1, #L.ZoneRarity)

	drops[player] = drops[player] or {}
	for _ = 1, count do
		if math.random() < chance then
			local item = Loot.RollItem(player, row, kind, zoneIndex, nil, Config.Uniques.FieldChance or 0.08) -- 필드 드랍: 세트가 섞여 나온다 / 신화에 유니크는 낮은 확률로만 (유니크는 주로 던전 쪽 보상)
			-- 세트 장비가 붙으면, 어느 구역 세트인지는 "1구역 ~ 내가 클리어한 가장 깊은 구역" 중에서 무작위 (등급은 지금 사냥하는 구역 기준: 깊을수록 신화가 잘 나온다)
			-- -> 앞 구역 세트를 모으려고 앞 구역으로 돌아갈 필요가 없다. 가장 깊은 곳에서 사냥하는 게 언제나 이득
			if item.Set then
				local maxZone = math.clamp(math.max(zoneIndex, player:GetAttribute("ClearedZone") or 0), 1, Config.Field.ZoneCount)
				local pick = Config.Sets.ZoneKeys[math.random(1, maxZone)]
				if pick then item.Set = pick end
			end
			nextDropId += 1
			local scatter = count > 1 and Vector3.new(math.random(-7, 7), 0, math.random(-7, 7)) or Vector3.zero
			local spot = position + scatter
			drops[player][nextDropId] = { Item = item, Position = spot, Expire = os.clock() + L.DropLifetime }
			Remotes.Loot:FireClient(player, "Drop", nextDropId, spot, item.Rarity, Inventory.ItemName(item))
		end
	end
end

local function announce(player, item)
	local mark = item.Rarity >= 5 and "👑 MYTHIC!" or "🌟 LEGENDARY!"
	local text = string.format("%s %s got %s!", mark, player.DisplayName, itemLabel(item))
	for _, other in ipairs(Players:GetPlayers()) do
		Remotes.Notify:FireClient(other, text)
	end
end

-- 자동 분해 알림 묶기: 몹이 많아 분해가 쉴 새 없이 일어나면 알림이 계속 올라와서, 2.5초 동안 모아 한 줄로 알린다 (한 개뿐이면 예전처럼 이름을 보여 준다)
local salvageBatch = setmetatable({}, { __mode = "k" })
local function noteSalvage(player, label, essence, gold)
	local batch = salvageBatch[player]
	if batch then
		batch.Count += 1
		batch.Essence += essence or 0
		batch.Gold += gold or 0
		return
	end
	batch = { Count = 1, Label = label, Essence = essence or 0, Gold = gold or 0 }
	salvageBatch[player] = batch
	task.delay(2.5, function()
		salvageBatch[player] = nil
		if not player.Parent then return end
		local text
		if batch.Count == 1 then
			text = string.format("♻ %s auto-salvaged (Essence +%d, %d G)", batch.Label, batch.Essence, batch.Gold)
		else
			text = string.format("♻ Auto-salvaged %d items (Essence +%d, %d G)", batch.Count, batch.Essence, batch.Gold)
		end
		Remotes.Notify:FireClient(player, text)
	end)
end

local function collect(player, drop)
	local item = drop.Item
	local equippedBefore = Inventory.GetEquipped(player, item.Slot)
	local betterThanEquipped = equippedBefore ~= nil and Config.GetItemScore(item) > Config.GetItemScore(equippedBefore)
	local betterPct = betterThanEquipped and math.max(1, math.floor((Config.GetItemScore(item) / math.max(1, Config.GetItemScore(equippedBefore)) - 1) * 100 + 0.5)) or nil -- 지금 장비보다 몇 % 좋은가

	local status, _, essence, gold = Inventory.Add(player, item)
	local label = itemLabel(item)
	local text
	if status == "Equipped" then
		text = "⚔ New gear equipped! " .. label
	elseif status == "Bag" then
		if betterThanEquipped or item.Rarity >= 3 then -- 평범한 가방 추가는 알리지 않는다 (알림이 쉴 새 없이 올라오던 것): 지금 장비보다 좋거나 영웅 이상일 때만
			text = "🎒 " .. label .. (betterPct and string.format("  ▲ +%d%% better than your current gear! (I → Bag)", betterPct) or "")
		end
	else
		noteSalvage(player, label, essence, gold)
	end
	if text then Remotes.Notify:FireClient(player, text) end

	if item.Rarity >= 4 and (status == "Equipped" or status == "Bag") then
		announce(player, item)
	end
end

-- 바닥에 남은 내 전리품을 전부 바로 받는다 (예: 튜토리얼 소환 결투로 끌려가기 직전)
function Loot.CollectAll(player)
	local list = drops[player]
	if not list then return end
	for id, drop in pairs(list) do
		list[id] = nil
		Remotes.Loot:FireClient(player, "Gone", id)
		collect(player, drop)
	end
end

------------------------------------------------------------
-- 던전 보스 상자: 바로 가방으로. 반환: 화면에 보여줄 줄 목록 { { Text, Rarity }... }
------------------------------------------------------------
function Loot.DungeonChest(player, typeKey, difficultyKey, count)
	-- 깊이("D12")면 등급 표의 줄이 깊이마다 이동하고 유니크 확률도 오른다 (화면의 확률 표와 같은 Odds.ChestParams 를 쓴다)
	local row, extra = Odds.ChestParams(typeKey, difficultyKey)
	local depth = Config.Dungeon.DepthOf(difficultyKey)
	local uniqueChance = depth and Config.Uniques.ChanceAtDepth(depth) or nil

	local lines = {}
	count = count or (depth and math.min(L.ChestMax or 6, L.DungeonChestCount + math.floor(depth / (L.ChestPerDepth or 10)))) or L.DungeonChestCount -- 깊을수록 상자가 늘어난다
	for _ = 1, count do
		local item = Loot.RollItem(player, row, "DungeonBoss", nil, extra, uniqueChance)
		if depth then -- 구역 세트 장비 (확률 / 구역은 Odds.ChestSet 과 같은 규칙)
			local chance, zones = Odds.ChestSet(difficultyKey, player:GetAttribute("ClearedZone") or 0)
			if #zones > 0 and math.random() * 100 < chance then
				item.Set = Config.Sets.ZoneKeys[zones[math.random(#zones)]]
			end
		end
		local status, _, essence, gold = Inventory.Add(player, item)
		local label = itemLabel(item)
		local text
		if status == "Equipped" then
			text = "⚔ " .. label .. " (equipped)"
		elseif status == "Bag" then
			text = "🎒 " .. label
		else
			text = string.format("♻ %s (auto-salvage +%d Essence)", label, essence or 0)
		end
		table.insert(lines, { Text = text, Rarity = item.Rarity })
		if item.Rarity >= 4 and (status == "Equipped" or status == "Bag") then
			announce(player, item)
		end
	end
	return lines
end

------------------------------------------------------------
-- 자동 줍기 / 만료 처리
------------------------------------------------------------
local timer = 0
RunService.Heartbeat:Connect(function(dt)
	timer += dt
	if timer < 0.25 then return end
	timer = 0

	local now = os.clock()
	for player, list in pairs(drops) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local radius = math.max(L.PickupRadius, player:GetAttribute("PetLoot") or 0) -- 펫 자동 루팅(레벨 5 / 12) + 레벨 스탯
		for id, drop in pairs(list) do
			if now > drop.Expire then
				list[id] = nil
				Remotes.Loot:FireClient(player, "Gone", id)
			elseif root and (root.Position - drop.Position).Magnitude <= radius then
				list[id] = nil
				Remotes.Loot:FireClient(player, "Gone", id)
				collect(player, drop)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	drops[player] = nil
end)

return Loot
