package avs

import (
	"crypto/ecdsa"
	"crypto/rand"
	"encoding/hex"
	"github.com/ethereum/go-ethereum/crypto"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
)

const avsABI = `[
	{"inputs":[{"internalType":"uint256","name":"roundId","type":"uint256"},{"internalType":"bytes32","name":"commitHash","type":"bytes32"}],
	 "name":"commit","outputs":[],"stateMutability":"nonpayable","type":"function"},
	{"inputs":[{"internalType":"uint256","name":"roundId","type":"uint256"},{"internalType":"int256","name":"predictionX96","type":"int256"},{"internalType":"bytes32","name":"salt","type":"bytes32"}],
	 "name":"reveal","outputs":[],"stateMutability":"nonpayable","type":"function"}
]`

type Client struct {
	addr common.Address
	abi  abi.ABI
	bc   *bind.BoundContract
}

func New(addr common.Address, backend bind.ContractBackend) (*Client, error) {
	a, err := abi.JSON(strings.NewReader(avsABI))
	if err != nil {
		return nil, err
	}
	return &Client{
		addr: addr,
		abi:  a,
		bc:   bind.NewBoundContract(addr, a, backend, backend, backend),
	}, nil
}

func KeccakPackedInt256Bytes32(x *big.Int, salt [32]byte) [32]byte {
	// abi.encodePacked(int256(x), bytes32(salt))
	// encode int256 as 32-byte big-endian two's complement
	b := make([]byte, 32+32)
	x.FillBytes(b[:32])
	copy(b[32:], salt[:])
	return common.BytesToHash(crypto.Keccak256(b))
}

// Helpers
func RandomSalt() ([32]byte, string) {
	var s [32]byte
	_, _ = rand.Read(s[:])
	return s, "0x" + hex.EncodeToString(s[:])
}

func (c *Client) Commit(auth *bind.TransactOpts, roundID *big.Int, commit [32]byte) (*types.Transaction, error) {
	return c.bc.Transact(auth, "commit", roundID, commit)
}

func (c *Client) Reveal(auth *bind.TransactOpts, roundID *big.Int, predictionX96 *big.Int, salt [32]byte) (*types.Transaction, error) {
	return c.bc.Transact(auth, "reveal", roundID, predictionX96, salt)
}

// BuildTransactor builds a keyed transactor for a given chain id
func BuildTransactor(pk *ecdsa.PrivateKey, chainID *big.Int) (*bind.TransactOpts, error) {
	return bind.NewKeyedTransactorWithChainID(pk, chainID)
}
