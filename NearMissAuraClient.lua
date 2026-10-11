-- NearMissAuraClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: NearMissAuraClient)
-- NEAR MISS 스택(공격력이 누적해서 오름)을 눈으로 보이게 한다: 스택이 쌓일수록 몸 주위로 기운이 모여들고,
-- 색이 연한 색에서 짙은 붉은색으로 바뀐다. 숫자는 보여 주지 않는다 (내 머리 위의 작은 막대 색 / 남은 시간으로만 알려 준다).
-- 서버가 NearMissStacks(스택 수) / NearMissEnd(끝나는 서버 시각) / NearMissLen(유지 시간)을 Attribute 로 알려 준다. 끝나기 2초 전부터 깜빡인다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
local player = Players.LocalPlayer
local MAX = Config.NearMiss.MaxStacks

-- 스택이 쌓일수록 연한 색 -> 짙은 붉은색
local PALE = Color3.fromRGB(255, 232, 224)
local DEEP = Color3.fromRGB(205, 22, 36)
local function heat(t)
	return PALE:Lerp(DEEP, math.clamp(t, 0, 1) ^ 0.8)
end

local auras = setmetatable({}, { __mode = "k" }) -- [플레이어] = { Part, Core, Character, Bar... }
local lastStacks = setmetatable({}, { __mode = "k" })

local function build(plr, character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
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
	core.LightEmission = 0.8
	core.Rate = 0
	core.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.8, 0.1), NumberSequenceKeypoint.new(1, 1) })
	core.Parent = holder
	holder.Parent = character
	local entry = { Part = holder, Core = core, Character = character }
	if plr == player then
		-- 은은한 윤곽선 (스택이 높을수록 진해진다)
		local outline = Instance.new("Highlight")
		outline.Name = "NearMissOutline"
		outline.FillTransparency = 1
		outline.OutlineTransparency = 1
		outline.DepthMode = Enum.HighlightDepthMode.Occluded
		outline.Adornee = character
		outline.Parent = character
		entry.Outline = outline
		-- 머리 위의 작은 막대: 색 = 스택, 길이 = 남은 시간 (숫자 없음)
		if head then
			local gui = Instance.new("BillboardGui")
			gui.Name = "NearMissBar"
			gui.Size = UDim2.new(0, 64, 0, 7)
			gui.StudsOffset = Vector3.new(0, 3.1, 0)
			gui.AlwaysOnTop = true
			gui.MaxDistance = 80
			gui.Adornee = head
			gui.Parent = head
			local back = Instance.new("Frame")
			back.Size = UDim2.new(1, 0, 1, 0)
			back.BackgroundColor3 = Color3.fromRGB(24, 20, 24)
			back.BackgroundTransparency = 0.35
			back.BorderSizePixel = 0
			back.Parent = gui
			Instance.new("UICorner", back).CornerRadius = UDim.new(0, 3)
			local fill = Instance.new("Frame")
			fill.Size = UDim2.new(1, 0, 1, 0)
			fill.BorderSizePixel = 0
			fill.Parent = back
			Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)
			entry.Gui, entry.Fill = gui, fill
		end
	end
	return entry
end

local function clear(plr)
	local entry = auras[plr]
	lastStacks[plr] = 0
	if not entry then return end
	auras[plr] = nil
	if entry.Part then entry.Part:Destroy() end
	if entry.Outline then entry.Outline:Destroy() end
	if entry.Gui then entry.Gui:Destroy() end
end

local lastStackSound = 0
local function refresh(plr)
	local stacks = plr:GetAttribute("NearMissStacks") or 0
	if plr == player then -- 내 스택이 늘어날 때마다 소리 (스택이 높을수록 음이 조금 높다)
		if stacks > lastStackSound then SoundBank.Play(game:GetService("SoundService"), "NearMiss_Get", { Pitch = 0.9 + math.min(stacks, MAX) * 0.04 }) end
		lastStackSound = stacks
	end
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
	local t = math.clamp(stacks / MAX, 0, 1)
	local color = heat(t)
	local flicker = remaining < 2 and (0.45 + 0.55 * math.abs(math.sin(os.clock() * 14))) or 1 -- 끝나기 2초 전: 깜빡
	entry.Core.Color = ColorSequence.new(color)
	entry.Core.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3 + 0.7 * t), NumberSequenceKeypoint.new(1, 0) })
	entry.Core.Speed = NumberRange.new(5 + 6 * t, 8 + 8 * t)
	entry.Core.Rate = (10 + 18 * stacks) * flicker
	if entry.Outline then
		entry.Outline.OutlineColor = color
		entry.Outline.OutlineTransparency = (0.8 - 0.65 * t) + (1 - flicker) * 0.3
	end
	if entry.Fill then
		local len = plr:GetAttribute("NearMissLen") or Config.NearMiss.Duration
		entry.Fill.BackgroundColor3 = color
		entry.Fill.Size = UDim2.new(math.clamp(remaining / len, 0, 1), 0, 1, 0)
		entry.Gui.Enabled = flicker > 0.6 -- 곧 끝나면 막대도 깜빡
	end
	-- 스택이 오를 때마다 한 번 팡 (최대 스택에서는 더 크게)
	local prev = lastStacks[plr] or 0
	if stacks > prev then
		entry.Core:Emit(12 + 4 * stacks)
		if stacks >= MAX then entry.Core:Emit(60) end
	end
	lastStacks[plr] = stacks
	return true
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
end)

Players.PlayerRemoving:Connect(clear)

-- (예전에 만든 조준점 아래 표시가 Studio 에 남아 있으면 지운다)
task.spawn(function()
	local old = player:WaitForChild("PlayerGui"):FindFirstChild("NearMissGui")
	if old then old:Destroy() end
end)
