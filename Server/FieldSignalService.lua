-- FieldSignalService (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldSignalService)
-- 필드 2축 신호의 서버 쪽: 8구역 몬스터 고정값을 서버 시작 때 한 번 계산해 ReplicatedStorage.FieldSignal 폴더의 Attribute 로 올린다.
--   이름: Z<구역>_MobHp / _MobHit (일반, ZonePools 가중평균) · _EliteHp / _EliteHit · _LordHp / _LordHit (구역마다 6개)
--   계산식은 FieldService.spawnMonster 와 같다: Config.Monster.GetStats -> MonsterTypes.ApplyDef -> Horde.Health(일반) / EliteMultiplier(엘리트)
--   -> ZoneDanger.Health x EarlyMobHealth, ZoneDanger.Damage x MobDamageMult x SniperDamage. 군주 = 레벨 +3, 체력 x60 x (LordHealth 또는 Health)
--   구역 몬스터 레벨은 구역마다 고정(Config.Field.GetZoneLevel)이라 플레이어와 상관없는 상수다: 다시 보낼 일이 없다.
-- 플레이어 쪽 합성(내 DPS / 최대 체력 / 받는 피해 배율)은 Shared/FieldSignal.lua. 서버에서 쓸 때는 DPS 를 DamageMeter.RecentDps 로 넣어 준다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local MonsterTypes = require(script.Parent:WaitForChild("MonsterTypes"))
local Meter = require(script.Parent:WaitForChild("DamageMeter"))
local Signal = require(ReplicatedStorage:WaitForChild("FieldSignal"))

local FieldSignalService = {}
local F = Config.Field

-- spawnMonster 의 일반 / 엘리트 몬스터 한 마리 (구역 난이도 배율까지)
local function mobStats(zone, typeKey, elite)
	local level = F.GetZoneLevel(zone)
	local stats = Config.Monster.GetStats(elite and level + 2 or level)
	MonsterTypes.ApplyDef(typeKey, stats)
	if elite then
		stats.MaxHealth = math.floor(stats.MaxHealth * F.EliteMultiplier)
	else
		stats.MaxHealth = math.max(1, math.floor(stats.MaxHealth * Config.Horde.Health))
	end
	local danger = F.ZoneDanger
	stats.MaxHealth = math.max(1, math.floor(stats.MaxHealth * danger.Health[zone] * (F.EarlyMobHealth[zone] or 1)))
	stats.ShotDamage = math.max(1, math.floor(stats.ShotDamage * danger.Damage[zone] * (F.MobDamageMult or 1)
		* ((F.SniperTypes and F.SniperTypes[typeKey] and F.SniperDamage and F.SniperDamage[zone]) or 1)))
	return stats.MaxHealth, stats.ShotDamage
end

-- 구역 평균 (ZonePools 가중평균)
local function poolAverage(zone, elite)
	local hp, hit, total = 0, 0, 0
	for typeKey, weight in pairs(F.ZonePools[zone] or {}) do
		if MonsterTypes.Defs[typeKey] then
			local h, d = mobStats(zone, typeKey, elite)
			hp += h * weight
			hit += d * weight
			total += weight
		end
	end
	if total <= 0 then return 0, 0 end
	return math.floor(hp / total + 0.5), math.floor(hit / total + 0.5)
end

local function lordStats(zone)
	local base = Config.Monster.GetStats(F.GetZoneLevel(zone) + 3)
	local danger = F.ZoneDanger
	local hp = math.floor(base.MaxHealth * 60 * ((danger.LordHealth and danger.LordHealth[zone]) or danger.Health[zone]))
	local shot = math.max(10, math.floor(base.ShotDamage * (zone >= 7 and 1.3 or 1.5) * danger.Damage[zone]))
	-- 군주 탄은 3갈래로 나가는데 한 발당 피해가 1.2배다 (FieldService 의 fireProjectile 호출과 같은 식. 1구역 튜토리얼 군주는 1배)
	local hit = math.floor(shot * (zone == 1 and 1 or 1.2))
	return hp, hit
end

do -- 서버 시작 때 한 번
	local folder = ReplicatedStorage:FindFirstChild("FieldSignal") or Instance.new("Folder")
	folder.Name = "FieldSignal"
	for zone = 1, F.ZoneCount do
		local mobHp, mobHit = poolAverage(zone, false)
		local eliteHp, eliteHit = poolAverage(zone, true)
		local lordHp, lordHit = lordStats(zone)
		folder:SetAttribute(("Z%d_MobHp"):format(zone), mobHp)
		folder:SetAttribute(("Z%d_MobHit"):format(zone), mobHit)
		folder:SetAttribute(("Z%d_EliteHp"):format(zone), eliteHp)
		folder:SetAttribute(("Z%d_EliteHit"):format(zone), eliteHit)
		folder:SetAttribute(("Z%d_LordHp"):format(zone), lordHp)
		folder:SetAttribute(("Z%d_LordHit"):format(zone), lordHit)
	end
	folder.Parent = ReplicatedStorage
end

-- 서버에서 FieldSignal 을 쓸 때의 DPS: 대미지 미터 최근 10초 (0 이면 nil -> FieldSignal 이 전투력 x 0.26 으로 대신)
Signal.ServerDps = function(player)
	local dps = Meter.RecentDps(player)
	return dps > 0 and dps or nil
end

function FieldSignalService.LordSec(player, zone) return Signal.KillSec(zone, "Lord", player) end
function FieldSignalService.HitPct(player, zone, kind) return Signal.HitPct(zone, kind or "Lord", player) end

-- 군주를 만났을 때 경고 (FieldService 가 90초 쿨로 부른다): 한 방 35% 이상이면 생존(방어 · 체력), 아니고 60초 이상이면 화력(무기 · 세트)
--   돌려주는 값: 제목 글자, 아이콘 키 (경고가 필요 없으면 nil)
function FieldSignalService.LordWarn(player, zone)
	local hit = Signal.HitPct(zone, "Lord", player)
	if hit and hit >= Signal.HitTiers[2] then
		return string.format("⚠ This lord hits for %d%% of your HP — add a defense effect (Y) or HP training", math.floor(hit + 0.5)), "🛡"
	end
	local sec = Signal.KillSec(zone, "Lord", player)
	if sec and sec >= Signal.Times.Lord[3] then
		return string.format("⚠ This lord would take ~%ds — upgrade your weapon or set effect", math.floor(sec + 0.5)), "⚒"
	end
	return nil
end

return FieldSignalService
