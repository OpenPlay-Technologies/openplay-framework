# Hardcode CORE_PACKAGE_ID
HOUSE_TX_CAP_ID="0x9e202ab97880d67908e9a45f5dcdeb73e0a7ab767cb1ac2760454bd4ab222d1d"
COIN_FLIP_PACKAGE_ID="0x9f9bfbe7b8de7fc93a780fcfcdb1d643ae332ecb9dad2bf6ed35586eac518b0c"
COIN_FLIP_CAP="0x599755609d1e0d18d03872e6c23b60f2ba290ea1a4fde6d5c9ed320f0c5e6aa3"

# add the game
sui client ptb \
--move-call sui::tx_context::sender \
--assign sender \
--assign max_stake 10000000000 \
--assign house_edge_bps 500 \
--assign payout_factor_bps 20000 \
--move-call $COIN_FLIP_PACKAGE_ID::game::admin_create @$COIN_FLIP_CAP @$HOUSE_TX_CAP_ID max_stake house_edge_bps payout_factor_bps \
--assign gameObj \
--move-call $COIN_FLIP_PACKAGE_ID::game::share gameObj