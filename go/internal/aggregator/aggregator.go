package aggregator

import (
	"context"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

const aggABI = `[
	{"inputs":[{"internalType":"uint32","name":"windowSeconds","type":"uint32"}],
	 "name":"twapPriceX96",
	 "outputs":[{"internalType":"uint256","name":"","type":"uint256"}],
	 "stateMutability":"view","type":"function"}
]`

type Aggregator struct {
	addr common.Address
	abi  abi.ABI
	cl   *ethclient.Client
}

func New(cl *ethclient.Client, addr common.Address) (*Aggregator, error) {
	a, err := abi.JSON(strings.NewReader(aggABI))
	if err != nil {
		return nil, err
	}
	return &Aggregator{addr: addr, abi: a, cl: cl}, nil
}

func (a *Aggregator) TwapPriceX96(ctx context.Context, window uint32) (*big.Int, error) {
	data, err := a.abi.Pack("twapPriceX96", window)
	if err != nil {
		return nil, err
	}
	out, err := a.cl.CallContract(ctx, ethereum.CallMsg{To: &a.addr, Data: data}, nil)
	if err != nil {
		return nil, err
	}
	var dec []interface{}
	if err := a.abi.UnpackIntoInterface(&dec, "twapPriceX96", out); err != nil {
		return nil, err
	}
	return dec[0].(*big.Int), nil
}
