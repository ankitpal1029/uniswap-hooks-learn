Ticks => represents token price of a pair

=> smallest possible amount by which price of asset can move up or down

price(i) => 1.0001 ^ i


at the begining tick = 0

Token A <> Token B trades 1 <> 1

price(i = 0) 1.0001 ^ 0 = 1 (same price)

tick goes down to -50

price(i = -50) 1.0001 ^ -50 = 0.9950127279

1 Token A = 0.9950127279 Token B

# sqrtPriceLimitX96

Q notion

v => q notion

v * (2 ^ k) where k is some constant in the ^case

v * (2 ^ 96)

`sqrtPriceX96` is the q notion value for the square root of the price (right now)

price (right now) = Price(i = currentTick) = 1.0001 ^ i

sqrtPriceX96 = ((sqrt(price))) * (2^96)

`sqrtPriceLimitX96` specifies a LIMIT on the price ratio.

- every pool can have atmost 1 hook
- 1 hook can be used in multiple pools

price changes when a swap happens so this is where you will deal with
- interest addition
- liquidation

but is there a better way to do this other than run a loop


# How to find price in uni v3
tick = -200697

# token 0 = ETH
decimals_0 = 1e18
# token 1 = USDC
decimals_1 = 1e6

p = 1.0001 ** tick * decimals_0 / decimals_1

tick spacing = number of ticks to skip when price moves