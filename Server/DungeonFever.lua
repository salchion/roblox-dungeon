-- DungeonFever (ServerScriptService > Modules 안의 ModuleScript, 이름: DungeonFever)
-- 피버 타임: 60초 동안 약한 몬스터가 사방 문에서 쏟아진다. 12초마다 이벤트(골드 러시 / 보물 비). 끝나면 결과 카드 후 필드의 원래 자리로 돌아간다.
--   DungeonService.lua 가 크기 한도(200,000자)에 닿아 따로 뺐다 (11-19 분할). 함수 몸통은 그대로 옮겼다.
--   DungeonService 의 지역 값 / 함수는 Make(ctx) 로 받는다 (require 순서가 꼬이지 않게 서비스 모듈도 ctx 로): ctx 키 = 원래 이름 그대로
local M = {}

function M.Make(ctx)
local Config, D, SoundBank, Loot, Remotes, Quest, Effects, broadcast, playerRun, resetStats, pivotTo, destroyRun, startAugLoop, waitFor, allDown, nearSpawnPoints, spawnMonster, notifyAll, giveGold, getAliveParts =
	ctx.Config, ctx.D, ctx.SoundBank, ctx.Loot, ctx.Remotes, ctx.Quest, ctx.Effects, ctx.broadcast, ctx.playerRun, ctx.resetStats, ctx.pivotTo, ctx.destroyRun, ctx.startAugLoop, ctx.waitFor, ctx.allDown, ctx.nearSpawnPoints, ctx.spawnMonster, ctx.notifyAll, ctx.giveGold, ctx.getAliveParts

local function feverFinish(run)
	if run.Phase == "Ended" then return end
	run.Phase = "Ended"
	run.PhaseEnd, run.SurviveEnd = nil, nil
	for part in pairs(run.Monsters) do part:Destroy() end
	run.Monsters = {}
	run.MonsterCount = 0
	for _, projectile in ipairs(run.Projectiles) do projectile.Part:Destroy() end
	run.Projectiles = {}
	local fever = run.Fever
	local F = Config.Fever
	for _, member in ipairs(run.Members) do
		local endRoot = member.Character and member.Character:FindFirstChild("HumanoidRootPart")
		if endRoot then SoundBank.Play(endRoot, "Dungeon_Clear") end
		-- 끝 보너스: 황금 상자 장비 + 뽑기 티켓 (많이 잡을수록 더)
		local tickets = math.min(F.TicketMax or 3, 1 + math.floor(fever.Kills / (F.TicketPerKills or 60)))
		member:SetAttribute("Tickets", (member:GetAttribute("Tickets") or 0) + tickets)
		run.TicketsEarned[member] = (run.TicketsEarned[member] or 0) + tickets
		local gearCount = math.min(F.GearMax or 4, 1 + math.floor(fever.Kills / (F.GearPerKills or 50)))
		local okLoot, lines = pcall(Loot.DungeonChest, member, "Cave", run.DiffKey, gearCount)
		local gearBest = 0
		if okLoot and lines then
			for _, line in ipairs(lines) do gearBest = math.max(gearBest, line.Rarity or 0) end
		else
			gearCount = 0
		end
		Remotes.Dungeon:FireClient(member, "Result", { -- (피버 전용 황금 결과 카드는 FeverResultClient 가 그린다: Fever 가 있으면 일반 결과 카드는 뜨지 않는다)
			Victory = true, Gold = run.Earned[member] or 0, Tickets = run.TicketsEarned[member] or 0, Loot = {},
			Wave = 0, TotalWaves = 0, TypeName = "🌟 Fever Time", DifficultyName = "", ReturnDelay = F.ReturnDelay or D.ReturnDelay,
			Fever = { Kills = fever.Kills, BestCombo = fever.BestCombo, Seconds = Config.Fever.Duration, GearCount = gearCount, GearBest = gearBest },
		})
	end
	broadcast(run)
	task.delay(F.ReturnDelay or D.ReturnDelay, function()
		-- 필드의 원래 자리로 돌려보낸다 (마을이 아니라)
		for _, member in ipairs(table.clone(run.Members)) do
			playerRun[member] = nil
			if member.Parent then
				member:SetAttribute("Zone", "Field")
				resetStats(member)
				if fever.Return then pivotTo(member, fever.Return) end
			end
		end
		run.Members = {}
		destroyRun(run)
	end)
end

local function feverLoop(run)
	local F = Config.Fever
	for _, member in ipairs(run.Members) do
		local startRoot = member.Character and member.Character:FindFirstChild("HumanoidRootPart")
		if startRoot then SoundBank.Play(startRoot, "Dungeon_Start") end
		member:SetAttribute("DungeonVisual", "Gold") -- (PlayerFX 의 황금빛 조명 / 대기: 이름이 "Gold" 여야 적용된다)
		Quest.Add(member, "FeverRuns", 1) -- 업적: 피버 타임 입장 횟수
		member:SetAttribute("DungeonTypeKey", "Fever")
		Remotes.Tutorial:FireClient(member, "Prompt", { Key = "🌟", Title = "FEVER TIME!", Text = string.format("%d seconds! Rewards x%d, combo adds up to x%d!", F.Duration, F.GoldMult, F.ComboMax), Duration = 5, Top = true })
	end
	startAugLoop(run) -- 세트 효과 / 펫 공격 (예전엔 피버에서만 빠져 있어서 세트 효과가 안 나갔다)
	run.PhaseEnd = os.clock() + 3
	if not waitFor(run, function() return os.clock() >= run.PhaseEnd end) then return end
	run.PhaseEnd = nil
	local startedAt = os.clock()
	run.SurviveEnd = startedAt + F.Duration -- (화면의 남은 시간 표시)
	run.Phase = "Wave"
	run.Wave, run.TotalWaves = 1, 0
	local level = math.max(1, D.GetWaveMonsterLevel(3) + run.LevelBonus)
	local nextSpawn, nextEvent, eventIndex = startedAt, startedAt + F.EventEvery, 0
	while not run.Destroyed and run.Phase ~= "Ended" do
		local now = os.clock()
		if now >= run.SurviveEnd or allDown(run) then break end
		if now >= nextSpawn then
			nextSpawn = now + F.SpawnEvery
			if run.MonsterCount < F.MaxMonsters then
				run.SpawnPoints = nearSpawnPoints(run, 22, 75) or run.AllSpawns
				for _ = 1, math.min(F.Burst, F.MaxMonsters - run.MonsterCount) do
					local data = spawnMonster(run, level)
					if data and run.FeverRushUntil and now < run.FeverRushUntil then data.FeverGold = true end
				end
			end
		end
		if now >= nextEvent then
			nextEvent = now + F.EventEvery
			eventIndex += 1
			if eventIndex % 2 == 1 then -- 골드 러시: 6초 동안 나오는 몬스터가 황금 몬스터 (골드 x3)
				run.FeverRushUntil = now + 6
				nextSpawn = now -- 바로 한 무더기
				for part, data in pairs(run.Monsters) do
					data.FeverGold = true
					part.Color = Color3.fromRGB(255, 205, 70)
				end
				notifyAll(run, "💰 GOLD RUSH! Golden monsters drop x3 gold for 6s!")
			else -- 보물 비: 내 주변에 골드가 쏟아진다
				giveGold(run, D.WaveClearGold * (2 + eventIndex))
				for _, member in ipairs(run.Members) do
					local root = getAliveParts(member)
					if root then
						for k = 1, 6 do
							local at = root.Position + Vector3.new(math.cos(k) * 6, 4, math.sin(k) * 6)
							Effects.Burst(at, Color3.fromRGB(255, 215, 80), 18)
						end
						SoundBank.Play(root, "Gacha_Drop")
					end
				end
				notifyAll(run, "🎁 TREASURE RAIN! Bonus gold!")
			end
		end
		task.wait(0.2)
	end
	feverFinish(run)
end

return { Loop = feverLoop }
end

return M
