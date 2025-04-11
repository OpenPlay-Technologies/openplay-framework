# Hardcode CORE_PACKAGE_ID
PIGGY_BANK_PACKAGE_ID="0xf04da529c10b9772f1c51b3644acafbad634f0c1638c5bf20c3f7be261926cc7"
PIGGY_BANK_CAP="0xfbe05967c5e529ea3b971165672f8d240ee3dbd8920f2df25d244bb8a01b6299"


# add the game (EASY)
sui client ptb \
--move-call sui::tx_context::sender \
--assign sender \
--assign min_stake 10000000 \
--assign max_stake 1000000000 \
--assign success_rate_bps 9000 \
--make-move-vec "<u64>" "[10740, 11535, 12388, 13305, 14290, 15347, 16483, 17702, 19012, 20419, 21930, 23553, 25296, 27168, 29179, 31338, 33657, 36147, 38822, 41695, 44781, 48094, 51653, 55476, 59581, 63990, 68725, 73811, 79273, 85139, 91439, 98206, 105473, 113278, 121661, 130663, 140333, 150717, 161870, 173849, 186713, 200530, 215369]" \
--assign steps_payout_bps \
--move-call $PIGGY_BANK_PACKAGE_ID::game::admin_create @$PIGGY_BANK_CAP min_stake max_stake success_rate_bps steps_payout_bps \
--assign gameObj \
--move-call $PIGGY_BANK_PACKAGE_ID::game::share gameObj

# add the game (MEDIUM)
sui client ptb \
--move-call sui::tx_context::sender \
--assign sender \
--assign min_stake 10000000 \
--assign max_stake 1000000000 \
--assign success_rate_bps 8000 \
--make-move-vec "<u64>" "[12070, 14568, 17584, 21224, 25617, 30920, 37321, 45046, 54371, 65626, 79210, 95606, 115397, 139284, 168116, 202916, 244920, 295618, 356811, 430671, 519820, 627422, 757299, 914060, 1103270]" \
--assign steps_payout_bps \
--move-call $PIGGY_BANK_PACKAGE_ID::game::admin_create @$PIGGY_BANK_CAP min_stake max_stake success_rate_bps steps_payout_bps \
--assign gameObj \
--move-call $PIGGY_BANK_PACKAGE_ID::game::share gameObj

# add the game (HARD)
sui client ptb \
--move-call sui::tx_context::sender \
--assign sender \
--assign min_stake 10000000 \
--assign max_stake 1000000000 \
--assign success_rate_bps 7000 \
--make-move-vec "<u64>" "[13800, 19044, 26281, 36267, 50049, 69068, 95313, 131532, 181515, 250490, 345677, 477034, 658306, 908463, 1253679]" \
--assign steps_payout_bps \
--move-call $PIGGY_BANK_PACKAGE_ID::game::admin_create @$PIGGY_BANK_CAP min_stake max_stake success_rate_bps steps_payout_bps \
--assign gameObj \
--move-call $PIGGY_BANK_PACKAGE_ID::game::share gameObj
