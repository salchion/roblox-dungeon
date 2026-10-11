-- LevelStatService (ServerScriptService > Modules 안의 ModuleScript, 이름: LevelStatService)
-- 레벨 스탯: 레벨이 오를 때마다 포인트 1개. 공격력 / 체력이 아니라 이동 속도 / 사정거리 / 더블샷 / 스킬 쿨타임 / 치명 피해에만 쓴다.
--   * 언제든 무료로 빼고 다시 넣을 수 있다 (몰빵 가능)
--   * 배분은 MetaService 의 Rift 표 안 LvStats 에 저장된다
--   * 효과는 플레이어 Attribute 로 알린다: LvMove / LvRange / LvDouble / LvHaste / LvCritDmg (다른 서비스가 읽어 쓴다), LvPointsLeft, LvPts_<키>

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Meta = require(script.Parent:WaitForChild("MetaService"))

local LS = Config.LevelStats
local LevelStat = {}

local watching = setmetatable({}, { __mode = "k" })
local lastPoints = setmetatable({}, { __mode = "k" })

local function statsOf(player)
	local rift = Meta.GetRift(player)
	if not rift then return nil end
	rift.LvStats = rift.LvStats or {}
	for _, key in ipairs(LS.Order) do
		rift.LvStats[key] = math.min(rift.LvStats[key] or 0, LS.Cap[key])
	end
	rift.LvGold = rift.LvGold or 0
	return rift.LvStats, rift
end

-- 쓸 수 있는 전체 포인트: 레벨로 얻은 것 + (최대 레벨을 찍었다면) 골드로 산 것
local function totalPoints(player, rift)
	local level = player:GetAttribute("Level") or 1
	local total = Config.GetLevelStatPoints(level)
	if level >= Config.Level.Max then total += rift.LvGold or 0 end
	return total
end

local function spent(stats)
	local sum = 0
	for _, key in ipairs(LS.Order) do sum += stats[key] end
	return sum
end

local function apply(player, announce)
	local stats, rift = statsOf(player)
	if not stats then return end
	local total = totalPoints(player, rift)
	if spent(stats) > total then -- 환생 등으로 레벨이 내려가 포인트가 모자라면 처음부터 다시 배분하게 한다
		for _, key in ipairs(LS.Order) do stats[key] = 0 end
	end
	for _, key in ipairs(LS.Order) do
		player:SetAttribute("LvPts_" .. key, stats[key])
	end
	player:SetAttribute("LvMove", Config.LevelStatValue("Move", stats.Move))
	player:SetAttribute("LvRange", Config.LevelStatValue("Range", stats.Range))
	player:SetAttribute("LvDouble", Config.LevelStatValue("Double", stats.Double))
	player:SetAttribute("LvHaste", math.min(0.5, Config.LevelStatValue("Haste", stats.Haste)))
	player:SetAttribute("LvCritDmg", Config.LevelStatValue("CritDmg", stats.CritDmg))
	local left = total - spent(stats)
	player:SetAttribute("LvPointsLeft", left)
	player:SetAttribute("LvTotal", total)
	player:SetAttribute("LvGoldBought", rift.LvGold or 0)
	player:SetAttribute("LvGoldCost", (rift.LvGold or 0) < LS.MaxGoldPoints and Config.GetLevelGoldPointCost(rift.LvGold or 0) or 0)
	if announce and lastPoints[player] and total > lastPoints[player] then
		Remotes.Notify:FireClient(player, string.format("✨ 스탯 포인트 +%d! 안 쓴 포인트 %d개 (T 키로 이동속도 / 사정거리 / 더블샷을 올려요)", total - lastPoints[player], left))
	end
	lastPoints[player] = total
end

-- 저장된 데이터가 적용된 뒤(Meta.Load 후) 호출
function LevelStat.Refresh(player)
	apply(player, false)
	if not watching[player] then
		watching[player] = true
		player:GetAttributeChangedSignal("Level"):Connect(function() apply(player, true) end)
	end
end

function LevelStat.Forget(player)
	watching[player] = nil
	lastPoints[player] = nil
end

Remotes.LevelStat.OnServerEvent:Connect(function(player, action, key, amount)
	local stats, rift = statsOf(player)
	if not stats then return end
	if action == "Buy" then -- 최대 레벨을 찍은 뒤 골드로 포인트 구매 (비용은 살수록 커진다)
		if (player:GetAttribute("Level") or 1) < Config.Level.Max then
			Remotes.Notify:FireClient(player, string.format("레벨 %d 을 찍으면 골드로 포인트를 살 수 있어요.", Config.Level.Max))
		elseif rift.LvGold >= LS.MaxGoldPoints then
			Remotes.Notify:FireClient(player, "골드로 살 수 있는 포인트를 모두 샀어요!")
		else
			local cost = Config.GetLevelGoldPointCost(rift.LvGold)
			local gold = player:GetAttribute("Gold") or 0
			if gold < cost then
				Remotes.Notify:FireClient(player, string.format("골드가 부족해요 (필요 %d G)", cost))
			else
				player:SetAttribute("Gold", gold - cost)
				rift.LvGold += 1
				Remotes.Notify:FireClient(player, string.format("💰 스탯 포인트 +1 구매! (%d / %d)", rift.LvGold, LS.MaxGoldPoints))
			end
		end
	elseif action == "Reset" then
		for _, k in ipairs(LS.Order) do stats[k] = 0 end
	elseif (action == "Add" or action == "Sub") and typeof(key) == "string" and LS[key] and table.find(LS.Order, key) then
		amount = typeof(amount) == "number" and math.clamp(math.floor(amount), 1, 99) or 1
		if action == "Add" then
			local left = totalPoints(player, rift) - spent(stats)
			local gained = math.min(amount, math.max(0, left), LS.Cap[key] - stats[key]) -- 한 스탯의 한계를 넘지 않는다
			stats[key] += gained
			if gained > 0 then
				local okQ, Quest = pcall(function() return require(script.Parent:WaitForChild("QuestService")) end)
				if okQ then Quest.Add(player, "StatPoints", gained) end -- 첫날 퀘스트 "스탯 찍기"
			end
		else
			stats[key] = math.max(0, stats[key] - amount)
		end
	end
	apply(player, false)
end)

return LevelStat
