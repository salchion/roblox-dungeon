-- IntensityClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: IntensityClient)
-- 박진감 연출 (내 화면에서만. 밸런스 / 서버와 무관):
--   1) 히트스톱: 큰 한 방(치명타 처치 / 연속 처치 이정표 / 보스 처치)에서 화면이 아주 잠깐 "멈칫" + 카메라가 앞으로 툭 밀린다
--   2) 연속 처치 열기: 콤보가 쌓일수록 화면 가장자리가 은은한 주황빛으로 달아오른다 (눈부시지 않게 아주 옅게)
--   3) 위기: 체력이 30% 아래면 심장 소리 "쿵-쿵" (낮을수록 빨라진다. 화면의 붉은 맥박은 PlayerFX 가 이미 그린다)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local okSound, SoundBank = pcall(function() return require(ReplicatedStorage:WaitForChild("SoundBank")) end)

local camera = workspace.CurrentCamera
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() camera = workspace.CurrentCamera end)

local function playSound(key, opts)
	if okSound and SoundBank then pcall(SoundBank.Play, SoundService, key, opts) end
end

local function shakeOn() -- 설정에서 화면 흔들림을 끈 사람은 히트스톱 / 밀림도 끈다
	return player:GetAttribute("SettingShake") ~= false
end

------------------------------------------------------------
-- 1) 히트스톱 + 카메라 밀림
------------------------------------------------------------
local stopUntil, frozenCF = 0, nil
local punch = 0
local lastStop = 0

local function hitStop(seconds, push)
	if not shakeOn() then return end
	local now = os.clock()
	if seconds > 0 and now >= stopUntil then
		stopUntil = now + seconds
		frozenCF = nil
	end
	punch = math.max(punch, push or 0)
end

RunService:BindToRenderStep("IntensityHitStop", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if not camera or camera.CameraType == Enum.CameraType.Scriptable then -- (연출 카메라 중에는 건드리지 않는다)
		frozenCF, punch = nil, 0
		return
	end
	local now = os.clock()
	if now < stopUntil then
		frozenCF = frozenCF or camera.CFrame
		camera.CFrame = frozenCF -- 아주 잠깐 화면을 그 자리에 붙잡는다 (멈칫)
		return
	end
	frozenCF = nil
	if punch > 0.01 then
		camera.CFrame = camera.CFrame * CFrame.new(0, 0, -punch) -- 앞으로 툭 (금방 돌아온다)
		punch = math.max(0, punch - dt * punch * 14 - dt * 0.4)
	end
end)

Remotes.Hit.OnClientEvent:Connect(function(isCrit, killed)
	local now = os.clock()
	if killed and isCrit and now - lastStop > 0.5 then -- 치명타로 잡았을 때만 (자동 공격으로 계속 잡을 때 화면이 덜컥거리지 않게)
		lastStop = now
		hitStop(0.045, 0.45)
	elseif killed then
		punch = math.max(punch, shakeOn() and 0.18 or 0)
	end
end)

-- 보스 처치: 서버가 군주 처치 순간에 BossKillTick 을 바꾼다 -> 크게 멈칫
player:GetAttributeChangedSignal("BossKillTick"):Connect(function()
	hitStop(0.14, 1.1)
end)

------------------------------------------------------------
-- 2) 연속 처치 열기 (화면 가장자리 주황빛) + 이정표 멈칫
------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "IntensityFx"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = -1 -- (다른 화면 아래에 깔린다)
gui.Parent = player:WaitForChild("PlayerGui")

local edges = {}
for _, side in ipairs({
	{ UDim2.new(1, 0, 0.16, 0), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), 90 },
	{ UDim2.new(1, 0, 0.16, 0), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1), 270 },
	{ UDim2.new(0.1, 0, 1, 0), UDim2.new(0, 0, 0, 0), Vector2.new(0, 0), 0 },
	{ UDim2.new(0.1, 0, 1, 0), UDim2.new(1, 0, 0, 0), Vector2.new(1, 0), 180 },
}) do
	local frame = Instance.new("Frame")
	frame.Size, frame.Position, frame.AnchorPoint = side[1], side[2], side[3]
	frame.BackgroundColor3 = Color3.fromRGB(255, 140, 40)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = side[4]
	gradient.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	gradient.Parent = frame
	table.insert(edges, frame)
end

local MILESTONES = { [10] = 1, [25] = 2, [50] = 3, [100] = 4, [200] = 5, [300] = 5, [500] = 6, [1000] = 7 }
local heat, flash = 0, 0
local lastCombo = 0
player:GetAttributeChangedSignal("Combo"):Connect(function()
	local combo = player:GetAttribute("Combo") or 0
	local tier = combo > lastCombo and MILESTONES[combo]
	if tier then
		hitStop(0.05 + tier * 0.012, 0.5 + tier * 0.15)
		flash = 1
		playSound("Crit", { Pitch = 0.8 + tier * 0.08, Volume = 1.6 })
	end
	lastCombo = combo
end)

RunService.RenderStepped:Connect(function(dt)
	local combo = player:GetAttribute("Combo") or 0
	-- 25연속부터 달아오르기 시작해서 200연속에서 가장 진하게 (그래도 옅게: 투명도 0.8 아래로는 안 내려간다)
	local target = combo >= 25 and math.clamp((combo - 25) / 175, 0, 1) or 0
	heat += (target - heat) * math.min(1, dt * 2)
	flash = math.max(0, flash - dt * 2.5)
	local pulse = 0.5 + 0.5 * math.sin(os.clock() * 4)
	local strength = heat * (0.1 + 0.04 * pulse) + flash * 0.16
	local transparency = strength > 0.005 and (1 - strength) or 1
	for _, frame in ipairs(edges) do
		frame.BackgroundTransparency = transparency
	end
end)

------------------------------------------------------------
-- 3) 위기: 심장 소리
------------------------------------------------------------
task.spawn(function()
	while true do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local ratio = humanoid and humanoid.Health > 0 and humanoid.Health / math.max(1, humanoid.MaxHealth) or 1
		if ratio <= 0.3 then
			local danger = (0.3 - ratio) / 0.3
			playSound("Low_Health", { Volume = 0.8 + danger * 0.5 })
			task.delay(0.2, function() playSound("Low_Health", { Volume = 0.55 + danger * 0.4, Pitch = 0.92 }) end) -- "쿵-쿵"
			task.wait(1.05 - danger * 0.45)
		else
			task.wait(0.25)
		end
	end
end)

------------------------------------------------------------
-- 4) 유니크 능력 표시: 방벽 보호막(몸을 감싼 옅은 푸른 막) / 행운의 별(몸 주위 별빛)
------------------------------------------------------------
do
	local bubble, sparkle
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local shieldOn = root ~= nil and player:GetAttribute("ShieldUp") == true
		if shieldOn then
			if not bubble or not bubble.Parent then
				bubble = Instance.new("Part")
				bubble.Name = "UniqueShieldBubble"
				bubble.Shape = Enum.PartType.Ball
				bubble.Size = Vector3.new(7.5, 7.5, 7.5)
				bubble.Material = Enum.Material.ForceField
				bubble.Color = Color3.fromRGB(130, 200, 255)
				bubble.Transparency = 0.2
				bubble.Anchored, bubble.CanCollide, bubble.CanQuery, bubble.CanTouch, bubble.CastShadow = true, false, false, false, false
				bubble.Parent = workspace
			end
			bubble.CFrame = root.CFrame
		elseif bubble then
			local old = bubble
			bubble = nil
			if old.Parent then -- 깨질 때: 크게 부풀며 사라진다
				game:GetService("TweenService"):Create(old, TweenInfo.new(0.25), { Size = Vector3.new(12, 12, 12), Transparency = 1 }):Play()
				game:GetService("Debris"):AddItem(old, 0.3)
			end
		end
		local starOn = root ~= nil and (player:GetAttribute("StarUntil") or 0) > workspace:GetServerTimeNow()
		if starOn and (not sparkle or not sparkle.Parent or sparkle.Parent ~= root) then
			if sparkle then sparkle:Destroy() end
			sparkle = Instance.new("ParticleEmitter")
			sparkle.Name = "LuckyStarAura"
			sparkle.Rate, sparkle.Lifetime, sparkle.Speed = 18, NumberRange.new(0.8, 1.3), NumberRange.new(1, 3)
			sparkle.SpreadAngle = Vector2.new(180, 180)
			sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
			sparkle.LightEmission = 0.6
			sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
			sparkle.Parent = root
		elseif not starOn and sparkle then
			sparkle:Destroy()
			sparkle = nil
		end
	end)
end

------------------------------------------------------------
-- 5) 개척 보너스 표시: 아직 군주를 못 잡은 다음 구역에서 사냥 중이면 화면 위쪽 가운데에 작은 깃발 알약
------------------------------------------------------------
do
	local chip = Instance.new("TextLabel")
	chip.Name = "FrontierChip"
	chip.AnchorPoint = Vector2.new(0.5, 0)
	chip.Position = UDim2.new(0.5, 0, 0, 14)
	chip.Size = UDim2.new(0, 330, 0, 28)
	chip.BackgroundColor3 = Color3.fromRGB(60, 40, 16)
	chip.BackgroundTransparency = 0.15
	chip.Font = Enum.Font.GothamBold
	chip.TextSize = 13
	chip.TextColor3 = Color3.fromRGB(255, 220, 130)
	chip.RichText = true
	chip.Text = "🚩 <b>Frontier Bonus</b> · Gold/XP x2 · Drops x1.5"
	chip.Visible = false
	chip.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = chip
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 190, 80)
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = chip
	local function sync()
		chip.Visible = player:GetAttribute("FrontierHere") == true and player:GetAttribute("Zone") == "Field"
	end
	player:GetAttributeChangedSignal("FrontierHere"):Connect(sync)
	player:GetAttributeChangedSignal("Zone"):Connect(sync)
	sync()
end
