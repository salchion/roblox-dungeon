-- LowSpecClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: LowSpecClient)
-- 설정(H) 창의 "저사양 모드"를 켜면 내 화면만 가볍게 한다 (다른 사람 화면 / 게임 규칙에는 영향이 없다).
--   * 그림자 끄기, 빛 번짐 / 햇살 / 심도 효과 끄기
--   * 파티클 양을 줄이기 (원래 값은 기억해 두었다가 끄면 되돌린다)
--   * 지형 풀 장식 끄기, 화면 품질 최저로 (가능한 경우)
--   설정 창은 PlayerClient 가 만들고 Attribute "LowSpec" 만 바꾼다. 이 스크립트는 그 Attribute 를 보고 일한다.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local PARTICLE_KEEP = 0.25 -- 저사양일 때 남기는 파티클 비율
local EFFECT_CLASSES = { "BloomEffect", "SunRaysEffect", "DepthOfFieldEffect" }

local on = false
local savedEmitters = setmetatable({}, { __mode = "k" }) -- [emitter] = 원래 Rate
local savedEffects = setmetatable({}, { __mode = "k" })  -- [effect] = 원래 Enabled
local savedLighting = nil
local savedQuality = nil

local function lowerEmitter(emitter)
	if savedEmitters[emitter] == nil then savedEmitters[emitter] = emitter.Rate end
	emitter.Rate = savedEmitters[emitter] * PARTICLE_KEEP
end

local function applyEffects()
	for _, child in ipairs(Lighting:GetChildren()) do
		for _, className in ipairs(EFFECT_CLASSES) do
			if child:IsA(className) then
				if savedEffects[child] == nil then savedEffects[child] = child.Enabled end
				child.Enabled = false
			end
		end
	end
end

local function applyAll()
	if not savedLighting then
		savedLighting = { GlobalShadows = Lighting.GlobalShadows, ShadowSoftness = Lighting.ShadowSoftness }
	end
	Lighting.GlobalShadows = false
	applyEffects()
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("ParticleEmitter") then lowerEmitter(instance) end
	end
	pcall(function() Workspace.Terrain.Decoration = false end)
	pcall(function()
		local gameSettings = UserSettings():GetService("UserGameSettings")
		if savedQuality == nil then savedQuality = gameSettings.SavedQualityLevel end
		gameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
	end)
end

local function restoreAll()
	if savedLighting then
		Lighting.GlobalShadows = savedLighting.GlobalShadows
		Lighting.ShadowSoftness = savedLighting.ShadowSoftness
		savedLighting = nil
	end
	for effect, enabled in pairs(savedEffects) do
		if effect.Parent then effect.Enabled = enabled end
	end
	table.clear(savedEffects)
	for emitter, rate in pairs(savedEmitters) do
		if emitter.Parent then emitter.Rate = rate end
	end
	table.clear(savedEmitters)
	pcall(function() Workspace.Terrain.Decoration = true end)
	pcall(function()
		if savedQuality ~= nil then
			UserSettings():GetService("UserGameSettings").SavedQualityLevel = savedQuality
			savedQuality = nil
		end
	end)
end

-- 켜 두는 동안 새로 생기는 파티클 / 효과도 같이 줄인다
Workspace.DescendantAdded:Connect(function(instance)
	if on and instance:IsA("ParticleEmitter") then
		task.defer(function()
			if on and instance.Parent then lowerEmitter(instance) end
		end)
	end
end)
Lighting.ChildAdded:Connect(function()
	if on then task.defer(applyEffects) end
end)

local function refresh()
	local want = player:GetAttribute("LowSpec") == true
	if want == on then return end
	on = want
	if on then applyAll() else restoreAll() end
end

player:GetAttributeChangedSignal("LowSpec"):Connect(refresh)
refresh()
