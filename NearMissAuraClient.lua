-- NearMissAuraClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: NearMissAuraClient)
-- NEAR MISS 스택(공격력 +5%씩 누적)을 눈으로 보이게 한다: 스택이 쌓일수록 몸 주위로 기가 모여들고 총이 빛난다.
-- 서버가 NearMissStacks(스택 수) / NearMissEnd(끝나는 서버 시각)를 Attribute 로 알려 준다. 끝나기 2초 전부터 깜빡여서 곧 사라진다는 걸 알린다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local player = Players.LocalPlayer
local MAX = Config.NearMiss.MaxStacks
local PER = Config.NearMiss.DamagePerStack

local COLD = Color3.fromRGB(110, 235, 255)
local WARM = Color3.fromRGB(255, 175, 70)
local HOT = Color3.fromRGB(255, 60, 40)
-- 스택이 쌓일수록 하늘색 -> 주황 -> 붉은색으로 달아오른다
local function heat(t)
	if t < 0.5 then return COLD:Lerp(WARM, t * 2) end
	return WARM:Lerp(HOT, (t - 0.5) * 2)
end
local GUN_RED = Color3.fromRGB(255, 70, 45)
local lastStacks = setmetatable({}, { __mode = "k" })

local auras = setmetatable({}, { __mode = "k" }) -- [플레이어] = { Part, Core, Gun, Light, Outline }

local function weaponHandle(character)
	local tool = character:FindFirstChildOfClass("Tool")
	return tool and (tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart"))
end

local function build(plr, character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local holder = Instance.new("Part") -- 눈에 안 보이는 구: 입자가 이 구 표면에서 몸 쪽으로 빨려 들어온다
	holder.Name = "NearMissAura"
	holder.Size = Vector3.new(6, 6, 6)
	holder.Transparency = 1
	holder.Massless, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
	holder.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = root, holder
	weld.Parent = holder
	local core = Instance.new("ParticleEmitter")
	core.Shape = Enum.ParticleEmitterShape.Sphere
	core.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	core.Lifetime = NumberRange.new(0.5, 0.8)
	core.Speed = NumberRange.new(5, 8)
	core.LightEmission = 1
	core.Rate = 0
	core.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.8, 0.1), NumberSequenceKeypoint.new(1, 1) })
	core.Parent = holder
	holder.Parent = character
	local entry = { Part = holder, Core = core, Character = character }
	if plr == player then -- 내 몸에는 은은한 윤곽선도 (스택이 높을수록 진해진다)
		local outline = Instance.new("Highlight")
		outline.Name = "NearMissOutline"
		outline.FillTransparency = 1
		outline.OutlineTransparency = 1
		outline.DepthMode = Enum.HighlightDepthMode.Occluded
		outline.Adornee = character
		outline.Parent = character
		entry.Outline = outline
	end
	return entry
end

local function ensureGun(entry, character)
	local handle = weaponHandle(character)
	if handle and entry.GunPart ~= handle then
		if entry.Gun then entry.Gun:Destroy() end
		if entry.Light then entry.Light:Destroy() end
		if entry.Shell then entry.Shell:Destroy() end
		if entry.Flames then entry.Flames:Destroy() end
		local sparks = Instance.new("ParticleEmitter")
		sparks.Lifetime = NumberRange.new(0.25, 0.45)
		sparks.Speed = NumberRange.new(1, 3)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.LightEmission = 1
		sparks.Rate = 0
		sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		sparks.Parent = handle
		local shell = Instance.new("Part") -- 총을 감싸고 달아오르는 붉은 기운 (스택이 쌓일수록 커진다)
		shell.Name = "NearMissGunGlow"
		shell.Shape = Enum.PartType.Ball
		shell.Material = Enum.Material.Neon
		shell.Color = GUN_RED
		shell.Transparency = 0.7
		shell.Size = Vector3.new(1.5, 1.5, 1.5)
		shell.Massless, shell.CanCollide, shell.CanQuery, shell.CanTouch, shell.CastShadow = true, false, false, false, false
		shell.CFrame = handle.CFrame
		local shellWeld = Instance.new("WeldConstraint")
		shellWeld.Part0, shellWeld.Part1 = handle, shell
		shellWeld.Parent = shell
		shell.Parent = handle
		local flames = Instance.new("ParticleEmitter") -- 총 둘레로 소용돌이치듯 감도는 붉은 불꽃
		flames.Lifetime = NumberRange.new(0.35, 0.6)
		flames.Speed = NumberRange.new(2, 5)
		flames.SpreadAngle = Vector2.new(180, 180)
		flames.RotSpeed = NumberRange.new(-180, 180)
		flames.LightEmission = 1
		flames.Rate = 0
		flames.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 50, 30))
		flames.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		flames.Parent = handle
		entry.Shell, entry.Flames = shell, flames
		local light = Instance.new("PointLight")
		light.Range = 7
		light.Brightness = 0
		light.Shadows = false
		light.Parent = handle
		entry.Gun, entry.Light, entry.GunPart = sparks, light, handle
	end
end

local function clear(plr)
	local entry = auras[plr]
	if not entry then return end
	auras[plr] = nil
	if entry.Part then entry.Part:Destroy() end
	if entry.Gun then entry.Gun:Destroy() end
	if entry.Light then entry.Light:Destroy() end
	if entry.Shell then entry.Shell:Destroy() end
	if entry.Flames then entry.Flames:Destroy() end
	if entry.Outline then entry.Outline:Destroy() end
end

local function refresh(plr)
	local stacks = plr:GetAttribute("NearMissStacks") or 0
	local endTime = plr:GetAttribute("NearMissEnd") or 0
	local remaining = endTime - workspace:GetServerTimeNow()
	local character = plr.Character
	if stacks <= 0 or remaining <= 0 or not character or not character.Parent then
		clear(plr)
		lastStacks[plr] = 0
		return false
	end
	local entry = auras[plr]
	if entry and (entry.Character ~= character or not entry.Part.Parent) then
		clear(plr)
		entry = nil
	end
	if not entry then
		entry = build(plr, character)
		if not entry then return false end
		auras[plr] = entry
	end
	ensureGun(entry, character)
	local t = math.clamp(stacks / MAX, 0, 1)
	local color = heat(t)
	local flicker = remaining < 2 and (0.45 + 0.55 * math.abs(math.sin(os.clock() * 14))) or 1 -- 끝나기 2초 전: 깜빡
	entry.Core.Color = ColorSequence.new(color)
	entry.Core.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3 + 0.7 * t), NumberSequenceKeypoint.new(1, 0) })
	entry.Core.Speed = NumberRange.new(5 + 6 * t, 8 + 8 * t)
	entry.Core.Rate = (10 + 18 * stacks) * flicker
	if entry.Gun then
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * (4 + 8 * t)) -- 스택이 높을수록 빨리 맥박친다
		entry.Gun.Color = ColorSequence.new(GUN_RED:Lerp(color, 0.3))
		entry.Gun.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3 + 0.5 * t), NumberSequenceKeypoint.new(1, 0) })
		entry.Gun.Speed = NumberRange.new(2 + 5 * t, 4 + 9 * t)
		entry.Gun.Rate = (8 + 12 * stacks) * flicker
		entry.Flames.Rate = (6 + 16 * stacks) * flicker
		entry.Flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 + 1.4 * t), NumberSequenceKeypoint.new(1, 0) })
		local size = (1.4 + 3.4 * t) * (0.9 + 0.2 * pulse)
		entry.Shell.Size = Vector3.new(size, size, size)
		entry.Shell.Color = GUN_RED:Lerp(Color3.fromRGB(255, 190, 90), t * t * 0.6) -- 최대에 가까워지면 백열
		entry.Shell.Transparency = (0.8 - 0.35 * t + (1 - flicker) * 0.15)
		entry.Light.Color = GUN_RED
		entry.Light.Range = 7 + 9 * t
		entry.Light.Brightness = (0.6 + 2.4 * t) * flicker
	end
	if entry.Outline then
		entry.Outline.OutlineColor = color
		entry.Outline.OutlineTransparency = (0.8 - 0.65 * t) + (1 - flicker) * 0.3
	end
	-- 스택이 오를 때마다 한 번 팡: 총과 몸에서 불꽃이 터진다 (최대 스택에서는 더 크게)
	local prev = lastStacks[plr] or 0
	if stacks > prev then
		entry.Core:Emit(12 + 4 * stacks)
		if entry.Flames then entry.Flames:Emit(10 + 3 * stacks) end
		if stacks >= MAX and entry.Shell then entry.Core:Emit(60) end
	end
	lastStacks[plr] = stacks
	return true
end

-- 내 화면에만: 조준점 아래에 작은 표시 (+N% 와 남은 시간 막대)
local gui = Instance.new("ScreenGui")
gui.Name = "NearMissGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")
local chip = Instance.new("TextLabel")
chip.Size = UDim2.new(0, 150, 0, 22)
chip.AnchorPoint = Vector2.new(0.5, 0)
chip.Position = UDim2.new(0.5, 0, 0.5, 52)
chip.BackgroundTransparency = 1
chip.Font = Enum.Font.GothamBlack
chip.TextSize = 15
chip.TextStrokeTransparency = 0.3
chip.Visible = false
chip.Parent = gui
local barBack = Instance.new("Frame")
barBack.Size = UDim2.new(0, 110, 0, 4)
barBack.AnchorPoint = Vector2.new(0.5, 0)
barBack.Position = UDim2.new(0.5, 0, 0.5, 76)
barBack.BackgroundColor3 = Color3.fromRGB(20, 30, 40)
barBack.BackgroundTransparency = 0.3
barBack.BorderSizePixel = 0
barBack.Visible = false
barBack.Parent = gui
local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(1, 0, 1, 0)
barFill.BorderSizePixel = 0
barFill.Parent = barBack

local function updateChip()
	local stacks = player:GetAttribute("NearMissStacks") or 0
	local remaining = (player:GetAttribute("NearMissEnd") or 0) - workspace:GetServerTimeNow()
	local on = stacks > 0 and remaining > 0
	chip.Visible, barBack.Visible = on, on
	if not on then return end
	local color = heat(math.clamp(stacks / MAX, 0, 1))
	chip.TextColor3, barFill.BackgroundColor3 = color, color
	chip.Text = string.format("⚡ 공격력 +%d%%", math.floor(stacks * PER * 100 + 0.5))
	barFill.Size = UDim2.new(math.clamp(remaining / (player:GetAttribute("NearMissLen") or Config.NearMiss.Duration), 0, 1), 0, 1, 0)
end

-- 스택이 있는 사람만 0.12초마다 갱신한다 (없으면 아무 일도 안 한다)
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.12 then return end
	acc = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if auras[plr] or (plr:GetAttribute("NearMissStacks") or 0) > 0 then
			refresh(plr)
		end
	end
	updateChip()
end)

Players.PlayerRemoving:Connect(clear)
