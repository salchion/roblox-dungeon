-- DeathLog (ServerScriptService > Modules 안의 ModuleScript, 이름: DeathLog)
-- 사망 원인 한 줄 (Studio Output 전용): 쓰러지는 순간 HP / 장소 / 방어 효과 단계 / 최근 피해 5건(출처 · 양 · 남은 체력 %) / 주변 군주 · 거신 거리.
--   최근 피해는 DamageGuard.Take 가 부른 곳("스크립트:줄")을 남긴다. 심판처럼 TakeDamage 를 바로 부르는 곳은 Guard.Note 로 출처를 직접 적는다 ("judge").
--   GameServer 가 require 하면 시작된다. 기존 파일에는 손대지 않는다 (P0: 큰 파일 크기 한도).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Guard = require(script.Parent:WaitForChild("DamageGuard"))

local DeathLog = {}
if not RunService:IsStudio() then return DeathLog end

local function placeOf(player)
	local zone = player:GetAttribute("Zone")
	if zone == "Field" then
		local okF, Field = pcall(function() return require(script.Parent:WaitForChild("FieldService")) end)
		local z = okF and Field.ZoneOf and Field.ZoneOf(player) or 0
		return string.format("필드 %d구역", z)
	elseif zone == "Dungeon" then
		return "던전 " .. tostring(player:GetAttribute("DungeonLabel") or "")
	end
	return tostring(zone)
end

local function nearby(root)
	local list = {}
	for _, part in ipairs(CollectionService:GetTagged("RadarBoss")) do
		if part:IsA("BasePart") and part.Parent then
			local d = (part.Position - root.Position).Magnitude
			if d <= 250 then table.insert(list, { Name = part.Name, D = d }) end
		end
	end
	table.sort(list, function(a, b) return a.D < b.D end)
	local out = {}
	for i = 1, math.min(3, #list) do out[i] = string.format("%s %dm", list[i].Name, math.floor(list[i].D)) end
	return #out > 0 and table.concat(out, ", ") or "없음"
end

local function watch(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	humanoid.Died:Connect(function()
		local root = character:FindFirstChild("HumanoidRootPart")
		local hits, now = {}, os.clock()
		for i = #Guard.RecentOf(player), 1, -1 do
			local h = Guard.RecentOf(player)[i]
			table.insert(hits, string.format("%s %d (남은 %d%%, %.1f초 전)", h.Source, h.Amount, h.Left, now - h.At))
		end
		print(string.format("[사망] %s · HP %d/%d · %s · 전투력 %d · 방어 효과 Lv%d · 최근 피해(최신부터): %s · 주변 군주/거신: %s",
			player.Name, math.max(0, math.floor(humanoid.Health)), math.floor(humanoid.MaxHealth), placeOf(player), player:GetAttribute("Power") or 0,
			player:GetAttribute("AugDefLv") or 0, #hits > 0 and table.concat(hits, " ← ") or "기록 없음", root and nearby(root) or "-"))
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(character) watch(player, character) end)
	if player.Character then task.spawn(watch, player, player.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do onPlayer(player) end

return DeathLog
