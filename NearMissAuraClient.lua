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
local HOT = Color3.fromRGB(255, 235, 140)

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
		local sparks = Instance.new("ParticleEmitter")
		sparks.Lifetime = NumberRange.new(0.25, 0.45)
		sparks.Speed = NumberRange.new(1, 3)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.LightEmission = 1
		sparks.Rate = 0
		sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		sparks.Parent = handle
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
	if entry.Outline then entry.Outline:Destroy() end
end

local function refresh(plr)
	local stacks = plr:GetAttribute("NearMissStacks") or 0
	local endTime = plr:GetAttribute("NearMissEnd") or 0
	local remaining = endTime - workspace:GetServerTimeNow()
	local character = plr.Character
	if stacks <= 0 or remaining <= 0 or not character or not character.Parent then
		clear(plr)
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
	local color = COLD:Lerp(HOT, t)
	local flicker = remaining < 2 and (0.45 + 0.55 * math.abs(math.sin(os.clock() * 14))) or 1 -- 끝나기 2초 전: 깜빡
	entry.Core.Color = ColorSequence.new(color)
	entry.Core.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25 + 0.5 * t), NumberSequenceKeypoint.new(1, 0) })
	entry.Core.Rate = (8 + 14 * stacks) * flicker
	if entry.Gun then
		entry.Gun.Color = ColorSequence.new(color)
		entry.Gun.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2 + 0.3 * t), NumberSequenceKeypoint.new(1, 0) })
		entry.Gun.Rate = (4 + 6 * stacks) * flicker
		entry.Light.Color = color
		entry.Light.Brightness = (0.4 + 1.6 * t) * flicker
	end
	if entry.Outline then
		entry.Outline.OutlineColor = color
		entry.Outline.OutlineTransparency = (0.85 - 0.6 * t) + (1 - flicker) * 0.3
	end
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
	local color = COLD:Lerp(HOT, math.clamp(stacks / MAX, 0, 1))
	chip.TextColor3, barFill.BackgroundColor3 = color, color
	chip.Text = string.format("⚡ 공격력 +%d%%", math.floor(stacks * PER * 100 + 0.5))
	barFill.Size = UDim2.new(math.clamp(remaining / Config.NearMiss.Duration, 0, 1), 0, 1, 0)
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
