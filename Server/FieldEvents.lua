-- FieldEvents (ServerScriptService > Modules 안의 ModuleScript, 이름: FieldEvents)
-- 필드 이벤트 중 FieldService 에서 떼어 낸 것 (FieldService 가 Studio 스크립트 한도 200KB 에 닿았다):
--   * 현상금(엘리트 무리): 큰길에서 벗어난 곳에 나타나고 제한 시간 안에 모두 잡으면 근처 모두 보상 (화면 표시: BountyClient)
--   * 공습: 경보 -> 폭격기가 지나가며 폭탄 (바닥 붉은 원을 피한다)
-- FieldService 가 Init(ctx) 로 필요한 함수 / 표를 넘겨준다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Guard = require(script.Parent:WaitForChild("DamageGuard"))

local FE = {}
local ctx
local F = Config.Field
local monsters
local function zoneBounds(...) return ctx.ZoneBounds(...) end
local function walkableAt(...) return ctx.WalkableAt(...) end
local function isSafe(...) return ctx.IsSafe(...) end
local function floorAt(...) return ctx.FloorAt(...) end
local function spawnMonster(...) return ctx.SpawnMonster(...) end
local function getAliveParts(...) return ctx.GetAliveParts(...) end
local function zoneOfX(...) return ctx.ZoneOfX(...) end
local function notify(...) return ctx.Notify(...) end
local function playersNear(...) return ctx.PlayersNear(...) end
local function playSfx(...) return ctx.PlaySfx(...) end
local Loot

-- 현상금: 사람이 있는 구역마다 가끔 "엘리트 무리"가 큰길에서 벗어난 곳(구역 옆쪽)에 나타난다. 제한 시간 안에 모두 잡으면
-- 근처에서 싸운 사람 모두 골드 + 티켓 + 장비. 직선으로 밀기만 하던 사냥에 "옆으로 돌아갈 이유"를 준다 (화면 위 작은 표시: BountyClient)
local bountyByZone = {}
local function startBounty(zone)
	local B = F.Bounty
	local x0, x1 = zoneBounds(zone)
	local spot
	for _ = 1, 30 do
		local x = math.random(math.floor(x0 + F.CampSafe + 120), math.floor(x1 - 120))
		local z = (math.random() < 0.5 and -1 or 1) * math.random(math.floor(F.Width * 0.22), math.floor(F.Width * 0.4))
		if walkableAt(x, z, 10) and not isSafe(Vector3.new(x, 0, z)) then spot = Vector3.new(x, floorAt(x), z) break end
	end
	if not spot then return end
	local pack = {}
	for i = 1, B.PackSize do
		local a = i / B.PackSize * math.pi * 2
		local at = spot + Vector3.new(math.cos(a) * 9, 0, math.sin(a) * 9)
		local ok, part, data = pcall(spawnMonster, zone, "Elite", at)
		if ok and part and data then
			data.Bounty = true
			data.Aggro = false
			table.insert(pack, { Part = part, Data = data })
		end
	end
	if #pack == 0 then return end
	local beacon = Instance.new("Part") -- 멀리서도 보이는 가는 금빛 줄기 (옅게)
	beacon.Anchored, beacon.CanCollide, beacon.CanQuery, beacon.CanTouch, beacon.CastShadow = true, false, false, false, false
	beacon.Material = Enum.Material.Neon
	beacon.Color = Color3.fromRGB(255, 205, 90)
	beacon.Transparency = 0.82
	beacon.Size = Vector3.new(1.6, 220, 1.6)
	beacon.CFrame = CFrame.new(spot + Vector3.new(0, 110, 0))
	beacon.Parent = ctx.GetWorldFolder()
	local endsAt = workspace:GetServerTimeNow() + B.Seconds
	local bounty = { Zone = zone, Spot = spot, Pack = pack, EndsAt = endsAt }
	bountyByZone[zone] = bounty
	local function sync(left)
		for _, player in ipairs(Players:GetPlayers()) do
			local root = getAliveParts(player)
			local here = root and player:GetAttribute("Zone") == "Field" and zoneOfX(root.Position.X) == zone
			player:SetAttribute("BountyEnd", here and left > 0 and endsAt or nil)
			player:SetAttribute("BountyLeft", here and left > 0 and left or nil)
			player:SetAttribute("BountyPos", here and left > 0 and spot or nil)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local root = getAliveParts(player)
		if root and player:GetAttribute("Zone") == "Field" and zoneOfX(root.Position.X) == zone then
			notify(player, string.format("🎯 Bounty! An elite pack appeared off the main road in Zone %d. Defeat all %d within %d seconds for a reward!", zone, #pack, B.Seconds))
		end
	end
	task.spawn(function()
		local left = #pack
		while workspace:GetServerTimeNow() < endsAt do
			left = 0
			for _, entry in ipairs(pack) do
				if monsters[entry.Part] == entry.Data then left += 1 end
			end
			sync(left)
			if left == 0 then break end
			task.wait(1)
		end
		beacon:Destroy()
		bountyByZone[zone] = nil
		sync(0)
		if left == 0 then -- 모두 잡았다: 근처에서 싸운 사람 모두에게 보상 (높은 구역일수록 크다)
			local gold = 0
			for _, entry in ipairs(pack) do gold += entry.Data.Stats.Gold or 0 end
			gold = math.floor(gold * B.GoldMult)
			local tickets = (B.TicketsByZone and B.TicketsByZone[zone]) or 1
			for _, entry in ipairs(playersNear(spot, B.RewardRadius)) do
				local player = Players:GetPlayerFromCharacter(entry.Root.Parent)
				if player then
					player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + math.floor(gold * Config.GoldBonus(player) + 0.5))
					player:SetAttribute("Tickets", (player:GetAttribute("Tickets") or 0) + tickets)
					Loot.DropFor(player, entry.Root.Position, "Event", zone)
					playSfx(player, "Quest_Claim")
					notify(player, string.format("🎯 Bounty complete! +%d G · 🎫 +%d · gear dropped", gold, tickets))
				end
			end
		else
			for _, entry in ipairs(pack) do -- 시간 초과: 남은 무리는 물러난다 (보상 없음)
				if monsters[entry.Part] == entry.Data then
					monsters[entry.Part] = nil
					entry.Part:Destroy()
				end
			end
		end
	end)
end

local function runBounties()
	task.wait(F.Bounty.FirstDelay)
	while true do
		local zones = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local root = getAliveParts(player)
			if root and player:GetAttribute("Zone") == "Field" and not player:GetAttribute("TutorialDoom") and not player:GetAttribute("TutorialActive") then
				local zone = zoneOfX(root.Position.X)
				if zone >= 1 and not bountyByZone[zone] then zones[zone] = true end
			end
		end
		for zone in pairs(zones) do pcall(startBounty, zone) end
		task.wait(math.random(F.Bounty.MinGap, F.Bounty.MaxGap))
	end
end


-- 공습: 경보가 울리고 하늘을 가로지르는 폭격기가 지나가며 폭탄을 떨어뜨린다. 바닥에 붉은 원이 먼저 나타나니 그 밖으로 피한다.
local function airRaid(player, zone)
	local root = getAliveParts(player)
	if not root then return end
	player:SetAttribute("EventFx", "Raid") -- 사이렌 대신 화면 가장자리가 붉게 맥박친다 (PlayerFX)
	player:SetAttribute("EventFxTick", (player:GetAttribute("EventFxTick") or 0) + 1)
	player:SetAttribute("ShakeStrength", 0.35)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")
	local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))

	local level = F.GetZoneLevel(zone)
	local stats = Config.Monster.GetStats(level)
	local damage = math.max(5, math.floor(stats.ShotDamage * F.ZoneDanger.Damage[zone] * 1.8))
	local center = root.Position
	local heading = math.random() < 0.5 and 1 or -1
	local axis = Vector3.new(math.random() < 0.5 and 1 or 0, 0, 0)
	if axis.Magnitude == 0 then axis = Vector3.new(0, 0, 1) end
	axis *= heading
	local lateral = Vector3.new(-axis.Z, 0, axis.X)
	local altitude = 85
	local startPos = Vector3.new(center.X, center.Y + altitude, center.Z) - axis * 170
	local speed = 95

	-- 폭격기: 어두운 몸체 + 날개 + 깜빡이는 붉은 등
	local plane = Instance.new("Model")
	plane.Name = "RaidBomber"
	local function body(size, offset, color, material)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.Metal
		p.CFrame = CFrame.lookAt(startPos, startPos + axis) * CFrame.new(offset)
		p.Parent = plane
		return p
	end
	local hull = body(Vector3.new(5, 4, 22), Vector3.zero, Color3.fromRGB(45, 48, 58))
	body(Vector3.new(30, 0.8, 7), Vector3.new(0, 0, 2), Color3.fromRGB(55, 58, 70))
	body(Vector3.new(10, 0.8, 4), Vector3.new(0, 1.2, 10), Color3.fromRGB(55, 58, 70))
	body(Vector3.new(0.8, 5, 4), Vector3.new(0, 2.5, 10), Color3.fromRGB(55, 58, 70))
	for _, side in ipairs({ -1, 1 }) do
		local light = body(Vector3.new(1.2, 1.2, 1.2), Vector3.new(side * 14.5, 0.6, 1), Color3.fromRGB(255, 60, 50), Enum.Material.Neon)
		local glow = Instance.new("PointLight")
		glow.Range = 30
		glow.Color = Color3.fromRGB(255, 60, 50)
		glow.Brightness = 3
		glow.Parent = light
	end
	plane.PrimaryPart = hull
	plane.Parent = workspace
	Debris:AddItem(plane, 8)

	-- 폭격기가 지나가는 중간에 낙하산 부대가 투하된다: 플레이어 주변 하늘에서 몬스터가 내려온다
	task.delay(1.3, function()
		local target = getAliveParts(player)
		if not target then return end
		local count = 3 + math.min(4, zone // 2 + 1)
		for _ = 1, count do
			local angle = math.random() * math.pi * 2
			local distance = 16 + math.random() * 30
			local at = target.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			if walkableAt(at.X, at.Z) and not isSafe(at) and zoneOfX(at.X) == zone then
				local part, data = spawnMonster(zone, "Normal", at, true)
				if part and data then
					data.Falling = true
					local drop = floorAt(at.X) + 90
					-- (Position 이 아니라 CFrame 으로 옮긴다: Position 으로 크게 순간이동하면 용접된 겉모양 조각이 땅에 남아 본체와 87 정도 어긋나 보였다 - [Monster desync] 로그)
					part.CFrame = CFrame.new(at.X, drop, at.Z) * part.CFrame.Rotation
					local canopy = Instance.new("Part")
					canopy.Name = "Chute"
					canopy.Anchored, canopy.CanCollide, canopy.CanQuery, canopy.CanTouch, canopy.Massless = false, false, false, false, true
					canopy.Shape = Enum.PartType.Ball
					canopy.Size = Vector3.new(data.Stats.Size * 2.4, data.Stats.Size * 1.2, data.Stats.Size * 2.4)
					canopy.Color = Color3.fromRGB(235, 90, 70)
					canopy.Material = Enum.Material.Fabric
					canopy.CFrame = part.CFrame * CFrame.new(0, data.Stats.Size * 1.6, 0)
					local weld = Instance.new("Weld") -- (Weld + 명시적 오프셋: WeldConstraint 는 클라이언트가 받는 순간의 위치로 오프셋을 다시 계산해서, 움직이는 몬스터의 겉모양이 본체에서 어긋나 보였다)
					weld.Part0 = part
					weld.Part1 = canopy
					weld.C0 = part.CFrame:ToObjectSpace(canopy.CFrame)
					weld.Parent = canopy
					canopy.Parent = part
				end
			end
		end
	end)

	local started = os.clock()
	local travel = 340 / speed
	local bombs = 8 + math.min(6, zone)
	local dropped = 0
	task.spawn(function()
		while os.clock() - started < travel and plane.Parent do
			local t = (os.clock() - started) / travel
			plane:PivotTo(CFrame.lookAt(startPos + axis * 340 * t, startPos + axis * 340 * t + axis))
			-- 비행 구간의 가운데 부분에서 폭탄을 떨어뜨린다
			local due = math.floor(math.clamp((t - 0.25) / 0.5, 0, 1) * bombs + 0.001)
			while dropped < due do
				dropped += 1
				local planePos = startPos + axis * 340 * t
				local lateralOffset = (math.random() - 0.5) * 70
				local spot = Vector3.new(planePos.X, 0, planePos.Z) + lateral * lateralOffset + axis * 18
				if dropped % 3 == 1 then -- 세 발에 한 발은 플레이어 위치를 노린다
					local target = getAliveParts(player)
					if target then spot = Vector3.new(target.Position.X, 0, target.Position.Z) end
				end
				local ground = floorAt(spot.X)
				local radius = 11
				local marker = Instance.new("Part")
				marker.Anchored, marker.CanCollide, marker.CanQuery, marker.CanTouch = true, false, false, false
				marker.Shape = Enum.PartType.Cylinder
				marker.Material = Enum.Material.Neon
				marker.Color = Color3.fromRGB(255, 50, 40)
				marker.Transparency = 0.55
				marker.Size = Vector3.new(0.4, radius * 2, radius * 2)
				marker.CFrame = CFrame.new(spot.X, ground + 0.4, spot.Z) * CFrame.Angles(0, 0, math.rad(90))
				marker.Parent = workspace
				local fuse = 1.5
				local bomb = Instance.new("Part")
				bomb.Anchored, bomb.CanCollide, bomb.CanQuery, bomb.CanTouch = true, false, false, false
				bomb.Shape = Enum.PartType.Ball
				bomb.Material = Enum.Material.Neon
				bomb.Color = Color3.fromRGB(255, 140, 50)
				bomb.Size = Vector3.new(3.2, 3.2, 3.2)
				bomb.Position = planePos - Vector3.new(0, 2, 0)
				bomb.Parent = workspace
				TweenService:Create(bomb, TweenInfo.new(fuse, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = Vector3.new(spot.X, ground + 1.5, spot.Z) }):Play()
				local trail = Instance.new("ParticleEmitter")
				trail.Rate = 40
				trail.Lifetime = NumberRange.new(0.3, 0.6)
				trail.Speed = NumberRange.new(0, 2)
				trail.LightEmission = 1
				trail.Color = ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 80, 30))
				trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0) })
				trail.Parent = bomb
				task.delay(fuse, function()
					bomb:Destroy()
					marker:Destroy()
					local at = Vector3.new(spot.X, ground, spot.Z)
					Effects.Burst(at + Vector3.new(0, 2, 0), Color3.fromRGB(255, 140, 50), 36)
					local boom = Instance.new("Part")
					boom.Anchored, boom.CanCollide, boom.CanQuery, boom.CanTouch = true, false, false, false
					boom.Shape = Enum.PartType.Ball
					boom.Material = Enum.Material.Neon
					boom.Color = Color3.fromRGB(255, 170, 70)
					boom.Transparency = 0.3
					boom.Size = Vector3.new(2, 2, 2)
					boom.Position = at + Vector3.new(0, 2, 0)
					boom.Parent = workspace
					TweenService:Create(boom, TweenInfo.new(0.4), { Size = Vector3.new(radius * 2.2, radius * 2.2, radius * 2.2), Transparency = 1 }):Play()
					Debris:AddItem(boom, 0.5)
					SoundBank.Play(boom, "Boom", { Volume = 0.9 })
					for _, other in ipairs(Players:GetPlayers()) do
						local otherRoot, humanoid = getAliveParts(other)
						if otherRoot and other:GetAttribute("Zone") == "Field" and not isSafe(otherRoot.Position) then
							local flat = Vector3.new(otherRoot.Position.X - at.X, 0, otherRoot.Position.Z - at.Z)
							if flat.Magnitude <= radius and otherRoot.Position.Y - ground < 8 then
								Guard.Take(humanoid, damage)
							end
						end
					end
				end)
			end
			task.wait(0.03)
		end
		plane:Destroy()
	end)
end

FE.AirRaid = airRaid
FE.RunBounties = runBounties

function FE.Init(context)
	ctx = context
	monsters = context.Monsters
	Loot = context.Loot
	return FE
end

return FE
