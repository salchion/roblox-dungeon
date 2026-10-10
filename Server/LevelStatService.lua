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
		rift.LvStats[key] = rift.LvStats[key] or 0
	end
	return rift.LvStats
end

local function spent(stats)
	local sum = 0
	for _, key in ipairs(LS.Order) do sum += stats[key] end
	return sum
end

local function apply(player, announce)
	local stats = statsOf(player)
	if not stats then return end
	local total = Config.GetLevelStatPoints(player:GetAttribute("Level") or 1)
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
	local stats = statsOf(player)
	if not stats then return end
	if action == "Reset" then
		for _, k in ipairs(LS.Order) do stats[k] = 0 end
	elseif (action == "Add" or action == "Sub") and typeof(key) == "string" and LS[key] and table.find(LS.Order, key) then
		amount = typeof(amount) == "number" and math.clamp(math.floor(amount), 1, 99) or 1
		if action == "Add" then
			local left = Config.GetLevelStatPoints(player:GetAttribute("Level") or 1) - spent(stats)
			local gained = math.min(amount, math.max(0, left))
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
