-- SoundBank (ReplicatedStorage 안의 ModuleScript, 이름: SoundBank)
-- 소리 한 곳 관리: 무기 종류마다 / 상황마다 소리가 다르게 들리게 한다.
--   * 내가 AudioIds 에 적은 기본 소리(Shot, EnhanceSuccess, ...) 하나를 "피치 / 길이 / 잔향 / 에코 / 왜곡 / 겹치기" 로 가공해서 여러 소리를 만든다.
--   * 소리 ID 가 따로 있으면 그걸 우선 쓴다: AudioIds 에  Bank = { Shot_Rail = 123456, Kill = 987654 }  처럼 적으면 된다 (키 이름은 아래 SPECS 참고).
--   * SoundBank.Play(부모, "Shot_Rocket", { Pitch = 배율, Volume = 배율, Name = "GunShot" })
-- 서버(총소리 / 스킬 / 폭발)와 클라이언트(적중음 / 처치음)가 같이 쓴다.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local SoundBank = {}

-- Base: Config.Audio 의 어떤 기본 소리를 가공할지 / Pitch: 재생 속도(높을수록 가늘고 빠름) / Volume: 배율 / Length: 이 시간(초) 뒤에 끊는다
-- Fx: 효과 목록 { 종류, 속성표 } / Layers: 겹쳐 울리는 소리 { Pitch, Volume, Delay }
local SPECS = {
	-- 무기 종류별 총소리 (Shot 소리를 가공)
	Shot_Pistol   = { Base = "Shot", Pitch = 1.15, Volume = 1.0, Length = 0.7 },
	Shot_Smg      = { Base = "Shot", CustomLength = 0.9, Pitch = 1.5, Volume = 0.55, Length = 0.35 },
	Shot_Revolver = { Base = "Shot", Pitch = 0.82, Volume = 1.2, Length = 1.3, Fx = { { "reverb", { DecayTime = 1.4, WetLevel = -4 } } } },
	Shot_Rifle    = { Base = "Shot", Pitch = 1.0, Volume = 0.9, Length = 0.9, Fx = { { "reverb", { DecayTime = 0.8, WetLevel = -9 } } } },
	Shot_Shotgun  = { Base = "Shot", Pitch = 0.7, Volume = 1.3, Length = 1.0, Fx = { { "distortion", { Level = 0.35 } } },
		Layers = { { Pitch = 0.5, Volume = 0.9, Delay = 0 }, { Pitch = 1.3, Volume = 0.5, Delay = 0.03 } } },
	Shot_Flamer   = { Base = "Shot", Pitch = 0.6, Volume = 0.7, Length = 0.4, Fx = { { "chorus", { Depth = 0.7, Mix = 0.6 } }, { "distortion", { Level = 0.3 } } } },
	Shot_Cannon   = { Base = "Shot", Pitch = 0.62, Volume = 1.3, Length = 1.5, Fx = { { "reverb", { DecayTime = 2.2, WetLevel = -3 } }, { "pitchshift", { Octave = 0.85 } } } },
	Shot_Sniper   = { Base = "Shot", Pitch = 0.8, Volume = 1.3, Length = 2.0, Fx = { { "reverb", { DecayTime = 2.8, WetLevel = -3 } }, { "echo", { Delay = 0.22, Feedback = 0.3, WetLevel = -8 } } } },
	Shot_Rocket   = { Base = "Shot", Pitch = 0.55, Volume = 1.4, Length = 1.5, Fx = { { "distortion", { Level = 0.5 } }, { "echo", { Delay = 0.15, Feedback = 0.35, WetLevel = -6 } } },
		Layers = { { Pitch = 0.4, Volume = 1.0, Delay = 0.12 } } },
	Shot_Rail     = { Base = "Shot", Pitch = 1.9, Volume = 1.0, Length = 1.0, Fx = { { "chorus", { Depth = 0.8, Mix = 0.7 } }, { "echo", { Delay = 0.07, Feedback = 0.45, WetLevel = -5 } } },
		Layers = { { Pitch = 0.9, Volume = 0.6, Delay = 0.02 } } },
	-- 적중 / 처치 / 치명타 (짧고 선명하게)
	Hit  = { Base = "Shot", CustomLength = 0.6, Pitch = 3.0, Volume = 0.5, Length = 0.09 },
	-- 치명타 (오버워치 헤드샷 느낌): 짧고 깨끗한 금속 "팅!" + 5도 위 배음이 살짝 늦게 + 아주 짧은 반짝 꼬리, 저음은 깎아 낸다
	Crit = { Base = "Enh_Success", Pitch = 2.3, Volume = 0.9, Length = 0.22, CustomLength = 0.7,
		Fx = { { "eq", { LowGain = -30, MidGain = 2, HighGain = 3 } }, { "echo", { Delay = 0.06, Feedback = 0.25, WetLevel = -9 } } },
		Layers = { { Pitch = 3.45, Volume = 0.55, Delay = 0.012 }, { Pitch = 4.6, Volume = 0.25, Delay = 0.03 } } },
	Kill = { Base = "EnhanceSuccess", CustomLength = 1.2, Pitch = 1.5, Volume = 0.7, Length = 0.35, Fx = { { "reverb", { DecayTime = 0.6, WetLevel = -10 } } } },
	-- 스킬 / 폭발 / 레벨업
	Skill_Heal = { CustomLength = 2.5, Base = "Enh_Success", Pitch = 1.1, Volume = 0.8, Length = 0.9, Fx = { { "reverb", { DecayTime = 1.6, WetLevel = -6 } } } },
	Skill_Ult  = { Base = "Shot", CustomLength = 3.0, Pitch = 0.4, Volume = 1.6, Length = 1.8, Fx = { { "reverb", { DecayTime = 3.0, WetLevel = -2 } }, { "distortion", { Level = 0.4 } } },
		Layers = { { Pitch = 1.6, Volume = 0.6, Delay = 0.08 } } },
	UltShot = { Base = "Shot", Pitch = 1.4, Volume = 0.8, Length = 0.3, Fx = { { "chorus", { Depth = 0.5, Mix = 0.5 } } } },
	Boom    = { CustomLength = 1.6, Base = "Enh_Hammer", Pitch = 0.45, Volume = 1.5, Length = 1.1, Fx = { { "distortion", { Level = 0.55 } }, { "reverb", { DecayTime = 1.8, WetLevel = -4 } } } },
	LevelUp = { Base = "Enh_Success", Pitch = 1.0, Volume = 1.0, Length = 1.4, Fx = { { "reverb", { DecayTime = 1.8, WetLevel = -5 } } },
		Layers = { { Pitch = 1.5, Volume = 0.7, Delay = 0.12 }, { Pitch = 2.0, Volume = 0.5, Delay = 0.26 } } },
}

-- 강화 / 뽑기 연출음 (UI 에서 재생)
SPECS.Enh_Hammer  = { Base = "Shot", CustomLength = 1.5, Pitch = 0.5, Volume = 1.0, Length = 0.18, Fx = { { "distortion", { Level = 0.45 } } },
	Layers = { { Pitch = 1.8, Volume = 0.35, Delay = 0.01 } } }                       -- 모루를 내려치는 "쾅"
SPECS.Enh_Success = { Base = "EnhanceSuccess", CustomLength = 1.6, Pitch = 1.0, Volume = 0.9, Length = 0.8, Fx = { { "reverb", { DecayTime = 1.0, WetLevel = -8 } } },
	Layers = { { Pitch = 1.5, Volume = 0.45, Delay = 0.07 } } }                        -- 성공 "띵~" (단계가 오를수록 음이 높아진다)
SPECS.Enh_Fail    = { Base = "Enh_Hammer", Pitch = 0.55, Volume = 0.8, Length = 0.6, Fx = { { "reverb", { DecayTime = 1.4, WetLevel = -6 } }, { "eq", { HighGain = -20, MidGain = -4 } } } } -- 둔탁하게 "툭..."
SPECS.Enh_Evolve  = { Base = "Enh_Success", Pitch = 0.9, Volume = 1.1, Length = 2.0, Fx = { { "reverb", { DecayTime = 2.4, WetLevel = -3 } } },
	Layers = { { Pitch = 1.13, Volume = 0.8, Delay = 0.12 }, { Pitch = 1.35, Volume = 0.8, Delay = 0.24 }, { Pitch = 1.8, Volume = 0.9, Delay = 0.36 }, { Pitch = 0.45, Volume = 1.0, Delay = 0.0 } } }
SPECS.Gacha_Drop  = { Base = "Enh_Hammer", Pitch = 0.9, Volume = 0.6, Length = 0.3, Fx = { { "reverb", { DecayTime = 0.8, WetLevel = -8 } } } }   -- 캡슐 낙하 "텅"
SPECS.Gacha_Tick  = { Base = "Hit", Pitch = 1.3, Volume = 0.7, Length = 0.1, CustomLength = 0.2 }                                                      -- 흔들릴 때 "틱틱"
SPECS.Gacha_Card  = { Base = "Kill", Pitch = 1.2, Volume = 0.5, Length = 0.25 }                                            -- 10연 카드 한 장씩
SPECS.Dash   = { Base = "Shot", Pitch = 0.35, Volume = 5.5, Length = 0.4, CustomLength = 1.0, Fx = { { "eq", { HighGain = -12 } } } }  -- 대시 "슈웅"
SPECS.Pickup = { Base = "Enh_Success", Pitch = 2.2, Volume = 0.5, Length = 0.25, CustomLength = 1.0 }                        -- 전리품 줍기 "팅"
local POP_PITCHES = { 1.0, 1.26, 1.5, 2.0, 2.52 }
for rarity = 1, 5 do                                                                                                                   -- 퍽! 등급이 높을수록 음이 더 많이 쌓인다
	local layers = {}
	for i = 2, rarity do
		table.insert(layers, { Pitch = POP_PITCHES[i], Volume = 0.65, Delay = (i - 1) * 0.1 })
	end
	SPECS["Gacha_Pop" .. rarity] = { Base = "Enh_Success", Pitch = POP_PITCHES[1], Volume = 0.8 + rarity * 0.08, Length = 0.9 + rarity * 0.2,
		Fx = { { "reverb", { DecayTime = 0.8 + rarity * 0.4, WetLevel = -7 + rarity } } }, Layers = layers }
end
-- ★ 직접 고른 소리 전용 항목: 기본 소리를 가공하지 않는다. AudioBank 에 ID 를 적기 전에는 소리가 나지 않는다.
--   (Volume = 음량 배율 / CustomLength = 이 시간(초)이 지나면 끊는다. 소리가 너무 크거나 길면 여기 숫자를 줄이면 된다.)
local CUSTOM_ONLY = {
	-- 어그먼트
	Aug_Get       = { Volume = 1.0, CustomLength = 1.6, CustomPitch = 1.0 }, -- 어그먼트를 얻는 순간 (몸에서 빛이 퍼진다)
	Aug_Synergy   = { Volume = 1.1, CustomLength = 2.2, CustomPitch = 1.0 }, -- 시너지 발동
	Aug_Missile   = { Volume = 0.7, CustomLength = 1.0, CustomPitch = 1.0 }, -- 치명타 미사일 발사
	Aug_MissileHit = { Volume = 0.35, CustomLength = 0.5, CustomPitch = 1.8 }, -- 미사일 명중
	Aug_Nova      = { Volume = 0.7, CustomLength = 1.2, CustomPitch = 1.2 }, -- 처치 폭발
	Aug_Blade     = { Volume = 0.5, CustomLength = 0.6 }, -- 회전 칼날이 벨 때 (자주 난다: 짧게)
	Aug_Storm     = { Volume = 1.0, CustomLength = 1.8 }, -- 낙뢰 (천둥)
	Aug_MeteorFall = { Volume = 0.8, CustomLength = 1.4, CustomPitch = 0.5 }, -- 유성이 떨어지는 소리
	Aug_MeteorHit = { Volume = 1.3, CustomLength = 2.0, CustomPitch = 0.7 }, -- 유성 착탄 (큰 폭발)
	Aug_Flame     = { Volume = 0.6, CustomLength = 1.2 }, -- 불길이 생길 때
	Aug_Execute   = { Volume = 0.5, CustomLength = 0.6, CustomPitch = 1.5 }, -- 처형
	Aug_Pulse     = { Volume = 0.6, CustomLength = 1.0, CustomPitch = 1.5 }, -- 수호 파동
	Buff_Get      = { Volume = 0.7, CustomLength = 1.0, CustomPitch = 1.25 }, -- 일반 랜덤 강화를 얻을 때
	Penalty_Get   = { Volume = 0.8, CustomLength = 1.4, CustomPitch = 0.55 }, -- 랜덤 패널티가 걸릴 때 (불길한 소리)
	-- 위기 / 경고
	Player_Hurt   = { Volume = 0.8, CustomLength = 0.6 }, -- 내가 맞았을 때
	Low_Health    = { Volume = 0.8, CustomLength = 1.0 }, -- 체력이 25% 아래일 때 (심장 소리 / 삐-)
	Warn_Overrun  = { Volume = 1.0, CustomLength = 2.0 }, -- 던전에서 몬스터가 한도를 넘었을 때 경고
	Shield_Block  = { Volume = 0.8, CustomLength = 0.6 }, -- 방패 기사에게 막혔을 때 (쨍!)
	-- 이벤트 / 보스
	Event_Siren   = { Volume = 1.0, CustomLength = 3.5 }, -- 공습 사이렌
	Event_Stampede = { Volume = 1.0, CustomLength = 3.0 }, -- 몬스터 대이동 (발굽 소리 / 뿔피리)
	Event_Elite   = { Volume = 1.0, CustomLength = 2.5 }, -- 엘리트 부대 출현 (나팔)
	Event_Goblin  = { Volume = 0.9, CustomLength = 2.0 }, -- 황금 고블린 출현 (반짝 / 동전)
	Event_Boss    = { Volume = 1.0, CustomLength = 2.2, CustomPitch = 0.6 }, -- 침공 사령관 출현 (공개 이벤트)
	Boss_Spawn    = { Volume = 1.2, CustomLength = 2.5, CustomPitch = 0.5 }, -- 던전 보스 등장 (포효)
	Boss_Enrage   = { Volume = 1.2, CustomLength = 2.5 }, -- 보스 격노
	-- 진행
	Dungeon_Start = { Volume = 0.8, CustomLength = 1.4, CustomPitch = 0.85 }, -- 던전 시작
	Dungeon_Clear = { Volume = 1.2, CustomLength = 3.0, CustomPitch = 0.9 }, -- 던전 클리어 (팡파르)
	Dungeon_Fail  = { Volume = 1.0, CustomLength = 3.0 }, -- 던전 실패
	Quest_Claim   = { Volume = 0.6, CustomLength = 1.0, CustomPitch = 1.5 }, -- 퀘스트 / 업적 보상 수령 (동전)
	Rare_Drop     = { Volume = 0.8, CustomLength = 1.8, CustomPitch = 1.15 }, -- 희귀 이상 장비 획득
}
for key, spec in pairs(CUSTOM_ONLY) do
	SPECS[key] = spec
end
SoundBank.Specs = SPECS

-- 이 항목에 소리가 있는지 (내가 넣은 ID 나 가공할 기본 소리가 있을 때만 true): 소리 없는 항목은 재생 준비도 하지 않게 한다
function SoundBank.Has(key)
	local spec = SPECS[key]
	if not spec then return false end
	local bank = Config.Audio.Bank
	if bank and bank[key] and bank[key] ~= 0 then return true end
	local base = spec.Base and ((bank and bank[spec.Base] and bank[spec.Base] ~= 0 and bank[spec.Base]) or Config.Audio[spec.Base])
	return base ~= nil and base ~= 0 and base ~= false
end

-- 사운드 테스트 창(Studio 에서 K 키)에 보이는 항목별 설명
SoundBank.Descriptions = {
	Dash = "대시 (Q)", Pickup = "전리품 줍기",
	Shot_Pistol = "권총 발사", Shot_Smg = "기관단총 발사", Shot_Revolver = "리볼버 발사", Shot_Rifle = "라이플 발사", Shot_Shotgun = "샷건 발사",
	Shot_Flamer = "화염방사기 발사", Shot_Cannon = "플라즈마 캐논 발사", Shot_Sniper = "저격총 발사", Shot_Rocket = "로켓 런처 발사", Shot_Rail = "레일건 발사",
	Hit = "적을 맞췄을 때 (짧게)", Crit = "치명타", Kill = "적 처치 (연속 처치할수록 높아짐)",
	Skill_Heal = "응급 치료 사용", Skill_Ult = "데드아이 발동", UltShot = "데드아이 연사 한 발", Boom = "몬스터 폭발 / 충격파 / 운석",
	LevelUp = "레벨업", Enh_Hammer = "강화: 망치 내려치기", Enh_Success = "강화 성공 (단계가 오를수록 높아짐)", Enh_Fail = "강화 실패",
	Enh_Evolve = "무기 진화", Gacha_Drop = "뽑기: 캡슐 낙하", Gacha_Tick = "뽑기: 흔들리는 틱틱", Gacha_Card = "10연 뽑기: 카드 한 장",
	Aug_Get = "어그먼트 획득", Aug_Synergy = "어그먼트 시너지 발동", Aug_Missile = "크리 미사일 발사", Aug_MissileHit = "미사일 명중", Aug_Nova = "처치 폭발",
	Aug_Blade = "회전 칼날 베기", Aug_Storm = "낙뢰", Aug_MeteorFall = "유성 낙하", Aug_MeteorHit = "유성 착탄", Aug_Flame = "화염 지대", Aug_Execute = "처형", Aug_Pulse = "수호 파동",
	Buff_Get = "일반 강화 획득", Penalty_Get = "패널티 발동", Player_Hurt = "내가 맞음", Low_Health = "체력 위험", Warn_Overrun = "몬스터 한도 경고", Shield_Block = "방패에 막힘",
	Event_Siren = "공습 사이렌", Event_Stampede = "몬스터 대이동", Event_Elite = "엘리트 부대 출현", Event_Goblin = "황금 고블린 출현", Event_Boss = "침공 사령관 출현",
	Boss_Spawn = "던전 보스 등장", Boss_Enrage = "보스 격노", Dungeon_Start = "던전 시작", Dungeon_Clear = "던전 클리어", Dungeon_Fail = "던전 실패", Quest_Claim = "퀘스트 보상 수령", Rare_Drop = "희귀 장비 획득",
	Gacha_Pop1 = "뽑기 결과: 일반", Gacha_Pop2 = "뽑기 결과: 희귀", Gacha_Pop3 = "뽑기 결과: 영웅", Gacha_Pop4 = "뽑기 결과: 전설", Gacha_Pop5 = "뽑기 결과: 신화",
}
SoundBank.Order = {
	"Shot_Pistol", "Shot_Smg", "Shot_Revolver", "Shot_Rifle", "Shot_Shotgun", "Shot_Flamer", "Shot_Cannon", "Shot_Sniper", "Shot_Rocket", "Shot_Rail",
	"Hit", "Crit", "Kill", "Skill_Heal", "Skill_Ult", "UltShot", "Boom", "LevelUp",
	"Dash", "Pickup", "Enh_Hammer", "Enh_Success", "Enh_Fail", "Enh_Evolve", "Gacha_Drop", "Gacha_Tick", "Gacha_Card",
	"Gacha_Pop1", "Gacha_Pop2", "Gacha_Pop3", "Gacha_Pop4", "Gacha_Pop5",
	"Aug_Get", "Aug_Synergy", "Aug_Missile", "Aug_MissileHit", "Aug_Nova", "Aug_Blade", "Aug_Storm", "Aug_MeteorFall", "Aug_MeteorHit", "Aug_Flame", "Aug_Execute", "Aug_Pulse",
	"Buff_Get", "Penalty_Get", "Player_Hurt", "Low_Health", "Warn_Overrun", "Shield_Block",
	"Event_Siren", "Event_Stampede", "Event_Elite", "Event_Goblin", "Event_Boss", "Boss_Spawn", "Boss_Enrage",
	"Dungeon_Start", "Dungeon_Clear", "Dungeon_Fail", "Quest_Claim", "Rare_Drop",
}

local EFFECT_CLASS = {
	reverb = "ReverbSoundEffect", echo = "EchoSoundEffect", distortion = "DistortionSoundEffect",
	chorus = "ChorusSoundEffect", pitchshift = "PitchShiftSoundEffect", eq = "EqualizerSoundEffect",
}

local function addEffects(sound, fxList)
	for _, fx in ipairs(fxList or {}) do
		local className = EFFECT_CLASS[fx[1]]
		if className then
			local ok, effect = pcall(Instance.new, className)
			if ok and effect then
				for property, value in pairs(fx[2] or {}) do
					pcall(function() effect[property] = value end)
				end
				effect.Parent = sound
			end
		end
	end
end

-- 키에 해당하는 소리 ID: 직접 적은 Bank ID 가 먼저, 없으면 기본 소리(Base)를 가공
local function idFor(key, spec)
	local bank = Config.Audio.Bank
	if bank and bank[key] and bank[key] ~= 0 then
		return bank[key], true
	end
	-- 기본 소리(Base)는 내가 넣은 다른 항목(Bank)도 될 수 있다: 예) 폭발음은 강화 망치 소리를 낮게 가공
	local base = (bank and bank[spec.Base] and bank[spec.Base] ~= 0 and bank[spec.Base]) or Config.Audio[spec.Base]
	if base and base ~= 0 then
		return base, false
	end
	return nil, false
end

local function playOne(parent, id, volume, pitch, length, name, fx)
	local sound = Instance.new("Sound")
	sound.Name = name or "Sfx"
	sound.SoundId = "rbxassetid://" .. id
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.RollOffMaxDistance = 90
	addEffects(sound, fx)
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, length + 0.2)
	return sound
end

-- opts: Pitch(배율) / Volume(배율) / Name(소리 이름; 총소리는 "GunShot" 으로 두면 설정창 볼륨이 적용된다)
function SoundBank.Play(parent, key, opts)
	local spec = SPECS[key]
	if not spec or not parent then return end
	local id, custom = idFor(key, spec)
	if not id then return end
	opts = opts or {}
	local volumeScale = (opts.Volume or 1) * spec.Volume
	if string.sub(key, 1, 4) == "Shot" then
		volumeScale *= Config.Audio.ShotVolume / 0.3 -- 총소리 기본 크기 설정(ShotVolume)을 그대로 따른다
	end
	local baseVolume = 0.35 * volumeScale
	local pitch = custom and (opts.Pitch or 1) * (spec.CustomPitch or 1) or spec.Pitch * (opts.Pitch or 1) -- CustomPitch: 같은 소리를 여러 항목에 재사용할 때 높낮이를 달리한다
	local length = spec.Length or 1
	if custom then length = spec.CustomLength or 2 end -- 내가 넣은 소리는 자연스러운 꼬리를 살리고, 너무 길 때만 끊는다
	local main = playOne(parent, id, baseVolume, pitch, length, opts.Name, not custom and spec.Fx or nil)
	if not custom then
		for _, layer in ipairs(spec.Layers or {}) do
			task.delay(layer.Delay or 0, function()
				if parent.Parent then
					playOne(parent, id, baseVolume * (layer.Volume or 1), layer.Pitch * (opts.Pitch or 1), length, opts.Name, nil)
				end
			end)
		end
	end
	-- 길이를 넘는 꼬리는 잘라 낸다 (짧고 또렷하게)
	task.delay(length, function()
		if main.Parent then
			main.Volume = main.Volume * 0.5
			task.delay(0.15, function() if main.Parent then main:Stop() end end)
		end
	end)
	return main
end

return SoundBank
