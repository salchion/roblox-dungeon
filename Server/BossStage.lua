-- BossStage (ServerScriptService > Modules 안의 ModuleScript, 이름: BossStage)
-- 필드 구역 군주 전투의 "연출": 등장(화면 흔들림 + 충격파 + 이름 배너 + 짧은 무적) / 격노(몸이 붉어지고 충격파 + 배너) / 처치(승리 배너 + 금빛 폭발).
--   서버는 월드 효과(충격파 / 폭발)와 신호만 보낸다. 화면(배너 / 번쩍임 / 시야 변화)은 클라이언트 BossStageClient 가 그린다 (Remotes.BossStage).
--   FieldService 가 Init(ctx) 로 필요한 도구를 넘겨 준다: GetWorldFolder, Effects, Config (FieldService 가 200KB 한계에 가까워 따로 뺐다).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local F = Config.Field
local Stage = {}
local ctx

local lastIntro = setmetatable({}, { __mode = "k" })

function Stage.Init(context)
	ctx = context
end

local function shake(player, strength)
	player:SetAttribute("ShakeStrength", strength)
	player:SetAttribute("ShakeTick", (player:GetAttribute("ShakeTick") or 0) + 1)
end

-- 땅에서 퍼지는 충격파 고리 (부품 하나, 0.9초 뒤 사라진다)
local function shockwave(position, size, color)
	local folder = ctx and ctx.GetWorldFolder and ctx.GetWorldFolder()
	if not folder then return end
	local y = ctx.FloorAt(position.X) + 0.5
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.5, size, size)
	ring.CFrame = CFrame.new(position.X, y, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.25
	ring.Parent = folder
	TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.5, size * 6, size * 6), Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 1.1)
end

local function fieldPlayersNear(position, radius)
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Zone") == "Field" then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - position).Magnitude <= radius then table.insert(list, player) end
		end
	end
	return list
end

-- 군주와 싸우기 시작한 플레이어에게: 등장 연출. 월드 효과와 짧은 무적은 군주마다 한 번만.
function Stage.Intro(part, data, player)
	if not ctx or not part.Parent then return end
	local now = os.clock()
	if now - (lastIntro[player] or -999) < 30 then return end -- 같은 플레이어에게 연달아 반복하지 않는다
	lastIntro[player] = now
	local zone = data.Zone
	if not data.IntroDone then
		data.IntroDone = true
		data.IntroUntil = now + 1.5 -- 포효하는 동안은 피해를 받지 않는다
		shockwave(part.Position, data.Stats.Size, Color3.fromRGB(255, 200, 120))
		ctx.Effects.Burst(part.Position, Color3.fromRGB(255, 180, 90), 70)
		ctx.Effects.FloatText(part.Position + Vector3.new(0, part.Size.Y / 2 + 6, 0), "ROAAAR!", Color3.fromRGB(255, 120, 90))
	end
	shake(player, 1.2)
	Remotes.BossStage:FireClient(player, "Intro", {
		Zone = zone,
		Name = Config.Codex.Bosses[zone] or "Lord",
		ZoneName = F.ZoneNames[zone] or "",
		Power = F.RecommendPower[zone] or 0,
	})
end

-- 체력 절반: 격노. 몸이 붉어지고 충격파가 퍼지고 주변 플레이어에게 배너가 뜬다.
function Stage.Enrage(part, data)
	if not ctx or not part.Parent then return end
	part.Color = part.Color:Lerp(Color3.fromRGB(255, 40, 40), 0.45)
	shockwave(part.Position, data.Stats.Size, Color3.fromRGB(255, 70, 60))
	ctx.Effects.Burst(part.Position, Color3.fromRGB(255, 70, 60), 90)
	for _, player in ipairs(fieldPlayersNear(part.Position, 160)) do
		shake(player, 1.0)
		player:SetAttribute("BossEnrage", true) -- 클라이언트가 음악을 한 단계 빠르게
		Remotes.BossStage:FireClient(player, "Enrage", { Zone = data.Zone })
	end
end

-- 처치: 승리 배너 + 금빛 폭발. first = 이 플레이어가 이 구역 군주를 처음 쓰러뜨렸다.
function Stage.Victory(player, part, data, first)
	if not ctx then return end
	if not data.VictoryDone then
		data.VictoryDone = true
		shockwave(part.Position, data.Stats.Size, Color3.fromRGB(255, 225, 120))
		ctx.Effects.Burst(part.Position, Color3.fromRGB(255, 225, 120), 140)
	end
	shake(player, 1.0)
	player:SetAttribute("BossEnrage", nil)
	Remotes.BossStage:FireClient(player, "Victory", {
		Zone = data.Zone, Name = Config.Codex.Bosses[data.Zone] or "Lord", First = first == true,
	})
end

function Stage.ClearEnrage(player)
	if player:GetAttribute("BossEnrage") then player:SetAttribute("BossEnrage", nil) end
end

return Stage
