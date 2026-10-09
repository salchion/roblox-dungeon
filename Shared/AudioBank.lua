-- AudioBank (ReplicatedStorage 안의 ModuleScript, 이름: AudioBank)
-- 항목별 효과음 ID 목록. 이 파일은 "던전 업데이트"로 갱신된다 (소리 ID 를 알려주면 여기에 적어서 올려 준다).
-- 0 이거나 없는 항목은 기본 소리를 가공해서 쓴다. 항목 이름과 설명은 Shared/SoundBank.lua 참고.
-- (ReplicatedStorage > AudioIds 의 Bank = { ... } 에 직접 적은 값이 있으면 그쪽이 우선한다.)

return {
	Shot_Smg = 133095953198600, -- 기관단총 발사
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
	Dungeon_Clear = 76357092271646,
	Rare_Drop = 76357092271646,
	Aug_Missile = 542181791,        -- missile launch -> Aug_Missile / Aug_MeteorFall(낮게)
	Aug_MeteorFall = 542181791,
	Player_Hurt = 139071137654755,  -- 내가 맞았을 때
}
