-- BalanceLog (ServerScriptService > Modules 안의 ModuleScript, 이름: BalanceLog)
-- Studio 전용 밸런스 로그: 1분마다 한 사람당 한 덩어리로 출력창에 찍는다. 게임 서버(실제 서비스)에서는 아무것도 안 한다.
--   피해: 기본 공격 / 치명타 / 스플래시 / 데드아이 / 스킬 / 세트·펫 별 합계와 비율
--   처치: 종류별 마릿수, 골드(처치 / 방치 / 기타), 경험치, 받은 피해 / 사망, NEAR MISS, 스킬 사용 횟수, 평균 체력 / 스택
-- 다른 서비스가 BL.Dmg / BL.Kill / BL.Gold / BL.Xp / BL.Count 를 부르고, 피해 종류는 BL.Ctx 로 구분한다(스킬 / 데드아이 / 세트·펫이 잠깐 켠다).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local STUDIO = RunService:IsStudio()
local BL = { Ctx = nil }

local data = setmetatable({}, { __mode = "k" })

local function fresh()
	return {
		Since = os.clock(), Dmg = {}, Hits = {}, Total = 0, CritDmg = 0, CritHits = 0, BasicHits = 0,
		Kills = {}, GoldIn = 0, GoldOut = 0, Gold = {}, Xp = 0, Taken = 0, TakenHits = 0, Deaths = 0, Counts = {},
		Seconds = { Field = 0, Dungeon = 0, Lobby = 0 }, HpSum = 0, StackSum = 0, UltSum = 0, Samples = 0,
	}
end

local function bucket(player)
	local b = data[player]
	if not b then b = fresh() data[player] = b end
	return b
end

local function addDmg(player, source, amount, isCrit)
	if not STUDIO or not player or amount <= 0 then return end
	local b = bucket(player)
	b.Dmg[source] = (b.Dmg[source] or 0) + amount
	b.Hits[source] = (b.Hits[source] or 0) + 1
	b.Total += amount
	if source == "Basic" then
		b.BasicHits += 1
		if isCrit then
			b.CritDmg += amount
			b.CritHits += 1
		end
	end
end

-- 피해: BL.Ctx(스킬 / 데드아이 / 세트·펫)가 켜져 있으면 그 종류, 아니면 기본 공격
function BL.Dmg(player, amount, isCrit)
	addDmg(player, BL.Ctx or "Basic", amount, isCrit)
end

function BL.DmgAs(player, source, amount)
	addDmg(player, source, amount, false)
end

function BL.Kill(player, kind)
	if not STUDIO or not player then return end
	local b = bucket(player)
	b.Kills[kind] = (b.Kills[kind] or 0) + 1
end

function BL.Gold(player, source, amount)
	if not STUDIO or not player or amount <= 0 then return end
	local b = bucket(player)
	b.Gold[source] = (b.Gold[source] or 0) + amount
end

function BL.Xp(player, amount)
	if not STUDIO or not player then return end
	bucket(player).Xp += amount
end

function BL.Count(player, key, n)
	if not STUDIO or not player then return end
	local b = bucket(player)
	b.Counts[key] = (b.Counts[key] or 0) + (n or 1)
end

local function track(player)
	if not STUDIO then return end
	local last = player:GetAttribute("Gold") or 0
	player:GetAttributeChangedSignal("Gold"):Connect(function()
		local now = player:GetAttribute("Gold") or 0
		local b = bucket(player)
		if now > last then b.GoldIn += now - last else b.GoldOut += last - now end
		last = now
	end)
	local function watch(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		local lastHealth = humanoid.Health
		humanoid.HealthChanged:Connect(function(health)
			if health < lastHealth - 0.01 then
				local b = bucket(player)
				b.Taken += lastHealth - health
				b.TakenHits += 1
			end
			lastHealth = health
		end)
		humanoid.Died:Connect(function() bucket(player).Deaths += 1 end)
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then task.spawn(watch, player.Character) end
end

local function pct(part, whole)
	return whole > 0 and math.floor(part / whole * 100 + 0.5) or 0
end

local SOURCE_ORDER = { "Basic", "스플래시", "데드아이", "스킬", "세트·펫" }
local KILL_ORDER = { "Normal", "Elite", "Boss", "Event", "Goblin", "던전" }
local KILL_NAMES = { Normal = "Normal", Elite = "Elite", Boss = "Lord", Event = "Titan", Goblin = "Goblin", ["던전"] = "Dungeon" }
local SOURCE_NAMES = { ["스플래시"] = "Splash", ["데드아이"] = "Dead Eye", ["스킬"] = "Skill", ["세트·펫"] = "Set/Pet" } -- (키는 다른 파일이 쓰는 값이라 그대로 둔다)

local function report(player, b)
	local seconds = math.max(1, os.clock() - b.Since)
	local parts = {}
	for _, source in ipairs(SOURCE_ORDER) do
		local value = b.Dmg[source]
		if value then
			local extra = ""
			if source == "Basic" and b.BasicHits > 0 then
				extra = string.format(" (crit %d%% · avg %d)", pct(b.CritDmg, value), math.floor(value / b.BasicHits))
			elseif b.Hits[source] and b.Hits[source] > 0 then
				extra = string.format(" (%dx · avg %d)", b.Hits[source], math.floor(value / b.Hits[source]))
			end
			table.insert(parts, string.format("%s %d%% %d%s", SOURCE_NAMES[source] or source, pct(value, b.Total), value, extra))
		end
	end
	local kills, killTotal = {}, 0
	for _, key in ipairs(KILL_ORDER) do
		if b.Kills[key] then
			killTotal += b.Kills[key]
			table.insert(kills, string.format("%s %d", KILL_NAMES[key] or key, b.Kills[key]))
		end
	end
	local known = 0
	local goldParts = {}
	for key, value in pairs(b.Gold) do
		known += value
		table.insert(goldParts, string.format("%s %d", key, value))
	end
	table.insert(goldParts, string.format("Other %d", math.max(0, b.GoldIn - known)))
	local samples = math.max(1, b.Samples)
	local lines = {
		string.format("[Balance %ds] %s · Level %d · Power %d · Weapon Lv.%d · Best field zone %d · Time in Field %ds / Dungeon %ds / Town %ds",
			math.floor(seconds), player.Name, player:GetAttribute("Level") or 1, player:GetAttribute("Power") or 0, player:GetAttribute("WeaponLevel") or 0,
			player:GetAttribute("MaxZone") or 0, b.Seconds.Field, b.Seconds.Dungeon, b.Seconds.Lobby),
		string.format("  Total damage %d (%d/s) | %s", b.Total, math.floor(b.Total / seconds), #parts > 0 and table.concat(parts, " | ") or "none"),
		string.format("  Kills %d (%d/min) | %s", killTotal, math.floor(killTotal / seconds * 60), #kills > 0 and table.concat(kills, " · ") or "none"),
		string.format("  Gold +%d / -%d (+%d/min) | %s | XP +%d", b.GoldIn, b.GoldOut, math.floor(b.GoldIn / seconds * 60), table.concat(goldParts, " · "), b.Xp),
		string.format("  Damage taken %d (%dx) · Deaths %d · Avg HP %d%% · NEAR MISS %dx · Avg stacks %.1f · Avg ult gauge %d%% · Ults %dx · Skills %dx",
			math.floor(b.Taken), b.TakenHits, b.Deaths, math.floor(b.HpSum / samples * 100), b.Counts.NearMiss or 0, b.StackSum / samples,
			math.floor(b.UltSum / samples * 100), b.Counts.Ult or 0, (b.Counts.Heal or 0) + (b.Counts.Dash or 0)),
	}
	print(table.concat(lines, "\n"))
end

if STUDIO then
	for _, player in ipairs(Players:GetPlayers()) do track(player) end
	Players.PlayerAdded:Connect(track)
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(5)
			tick += 1
			for _, player in ipairs(Players:GetPlayers()) do
				local b = bucket(player)
				local zone = player:GetAttribute("Zone") or "Lobby"
				b.Seconds[zone] = (b.Seconds[zone] or 0) + 5
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				b.HpSum += humanoid and humanoid.Health / math.max(1, humanoid.MaxHealth) or 0
				b.StackSum += player:GetAttribute("NearMissStacks") or 0
				b.UltSum += math.min(1, (player:GetAttribute("UltCharge") or 0) / math.max(1, Config.Skills.Ult.Cost))
				b.Samples += 1
				if tick % 12 == 0 then
					if b.Seconds.Field + b.Seconds.Dungeon > 0 then report(player, b) end
					data[player] = fresh()
				end
			end
		end
	end)
end

return BL
