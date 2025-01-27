# Hardcode CORE_PACKAGE_ID
HOUSE_TX_CAP_ID="0xd523eab2ce877a593dfd732efd876a3094b99db8786bda1dca914ce4d47d7167"
COIN_FLIP_PACKAGE_ID="0xf9f263e2297a634f0bd90269f55c9501f2914a026a2ff6c6d9cb37b398cd35f4"
COIN_FLIP_CAP="0x88b3e292d9cdd3da4aff53eab2cc39df6473b4501ff3834de893190377666910"

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