-- AudioBank (ReplicatedStorage 안의 ModuleScript, 이름: AudioBank)
-- 항목별 효과음 ID 목록. 이 파일은 "던전 업데이트"로 갱신된다 (소리 ID 를 알려주면 여기에 적어서 올려 준다).
-- 0 이거나 없는 항목은 기본 소리를 가공해서 쓴다. 항목 이름과 설명은 Shared/SoundBank.lua 참고.
-- (ReplicatedStorage > AudioIds 의 Bank = { ... } 에 직접 적은 값이 있으면 그쪽이 우선한다.)

return {
	Shot_Pistol = 0, -- 라이플 발사: 기본 총소리를 가공해서 쓴다 (저격총 소리는 길어서 연사 때 서로 씹혀 뺐다)
	Shot_Rocket = 100753572745319,  -- 로켓 발사
	Shot_Sniper = 0, -- 무기 종류가 총이 아닌 것으로 바뀌어서(활 / 석궁 / 수리검 / 폭탄 / 박격포 / 지팡이 / 마도서) 이전 총소리 ID 103104730555203 는 쓰지 않는다 (SoundBank 의 가공 소리가 나온다). 새 소리 ID 를 적으면 그게 우선이다
	Shot_Shotgun = 118157022689657, -- 샷건
	Shot_Rail = 76452326804540,     -- 레일건
	Shot_Cannon = 0, -- 무기 종류가 총이 아닌 것으로 바뀌어서(활 / 석궁 / 수리검 / 폭탄 / 박격포 / 지팡이 / 마도서) 이전 총소리 ID 86974396086300 는 쓰지 않는다 (SoundBank 의 가공 소리가 나온다). 새 소리 ID 를 적으면 그게 우선이다
	Shot_Flamer = 9116273112, -- 마법책 체인 라이트닝: Lightning Flashes Quick Electrical Bursts 19 (ProSoundEffects). 예전 소리 88135637638235
	Shot_Revolver = 0, -- 무기 종류가 총이 아닌 것으로 바뀌어서(활 / 석궁 / 수리검 / 폭탄 / 박격포 / 지팡이 / 마도서) 이전 총소리 ID 18267120562 는 쓰지 않는다 (SoundBank 의 가공 소리가 나온다). 새 소리 ID 를 적으면 그게 우선이다
	Skill_Heal = 136612911524402, -- 응급 치료 스킬
	Hit = 3748776946,             -- 적중
	Kill = 98731043228812,        -- 적 처치 (enemy defeat)
	Enh_Success = 2686079706,     -- 강화 성공: level up sound effect (예전: 9116384799 Magic Burst 2)
	Enh_Fail = 9119049679,        -- 강화 실패: Shale Break 9 (ProSoundEffects) 바위가 부서지는 "콰직"
	Enh_Evolve = 9120769331,      -- 무기 진화: Wind Whoosh Sonic Boom Low End Impact 1 (ProSoundEffects)
	Thunder_Crack = 9126069842,   -- 마법서 번개 끝 천둥: Synth Lightning Crack Sharp Some Rolling Tails (ProSoundEffects)
	Gacha_Shake = 9116420445,     -- 뽑기 흔들림: Magic Tone Tonal Shimmer Shaking Rattle 1 (ProSoundEffects)
	Chime = 73627822697931,       -- 예전 강화 성공 "띵": 치명타 / 줍기 / 레벨업 / 힐 / 데드아이 락온 소리의 기본 재료로 계속 쓴다
	Enh_Hammer = 9125819216,      -- 강화 망치 (metal clang)
	Skill_Ult = 70952641415058,   -- 데드아이 발동 (power up charge)
	Dash = 90661028523798,        -- 대시 (dash whoosh)
	Pickup = 107673144903206,     -- 전리품 줍기 (loot pickup)
	-- ↓ 아래 소리는 같은 ID 를 높낮이 / 음량만 달리해서 여러 항목에 돌려 쓴다 (높낮이는 Shared/SoundBank.lua 의 CustomPitch)
	Boom = 140615626179933,         -- 폭발 (boom)  -> Boom / Aug_Nova / Aug_MissileHit / Aug_MeteorHit / Aug_Execute / Boss_Spawn / Event_Boss / Penalty_Get
	Aug_MissileHit = 140615626179933,
	Aug_Nova = 140615626179933,
	Aug_MeteorHit = 140615626179933,
	Aug_Execute = 140615626179933,
	Boss_Spawn = 140615626179933,
	Event_Boss = 140615626179933,
	Penalty_Get = 140615626179933,
	Aug_Get = 130904532062911,      -- power up  -> Aug_Get / Buff_Get / Aug_Pulse / Dungeon_Start / Quest_Claim
	Buff_Get = 130904532062911,
	Aug_Pulse = 130904532062911,
	Dungeon_Start = 130904532062911,
	Quest_Claim = 130904532062911,
	Aug_Synergy = 76357092271646,   -- epic power up -> Aug_Synergy / Dungeon_Clear / Rare_Drop
	Dungeon_Clear = 9045298695,     -- 던전 클리어 (희귀 드랍 / 시너지와 따로)
	Dungeon_Fail = 140107605044294, -- 던전 실패
	Warn_Overrun = 6783209805,      -- 몬스터가 한도를 넘음 (경고음)
	Reel_Stop = 9119221148,         -- 첫 장비 슬롯 릴이 멈출 때 "띵"
	NearMiss_Get = 138149044086182, -- NEAR MISS 성공
	Rare_Drop = 76357092271646,
	Aug_Missile = 542181791,        -- missile launch -> Aug_Missile / Aug_MeteorFall(낮게)
	Aug_MeteorFall = 130619201421833, -- 유성 낙하 (전용 소리)
	Aug_Storm = 133560890939895,    -- 낙뢰 (천둥)
	-- F 스킬(죽음의 연꽃): 이미 있는 소리 ID 를 빌려 쓴다 (가공 소리는 너무 작게 들려서 원본 소리를 크게 튼다)
	Skill_LotusCast = 132487795891509,  -- 시전: 칼이 휘몰아치기 시작하는 소리 (직접 고른 소리)
	Skill_LotusThump = 140615626179933, -- 시전 때 깔리는 낮은 쿵: boom
	Skill_LotusSlash = 77197450336121,  -- 도는 동안 반복: 칼이 도는 소리 (직접 고른 소리)
	Skill_LotusStab = 78248480345821,   -- 꽂힐 때: 칼이 꽂히는 소리 (직접 고른 소리)
	Skill_LotusClang = 9125819216,      -- 칼끼리 부딪혀 튕기는 "챙": 강화 망치의 금속음(Enh_Hammer)을 아주 높고 짧게
	Aug_Blade = 121422898567513,    -- 튕기는 표창
	Aug_Flame = 138257634793906,    -- 화염 지대
	Ult_Missile = 112204190873336,  -- 데드아이 미사일 발사
	Player_Hurt = 139071137654755,  -- 내가 맞았을 때
}
