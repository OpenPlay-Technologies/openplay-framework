CORE_PACKAGE_ID="0x4653705e1b2a974bfb41904435819665028f7bbcb53f467ec74bf4efca4fae5c"


# create the bm
sui client ptb \
--move-call sui::tx_context::sender \
--assign sender \
--move-call $CORE_PACKAGE_ID::balance_manager::new \
--assign bmOutput \
--move-call $CORE_PACKAGE_ID::balance_manager::share bmOutput.0 \
--transfer-objects [bmOutput.1] sender

# fund the BM
# tip: use sui client gas to see your coins
BALANCE_MANAGER_ID="0xff83966047f5b5483ce75e475dece6b3c60ca39ed28f5e6b387fb66a9a0d2fcf"
BALANCE_MANAGER_CAP_ID="0x2acfe15698a0b85d87e73b655c2030117ba6e788d416dbe8ce972cee249df5e0"
COIN_ID="0x160df7789d7406600c544eff5be4b644ca47ea82499d23c5eb9bf02573f380ae"

sui client ptb \
--move-call $CORE_PACKAGE_ID::balance_manager::deposit @$BALANCE_MANAGER_ID @$BALANCE_MANAGER_CAP_ID @$COIN_ID

# crete a play cap to interact with it
sui client ptb \
--move-call $CORE_PACKAGE_ID::balance_manager::mint_play_cap @$BALANCE_MANAGER_ID @$BALANCE_MANAGER_CAP_ID \
--assign playCap \
--move-call sui::tx_context::sender \
--assign sender \
--transfer-objects [playCap] sender