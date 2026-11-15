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
	if not quiet and before ~= nil and stage > before then
		Remotes.Notify:FireClient(player, stage >= 2 and "⚡ Evolved: Awakening" or "💨 Evolved: Gale Dash")
	end
end

local function stagger(folder, center, radius, seconds)
	if not folder then return end
	local untilAt = os.clock() + seconds
	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart") and (part.Position - center).Magnitude <= radius + part.Size.X / 2 then
			part:SetAttribute("StaggerUntil", untilAt)
		end
	end
end

local function galeBurst(player, root)
	local E = Config.Evolve
	local zone = player:GetAttribute("Zone")
	if zone ~= "Field" and zone ~= "Dungeon" then return end
	if player:GetAttribute("IntroPlaying") or player:GetAttribute("TutorialActive") then return end
	local center = root.Position
	local damage = math.max(1, math.floor(Dungeon.ComputeDamage(player) * E.GaleDamage))
	local hit
	if zone == "Dungeon" then
		hit = Dungeon.AreaDamage(player, center, E.GaleRadius, damage)
		stagger(Dungeon.MonstersFolder(player), center, E.GaleRadius, E.GaleStagger)
	else
		hit = Field.AreaDamage(player, center, E.GaleRadius, damage)
		stagger(workspace:FindFirstChild("FieldMonsters"), center, E.GaleRadius, E.GaleStagger)
	end
	-- 연출: 기존 효과 이벤트 재사용 (퍼지는 고리 + 파편)
	local color = Color3.fromRGB(150, 230, 255)
	Effects.Raw(center, { "R", center - Vector3.new(0, 2.5, 0), E.GaleRadius, color })
	if hit and #hit > 0 then Effects.Burst(center, color, 24) end
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
