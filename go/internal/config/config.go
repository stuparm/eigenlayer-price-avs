package config

import (
	"log"
	"math/big"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

type Config struct {
	RPC           string
	PrivateKeyHex string
	ChainID       *big.Int
	AVSManager    string
	Aggregator    string // optional: your on-chain PriceAggregator; if empty we call pool directly
	Pool          string // Uniswap v3 pool (defaults to USDC/WETH 0.05%)
	TwapLongSec   uint32 // e.g. 300
	TwapShortSec  uint32 // e.g. 30
	AlphaBps      int64  // drift strength, e.g. 200 (=2%)
	RoundID       *big.Int
}

func mustEnv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	if def != "" {
		return def
	}
	log.Fatalf("missing env %s", k)
	return ""
}

func Load() Config {
	_ = godotenv.Load()

	chainID, _ := new(big.Int).SetString(mustEnv("CHAIN_ID", "1"), 10)
	roundID, _ := new(big.Int).SetString(mustEnv("ROUND_ID", "1"), 10)

	tl, _ := strconv.ParseUint(mustEnv("TWAP_LONG_SEC", "300"), 10, 32)
	ts, _ := strconv.ParseUint(mustEnv("TWAP_SHORT_SEC", "30"), 10, 32)
	alpha, _ := strconv.ParseInt(mustEnv("ALPHA_BPS", "200"), 10, 64) // 2%

	return Config{
		RPC:           mustEnv("RPC_URL", ""),
		PrivateKeyHex: mustEnv("OPERATOR_PRIVKEY", ""),
		ChainID:       chainID,
		AVSManager:    mustEnv("AVS_MANAGER_ADDR", ""),
		Aggregator:    os.Getenv("AGGREGATOR_ADDR"),
		Pool:          mustEnv("POOL_ADDR", "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640"),
		TwapLongSec:   uint32(tl),
		TwapShortSec:  uint32(ts),
		AlphaBps:      alpha,
		RoundID:       roundID,
	}
}
