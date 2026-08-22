-- One row per ERC-20 token this nest has ever seen in a pool, with the two facts a log cannot
-- carry: `symbol()` and `decimals()`. They come from the `[[calls]]` declarations in nuthatch.toml,
-- which fire once per `PoolCreated` row against the token address that row names — the same reads
-- the Uniswap subgraph's `fetchTokenSymbol`/`fetchTokenDecimals` make, at the same moment.
--
-- The call tables store the raw ABI return bytes, so the decoding happens here:
--   decimals()  a single 32-byte word; the value is its last byte.
--   symbol()    usually a dynamic `string` — offset word, length word, then the bytes. A handful of
--               older tokens return `bytes32` instead (a 66-char result), so both are handled; a
--               revert or an empty return becomes NULL rather than an empty string that would read
--               like a token genuinely called "".
--
-- A token in N pools is answered N times, once per creation block. `decimals` and `symbol` are
-- immutable in every ERC-20 worth indexing, so the earliest answer is taken and the rest discarded —
-- earliest rather than latest so the row does not change as new pools are created.
CREATE VIEW token_metadata AS
-- The hex→integer arithmetic below is spelled out with `position(… IN '0123456789abcdef')` because
-- DuckDB has no BLOB→INTEGER cast; `unhex` gives a BLOB and there is nowhere to take it from there.
WITH sym AS (
  SELECT address, block_number, result, reverted FROM token0_symbol
  UNION ALL
  SELECT address, block_number, result, reverted FROM token1_symbol
),
dec AS (
  SELECT address, block_number, result, reverted FROM token0_decimals
  UNION ALL
  SELECT address, block_number, result, reverted FROM token1_decimals
),
sym1 AS (
  SELECT address,
         CASE
           WHEN reverted = 'true' OR length(result) < 66 THEN NULL
           -- bytes32: the symbol is the leading bytes, right-padded with NULs.
           WHEN length(result) = 66
             THEN nullif(rtrim(decode(unhex(substr(result, 3))), chr(0)), '')
           -- dynamic string: chars 1..64 offset, 65..128 length, 129.. the bytes themselves.
           ELSE nullif(decode(unhex(substr(substr(result, 3), 129,
                  2 * ((position(substr(substr(result, 3), 127, 1) IN '0123456789abcdef') - 1) * 16
                     + (position(substr(substr(result, 3), 128, 1) IN '0123456789abcdef') - 1))))), '')
         END AS symbol,
         row_number() OVER (PARTITION BY address ORDER BY block_number, result) AS rn
  FROM sym
),
dec1 AS (
  SELECT address,
         CASE
           WHEN reverted = 'true' OR length(result) <> 66 THEN NULL
           ELSE (position(substr(result, 65, 1) IN '0123456789abcdef') - 1) * 16
              + (position(substr(result, 66, 1) IN '0123456789abcdef') - 1)
         END AS decimals,
         row_number() OVER (PARTITION BY address ORDER BY block_number, result) AS rn
  FROM dec
)
SELECT
  coalesce(s.address, d.address) AS token,
  s.symbol                       AS symbol,
  d.decimals                     AS decimals
FROM (SELECT address, symbol FROM sym1 WHERE rn = 1) s
FULL OUTER JOIN (SELECT address, decimals FROM dec1 WHERE rn = 1) d
  ON s.address = d.address;
