package predictor

import (
	"log"
	"math/big"
)

// PredictNext returns a next-block price in Q64.96.
// baseX96: long TWAP price (Q64.96)
// driftBps: computed from short vs long ticks; pass as basis points delta (can be negative)
// alphaBps: how strongly to follow the drift (0..10000)
func PredictNext(baseX96 *big.Int, driftBps int64, alphaBps int64) *big.Int {
	if baseX96 == nil || baseX96.Sign() <= 0 {
		log.Println("PredictNext: invalid base")
		return big.NewInt(0)
	}
	// scale: predicted = base * (1 + alpha * drift / 10_000 / 10_000)
	//        = base * (1 + (alphaBps * driftBps)/1e8)
	scaleNum := big.NewInt(10_000 * 10_000) // 1e8
	adj := big.NewInt(10_000 * 10_000)      // start at 1.0

	tmp := big.NewInt(alphaBps)
	tmp.Mul(tmp, big.NewInt(driftBps)) // alphaBps * driftBps
	adj.Add(adj, tmp)                  // 1e8 + alpha*drift

	p := new(big.Int).Mul(baseX96, adj)
	p.Quo(p, scaleNum)
	return p
}

// DriftBpsFromTicks: if short tick > long tick, drift up, else down.
// One tick ~ 0.01% => ~1 bp. We’ll approximate driftBps = (short - long).
func DriftBpsFromTicks(shortTick, longTick int64) int64 {
	return shortTick - longTick
}
