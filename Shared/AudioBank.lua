-- AudioBank (ReplicatedStorage 안의 ModuleScript, 이름: AudioBank)
-- 항목별 효과음 ID 목록. 이 파일은 "던전 업데이트"로 갱신된다 (소리 ID 를 알려주면 여기에 적어서 올려 준다).
-- 0 이거나 없는 항목은 기본 소리를 가공해서 쓴다. 항목 이름과 설명은 Shared/SoundBank.lua 참고.
-- (ReplicatedStorage > AudioIds 의 Bank = { ... } 에 직접 적은 값이 있으면 그쪽이 우선한다.)

return {
	Shot_Smg = 103104730555203, -- 저격총 발사 (Smg = 저격총)
	Shot_Rocket = 100753572745319,  -- 로켓 발사
	Shot_Sniper = 0, -- 무기 종류가 총이 아닌 것으로 바뀌어서(활 / 석궁 / 수리검 / 폭탄 / 박격포 / 지팡이 / 마도서) 이전 총소리 ID 103104730555203 는 쓰지 않는다 (SoundBank 의 가공 소리가 나온다). 새 소리 ID 를 적으면 그게 우선이다
	Shot_Shotgun = 0, -- 무기 종류가 총이 아닌 것으로 바뀌어서(활 / 석궁 / 수리검 / 폭탄 / 박격포 / 지팡이 / 마도서) 이전 총소리 ID 118157022689657 는 쓰지 않는다 (SoundBank 의 가공 소리가 나온다). 새 소리 ID 를 적으면 그게 우선이다
	Shot_Rail = 76452326804540,     -- 레일건
	Shot_Cannon = 0, -- 무기 종류가 총이 아닌 것으로 바뀌어서(활 / 석궁 / 수리검 / 폭탄 / 박격포 / 지팡이 / 마도서) 이전 총소리 ID 86974396086300 는 쓰지 않는다 (SoundBank 의 가공 소리가 나온다). 새 소리 ID 를 적으면 그게 우선이다
	Shot_Flamer = 0, -- 무기 종류가 총이 아닌 것으로 바뀌어서(활 / 석궁 / 수리검 / 폭탄 / 박격포 / 지팡이 / 마도서) 이전 총소리 ID 138257634793906 는 쓰지 않는다 (SoundBank 의 가공 소리가 나온다). 새 소리 ID 를 적으면 그게 우선이다
	Shot_Revolver = 0, -- 무기 종류가 총이 아닌 것으로 바뀌어서(활 / 석궁 / 수리검 / 폭탄 / 박격포 / 지팡이 / 마도서) 이전 총소리 ID 18267120562 는 쓰지 않는다 (SoundBank 의 가공 소리가 나온다). 새 소리 ID 를 적으면 그게 우선이다
	Skill_Heal = 136612911524402, -- 응급 치료 스킬
	Hit = 3748776946,             -- 적중
	Kill = 98731043228812,        -- 적 처치 (enemy defeat)
	Enh_Success = 73627822697931, -- 강화 성공 (upgrade success)
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
	Aug_Blade = 121422898567513,    -- 튕기는 표창
	Aug_Flame = 138257634793906,    -- 화염 지대
	Ult_Missile = 112204190873336,  -- 데드아이 미사일 발사
	Player_Hurt = 139071137654755,  -- 내가 맞았을 때
}
