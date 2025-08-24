package uniswap

import (
	"context"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

const poolABI = `[
	{"inputs":[{"internalType":"uint32[]","name":"secondsAgos","type":"uint32[]"}],
	 "name":"observe","outputs":[
		{"internalType":"int56[]","name":"tickCumulatives","type":"int56[]"},
		{"internalType":"uint160[]","name":"secondsPerLiquidityCumulativeX128","type":"uint160[]"}],
	 "stateMutability":"view","type":"function"},
	{"inputs":[],"name":"slot0","outputs":[
		{"internalType":"uint160","name":"sqrtPriceX96","type":"uint160"},
		{"internalType":"int24","name":"tick","type":"int24"},
		{"internalType":"uint16","name":"observationIndex","type":"uint16"},
		{"internalType":"uint16","name":"observationCardinality","type":"uint16"},
		{"internalType":"uint16","name":"observationCardinalityNext","type":"uint16"},
		{"internalType":"uint8","name":"feeProtocol","type":"uint8"},
		{"internalType":"bool","name":"unlocked","type":"bool"}],
	 "stateMutability":"view","type":"function"}
]`

type Pool struct {
	addr common.Address
	abi  abi.ABI
	cl   *ethclient.Client
}

func NewPool(cl *ethclient.Client, addr common.Address) (*Pool, error) {
	a, err := abi.JSON(strings.NewReader(poolABI))
	if err != nil {
		return nil, err
	}
	return &Pool{addr: addr, abi: a, cl: cl}, nil
}

func (p *Pool) SpotPriceX96(ctx context.Context) (*big.Int, error) {
	data, err := p.abi.Pack("slot0")
	if err != nil {
		return nil, err
	}
	out, err := p.cl.CallContract(ctx, ethereum.CallMsg{To: &p.addr, Data: data}, nil)
	if err != nil {
		return nil, err
	}
	var dec []interface{}
	if err := p.abi.UnpackIntoInterface(&dec, "slot0", out); err != nil {
		return nil, err
	}
	// dec[0] sqrtPriceX96 (uint160)
	sqrt := dec[0].(*big.Int)
	// priceX96 = (sqrt^2) >> 96
	priceX96 := new(big.Int).Mul(sqrt, sqrt)
	priceX96.Rsh(priceX96, 96)
	return priceX96, nil
}

func (p *Pool) TwapTick(ctx context.Context, windowSec uint32) (int64, error) {
	args := []uint32{windowSec, 0}
	data, err := p.abi.Pack("observe", args)
	if err != nil {
		return 0, err
	}
	out, err := p.cl.CallContract(ctx, ethereum.CallMsg{To: &p.addr, Data: data}, nil)
	if err != nil {
		return 0, err
	}
	var dec []interface{}
	if err := p.abi.UnpackIntoInterface(&dec, "observe", out); err != nil {
		return 0, err
	}
	// tickCumulatives is []int56 -> []*big.Int
	ticks := dec[0].([]*big.Int)
	delta := new(big.Int).Sub(ticks[1], ticks[0]) // int56
	// average tick = delta / window
	avg := new(big.Int).Quo(delta, new(big.Int).SetUint64(uint64(windowSec)))
	return avg.Int64(), nil
}
