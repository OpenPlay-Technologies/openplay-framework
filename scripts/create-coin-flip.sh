# Hardcode CORE_PACKAGE_ID
HOUSE_TX_CAP_ID="0xd87326789c37dcf81da12278ce53d8d28c9583fb471a31594d994c93ca6306c4"
COIN_FLIP_PACKAGE_ID="0x90b4964d369e4dfc4e8e0cf937968ca67909452c75ec50813aeed69748b73f2d"
COIN_FLIP_CAP="0xba606ad76782c94300aa4021e9e6becae6899911f7e3ae3324b1e9f55e49bd4e"

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