package main

import (
	"context"
	"crypto/ecdsa"
	"encoding/hex"
	"fmt"
	"log"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"

	"github.com/stuparm/eigenlayer-price-avs/go/internal/aggregator"
	"github.com/stuparm/eigenlayer-price-avs/go/internal/avs"
	"github.com/stuparm/eigenlayer-price-avs/go/internal/config"
	"github.com/stuparm/eigenlayer-price-avs/go/internal/predictor"
	"github.com/stuparm/eigenlayer-price-avs/go/internal/uniswap"
)

type RoundState struct {
	PredX96 *big.Int
	SaltHex string
}

func mustPriv(hexkey string) *ecdsa.PrivateKey {
	k, err := crypto.HexToECDSA(strings.TrimPrefix(hexkey, "0x"))
	if err != nil {
		log.Fatal(err)
	}
	return k
}

func saveState(round string, st RoundState) {
	_ = os.MkdirAll("state", 0o755)
	f := filepath.Join("state", fmt.Sprintf("%s.json", round))
	b := []byte(fmt.Sprintf(`{"pred":"%s","salt":"%s"}`, st.PredX96.Text(10), st.SaltHex))
	_ = os.WriteFile(f, b, 0o644)
}

func loadSalt(round string) ([32]byte, *big.Int, error) {
	f := filepath.Join("state", fmt.Sprintf("%s.json", round))
	b, err := os.ReadFile(f)
	if err != nil {
		return [32]byte{}, nil, err
	}
	var saltHex string
	var predStr string
	_, err = fmt.Sscanf(string(b), `{"pred":"%s","salt":"%s"}`, &predStr, &saltHex)
	if err != nil {
		return [32]byte{}, nil, err
	}
	p := new(big.Int)
	p.SetString(strings.TrimSuffix(predStr, `","salt":"`), 10)
	saltBytes, _ := hex.DecodeString(strings.TrimPrefix(strings.TrimSuffix(saltHex, `"}"`), "0x"))
	var s [32]byte
	copy(s[:], saltBytes)
	return s, p, nil
}

func main() {
	cfg := config.Load()
	ctx := context.Background()

	cl, err := ethclient.Dial(cfg.RPC)
	if err != nil {
		log.Fatal(err)
	}

	// set up contracts
	avsCli, err := avs.New(common.HexToAddress(cfg.AVSManager), cl)
	if err != nil {
		log.Fatal(err)
	}

	var priceX96Long *big.Int
	var tickShort, tickLong int64

	if cfg.Aggregator != "" {
		agg, err := aggregator.New(cl, common.HexToAddress(cfg.Aggregator))
		if err != nil {
			log.Fatal(err)
		}
		priceX96Long, err = agg.TwapPriceX96(ctx, cfg.TwapLongSec)
		if err != nil {
			log.Fatal(err)
		}
		// drift via ticks from pool directly (optional)
		pool, _ := uniswap.NewPool(cl, common.HexToAddress(cfg.Pool))
		tickShort, _ = pool.TwapTick(ctx, cfg.TwapShortSec)
		tickLong, _ = pool.TwapTick(ctx, cfg.TwapLongSec)
	} else {
		pool, err := uniswap.NewPool(cl, common.HexToAddress(cfg.Pool))
		if err != nil {
			log.Fatal(err)
		}
		// approximate long TWAP: use long tick -> derive price from slot0 squared; to keep simple, use spot as base
		priceX96Long, err = pool.SpotPriceX96(ctx)
		if err != nil {
			log.Fatal(err)
		}
		tickShort, _ = pool.TwapTick(ctx, cfg.TwapShortSec)
		tickLong, _ = pool.TwapTick(ctx, cfg.TwapLongSec)
	}

	drift := predictor.DriftBpsFromTicks(tickShort, tickLong)
	pred := predictor.PredictNext(priceX96Long, drift, cfg.AlphaBps)

	// --- commit
	priv := mustPriv(cfg.PrivateKeyHex)
	auth, _ := avs.BuildTransactor(priv, cfg.ChainID)
	salt, saltHex := avs.RandomSalt()
	commit := avs.KeccakPackedInt256Bytes32(pred, salt)
	tx1, err := avsCli.Commit(auth, cfg.RoundID, commit)
	if err != nil {
		log.Fatal("commit:", err)
	}
	fmt.Println("commit tx:", tx1.Hash().Hex())
	saveState(cfg.RoundID.String(), RoundState{PredX96: pred, SaltHex: saltHex})

	// Wait a bit (you can also run 'reveal' as a separate subcommand)
	time.Sleep(15 * time.Second)

	// --- reveal
	auth2, _ := avs.BuildTransactor(priv, cfg.ChainID)
	tx2, err := avsCli.Reveal(auth2, cfg.RoundID, pred, salt)
	if err != nil {
		log.Fatal("reveal:", err)
	}
	fmt.Println("reveal tx:", tx2.Hash().Hex())
}
