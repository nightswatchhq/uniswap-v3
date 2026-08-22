-- Every token that appears in any pool, with its symbol, decimals, and how many pools reference it —
-- the token universe this nest touches, ranked by pool count (a proxy for how central a token is:
-- WETH, USDC, and friends sit at the top).
--
-- `symbol` and `decimals` come from `token_metadata`, i.e. from the declared `[[calls]]`. Because
-- this nest declares them, it will not start without `--state-rpc <archive>` at all — see the README.
-- The join is still a LEFT one rather than an inner: a token whose `symbol()` reverted, or which was
-- created in a block the call layer could not resolve, keeps its row here with the columns empty
-- instead of vanishing from the token universe entirely. `decimals` is what turns a raw `amount`
-- into the subgraph's decimal-adjusted figure, so anything comparing volumes to a subgraph needs it.
CREATE VIEW tokens AS
SELECT
  t.token,
  m.symbol,
  m.decimals,
  t.pools
FROM (
  SELECT token, count(*) AS pools
  FROM (
    SELECT token0 AS token FROM pools
    UNION ALL
    SELECT token1 AS token FROM pools
  )
  GROUP BY token
) t
LEFT JOIN token_metadata m ON m.token = t.token
ORDER BY t.pools DESC, t.token;
