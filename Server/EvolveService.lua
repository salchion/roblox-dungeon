-- EvolveService (ServerScriptService > Modules): 전투 진화 — 무기 시대(Era)가 오르면 손끝이 바뀐다
--   1단계 질풍 대시 (Era >= Config.Evolve.GaleEra): 대시를 "시작하는 순간" 내 주변 GaleRadius 안의 적에게 한 발 x GaleDamage + 짧은 경직
--   대시는 클라이언트 속도로만 일어나서 서버 이벤트가 없다: 0.1초마다 속도를 보고 "대시가 아니었다 -> 대시"로 바뀌는 순간만 잡는다 (새 리모트 없음 = 클라 스팸으로 피해를 낼 수 없다)
--   EvolveStage(0/1/2) 를 플레이어 속성으로 보여 주고, 단계가 오를 때만 한 번 알린다 (접속할 때는 알리지 않는다)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Effects = require(script.Parent:WaitForChild("Effects"))

local Evolve = {}
local Dungeon, Field -- (Init 에서 받는다: 서로 부르는 순환 require 를 피한다)
local wasDashing = setmetatable({}, { __mode = "k" })
local shownStage = setmetatable({}, { __mode = "k" })

local function stageOf(player)
	local E = Config.Evolve
	local era = Config.GetWeaponTier(player:GetAttribute("WeaponLevel") or 0).Era or 1
	if era >= E.AwakenEra then return 2 elseif era >= E.GaleEra then return 1 end
	return 0
end
Evolve.StageOf = stageOf

local function refreshStage(player, quiet)
	local stage = stageOf(player)
	local before = shownStage[player]
	shownStage[player] = stage
	player:SetAttribute("EvolveStage", stage)
	if player:GetAttribute("DataReady") ~= true then quiet = true end -- (불러오는 중 WeaponLevel 이 들어오는 것은 "진화"가 아니다: 재접속마다 알림이 뜨던 것)
	if not quiet and before ~= nil and stage > before then
		Remotes.Notify:FireClient(player, stage >= 2 and "⚡ Evolved: Awakening" or "💨 Evolved: Gale Dash")
	end
end

local function galeBurst(player, root)
	local E = Config.Evolve
	local zone = player:GetAttribute("Zone")
	if zone ~= "Field" and zone ~= "Dungeon" then return end
	if player:GetAttribute("IntroPlaying") or player:GetAttribute("TutorialActive") then return end
	local center = root.Position
	if zone == "Field" and Field.InSafeZone and Field.InSafeZone(center) then return end -- (캠프 안전지대에서는 사격처럼 대시 충격파도 막는다)
	local damage = math.max(1, math.floor(Dungeon.ComputeDamage(player) * E.GaleDamage))
	local hit
	if zone == "Dungeon" then
		hit = Dungeon.AreaDamage(player, center, E.GaleRadius, damage)
		Dungeon.Stagger(player, center, E.GaleRadius, E.GaleStagger)
	else
		hit = Field.AreaDamage(player, center, E.GaleRadius, damage)
		Field.Stagger(player, center, E.GaleRadius, E.GaleStagger)
	end
	-- 연출: 기존 효과 이벤트 재사용 (퍼지는 고리 + 파편)
	local color = Color3.fromRGB(150, 230, 255)
	Effects.Raw(center, { "R", center - Vector3.new(0, 2.5, 0), E.GaleRadius, color })
	if hit and #hit > 0 then Effects.Burst(center, color, 24) end
end

-- 2단계 각성: 스킬(힐 / 정령 / 궁극기)을 쓰면 AwakenSeconds 동안 피해 x AwakenMult (Dungeon.ComputeDamage 가 AwakenUntil 을 읽는다)
--   캐릭터 Highlight 1개 (다시 쓰면 시간만 늘린다, 끝나면 지운다) + 시작할 때 떠오르는 글자
local awakenFx = setmetatable({}, { __mode = "k" })
function Evolve.Awaken(player)
	local E = Config.Evolve
	if not E.Enabled or (shownStage[player] or 0) < 2 then return end
	if player:GetAttribute("IntroPlaying") then return end
	local zone = player:GetAttribute("Zone")
	if zone ~= "Field" and zone ~= "Dungeon" then return end
	local untilAt = workspace:GetServerTimeNow() + E.AwakenSeconds
	player:SetAttribute("AwakenUntil", untilAt)
	local character = player.Character
	if not character then return end
	local hl = awakenFx[player]
	if not (hl and hl.Parent == character) then
		hl = Instance.new("Highlight")
		hl.Name = "AwakenGlow"
		hl.FillColor = Color3.fromRGB(255, 220, 120)
		hl.FillTransparency = 0.75
		hl.OutlineColor = Color3.fromRGB(255, 240, 170)
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = character
		awakenFx[player] = hl
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then Effects.FloatText(root.Position + Vector3.new(0, 6, 0), "⚡ Evolved: Awakening", Color3.fromRGB(255, 220, 120)) end
	end
	task.delay(E.AwakenSeconds + 0.05, function()
		if (player:GetAttribute("AwakenUntil") or 0) <= workspace:GetServerTimeNow() and awakenFx[player] == hl then
			hl:Destroy()
			awakenFx[player] = nil
		end
	end)
end

-- 각성 중 샷건 명중: 7칸 밀치기 + 0.5초 경직 (샷건만의 역할). canMove(위치) 가 true 일 때만 민다 (필드: 걸을 수 있는 땅 / 던전: 아레나 안)
--   밀 때는 CFrame 으로 (Position 으로 옮기면 용접된 장식이 남는다)
function Evolve.ShotgunHit(player, part, data, canMove)
	if not part or not part.Parent or (shownStage[player] or 0) < 2 then return end
	if (player:GetAttribute("AwakenUntil") or 0) <= workspace:GetServerTimeNow() then return end
	if Config.ResolveWeaponType(player:GetAttribute("WeaponLevel") or 0, player:GetAttribute("WeaponType")) ~= "Shotgun" then return end -- (Form 은 모델 모양 값이라 무기 종류 판정에 못 쓴다)
	if data and (data.IsBoss or data.Kind == "Boss" or data.BossLike) then return end -- (보스는 밀리지 않는다)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	part:SetAttribute("StaggerUntil", os.clock() + 0.5)
	local away = Vector3.new(part.Position.X - root.Position.X, 0, part.Position.Z - root.Position.Z)
	if away.Magnitude < 0.1 then return end
	local pushed = part.Position + away.Unit * 7
	if canMove and canMove(pushed) then
		part.CFrame = CFrame.new(pushed) * part.CFrame.Rotation
	end
end

function Evolve.Init(ctx)
	Dungeon, Field = ctx.Dungeon, ctx.Field
	local function hook(player)
		refreshStage(player, true)
		player:GetAttributeChangedSignal("WeaponLevel"):Connect(function() refreshStage(player, false) end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end
	task.spawn(function()
		while true do
			task.wait(0.1)
			if Config.Evolve.Enabled then
				for _, player in ipairs(Players:GetPlayers()) do
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					local dashing = false
					if root and (shownStage[player] or 0) >= 1 then
						local v = root.AssemblyLinearVelocity
						local humanoid = root.Parent:FindFirstChildOfClass("Humanoid")
						local walk = humanoid and humanoid.WalkSpeed or Config.Player.WalkSpeed
						dashing = Vector3.new(v.X, 0, v.Z).Magnitude > math.max(60, walk + 25) -- (NearMissService 와 같은 대시 판정)
						if dashing and not wasDashing[player] and humanoid and humanoid.Health > 0 then
							pcall(galeBurst, player, root)
						end
					end
					wasDashing[player] = dashing
				end
			end
		end
	end)
end

return Evolve
