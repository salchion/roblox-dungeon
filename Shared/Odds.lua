-- Odds (ReplicatedStorage > ModuleScript, 이름: Odds)
-- 유료 랜덤 아이템 정책: 확률을 숫자(%)로, 모든 결과의 합이 100% 가 되게 보여 준다.
-- 이 모듈이 "확률의 단일 출처"다: 서버(LootService)가 실제로 뽑을 때와 화면(OddsClient)이 보여 줄 때 같은 계산을 쓴다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Odds = {}

-- 구역 줄(row)의 가중치: 영웅(3) 이상 가중치만 행운 / 종류 보너스를 받는다 (LootService.rollRarity 와 같은 규칙)
-- row 는 소수도 된다: 인접한 두 줄을 섞는다 (던전 깊이마다 확률이 조금씩 오르게)
function Odds.Weights(row, luck, kindMult)
	local rows = Config.Loot.ZoneRarity
	row = math.clamp(row, 1, #rows)
	local lo = math.floor(row)
	local hi = math.min(#rows, lo + 1)
	local f = row - lo
	local weights = {}
	for index = 1, #rows[lo] do
		local weight = rows[lo][index] * (1 - f) + rows[hi][index] * f
		if index >= 3 then
			weight *= (1 + (luck or 0)) * (kindMult or 1)
		end
		weights[index] = weight
	end
	return weights
end

-- 가중치 -> 소수점 둘째 자리 퍼센트 (합이 정확히 100.00 이 되도록 가장 큰 나머지 순으로 0.01 씩 보정)
function Odds.Percentages(weights)
	local total = 0
	for _, w in ipairs(weights) do total += w end
	local units, rest, sum = {}, {}, 0
	for index, w in ipairs(weights) do
		local exact = total > 0 and w / total * 10000 or 0
		units[index] = math.floor(exact)
		rest[index] = { Index = index, Frac = exact - units[index] }
		sum += units[index]
	end
	table.sort(rest, function(a, b) return a.Frac > b.Frac end)
	local missing = 10000 - sum
	for i = 1, missing do
		local entry = rest[((i - 1) % #rest) + 1]
		units[entry.Index] += 1
	end
	local out = {}
	for index, u in ipairs(units) do out[index] = u / 100 end
	return out
end

function Odds.Format(pct)
	return string.format("%.2f%%", pct)
end

-- 행운: 장비 옵션(GearLuck) + 행운 부스터 (켜져 있을 때). withBooster = nil 이면 지금 상태 그대로
function Odds.LuckOf(player, withBooster)
	local luck = player:GetAttribute("GearLuck") or 0
	local active = (player:GetAttribute("LuckBoostUntil") or 0) > os.time()
	if withBooster == true or (withBooster == nil and active) then
		luck += Config.Shop.LuckBoostBonus
	end
	return luck
end

-- 장비 뽑기(티켓): 등급은 Config.Gacha.Rates, 부위는 균등
function Odds.Gacha()
	local pct = Odds.Percentages(Config.Gacha.Rates)
	local rarities = {}
	for index, p in ipairs(pct) do
		rarities[index] = { Name = Config.Gear.RarityNames[index], Color = Config.Gear.RarityColors[index], Pct = p }
	end
	local slotWeights = {}
	for index in ipairs(Config.Gear.Slots) do slotWeights[index] = 1 end
	local slotPct = Odds.Percentages(slotWeights)
	local slots = {}
	for index, slot in ipairs(Config.Gear.Slots) do
		slots[index] = { Name = slot.Name, Pct = slotPct[index] }
	end
	return { Rarities = rarities, Slots = slots, UniqueChance = Config.Uniques.Chance * 100 }
end

-- 던전 보스 상자 한 개: 던전 종류 / 깊이("D12") 또는 옛 난이도("Normal") -> 등급 표의 줄(소수 가능)과 높은 등급 추가 배율
function Odds.ChestParams(typeKey, diffKey)
	local L = Config.Loot
	local depth = Config.Dungeon.DepthOf(diffKey)
	local start = depth and L.DungeonDepthRow or (L.DungeonRarityRow[typeKey] or 3)
	if depth then
		local D = Config.Dungeon.Depth
		local raw = start + (depth - 1) * D.RowPerDepth
		local last = #L.ZoneRarity
		local extra = raw > last and (1 + (raw - last) * D.ExtraPerRow) or 1
		return math.min(raw, last), extra
	end
	return math.clamp(start + (L.DungeonDifficultyRow[diffKey] or 0), 1, #L.ZoneRarity), 1
end

function Odds.ChestRow(typeKey, diffKey)
	local row = Odds.ChestParams(typeKey, diffKey)
	return row
end

function Odds.Chest(typeKey, diffKey, luck)
	local row, extra = Odds.ChestParams(typeKey, diffKey)
	local pct = Odds.Percentages(Odds.Weights(row, luck, Config.Loot.BossBonus * extra))
	local out = {}
	for index, p in ipairs(pct) do
		out[index] = { Name = Config.Gear.RarityNames[index], Color = Config.Gear.RarityColors[index], Pct = p }
	end
	return out
end

-- 던전 상자에서 나온 신화 장비에 유니크 효과가 붙을 확률(%): 깊이가 아니면 필드와 같은 기본 확률
function Odds.ChestUnique(diffKey)
	local depth = Config.Dungeon.DepthOf(diffKey)
	return (depth and Config.Uniques.ChanceAtDepth(depth) or Config.Uniques.Chance) * 100
end

-- 필드 몬스터 드롭 (행운 부스터가 영향을 주는 곳): 구역 / 종류별 등급 확률 (드롭이 나왔을 때의 등급 확률)
function Odds.Field(zone, kind, luck)
	local L = Config.Loot
	local mult = kind == "Elite" and L.EliteBonus or ((kind == "Boss" or kind == "Event") and L.BossBonus or 1)
	local pct = Odds.Percentages(Odds.Weights(math.clamp(zone, 1, #L.ZoneRarity), luck, mult))
	local out = {}
	for index, p in ipairs(pct) do
		out[index] = { Name = Config.Gear.RarityNames[index], Color = Config.Gear.RarityColors[index], Pct = p }
	end
	return out
end

return Odds
