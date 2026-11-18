-- DepthPace (ServerScriptService > Modules 안의 ModuleScript, 이름: DepthPace)
-- 던전 보스 처치 속도 기록: 버티기 던전에서 보스를 잡으면 "깊이 · 전투력 · 보스 처치 시간"을 저장하고 Studio Output 에 찍는다.
--   * 저장: MetaService.PaceRecord (가장 최근 클리어로 덮어쓴다) -> Attribute PaceDepth / PaceSecs / PacePower
--   * 시간은 혼자 기준으로 환산한다 (파티는 보스 체력이 Config.Dungeon.GetHealthScale(인원) 배이고 인원만큼 같이 때린다)
--   * 깊이 창의 예상 시간은 Config.Dungeon.PaceEstimate 가 이 기록으로 계산한다 (시안: Docs/preview/depth-pace-preview.svg)
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local DepthPace = {}

-- run: 버티기 던전 판 (BossAt = 보스가 나타난 시각, Boss = 보스 data). 보스를 잡은 순간 부른다
function DepthPace.Record(run)
	if not run or not run.BossAt or run.Tutorial or run.RiftMode or run.Fever or run.Tower then return end
	local D = Config.Dungeon
	local depth = D.DepthOf(run.DiffKey)
	if not depth then return end
	local secs = os.clock() - run.BossAt
	local members = {}
	for _, member in ipairs(run.Members or {}) do
		if member.Parent then table.insert(members, member) end
	end
	local n = math.max(1, #run.Members)
	local solo = secs * n / D.GetHealthScale(n) -- (혼자였다면 걸렸을 시간)
	solo = solo * (D.PaceScaleRef or 1) / math.max(0.1, run.BossHealthScale or D.PaceScaleRef or 1) -- (그 판의 보스 체력 배율(보너스 횟수 / 패널티)을 기준 배율로 환산)
	local hp = run.Boss and run.Boss.MaxHealth or 0
	local okMeta, Meta = pcall(function() return require(script.Parent:WaitForChild("MetaService")) end)
	for _, member in ipairs(members) do
		local power = member:GetAttribute("Power") or 0
		if okMeta then Meta.PaceRecord(member, depth, solo, power) end
		if RunService:IsStudio() then
			print(string.format("[던전 기록] %s · 깊이 %d · 전투력 %d · 파티 %d명 · 보스 처치 %.1f초 (혼자 기준 %.1f초 / 제한 %s초) · 보스 체력 %d · 보스 DPS %d · 다음 깊이 예상 %.1f초",
				member.Name, depth, power, n, secs, solo, tostring(D.BossTimeLimit or "-"), hp, secs > 0 and math.floor(hp / secs) or 0,
				D.PaceEstimate(depth + 1, depth, solo, power, power) or 0))
		end
	end
end

-- 보스 시간 초과 (DungeonService 가 한 줄로 부른다): 보스 처치 골드의 TimeoutGoldRatio 만 주고 알린다 + 진단 한 줄 (B안 판단용)
function DepthPace.Timeout(run, giveGold)
	local D = Config.Dungeon
	local ratio = D.TimeoutGoldRatio or 0
	if ratio > 0 and giveGold then giveGold(run, (D.VictoryGold or 0) * ratio) end
	local text = string.format("⏰ Time's up! The boss escaped — you got %d%% of the clear gold (no chest, tickets or depth record)", math.floor(ratio * 100 + 0.5))
	local okR, Remotes = pcall(function() return require(ReplicatedStorage:WaitForChild("Remotes")) end)
	for _, member in ipairs(run.Members or {}) do
		if okR then Remotes.Notify:FireClient(member, text) end
		if RunService:IsStudio() then
			local depth = D.DepthOf(run.DiffKey) or 0
			local boss = run.Boss
			local power = member:GetAttribute("Power") or 0
			local est = D.PaceEstimate(depth, member:GetAttribute("PaceDepth"), member:GetAttribute("PaceSecs"), member:GetAttribute("PacePower"), power)
			print(string.format("[던전 시간초과] %s · 깊이 %d · 전투력 %d · 보스 최대 체력 %d · 보스 남은 체력 %d%% · 경과 %.1f초 · 예상 %s초",
				member.Name, depth, power, boss and boss.MaxHealth or 0, boss and boss.MaxHealth > 0 and math.floor(math.max(0, boss.Health) / boss.MaxHealth * 100 + 0.5) or 0,
				run.BossAt and os.clock() - run.BossAt or 0, est and string.format("%.1f", est) or "-"))
		end
	end
end

return DepthPace
