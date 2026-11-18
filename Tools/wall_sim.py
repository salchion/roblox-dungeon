#!/usr/bin/env python3
"""벽 난이도 시뮬레이션 — 권장 전투력 vs 도달 가능 전투력 · 벽 비용 배율 · 최종 군주 처치 시간.

사용:
    python3 Tools/wall_sim.py             표를 터미널에 출력
    python3 Tools/wall_sim.py --md FILE   같은 내용을 마크다운으로 저장

읽기 전용 분석 도구. Config / 서버 파일은 건드리지 않는다.
모든 숫자는 Shared/Config.lua · Server/FieldService.lua · Server/MonsterTypes.lua 의
실제 공식을 그대로 옮겨 계산한다 (아래 CONFIG 절 주석의 줄 번호는 2026-11-18 main = 1c34758 기준).

2026-11-18 (1c34758 "전투력에 켜 둔 세트 효과 단계 반영"):
  * Config.GetPower 가 (dps x 10 + 체력 x 0.5) x (1 + 0.12 x AugAtkLv + 0.05 x AugDefLv) 로 바뀌었다.
    여기의 `power()` / `aug_*` 가 그 식을 그대로 따라간다.
  * 권장 전투력도 RecommendPowerBase x (1 + 0.12 x RecommendAugLv) 로 계산해 쓴다.
  * 세트 효과 단계(AugAtkLv)는 플레이어 선택에 달렸으므로 아래 세 가정으로 계산한다:
    번 돈의 AUG_BUDGET_SHARE 를 세트 효과에 쓰고(골드 0~3단계), 세트 부위 0~3, 방어 기재만 수호석 4~6.
가정은 docs 문자열과 `analysis/gear-rush-wall-simulation-2026-11-16.md` 에 함께 적혀 있다.
"""
import math
import sys

# =====================================================================
# CONFIG — Shared/Config.lua · Server 코드에서 옮긴 값
# =====================================================================
BASE_DAMAGE = 10            # Config.Player.BaseDamage
BASE_COOLDOWN = 0.35        # Config.Player.BaseCooldown
CRIT_MULT = 2               # Config.Player.CritMultiplier
CRIT_PER_POINT = 0.04       # Config.Player.CritPerPoint
SPEED_PER_POINT = 0.08      # Config.Player.SpeedPerPoint

LEVEL_MAX = 400             # Config.Level.Max
LATE_START = 50             # Config.Level.LateStart
DMG_PER_LEVEL = 0.03        # Config.Level.DamagePerLevel
LATE_DMG_PER_LEVEL = 0.006  # Config.Level.LateDamagePerLevel
HP_PER_LEVEL = 8            # Config.Level.HealthPerLevel
STAT_CAP = 200              # Config.Level.StatCap
POST_HP_PER_LEVEL = 25      # Config.Level.PostHealthPerLevel

WEAPON_COUNT = 50           # Config.Weapon.WeaponCount
ERAS_PER_LEVEL = 1.4
ERAS_LATE = 1.25


def steps_for(index):
    if index <= 5:
        return 15
    if index <= 10:
        return 20
    if index <= 30:
        return 24
    return 20


STEPS = [steps_for(i) for i in range(1, WEAPON_COUNT + 1)]
TOTAL_STEPS = sum(STEPS)                       # 1,055
MAX_LEVEL = TOTAL_STEPS - 1                    # 1,054
LEVEL_SCALE = 326 / TOTAL_STEPS                # Config.Weapon.LevelScale = 326/1055
TIER_START, _acc = [], 0
for _s in STEPS:
    TIER_START.append(_acc)
    _acc += _s

INCOME_BASE = 1500          # Config.Economy.IncomeBase
STEP_MIN_EARLY = 0.2        # Config.Economy.StepMinutesEarly
STEP_MIN_LATE = 1.2         # Config.Economy.StepMinutesLate
LATE_LEVEL = 600            # Config.Economy.LateLevel

ZONE_COUNT = 8
# 권장 전투력: 표 값(RecommendPowerBase) x 세트 효과 배율 (11-17 B안, Config.PowerAug)
#   Config.Field.RecommendAugLv = 그 구역 관문에 도달할 때 보통 켜 둔 공격 효과 단계 합 (임시 가정)
POWER_AUG_ATTACK = 0.12     # Config.PowerAug.Attack
POWER_AUG_DEFENSE = 0.05    # Config.PowerAug.Defense
RECOMMEND_POWER_BASE = [350, 750, 1700, 5500, 12000, 33000, 84000, 310000]  # Config.Field.RecommendPowerBase
RECOMMEND_AUG_LV = [0, 1, 3, 5, 7, 9, 11, 12]                              # Config.Field.RecommendAugLv (임시 가정)


def _recommend_power(aug_atk):
    """Config.lua 1140~1146행의 do 블록과 같은 식 (50 단위 반올림)."""
    return [int(math.floor(base * (1 + POWER_AUG_ATTACK * (aug_atk[z - 1] or 0)) / 50 + 0.5) * 50)
            for z, base in enumerate(RECOMMEND_POWER_BASE, start=1)]


RECOMMEND_POWER = _recommend_power(RECOMMEND_AUG_LV)   # 350/850/2300/8800/22100/68650/194900/756400

# ---------------------------------------------------------------- 세트 효과 (Config.Sets / AugService)
AUG_SLOTS = 14                                    # Config.Sets.ZoneAug: 1~8 공격 / 9~14 방어
AUG_ATTACK = range(1, 9)
AUG_DEFENSE = range(9, 15)
AUG_HOME_ZONE = {9: 3, 10: 4, 11: 5, 12: 6, 13: 7, 14: 8}   # Config.Sets.AugHomeZone (방어 기재)
AUG_SLOT_ZONES = (0, 2, 4)                        # Config.Sets.AugSlotZones
AUG_MAX_LEVEL = 6                                 # Config.Inventory.AugMaxLevel (골드 3 + 세트 부위 3)
AUG_COST_MULT = (1, 2.5, 6)                       # Config.Sets.AugCostMult
ZONE_HEALTH = [1, 1.5, 2.4, 13, 24, 57, 120, 195]                            # Config.Field.ZoneDanger.Health
ZONE_DAMAGE = [1, 1.5, 2.5, 5.6, 7.1, 11, 12.1, 15.5]                        # Config.Field.ZoneDanger.Damage
ZONE_REWARD = [1, 1.5, 2.2, 7.2, 9.2, 14.3, 21.6, 33.8]                      # Config.Field.ZoneDanger.Reward
EARLY_MOB_HEALTH = {1: 0.45, 2: 0.8}                                         # Config.Field.EarlyMobHealth
GATE_KILLS = [40, 55, 70, 85, 100, 120, 140]                                 # Config.Field.Gate.KillsNeeded
LORD_HEALTH = {4: 10}                                                        # Config.Field.ZoneDanger.LordHealth
ZONE_POOLS = [                                                               # Config.Field.ZonePools
    {"Slime": 5, "Bat": 2, "Spider": 1},
    {"Slime": 3, "Spitter": 3, "Bat": 2, "Spider": 2, "Wisp": 1},
    {"Spitter": 2, "Charger": 2, "Golem": 1, "Imp": 3, "Turret": 3, "Healer": 1},
    {"Charger": 3, "Bomber": 3, "Spitter": 2, "Spider": 2, "Imp": 2, "Healer": 1},
    {"Mage": 3, "Golem": 2, "Bat": 3, "Wisp": 2},
    {"Bomber": 3, "Charger": 3, "Mage": 2, "Turret": 2, "Totem": 1},
    {"Mage": 3, "Golem": 2, "Charger": 2, "Bomber": 2, "Imp": 2, "Totem": 1},
    {"Mage": 2, "Golem": 3, "Charger": 3, "Bomber": 3, "Spitter": 1, "Turret": 2, "Totem": 2, "Wisp": 2},
]
MOB_DEFS = {  # Server/MonsterTypes.lua M.Defs : (HealthMult, GoldMult)
    "Slime": (1.0, 1.0), "Spitter": (0.9, 1.1), "Bat": (0.55, 0.9), "Mage": (0.8, 1.4),
    "Golem": (2.2, 1.7), "Charger": (1.3, 1.4), "Bomber": (0.6, 0.8), "Imp": (0.6, 1.3),
    "Turret": (1.7, 1.4), "Spider": (0.8, 1.0), "Wisp": (0.45, 1.1), "Healer": (1.0, 2.2),
    "Totem": (2.2, 1.8),
}
HORDE_HEALTH, HORDE_REWARD = 0.7, 0.72      # Config.Horde.Health / Reward
FIELD_GOLD_MULT = 2.6                       # Config.Economy.FieldGoldMult
MOB_DAMAGE_MULT = 1.2                       # Config.Field.MobDamageMult
XP_PER_MOB_LEVEL = 4                        # Config.Xp.FieldPerMonsterLevel
XP_ZONE_MULT = [1, 1.5, 2.2, 5.4, 8, 12, 18, 26]   # Config.Xp.ZoneMult
KILLS_PER_MIN_REF = 100                     # Config.Idle.KillsPerMin (수입 공식의 전제)

GEAR_MAX_LEVEL = 30                         # Config.Gear.MaxLevel
GEAR_LEVEL_BONUS = 0.05                     # Config.Gear.LevelBonus
RARITY_MULT = [1, 1.8, 3.2, 5.4, 8.2]       # Config.Gear.RarityMult
GEAR_SLOTS = {                              # Config.Gear.Slots
    "Armor": ("Health", 40.0), "Helmet": ("Damage", 0.03), "Gloves": ("Crit", 0.02),
    "Boots": ("Speed", 0.6), "Ring": ("Haste", 0.02), "Necklace": ("Luck", 0.05),
}
GEAR_BASE_COST = {"Armor": 120, "Gloves": 100, "Boots": 100, "Helmet": 130, "Ring": 140, "Necklace": 140}
AFFIX_SCALE = [1, 1.3, 1.7, 2.2, 3.0]       # Config.Inventory.AffixRarityScale
AFFIX_COUNT = [0, 1, 2, 3, 4]               # Config.Inventory.AffixCount
AFFIX_BASE = {"Health": 30, "Crit": 0.012, "Damage": 0.03}
AFFIX_WEIGHT = {"Health": 1, "Crit": 1, "Speed": 0.6, "Damage": 1, "Xp": 0.5, "Luck": 0.5,
                "CritDmg": 1, "AtkSpeed": 1, "BossDmg": 1, "Haste": 1, "Bulwark": 1, "LifeOnKill": 1}
FIRST_CLEAR_RARITY = [3, 3, 4, 4, 4, 5, 5, 5]   # Config.Loot.FirstClear.GearRarity (대표 등급)
TRAIN_TIME_BASE, TRAIN_TIME_GROWTH = 120, 1.22  # Config.Growth.TimeBase / TimeGrowth
TRAIN_PER = {"Attack": 0.025, "Health": 12, "Crit": 0.012}   # Config.Growth.Stats.*.Per
TRAIN_MAXLV = {"Attack": 30, "Health": 30, "Crit": 10}
SINK_MINUTES = 600                          # Config.SinkMinutes

# =====================================================================
# 공식
# =====================================================================


def tier_of(level):
    idx = 0
    for i, first in enumerate(TIER_START):
        if level >= first:
            idx = i
    return idx + 1


def era_of(level):
    return (tier_of(level) - 1) // 5 + 1


def weapon_power(level):
    """Config.GetWeaponPower (2388행)."""
    era = era_of(level)
    e = level * LEVEL_SCALE
    return (1 + 0.04 * e + 0.00012 * e * e) * ERAS_PER_LEVEL ** min(era - 1, 4) * ERAS_LATE ** max(0, era - 5)


def damage_multiplier(level):
    """Config.GetDamageMultiplier (2380행) — 경제 계산용."""
    era = era_of(level)
    e = level * LEVEL_SCALE
    return (1 + 0.04 * e + 0.00012 * e * e) * ERAS_PER_LEVEL ** (era - 1)


def price_mult(level):
    """Config.PriceMult (2420행)."""
    def lerp(a, b, t):
        return a + (b - a) * min(1.0, max(0.0, t))
    if level <= 175:
        return 1.0
    if level <= 215:
        return lerp(1, 5, (level - 175) / 40)
    if level <= 300:
        return lerp(5, 3, (level - 215) / 85)
    if level <= 400:
        return lerp(3, 2.5, (level - 300) / 100)
    if level <= 700:
        return lerp(2.5, 2.2, (level - 400) / 300)
    return lerp(2.2, 1.5, (level - 700) / max(1, MAX_LEVEL - 700))


def step_cost(level):
    """Config.GetEnhanceCost 의 원래 식 (2420·2371행)."""
    minutes = STEP_MIN_EARLY + (STEP_MIN_LATE - STEP_MIN_EARLY) * min(1, level / LATE_LEVEL)
    return max(1, math.floor(INCOME_BASE * damage_multiplier(level) * minutes * price_mult(level)))


def step_chance(level):
    """Config.GetEnhanceChance (2376행)."""
    return max(0.5, 0.95 - 0.0015 * level * LEVEL_SCALE)


COST_TABLE, _best = [], 0                    # Config.GetEnhanceCost 은 '최댓값 표'를 쓴다 (2543행)
for _l in range(MAX_LEVEL + 1):
    _best = max(_best, step_cost(_l))
    COST_TABLE.append(_best)


def cost_at(level):
    return COST_TABLE[min(max(level, 0), MAX_LEVEL)]


def expected_step_gold(level):
    return cost_at(level) / step_chance(level)


def level_damage_mult(level):
    early = min(level, LATE_START) - 1
    late = max(0, level - LATE_START)
    return 1 + DMG_PER_LEVEL * early + LATE_DMG_PER_LEVEL * late


def level_health(level):
    return (min(level, STAT_CAP) - 1) * HP_PER_LEVEL + max(0, level - STAT_CAP) * POST_HP_PER_LEVEL


def xp_needed(level):
    """Config.GetXpNeeded (1593행)."""
    if level <= LATE_START:
        return math.floor(50 * level ** 1.75)
    base = 50 * LATE_START ** 1.75
    return math.floor(base * (level / LATE_START) ** 1.35)


def power(weapon_level, level, gear_hp, gear_crit, bonus_damage, crit_points=0, speed_points=0, aug_atk=0, aug_def=0):
    """Config.GetPower(..., "Neutral", ...) — GameServer.lua:279 의 updatePower 와 같은 입력.
    11-17 B안부터 켜 둔 세트 효과 단계가 전투력에 곱해진다 (Config.PowerAug)."""
    damage = BASE_DAMAGE * weapon_power(weapon_level) * level_damage_mult(level) * (1 + bonus_damage)
    raw_crit = crit_points * CRIT_PER_POINT + gear_crit
    crit = min(0.9, raw_crit)
    crit_mult = CRIT_MULT + max(0, raw_crit - 0.9)
    rate = 1 / (BASE_COOLDOWN / (1 + speed_points * SPEED_PER_POINT))
    dps = damage * (1 + crit * (crit_mult - 1)) * rate
    aug = 1 + POWER_AUG_ATTACK * aug_atk + POWER_AUG_DEFENSE * aug_def
    return math.floor((dps * 10 + (gear_hp + level_health(level)) * 0.5) * aug), dps


# ---------------------------------------------------------------- 필드 몬스터
def _pool_avg(zone, column):
    pool = ZONE_POOLS[zone - 1]
    total = sum(pool.values())
    return sum(MOB_DEFS[k][column] * w for k, w in pool.items()) / total


def mob_stats(zone):
    """필드 일반 몬스터 1마리 (FieldService.lua:878~918 · MonsterTypes.ApplyDef)."""
    level = 1 + 3 * (zone - 1)
    hp = math.floor(40 * 1.22 ** (level - 1))
    hp = max(1, math.floor(hp * _pool_avg(zone, 0)))
    hp = max(1, math.floor(hp * HORDE_HEALTH))
    hp = max(1, math.floor(hp * ZONE_HEALTH[zone - 1] * EARLY_MOB_HEALTH.get(zone, 1)))
    gold = math.floor((8 + 4 * level) * _pool_avg(zone, 1))
    gold = max(1, math.floor(gold * HORDE_REWARD))
    gold = math.floor(gold * ZONE_REWARD[zone - 1] * FIELD_GOLD_MULT)
    xp = XP_PER_MOB_LEVEL * level * HORDE_REWARD * XP_ZONE_MULT[zone - 1]
    shot = math.floor((8 + level * 2) * ZONE_DAMAGE[zone - 1] * MOB_DAMAGE_MULT)
    return {"hp": hp, "gold": gold, "xp": xp, "shot": shot, "level": level}


def boss_hp(zone):
    """구역 군주 (FieldService.lua:874~885)."""
    level = 1 + 3 * (zone - 1) + 3
    base = math.floor(40 * 1.22 ** (level - 1))
    mult = LORD_HEALTH.get(zone, ZONE_HEALTH[zone - 1])
    return math.floor(base * 60 * mult)


# ---------------------------------------------------------------- 장비 / 훈련 / 펫
def affix_expected(rarity):
    if rarity <= 1:
        return 0.0, 0.0, 0.0
    count = AFFIX_COUNT[rarity - 1]
    scale = AFFIX_SCALE[rarity - 1]
    total_w = sum(AFFIX_WEIGHT.values())
    return tuple(count * AFFIX_WEIGHT[k] / total_w * AFFIX_BASE[k] * scale for k in ("Damage", "Crit", "Health"))


def price_mult_ref(level):
    """Config.PriceMultRef (2436행)."""
    def lerp(a, b, t):
        return a + (b - a) * min(1.0, max(0.0, t))
    if level <= 60:
        return 1.0
    if level <= 200:
        return lerp(1, 5, (level - 60) / 140)
    if level <= 700:
        return lerp(5, 3, (level - 200) / 500)
    return lerp(3, 1, (level - 700) / max(1, MAX_LEVEL - 700))


def ref_income(f):
    """Config.RefIncome (2445행)."""
    level = int(min(max(f, 0), 1) * MAX_LEVEL)
    return INCOME_BASE * damage_multiplier(level) * price_mult_ref(level)


def progressive(f):
    return 0.3 + 0.7 * f


def ease(f):
    return 0.5 + 0.5 * min(1.0, max(0.0, f) / 0.5)


_gear_sum = sum(progressive(lv / (GEAR_MAX_LEVEL - 1)) / max(0.35, 1 - 0.045 * lv) for lv in range(GEAR_MAX_LEVEL))
GEAR_K = SINK_MINUTES / (6 * _gear_sum)
_train_sum = sum(progressive(lv / 29) for lv in range(30))
TRAIN_K = SINK_MINUTES / (4 * _train_sum)
_pet_sum = sum(progressive(s / 14) for s in range(15))
PET_K = SINK_MINUTES / _pet_sum
_aug_sum = sum(progressive((z - 1) / (ZONE_COUNT - 1)) * m for z in range(1, ZONE_COUNT + 1) for m in AUG_COST_MULT)
AUG_K = SINK_MINUTES / _aug_sum * 0.6      # Config.lua 2556행 (세트 효과는 다른 성장보다 40% 싸게)


def gear_step_cost(slot, level):
    f = min(max(level, 0), GEAR_MAX_LEVEL - 1) / (GEAR_MAX_LEVEL - 1)
    return max(1, math.floor(ref_income(f) * GEAR_K * progressive(f) * ease(f) * GEAR_BASE_COST[slot] / 121.67))


def train_gold(level, stat="Attack"):
    maxlv = TRAIN_MAXLV[stat]
    equiv = level * 29 / max(1, maxlv - 1)
    f = min(max(equiv, 0), 29) / 29
    return max(1, math.floor(ref_income(f) * TRAIN_K * progressive(f) * ease(f) * 30 / max(1, maxlv)))


def train_time(level, stat="Attack"):
    equiv = level * 29 / max(1, TRAIN_MAXLV[stat] - 1)
    return math.floor(TRAIN_TIME_BASE * TRAIN_TIME_GROWTH ** equiv)


def pet_time(level):
    return math.floor(120 * 1.35 ** (level - 1))


def pet_unlock_cost():
    return max(1, math.floor(ref_income(0) * PET_K * progressive(0) * ease(0)))


def pet_level_cost(level):
    f = min(max(level, 1), 14) / 14
    return max(1, math.floor(ref_income(f) * PET_K * progressive(f) * ease(f)))


def pet_damage(level):
    return 0.04 if level >= 3 else 0.0     # Config.Pet 레벨 3 "Power" (Attack +4%)


# ---------------------------------------------------------------- 세트 효과 단계 (Config.Sets / AugService)
# 전투력에 곱해지는 세트 효과 단계 합(AugAtkLv / AugDefLv)은 플레이어가 무엇을 몇 단계까지 올렸는지에 달려 있다.
#  * 골드 단계(0~3): 번 돈의 AUG_BUDGET_SHARE 만큼을 세트 효과에 쓴다고 보고, 싼 것부터 사 간다 (해금 뒤 한 구역마다 +1 까지만)
#  * 세트 부위(0~3): 해금 직후 1부위, 한 구역 지날 때마다 +1, 최대 3 (Config.Inventory.SetCounts / EquipForAugs 로 맞춤)
#  * 수호석(0~3): 방어 기재만 4~6단계 (해금 2구역 뒤부터)
# 4구역 이전 실제 진행과 대조할 때는 Studio 로그(세트 단계가 화면에 뜼다)로 다시 맞춘다.
AUG_SCENARIOS = ("낮음(골드만)", "기본(골드+세트)", "높음(골드+세트+수호석)")
AUG_SCENARIO = "기본(골드+세트)"
AUG_BUDGET_SHARE = 0.35      # 번 돈 중 세트 효과 골드 단계에 쓰는 몫 (나머지는 무기 / 장비 / 훈련 / 펫)
AUG_GEAR_RAMP = (1, 2, 3)    # 해금 뒤 age 0 / 1 / 2+ 의 세트 부위 수


def aug_unlock_gate(effect):
    """그 효과를 켤 수 있는 첫 구역 관문 (해금 구역 군주 + 1)."""
    return AUG_HOME_ZONE.get(effect, effect) + 1


def aug_slots_at(gate):
    """그 구역에 들어갈 때 쓸 수 있는 칸 수 (AugSlotZones: 0 / 2 / 4구역 클리어)."""
    cleared = gate - 1
    return max(1, sum(1 for need in AUG_SLOT_ZONES if cleared >= need))


_AUG_GATE_CACHE = {}
_AUG_DESIGN = None       # (설계 기준 진행: 누적 수입을 구역 관문 별로 알기 위해)


def aug_gold_at(gate):
    """그 구역 관문까지 실제로 살 수 있는 골드 단계 (예산 = 누적 수입 x AUG_BUDGET_SHARE)."""
    if gate in _AUG_GATE_CACHE:
        return _AUG_GATE_CACHE[gate]
    global _AUG_DESIGN
    if _AUG_DESIGN is None:
        _AUG_DESIGN = simulate(aoe_mult=1e9)
    gross = _AUG_DESIGN[gate]["total_gold"]
    budget = gross * AUG_BUDGET_SHARE
    gold = {e: 0 for e in list(AUG_ATTACK) + list(AUG_DEFENSE)}
    slots = aug_slots_at(gate)
    spent = 0.0
    for _ in range(64):
        unlocked = [e for e in gold if gate >= aug_unlock_gate(e)]
        # 지금 끼울 수 있는 칸 안의 효과만 올린다 (단계 = 골드 + 세트 부위, 같으면 공격 우선)
        ranked = sorted(((aug_gear(e, gate) + gold[e], 0 if e in AUG_ATTACK else 1, e) for e in unlocked),
                        key=lambda p: (-p[0], p[1], p[2]))
        in_slots = [e for _, _, e in ranked[:slots]]
        cands = []
        for e in in_slots:
            if gold[e] >= min(3, gate - aug_unlock_gate(e) + 1):
                continue
            cands.append((aug_cost(AUG_HOME_ZONE.get(e, e), gold[e] + 1, gate), e))
        if not cands:
            break
        cost, e = min(cands)
        if spent + cost > budget:
            break
        spent += cost
        gold[e] += 1
    _AUG_GATE_CACHE[gate] = gold
    return gold


def aug_gear(effect, gate, scenario=AUG_SCENARIO):
    """세트 부위로 오른 단계 (0~3)."""
    if scenario == AUG_SCENARIOS[0]:
        return 0
    age = gate - aug_unlock_gate(effect)
    if age < 0:
        return 0
    return min(3, 1 + age)


def aug_level(effect, gate, scenario=AUG_SCENARIO):
    age = gate - aug_unlock_gate(effect)
    if age < 0:
        return 0
    gold = aug_gold_at(gate)[effect]
    gear = aug_gear(effect, gate, scenario)
    stone = min(3, max(0, age - 1)) if scenario == AUG_SCENARIOS[2] and effect in AUG_DEFENSE else 0
    return min(AUG_MAX_LEVEL, gold + gear + stone)


def aug_profile(gate, scenario=AUG_SCENARIO):
    """(AugAtkLv, AugDefLv, 켜 둔 효과 목록) — 칸은 단계 높은 순, 같으면 공격 우선(사냥 세팅)."""
    picks = []
    for effect in list(AUG_ATTACK) + list(AUG_DEFENSE):
        lv = aug_level(effect, gate, scenario)
        if lv > 0:
            picks.append((lv, 0 if effect in AUG_ATTACK else 1, effect))
    picks.sort(key=lambda p: (-p[0], p[1], p[2]))
    picks = picks[:aug_slots_at(gate)]
    atk = sum(lv for lv, _, e in picks if e in AUG_ATTACK)
    dfs = sum(lv for lv, _, e in picks if e in AUG_DEFENSE)
    return atk, dfs, [(e, lv) for lv, _, e in picks]


def aug_mult(gate, scenario=AUG_SCENARIO):
    atk, dfs, _ = aug_profile(gate, scenario)
    return 1 + POWER_AUG_ATTACK * atk + POWER_AUG_DEFENSE * dfs


def power_aug(zone, raw_power, scenario=AUG_SCENARIO):
    return int(raw_power * aug_mult(zone, scenario))


def aug_spend_at(gate):
    """그 구역 관문까지 세트 효과 골드 단계에 쓴 돈."""
    gold = aug_gold_at(gate)
    total = 0
    for e, g in gold.items():
        for step in range(1, g + 1):
            total += aug_cost(AUG_HOME_ZONE.get(e, e), step, gate)
    return total


def aug_cost(zone, level, max_zone):
    """Config.Sets.AugCost (2561행)."""
    price_zone = max(zone, max_zone)
    f = (min(max(price_zone, 1), ZONE_COUNT) - 1) / (ZONE_COUNT - 1)
    return max(1, int(ref_income(f) * AUG_K * progressive(f) * ease(f) * (AUG_COST_MULT[level - 1] if level <= len(AUG_COST_MULT) else 8)))


# =====================================================================
# 진행 시뮬레이션
# =====================================================================
# 가정 A1  현재 구역 필드에서 '일반 몬스터'만 잡는다 (엘리트 / 군주 / 현상금 / 퀘스트 제외).
# 가정 A2  한 마리 처치 시간 = 몬스터 체력 / 내 단일 대상 dps → 처치율 = min(100, 60 x dps / hp).
#          (Config.Idle.KillsPerMin = 100 이 상한. 실제로는 광역 피해로 더 빨리 잡을 수 있다 → 감도 표)
# 가정 A3  골드는 무기 강화가 최우선. 남는 골드는 장비 강화 / 훈련 / 펫.
# 가정 A4  훈련 / 펫은 실제 시간이 걸린다 (훈련 1칸 · 펫 1칸, 시간 단축권 / VIP 없음).
# 가정 A5  다음 구역으로 넘어가는 시점 = 그 구역의 '설계된 무기 티어'를 다 올린 순간 (economy_model 과 같은 가정).
ZONE_TIER = {1: 1, 2: 2, 3: 6, 4: 11, 5: 14, 6: 18, 7: 24, 8: 34}
TRAIN_ORDER = ["Attack", "Health", "Crit"]


class State:
    def __init__(self):
        self.minutes = 0.0
        self.zone = 1
        self.weapon = 0
        self.gold = 0.0
        self.level = 1
        self.xp = 0.0
        self.gear_rarity = [3] * 6
        self.gear_level = [0] * 6
        self.train = {"Attack": 0, "Health": 0, "Crit": 0}
        self.train_job = None
        self.pet = 0
        self.pet_job = None
        self.pet_unlocked = False
        self.total_gold = 0.0

    def copy(self):
        s = State()
        s.__dict__.update({
            "minutes": self.minutes, "zone": self.zone, "weapon": self.weapon, "gold": self.gold,
            "level": self.level, "xp": self.xp, "gear_rarity": list(self.gear_rarity),
            "gear_level": list(self.gear_level), "train": dict(self.train),
            "train_job": self.train_job, "pet": self.pet, "pet_job": self.pet_job,
            "pet_unlocked": self.pet_unlocked, "total_gold": self.total_gold,
        })
        return s

    def gear(self):
        dmg = crit = hp = 0.0
        for i, slot in enumerate(GEAR_SLOTS):
            stat, base = GEAR_SLOTS[slot]
            value = base * RARITY_MULT[self.gear_rarity[i] - 1] * (1 + GEAR_LEVEL_BONUS * self.gear_level[i])
            if stat == "Damage":
                dmg += value
            elif stat == "Crit":
                crit += value
            elif stat == "Health":
                hp += value
            ad, ac, ah = affix_expected(self.gear_rarity[i])
            dmg += ad
            crit += ac
            hp += ah
        return dmg, crit, hp

    def stats(self):
        d, c, h = self.gear()
        bonus = (1 + d) * (1 + self.train["Attack"] * TRAIN_PER["Attack"]) * (1 + pet_damage(self.pet)) - 1
        p, dps = power(self.weapon, self.level, h + self.train["Health"] * TRAIN_PER["Health"],
                       c + self.train["Crit"] * TRAIN_PER["Crit"], bonus)
        return p, dps, bonus, h, c, d

    def kill_rate(self, zone, aoe_mult=1.0):
        _, dps, *_ = self.stats()
        hp = mob_stats(zone)["hp"]
        return min(float(KILLS_PER_MIN_REF), 60.0 * dps * aoe_mult / hp)

    def snapshot(self):
        p, dps, bonus, h, c, d = self.stats()
        return {"minutes": self.minutes, "zone": self.zone, "weapon": self.weapon, "level": self.level, "total_gold": self.total_gold, "gold": self.gold,
                "power": p, "dps": dps, "gear_rarity": self.gear_rarity[0], "gear_level": list(self.gear_level),
                "gear_hp": h, "gear_crit": c, "gear_dmg": d, "train": dict(self.train), "pet": self.pet}


def _step_time_growths(st, dt):
    if st.train_job:
        st.train_job = (st.train_job[0], st.train_job[1] - dt * 60)
        if st.train_job[1] <= 0:
            st.train[st.train_job[0]] += 1
            st.train_job = None
    if st.pet_job is not None:
        st.pet_job -= dt * 60
        if st.pet_job <= 0:
            st.pet += 1
            st.pet_job = None


def _spend(st, others=True):
    while st.weapon < MAX_LEVEL and st.gold >= expected_step_gold(st.weapon):
        st.gold -= expected_step_gold(st.weapon)
        st.weapon += 1
    if not others:
        return
    if st.train_job is None:
        for stat in TRAIN_ORDER:
            if st.train[stat] >= TRAIN_MAXLV[stat]:
                continue
            g = train_gold(st.train[stat], stat)
            if st.gold >= g:
                st.gold -= g
                st.train_job = (stat, train_time(st.train[stat], stat))
                break
    if not st.pet_unlocked:
        if st.gold >= pet_unlock_cost():
            st.gold -= pet_unlock_cost()
            st.pet_unlocked, st.pet = True, 1
    elif st.pet_job is None and st.pet < 15:
        g = pet_level_cost(st.pet)
        if st.gold >= g:
            st.gold -= g
            st.pet_job = pet_time(st.pet)
    for _ in range(6):
        choices = [(gear_step_cost(slot, st.gear_level[i]), i, slot)
                   for i, slot in enumerate(GEAR_SLOTS) if st.gear_level[i] < GEAR_MAX_LEVEL - 1]
        if not choices:
            break
        cost, i, slot = min(choices)
        if st.gold < cost * 3:
            break
        st.gold -= cost
        st.gear_level[i] += 1


def _tick(st, dt, aoe_mult=1.0):
    m = mob_stats(st.zone)
    kills = st.kill_rate(st.zone, aoe_mult) * dt
    income = kills * m["gold"]
    st.gold += income
    st.total_gold += income
    st.xp += kills * m["xp"]
    while st.level < LEVEL_MAX and st.xp >= xp_needed(st.level):
        st.xp -= xp_needed(st.level)
        st.level += 1
    _step_time_growths(st, dt)
    _spend(st)
    st.minutes += dt
    return kills


def simulate(max_minutes=200000, aoe_mult=1.0, dt=0.25):
    """구역별 '그 구역 관문에 처음 도달한 순간'의 상태를 모은다."""
    st = State()
    marks = {1: st.snapshot()}
    target = 2
    while st.minutes < max_minutes and target <= ZONE_COUNT:
        _tick(st, dt, aoe_mult)
        if st.weapon >= TIER_START[ZONE_TIER[target] - 1]:
            st.zone = target
            st.gear_rarity = [FIRST_CLEAR_RARITY[target - 1]] * 6
            marks[target] = st.snapshot()
            target += 1
    return marks


def time_to_power(zone, start_state, target_power, aoe_mult=1.0, dt=0.25, max_minutes=100000):
    """그 구역에서 계속 파밍해 target_power 에 닿는 데 걸리는 분 (못 닿으면 None)."""
    s = start_state
    st = State()
    st.weapon = s["weapon"]
    st.level = s["level"]
    st.gold = s.get("gold", 0.0)
    st.xp = s.get("xp", 0.0)
    st.gear_rarity = [s["gear_rarity"]] * 6
    st.gear_level = list(s["gear_level"])
    st.train = dict(s["train"])
    st.pet = s["pet"]
    st.pet_unlocked = st.pet > 0
    st.minutes, st.zone = 0.0, zone
    st.total_gold = 0.0
    while st.minutes < max_minutes:
        _tick(st, dt, aoe_mult)
        p = st.stats()[0]
        if p >= target_power:
            return st.minutes, st.snapshot()
    return None, st.snapshot()


# =====================================================================
# 리포트
# =====================================================================
def pct(a, b):
    return a / b


def power_at(state, weapon_level):
    """도달 상태의 레벨 / 장비 / 훈련 / 펫을 고정하고 무기 단계만 바꿨을 때의 전투력 (세트 효과 제외)."""
    bonus = (1 + state["gear_dmg"]) * (1 + state["train"]["Attack"] * TRAIN_PER["Attack"]) * (1 + pet_damage(state["pet"])) - 1
    return power(weapon_level, state["level"], state["gear_hp"] + state["train"]["Health"] * TRAIN_PER["Health"],
                 state["gear_crit"] + state["train"]["Crit"] * TRAIN_PER["Crit"], bonus)[0]


def mult(z, scenario=AUG_SCENARIO):
    """그 구역 관문에서의 세트 효과 배율 (Config.PowerAug)."""
    return aug_mult(z, scenario)


def pz(z, raw_power, scenario=AUG_SCENARIO):
    """세트 효과를 넣은 전투력 (화면에 보이는 숫자)."""
    return int(raw_power * mult(z, scenario))


def raw_need(z, target_power, scenario=AUG_SCENARIO):
    """화면 전투력 목표를 세트 효과 없는 전투력으로 되돌린 값."""
    return target_power / mult(z, scenario)


def ttp(z, state, target_power, aoe_mult, max_minutes=20000, scenario=AUG_SCENARIO):
    """화면 전투력 target_power 에 닿는 시간 (세트 효과 배율은 구역 고정)."""
    return time_to_power(z, state, raw_need(z, target_power, scenario), aoe_mult=aoe_mult, max_minutes=max_minutes)


def tier_label(level):
    """그 무기 단계가 '몇 구역 티어' 인가."""
    label = "1구역 이전"
    for z in range(1, ZONE_COUNT + 1):
        if level >= TIER_START[ZONE_TIER[z] - 1]:
            label = f"{z}구역 티어"
    return label


def gold_between(lo, hi):
    return sum(expected_step_gold(l) for l in range(lo, hi))


def power_for_budget(z, state, minutes, aoe_mult, scenario=AUG_SCENARIO):
    """그 구역에서 minutes 분 파밍해 닿는 최대 전투력 (세트 효과 포함, 화면 숫자)."""
    lo, hi = int(state["power"] * mult(z, scenario)), RECOMMEND_POWER[z - 1] * 4
    for _ in range(20):
        mid = (lo + hi) // 2
        t, _ = time_to_power(z, state, raw_need(z, mid, scenario), aoe_mult=aoe_mult, max_minutes=20000)
        if t is None or t > minutes:
            hi = mid
        else:
            lo = mid
    return int(lo)


def build_report():
    marks = simulate(aoe_mult=1.0)            # 체감: 단일 대상 처치율
    design = simulate(aoe_mult=1e9)           # 설계: Config.Idle.KillsPerMin = 100/분 상한
    aoe3 = simulate(aoe_mult=3.0)             # 중간: 광역 피해 3배
    L = []
    A = L.append

    # ---------------------------------------------------------------- 0
    A("## 1. 구역 기본 수치 (코드 공식 그대로)")
    A("")
    A("| 구역 | 몹렙 | 일반몹 HP | 골드/마리 | XP/마리 | 권장 전투력 | 권장 ÷ 10 (dps 환산) | 권장이 뜻하는 처치시간 | 3초 처치에 필요한 전투력 |")
    A("|---|---|---|---|---|---|---|---|---|")
    for z in range(1, ZONE_COUNT + 1):
        m = mob_stats(z)
        p = RECOMMEND_POWER[z - 1]
        dps = p / 10.0
        A(f"| {z} | {m['level']} | {m['hp']:,} | {m['gold']:,} | {m['xp']:,.0f} | {p:,} | {dps:,.0f} | {m['hp'] / dps:.1f}초 | {10 * m['hp'] / 3:,.0f} |")
    A("")
    A("> 권장 전투력 = `RecommendPowerBase` x (1 + 0.12 x `RecommendAugLv`) = "
      + " / ".join(f"{v:,}" for v in RECOMMEND_POWER) + ". `÷ 10` 은 전투력 공식의 총기 dps 항(x10)을 되돌린 값이라, 세트 효과 / 펫 피해를 넣으면 실제 처치 시간은 더 짧다.")
    A("")

    # ---------------------------------------------------------------- 1
    A("## 2. 구역 관문 도달 시점의 '도달 가능 전투력' (세트 효과 포함)")
    A("")
    A(f"세트 효과 가정: **{AUG_SCENARIO}** (골드 단계 = 해금 뒤 한 구역마다 +1 최대 3, 세트 부위 = 해금 직후 1부위부터 최대 3, 칸은 단계 높은 순 · 같으면 공격 우선). Config.PowerAug 로 전투력에 곱해진다.")
    A("")
    A("| 구역 | 도달 누적 시간<br>(설계 100마리/분) | 도달 누적 시간<br>(단일 대상 처치율) | 무기 단계 | 레벨 | 장비 | 훈련 A/H/C | 펫 | 세트 단계<br>(공/방) | 칸 | 세트 배율 | 세트 제외 전투력 | **도달 전투력** | 권장 | **괴리** | 도달 시 처치 시간 |")
    A("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for z in range(1, ZONE_COUNT + 1):
        s, d = marks[z], design[z]
        tr = s["train"]
        m = mob_stats(z)
        atk, dfs, _ = aug_profile(z)
        A(f"| {z} | {d['minutes'] / 60:,.1f}h | {s['minutes'] / 60:,.1f}h | {s['weapon']:,} | Lv{s['level']} | R{s['gear_rarity']}+{min(s['gear_level'])} | "
          f"{tr['Attack']}/{tr['Health']}/{tr['Crit']} | {s['pet']} | {atk}/{dfs} | {aug_slots_at(z)} | x{mult(z):.2f} | {s['power']:,} | "
          f"**{pz(z, s['power']):,}** | {RECOMMEND_POWER[z - 1]:,} | "
          f"**{RECOMMEND_POWER[z - 1] / pz(z, s['power']):.2f}x** | {m['hp'] / s['dps']:.1f}초 |")
    A("")

    # ---------------------------------------------------------------- 1b
    A("## 2b. 세트 효과 시나리오별 괴리 (같은 진행, 세트 단계만 바꿔서)")
    A("")
    A("| 구역 | 권장 | 낮음(골드만) | 괴리 | 기본(골드+세트) | 괴리 | 높음(+수호석) | 괴리 | 기본 시나리오 x 1.10 (제안 권장) |")
    A("|---|---|---|---|---|---|---|---|---|")
    gaps = []
    for z in range(1, ZONE_COUNT + 1):
        s = marks[z]
        row = [str(z), f"{RECOMMEND_POWER[z - 1]:,}"]
        for sc in AUG_SCENARIOS:
            v = pz(z, s["power"], sc)
            row += [f"{v:,}", f"{RECOMMEND_POWER[z - 1] / v:.2f}x"]
        suggest = int(round(pz(z, s["power"]) * 1.10 / 50.0) * 50)
        gaps.append(suggest)
        row.append(f"{suggest:,}")
        A("| " + " | ".join(row) + " |")
    A("")
    A("| 구역 | 지금 권장 | 제안 권장 | 제안 ÷ RecommendPowerBase | 그때 필요한 RecommendAugLv | 지금 RecommendAugLv |")
    A("|---|---|---|---|---|---|")
    for z in range(1, ZONE_COUNT + 1):
        base = RECOMMEND_POWER_BASE[z - 1]
        need_aug = (gaps[z - 1] / base - 1) / POWER_AUG_ATTACK
        A(f"| {z} | {RECOMMEND_POWER[z - 1]:,} | {gaps[z - 1]:,} | x{gaps[z - 1] / base:.2f} | {max(0.0, need_aug):.1f} | {RECOMMEND_AUG_LV[z - 1]} |")
    A("")

    # ---------------------------------------------------------------- 2
    A("## 3. 벽 비용 배율 (권장 전투력까지, 세트 효과 포함 숫자로)")
    A("")
    A("정적 배율 = (권장까지 필요한 추가 골드) ÷ (그 구역에서 30분 사냥 수입). 동적 시간 = 그 구역에서 계속 파밍했을 때 실제로 걸리는 시간.")
    A("")
    A("| 구역 | 도달 전투력 | 권장 | 권장까지 필요 무기 단계 | 그 무기 티어 | 추가 골드 | 30분 수입<br>(설계) | **배율(설계)** | 30분 수입<br>(체감) | **배율(체감)** | 실제 소요<br>(설계·광역x3·체감) | 세션 수 |")
    A("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for z in range(1, ZONE_COUNT + 1):
        s = marks[z]
        target = RECOMMEND_POWER[z - 1]
        now = pz(z, s["power"])
        m = mob_stats(z)
        inc_design = 30 * KILLS_PER_MIN_REF * m["gold"]
        kr = min(KILLS_PER_MIN_REF, 60.0 * s["dps"] / m["hp"])
        inc_feel = 30 * kr * m["gold"]
        if target <= now:
            A(f"| {z} | {now:,} | {target:,} | 이미 초과 | — | 0 | {inc_design:,.0f} | 0.0x | {inc_feel:,.0f} | 0.0x | 0h | 0 |")
            continue
        weapon_only = power_at(s, MAX_LEVEL) >= raw_need(z, target)
        if weapon_only:
            lo, hi = s["weapon"], MAX_LEVEL
            while lo < hi:
                mid = (lo + hi) // 2
                if power_at(s, mid) >= raw_need(z, target):
                    hi = mid
                else:
                    lo = mid + 1
            need = lo
            gold = gold_between(s["weapon"], need)
            step_col = f"{s['weapon']:,}→{need:,} (+{need - s['weapon']})"
            tier_col = tier_label(need)
            gold_col = f"{gold:,.0f}"
        else:
            need, gold = None, None
            step_col = "무기 최대로도 미달"
            tier_col = "무기 밖(레벨·장비·훈련 필요)"
            gold_col = "—"
        t_d, _ = ttp(z, s, target, aoe_mult=1e9)
        t_3, _ = ttp(z, s, target, aoe_mult=3.0)
        t_f, _ = ttp(z, s, target, aoe_mult=1.0)
        fmt = lambda t: "도달 불가" if t is None else f"{t / 60:.1f}h"
        ratio_d = gold / inc_design if gold else float("inf")
        ratio_f = gold / inc_feel if gold else float("inf")
        A(f"| {z} | {now:,} | {target:,} | {step_col} | {tier_col} | {gold_col} | {inc_design:,.0f} | "
          f"{'∞' if gold is None else f'{ratio_d:.1f}x'} | {inc_feel:,.0f} | {'∞' if gold is None else f'{ratio_f:.1f}x'} | {fmt(t_d)} · {fmt(t_3)} · {fmt(t_f)} | "
          f"{'—' if t_d is None else f'{t_d / 30:.0f}/{t_3 / 30:.0f}/{t_f / 30:.0f}'} |")
    A("")

    # ---------------------------------------------------------------- 3
    A("## 4. 진단 근거")
    A("")
    A("| 구역 | 몬스터 HP 증가 | 도달 전투력 증가 | HP/전투력 증가비 | 도달 시 처치 시간 | 권장값 ÷ 3초 필요값 | 군주 체력 | 도달 전투력으로 군주 처치 | 권장 전투력으로 군주 처치 |")
    A("|---|---|---|---|---|---|---|---|---|")
    for z in range(2, ZONE_COUNT + 1):
        a, b = marks[z - 1], marks[z]
        m0, m1 = mob_stats(z - 1), mob_stats(z)
        hp_ratio = m1["hp"] / m0["hp"]
        pw_ratio = pz(z, b["power"]) / pz(z - 1, a["power"])
        p3 = 10 * m1["hp"] / 3
        bh = boss_hp(z)
        ttk_boss_now = bh / b["dps"] / 60
        dps_rec = RECOMMEND_POWER[z - 1] / 10.0
        ttk_boss_rec = bh / dps_rec / 60
        A(f"| {z} | ×{hp_ratio:.2f} | ×{pw_ratio:.2f} | ×{hp_ratio / pw_ratio:.2f} | {m1['hp'] / b['dps']:.1f}초 | "
          f"{RECOMMEND_POWER[z - 1] / p3:.2f}x | {bh:,} | {ttk_boss_now:.1f}분 | {ttk_boss_rec:.1f}분 |")
    A("")

    # ---------------------------------------------------------------- 4
    A("## 5. 조정안 계산 (2.5세션 = 75분 파밍으로 닿는 값)")
    A("")
    A("| 구역 | 도달 전투력 | 2.5세션 목표(설계) | 2.5세션 목표(광역x3) | 5세션 목표(설계) | 현재 권장 | 권장 ÷ 도달 |")
    A("|---|---|---|---|---|---|---|")
    for z in range(4, ZONE_COUNT + 1):
        s = marks[z]
        b2, b2b, b5 = power_for_budget(z, s, 75, 1e9), power_for_budget(z, s, 75, 3.0), power_for_budget(z, s, 150, 1e9)
        A(f"| {z} | {pz(z, s['power']):,} | {b2:,} | {b2b:,} | {b5:,} | {RECOMMEND_POWER[z - 1]:,} | {RECOMMEND_POWER[z - 1] / pz(z, s['power']):.2f}x |")
    A("")

    # ---------------------------------------------------------------- 5
    A("## 6. 최종 군주 (8구역 끝) 예상 클리어 시간")
    A("")
    fl_health = 22320000
    rec8 = RECOMMEND_POWER[ZONE_COUNT - 1]
    gate8 = design[ZONE_COUNT]
    gun_dps = gate8["dps"]
    aug_atk8, aug_def8, _ = aug_profile(ZONE_COUNT)
    power8 = pz(ZONE_COUNT, gate8["power"])
    A(f"- `Config.FinalLord.Health` = {fl_health:,} (11-17 cb71b5c). 주석의 산식: 310,000 x 0.4 x 180초.")
    A(f"- 지금 8구역 권장 전투력 = **{rec8:,}** ({RECOMMEND_POWER_BASE[7]:,} x (1 + 0.12 x {RECOMMEND_AUG_LV[7]})). 예전 값 310,000 의 x{rec8 / 310000:.2f}.")
    A(f"- 시뮬레이션 8구역 관문 도달 전투력 = **{power8:,}** (세트 효과 공격 {aug_atk8} / 방어 {aug_def8}단계, 총기만 센 dps {gun_dps:,.0f}).")
    A("")
    A("| 기준 | dps / 전투력 | 권장 전투력에서 dps | 22,320,000 클리어 | 3분(180초)에 맞추는 체력 |")
    A("|---|---|---|---|---|")
    bases = [
        ("코드 주석의 산식 (0.4 x 전투력)", 0.4),
        ("실측 앵커 (4,180,000 구식 전투력 -> 2.63M dps = 8.5초. 세트 단계 6 이면 새 전투력 x2.44)", 0.63 / 2.44),
        ("시뮬레이션 총기 dps (세트 효과 / 펫 / 스킬 제외)", gun_dps / power8),
    ]
    for label, ratio in bases:
        dps = rec8 * ratio
        A(f"| {label} | x{ratio:.3f} | {dps:,.0f} | {fl_health / dps:.0f}초 ({fl_health / dps / 60:.1f}분) | {dps * 180:,.0f} |")
    A("")
    return "\n".join(L)




def proposal_sessions(mults=(1.10, 1.50)):
    """도달 전투력 × 1.10 / × 1.50 을 권장으로 넣었을 때의 벽(세션 수), 지금 권장과 비교."""
    d = simulate(aoe_mult=1e9)
    f = simulate(aoe_mult=1.0)
    L = ["## 7. 도달 × 1.10 / × 1.50 을 권장으로 두면 벽이 얼마나 되나 (세션 수 = 30분 기준, 설계~체감)", "",
         "| 구역 | 도달 전투력(세트 포함) | 지금 권장 → 세션 | 도달×1.10 → 세션 | 도달×1.50 → 세션 |", "|---|---|---|---|---|"]

    def sess(z, target):
        t1, _ = ttp(z, d[z], target, aoe_mult=1e9, max_minutes=40000)
        tf, _ = ttp(z, f[z], target, aoe_mult=1.0, max_minutes=40000)
        g = lambda t: "X" if t is None else f"{t / 30:.1f}"
        return f"{g(t1)} ~ {g(tf)}"

    for z in range(4, ZONE_COUNT + 1):
        now = RECOMMEND_POWER[z - 1]
        arrive = pz(z, d[z]["power"])
        a1 = int(round(arrive * mults[0] / 50.0) * 50)
        a2 = int(round(arrive * mults[1] / 50.0) * 50)
        L.append(f"| {z} | {arrive:,} | {now:,} → {sess(z, now)} | {a1:,} → {sess(z, a1)} | "
                 f"{a2:,} → {sess(z, a2)} |")
    L.append("")
    return "\n".join(L)


def relaxation_check(health, reward):
    """ZoneDanger.Health / Reward 를 바꿨을 때를 다시 돌려 본다 (참고용)."""
    global ZONE_HEALTH, ZONE_REWARD
    keep_h, keep_r = ZONE_HEALTH, ZONE_REWARD
    ZONE_HEALTH, ZONE_REWARD = health, reward
    d = simulate(aoe_mult=1e9)
    f = simulate(aoe_mult=1.0)
    L = ["## 8. 참고: ZoneDanger.Health / Reward 를 낮췄을 때", "",
         f"Health = {health} · Reward = {reward}", "",
         "| 구역 | 도달 전투력(세트 포함) | 도달 시 처치 시간 | 도달×1.50 세션 수(설계~체감) |", "|---|---|---|---|"]
    for z in range(4, ZONE_COUNT + 1):
        s = d[z]
        tgt = int(round(pz(z, s["power"]) * 1.5 / 50.0) * 50)
        t1, _ = ttp(z, s, tgt, aoe_mult=1e9, max_minutes=40000)
        tf, _ = ttp(z, f[z], tgt, aoe_mult=1.0, max_minutes=40000)
        g = lambda t: "X" if t is None else f"{t / 30:.1f}"
        L.append(f"| {z} | {pz(z, s['power']):,} | {mob_stats(z)['hp'] / s['dps']:.1f}초 | {g(t1)} ~ {g(tf)} |")
    L.append("")
    ZONE_HEALTH, ZONE_REWARD = keep_h, keep_r
    return "\n".join(L)


def full_report():
    parts = [build_report(),
             proposal_sessions(),
             relaxation_check([1, 1.5, 2.4, 9, 14, 24, 45, 70], [1, 1.5, 2.2, 9.5, 13, 24, 40, 65])]
    return "\n".join(parts)


def main():
    text = full_report()
    if "--md" in sys.argv:
        path = sys.argv[sys.argv.index("--md") + 1]
        with open(path, "w") as f:
            f.write(text + "\n")
        print("saved", path)
    else:
        print(text)


if __name__ == "__main__":
    main()
