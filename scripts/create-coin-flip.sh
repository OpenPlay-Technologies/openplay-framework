# Hardcode CORE_PACKAGE_ID
COIN_FLIP_PACKAGE_ID="0x5f956e17034d35d9c66a429f8e312c2ce8daad4190c36a992b956ca94f924226"
COIN_FLIP_CAP="0xcb3a826f82b1106adeed699f4c0c92bf2f98b2d8cc511a26b2038724601d095f"

# add the game
sui client ptb \
--move-call sui::tx_context::sender \
--assign sender \
--assign min_stake 10000000 \
--assign max_stake 100000000 \
--assign house_edge_bps 500 \
--assign payout_factor_bps 20000 \
--move-call $COIN_FLIP_PACKAGE_ID::game::admin_create @$COIN_FLIP_CAP min_stake max_stake house_edge_bps payout_factor_bps \
--assign gameObj \
--move-call $COIN_FLIP_PACKAGE_ID::game::share gameObj