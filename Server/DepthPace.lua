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

return DepthPace
