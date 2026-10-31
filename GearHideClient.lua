-- GearHideClient (StarterPlayer > StarterPlayerScripts 안의 LocalScript, 이름: GearHideClient)
-- 설정(H)의 "장비 외형 숨기기" 켜기 / 끄기 (기본: 켜짐 = 숨김): 내 캐릭터에 붙는 장비 모양(갑옷 / 투구 / 장갑 / 신발 등 GearVisual_* 폴더와 GearAura 기운)을 내 화면에서 숨긴다.
--   * 무기는 그대로 보인다. 능력치는 바뀌지 않는다 (보이는 것만).
--   * 설정 창은 PlayerClient 가 만들고 Attribute "HideGear" 만 바꾼다. 이 스크립트는 그 Attribute 를 보고 일한다.
--   * 장비를 바꿔 모양이 다시 만들어져도 자동으로 다시 숨긴다.

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local saved = setmetatable({}, { __mode = "k" }) -- 숨기기 전 Enabled 값 (빛 / 입자)
local savedT = setmetatable({}, { __mode = "k" }) -- 숨기기 전 Transparency 값 (조각)

-- 기본은 장비 외형을 숨긴다 (설정 H 의 "Hide gear look" 이 처음부터 ON). 설정에서 끄면 다시 보인다. (저장하지 않는 값이라 접속할 때마다 기본값으로 시작)
if player:GetAttribute("HideGear") == nil then
	player:SetAttribute("HideGear", true)
end

local function isGear(instance, character)
	local current = instance
	while current and current ~= character do
		local name = current.Name
		if string.sub(name, 1, 11) == "GearVisual_" or name == "GearAura" then return true end
		current = current.Parent
	end
	return false
end

local function apply(instance, hide)
	if instance:IsA("BasePart") or instance:IsA("Decal") then
		-- (LocalTransparencyModifier 는 기본 카메라가 줌할 때마다 0 으로 되돌려서 장비가 다시 보였다: 내 화면에서만 Transparency 를 직접 바꾼다)
		if hide then
			if savedT[instance] == nil then savedT[instance] = instance.Transparency end
			instance.Transparency = 1
		elseif savedT[instance] ~= nil then
			instance.Transparency = savedT[instance]
			savedT[instance] = nil
		end
	elseif instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail") or instance:IsA("Light") then
		if hide then
			if saved[instance] == nil then saved[instance] = instance.Enabled end
			instance.Enabled = false
		elseif saved[instance] ~= nil then
			instance.Enabled = saved[instance]
			saved[instance] = nil
		end
	end
end

local function refresh()
	local character = player.Character
	if not character then return end
	local hide = player:GetAttribute("HideGear") == true
	for _, instance in ipairs(character:GetDescendants()) do
		if isGear(instance, character) then apply(instance, hide) end
	end
end

local function watch(character)
	character.DescendantAdded:Connect(function(instance)
		if player:GetAttribute("HideGear") == true and isGear(instance, character) then
			task.defer(apply, instance, true) -- (속성이 다 정해진 다음에)
		end
	end)
	refresh()
end

player:GetAttributeChangedSignal("HideGear"):Connect(refresh)
player.CharacterAdded:Connect(watch)
if player.Character then watch(player.Character) end
