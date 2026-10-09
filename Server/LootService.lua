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

-- 구역 줄(row)의 가중치로 등급을 뽑는다. 영웅(3) 이상 가중치만 행운 / 종류 보너스를 받는다.
local function rollRarity(row, luck, kindMult)
	local weights, total = {}, 0
	for index, weight in ipairs(L.ZoneRarity[row]) do
		if index >= 3 then
			weight *= (1 + luck) * kindMult
		end
		weights[index] = weight
		total += weight
	end
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
	elseif kind == "Boss" or kind == "Event" or kind == "DungeonBoss" then
		return L.BossBonus
	end
	return 1
end

function Loot.RollItem(player, row, kind, zoneIndex)
	local rarity = rollRarity(row, luckOf(player), kindMultiplier(kind))
	local slot = G.Slots[math.random(#G.Slots)]
	return Inventory.NewItem(slot.Key, rarity, 0, zoneIndex)
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
			local item = Loot.RollItem(player, row, kind, zoneIndex) -- 필드 드랍: 그 구역 전용 세트가 섞여 나온다
			nextDropId += 1
			local scatter = count > 1 and Vector3.new(math.random(-7, 7), 0, math.random(-7, 7)) or Vector3.zero
			local spot = position + scatter
			drops[player][nextDropId] = { Item = item, Position = spot, Expire = os.clock() + L.DropLifetime }
			Remotes.Loot:FireClient(player, "Drop", nextDropId, spot, item.Rarity, Inventory.ItemName(item))
		end
	end
end

local function announce(player, item)
	local mark = item.Rarity >= 5 and "👑 신화!" or "🌟 전설!"
	local text = string.format("%s %s 님이 %s 획득!", mark, player.DisplayName, itemLabel(item))
	for _, other in ipairs(Players:GetPlayers()) do
		Remotes.Notify:FireClient(other, text)
	end
end

local function collect(player, drop)
	local item = drop.Item
	local equippedBefore = Inventory.GetEquipped(player, item.Slot)
	local betterThanEquipped = equippedBefore ~= nil and Config.GetItemScore(item) > Config.GetItemScore(equippedBefore)

	local status, _, essence, gold = Inventory.Add(player, item)
	local label = itemLabel(item)
	local text
	if status == "Equipped" then
		text = "⚔ 새 장비 장착! " .. label
	elseif status == "Bag" then
		text = "🎒 " .. label .. (betterThanEquipped and "  ▲ 지금 장비보다 좋아요! (I → 가방)" or "")
	else
		text = string.format("♻ %s 자동 분해 (에센스 +%d, %d G)", label, essence or 0, gold or 0)
	end
	Remotes.Notify:FireClient(player, text)

	if item.Rarity >= 4 and (status == "Equipped" or status == "Bag") then
		announce(player, item)
	end
end

------------------------------------------------------------
-- 던전 보스 상자: 바로 가방으로. 반환: 화면에 보여줄 줄 목록 { { Text, Rarity }... }
------------------------------------------------------------
function Loot.DungeonChest(player, typeKey, difficultyKey, count)
	local row = (L.DungeonRarityRow[typeKey] or 3) + (L.DungeonDifficultyRow[difficultyKey] or 0)
	row = math.clamp(row, 1, #L.ZoneRarity)

	local lines = {}
	for _ = 1, count or L.DungeonChestCount do
		local item = Loot.RollItem(player, row, "DungeonBoss")
		local status, _, essence, gold = Inventory.Add(player, item)
		local label = itemLabel(item)
		local text
		if status == "Equipped" then
			text = "⚔ " .. label .. " (장착)"
		elseif status == "Bag" then
			text = "🎒 " .. label
		else
			text = string.format("♻ %s (자동 분해 +%d 에센스)", label, essence or 0)
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
		local radius = math.max(L.PickupRadius, player:GetAttribute("PetLoot") or 0) + (player:GetAttribute("LvLoot") or 0) -- 펫 자동 루팅(레벨 5 / 12) + 레벨 스탯
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
