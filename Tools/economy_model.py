#!/usr/bin/env python3
"""경제 모델 (Config.Economy 와 같은 공식): 무기 진화 한 번에 걸리는 시간 표를 뽑는다.
사용: python3 Tools/economy_model.py   (Config.lua 의 값을 바꾸면 아래 상수도 같이 바꿔서 다시 돌려 본다)
"""
LS = 326 / 1090                 # Config.Weapon.LevelScale
INCOME_BASE, EARLY, LATE, LATE_LEVEL = 1500, 0.27, 0.6, 600
IDLE_FRACTION, MANUAL_FRACTION = 0.34, 0.11  # Config.Idle.Fraction / Config.Dummy.ManualFraction (활동 수입 대비 비율)
BASE_DAMAGE, BASE_COOLDOWN = 10, 0.35
ORDER = ["Pistol", "Smg", "Revolver", "Rifle", "Shotgun", "Flamer", "Cannon", "Sniper", "Rocket", "Rail"]
FACTOR = [1.00, 1.04, 1.08, 1.12, 1.16, 1.20, 1.24, 1.28, 1.32, 1.36]  # 무기 종류 초당 피해 계수 (Config.WeaponDpsFactor)

def dm(level, era):
    e = level * LS
    return (1 + 0.04 * e + 0.00012 * e * e) * 1.4 ** (era - 1)

def step_cost(level, era):
    minutes = EARLY + (LATE - EARLY) * min(1, level / LATE_LEVEL)
    return int(INCOME_BASE * dm(level, era) * minutes)

tiers, total = [], 0
for i in range(1, 101):
    steps = 15 if i <= 10 else (12 if i <= 30 else 10)
    tiers.append((i, total, steps, (i - 1) // 10 + 1, (i - 1) % 10))
    total += steps

print(f"총 강화 단계 {total}")
print(f"{'무기':>4} {'강화단계':>7} {'진화비용':>12} {'활동수입/분':>12} {'진화(활동)':>10} {'방치/분':>10} {'진화(방치만)':>12} {'직접허수/분':>10}")
cum = 0
for i, mn, steps, era, cls in tiers:
    cost = sum(step_cost(l, era) for l in range(mn, mn + steps))
    cum += cost
    mid = mn + steps // 2
    active = INCOME_BASE * dm(mid, era)
    idle = IDLE_FRACTION * active            # 방치(분당, 배율 x1)
    manual = MANUAL_FRACTION * active        # 직접 쏘기(분당)
    if i in (1, 2, 3, 4, 5, 10, 15, 20, 30, 40, 50, 70, 100):
        print(f"{i:>4} {mn:>7} {cost:>12,} {active:>12,.0f} {cost / active:>8.1f}분 {idle:>10,.0f} {cost / idle / 60:>10.1f}시간 {manual:>10,.0f}")
print(f"누적 비용(마지막 무기까지) {cum:,}")
