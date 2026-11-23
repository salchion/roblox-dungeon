-- DungeonRushGimmicks (ServerScriptService > Modules 안의 ModuleScript, 이름: DungeonRushGimmicks)
-- 보스러쉬 전용 기믹 (보스가 쌓일수록 경기장이 험해진다)
--   * 경기장 축소: 5번째 보스부터 바깥 고리가 붉게 물들며 조금씩 좁아진다 (밖에 서 있으면 0.5초마다 Config.Rift.RingDamage = 45 고정 피해)
--   * 합동 공격: 보스가 둘 이상이면 22초마다 두 보스가 동시에 (바닥 줄 + 메테오)
--   * 거울 탄막: 12초마다 내 주변 원에서 탄이 한꺼번에 안쪽으로 몰려온다 (보스 3마리 이상)
--   * 시간 압박: 30초 넘게 살아 있는 보스는 격노한다 (빨리 잡으라는 신호)
--   DungeonService.lua 가 크기 한도(200,000자)에 닿아 따로 뺐다 (11-19 분할). 함수 몸통은 그대로 옮겼다.
--   DungeonService 의 지역 값 / 함수는 Make(ctx) 로 받는다: ctx 키 = 원래 이름 그대로 (Config / Guard / getAliveParts / BOSS_PATTERNS / shockRing / fireProjectile)
local M = {}

function M.Make(ctx)
local Config, Guard, getAliveParts, BOSS_PATTERNS, shockRing, fireProjectile = ctx.Config, ctx.Guard, ctx.getAliveParts, ctx.BOSS_PATTERNS, ctx.shockRing, ctx.fireProjectile

local RUSH_RING_SEGMENTS = 32
local function rushGimmicks(run)
	local R = Config.Rift
	local center = run.ArenaCenter or (run.Origin + Vector3.new(140, 0, 0))
	local outer = 110
	local safeR = outer
	local band = {}
	local nextShrink, nextJoint, nextMirror, nextTick = 0, os.clock() + 22, os.clock() + 12, 0
	local function bossesAlive()
		local list = {}
		for part, data in pairs(run.Monsters) do
			if data.IsBoss and part.Parent and data.Health > 0 then table.insert(list, { Part = part, Data = data }) end
		end
		return list
	end
	local function drawBand()
		if #band == 0 then
			for i = 1, RUSH_RING_SEGMENTS do
				local seg = Instance.new("Part")
				seg.Name = "RushHazard"
				seg.Anchored, seg.CanCollide, seg.CanQuery, seg.CanTouch, seg.CastShadow = true, false, false, false, false
				seg.Material = Enum.Material.Neon
				seg.Color = Color3.fromRGB(150, 30, 40)
				seg.Transparency = 0.72
				seg.Parent = run.Folder
				band[i] = seg
			end
		end
		local width = outer - safeR
		local mid = safeR + width / 2
		for i, seg in ipairs(band) do
			local angle = (i - 0.5) / RUSH_RING_SEGMENTS * math.pi * 2
			local pos = center + Vector3.new(math.cos(angle) * mid, 0.35, math.sin(angle) * mid)
			seg.Size = Vector3.new(2 * math.pi * mid / RUSH_RING_SEGMENTS + 0.6, 0.15, math.max(0.5, width))
			seg.CFrame = CFrame.lookAt(pos, center + Vector3.new(0, 0.35, 0))
		end
	end
	while not run.Destroyed and run.Phase ~= "Ended" do
		local now = os.clock()
		local index = run.RushSpawned or 0
		local damage = math.floor(R.DamageBase * math.min(R.DamageGrowCap, R.DamageGrow ^ math.max(index - 1, 0)))
		-- 경기장 축소
		if index >= 5 and now >= nextShrink and safeR > 64 then
			nextShrink = now + 20
			safeR = math.max(64, safeR - 7)
			drawBand()
			if safeR <= outer - 7 and safeR > outer - 8 then
			end
		end
		if safeR < outer and now >= nextTick then
			nextTick = now + 0.5
			for _, member in ipairs(run.Members) do
				local root, humanoid = getAliveParts(member)
				if root and humanoid then
					local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
					if flat.Magnitude > safeR then Guard.Take(humanoid, R.RingDamage or 45) end -- (5구역 적정 체력 866의 약 5%: 내 최대 체력 비례가 아니라 고정값)
				end
			end
		end
		-- 합동 공격
		if now >= nextJoint then
			nextJoint = now + 22
			local list = bossesAlive()
			if #list >= 2 then
				local a = table.remove(list, math.random(#list))
				local b = table.remove(list, math.random(#list))
				for _, pair in ipairs({ { a, BOSS_PATTERNS.Lanes or BOSS_PATTERNS.Fan }, { b, BOSS_PATTERNS.Meteor or BOSS_PATTERNS.Ring } }) do
					local entry, fn = pair[1], pair[2]
					if not entry.Data.Casting then
						entry.Data.Casting = true
						task.spawn(function()
							pcall(fn, run, entry.Part, entry.Data)
							entry.Data.Casting = false
							entry.Data.NextPattern = os.clock() + 2
						end)
					end
				end
			end
		end
		-- 거울 탄막
		if now >= nextMirror then
			nextMirror = now + 12
			if #bossesAlive() >= 3 then
				for _, member in ipairs(run.Members) do
					local root = getAliveParts(member)
					if root then
						local at = root.Position
						shockRing(run, Vector3.new(at.X, at.Y - 2.5, at.Z), 46, Color3.fromRGB(200, 80, 160))
						task.delay(0.9, function()
							if run.Destroyed or run.Phase == "Ended" then return end
							for k = 0, 11 do
								local angle = k / 12 * math.pi * 2
								local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
								fireProjectile(run, at + dir * 46, -dir, 26, math.floor(damage * 0.7), 2.4, Color3.fromRGB(210, 110, 200), "Crystal")
							end
						end)
					end
				end
			end
		end
		-- 시간 압박
		for _, entry in ipairs(bossesAlive()) do
			local data = entry.Data
			if not data.Enraged and data.BornAt and now - data.BornAt > 30 then
				data.Enraged = true
				data.BaseColor = Color3.fromRGB(255, 60, 20)
				entry.Part.Color = data.BaseColor
			end
		end
		task.wait(0.25)
	end
	for _, seg in ipairs(band) do seg:Destroy() end
end

return rushGimmicks
end

return M
