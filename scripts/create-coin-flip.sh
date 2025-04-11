# Hardcode CORE_PACKAGE_ID
COIN_FLIP_PACKAGE_ID="0x2ff81d5d87ef2847d26de1920c70871f3a90b9d7471c917c9dd41f75c3dd4709"
COIN_FLIP_CAP="0x7163420f20b29b12c7bd3ba33f6eb23d3862e6318271362a54e5f2cbec121355"

# add the game
sui client ptb \
--move-call sui::tx_context::sender \
--assign sender \
--assign min_stake 10000000 \
--assign max_stake 10000000000 \
--assign house_edge_bps 500 \
--assign payout_factor_bps 20000 \
--move-call $COIN_FLIP_PACKAGE_ID::game::admin_create @$COIN_FLIP_CAP min_stake max_stake house_edge_bps payout_factor_bps \
--assign gameObj \
--move-call $COIN_FLIP_PACKAGE_ID::game::share gameObj