-- FieldSignal (ReplicatedStorage 안의 ModuleScript, 이름: FieldSignal)
-- 필드 2축 신호 (11-19): 권장 전투력 대신 "내가 이 몹을 몇 초에 잡나(화력)" + "한 방에 내 체력의 몇 %가 깎이나(생존)".
--   구역 고정값은 서버(FieldSignalService)가 ReplicatedStorage.FieldSignal 폴더 Attribute 로 올린다: Z<구역>_MobHp / MobHit / EliteHp / EliteHit / LordHp / LordHit
--   내 값과 합성한다:
--     * DPS: 클라이언트는 대미지 미터(Attribute DmgMeter 의 Dps)를 1초마다 읽어 최근 25개(공격 중인 초만)의 평균. 공격이 없으면 마지막 값 유지.
--       서버는 FieldSignal.ServerDps(player) (FieldSignalService 가 DamageMeter.RecentDps 로 채운다). 둘 다 없으면 전투력 x 0.26 (실측 앵커)
--     * 최대 체력: Humanoid.MaxHealth · 받는 피해 배율: Attribute TakenMult (DamageGuard 가 1초마다)
--   색 기준: 처치 시간(일반 0.5 / 3 / 8초, 엘리트 1.5 / 9 / 25초, 군주 10 / 30 / 60초 -> 회색 / 흰 / 주황 / 빨강) + 한 방 %(15% / 35%, 모든 등급) 중 나쁜 쪽
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local FieldSignal = {}
FieldSignal.Times = { Normal = { 0.5, 3, 8 }, Elite = { 1.5, 9, 25 }, Lord = { 10, 30, 60 } }
FieldSignal.HitTiers = { 15, 35 }
FieldSignal.PowerToDps = 0.26 -- (DPS 기록이 없을 때: 실측 실딜 / 전투력)
FieldSignal.Colors = { -- [심각도 0~3]
	[0] = Color3.fromRGB(165, 168, 180), -- 회색: 훨씬 강하다
	[1] = Color3.new(1, 1, 1),           -- 흰색: 적당
	[2] = Color3.fromRGB(255, 185, 100), -- 주황: 버겁다
	[3] = Color3.fromRGB(255, 105, 105), -- 빨강: 위험
}
FieldSignal.ServerDps = nil -- (서버 전용: FieldSignalService 가 넣는다)

local KIND = { Normal = "Mob", Mob = "Mob", Elite = "Elite", Lord = "Lord", Boss = "Lord" }
local function timeKind(kind) return (kind == "Boss" or kind == "Lord") and "Lord" or (kind == "Elite" and "Elite" or "Normal") end

-- 구역 고정값 (없으면 nil: 서버가 아직 안 올렸다)
function FieldSignal.Base(zone, kind)
	local folder = ReplicatedStorage:FindFirstChild("FieldSignal")
	local key = KIND[kind or "Mob"]
	if not folder or not key then return nil end
	return folder:GetAttribute(("Z%d_%sHp"):format(zone, key)), folder:GetAttribute(("Z%d_%sHit"):format(zone, key))
end

-- 클라이언트: 내 DPS 이동 평균 (최근 25초 중 공격한 초만)
local samples, sampleAt = {}, 1
if RunService:IsClient() then
	task.spawn(function()
		local me = Players.LocalPlayer
		while true do
			task.wait(1)
			local raw = me and me:GetAttribute("DmgMeter")
			if typeof(raw) == "string" then
				local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
				local dps = ok and typeof(data) == "table" and tonumber(data.Dps) or 0
				if dps and dps > 0 then
					samples[sampleAt] = dps
					sampleAt = sampleAt % 25 + 1
				end
			end
		end
	end)
end

function FieldSignal.Dps(player)
	player = player or Players.LocalPlayer
	if not player then return nil end
	local dps
	if RunService:IsClient() and player == Players.LocalPlayer then
		if #samples > 0 then
			local sum = 0
			for _, v in ipairs(samples) do sum += v end
			dps = sum / #samples
		end
	elseif FieldSignal.ServerDps then
		dps = FieldSignal.ServerDps(player)
	end
	if not dps or dps <= 0 then
		local power = player:GetAttribute("Power") or 0
		dps = power > 0 and power * FieldSignal.PowerToDps or nil
	end
	return dps
end

function FieldSignal.KillSecFor(hp, player)
	local dps = FieldSignal.Dps(player)
	if not hp or not dps or dps <= 0 then return nil end
	return hp / dps
end

function FieldSignal.HitPctFor(hit, player)
	player = player or Players.LocalPlayer
	local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local maxHp = humanoid and humanoid.MaxHealth or 0
	if not hit or maxHp <= 0 then return nil end
	return hit * (player:GetAttribute("TakenMult") or 1) / maxHp * 100
end

function FieldSignal.KillSec(zone, kind, player)
	local hp = FieldSignal.Base(zone, kind)
	return FieldSignal.KillSecFor(hp, player)
end

function FieldSignal.HitPct(zone, kind, player)
	local _, hit = FieldSignal.Base(zone, kind)
	return FieldSignal.HitPctFor(hit, player)
end

-- 처치 시간 단계 0~3 (회색 / 흰 / 주황 / 빨강) · 한 방 단계 0~2 (안전 / 주의 / 위험)
function FieldSignal.TimeTier(kind, sec)
	if not sec then return 1 end
	local t = FieldSignal.Times[timeKind(kind)]
	if sec < t[1] then return 0 elseif sec <= t[2] then return 1 elseif sec <= t[3] then return 2 end
	return 3
end
function FieldSignal.HitTier(pct)
	if not pct then return 0 end
	local h = FieldSignal.HitTiers
	if pct < h[1] then return 0 elseif pct <= h[2] then return 1 end
	return 2
end
-- 두 축 중 나쁜 쪽 심각도 (한 방 주의 = 주황, 위험 = 빨강)
function FieldSignal.Severity(timeTier, hitTier)
	local hitSeverity = hitTier == 2 and 3 or (hitTier == 1 and 2 or 0)
	return math.max(timeTier, hitSeverity)
end
function FieldSignal.Color(kind, sec, pct)
	return FieldSignal.Colors[FieldSignal.Severity(FieldSignal.TimeTier(kind, sec), FieldSignal.HitTier(pct))]
end

-- "⏱ ~%ds · 💥 %d%% HP" 에 넣을 숫자 (없으면 nil)
function FieldSignal.Pair(zone, kind, player)
	local sec, pct = FieldSignal.KillSec(zone, kind, player), FieldSignal.HitPct(zone, kind, player)
	if not sec or not pct then return nil end
	return math.max(1, math.floor(sec + 0.5)), math.floor(pct + 0.5)
end

return FieldSignal
