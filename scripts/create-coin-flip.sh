# Hardcode CORE_PACKAGE_ID
COIN_FLIP_PACKAGE_ID="0x307264d88fdfb449a70187a53d054a050233abf1ca73fec68de626523eaa2065"
COIN_FLIP_CAP="0xaef1ef7765e7df70720f7124db67139986fd15e77fdce6621fb095a70cca14e0"

# add the game
sui client ptb \
--move-call sui::tx_context::sender \
--assign sender \
--assign max_stake 10000000000 \
--assign house_edge_bps 500 \
--assign payout_factor_bps 20000 \
--move-call $COIN_FLIP_PACKAGE_ID::game::admin_create @$COIN_FLIP_CAP max_stake house_edge_bps payout_factor_bps \
--assign gameObj \
--move-call $COIN_FLIP_PACKAGE_ID::game::share gameObj