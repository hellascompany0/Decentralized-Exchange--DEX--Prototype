# 🏦 Decentralized Exchange (DEX) Prototype

🎯 **An educational AMM-based DEX implementation in Clarity for the Stacks blockchain**

## 📋 Overview

This project demonstrates a **Minimum Viable Product (MVP)** of a decentralized exchange using **Automated Market Maker (AMM)** logic. Built with Clarity smart contracts, it showcases core DeFi concepts including liquidity pools, token swapping, and yield farming fundamentals.

## ✨ Features

- 🔄 **Token Swapping**: Exchange tokens using constant product formula (x * y = k)
- 💧 **Liquidity Pools**: Create and manage token pair pools
- 🏊 **Liquidity Provision**: Add/remove liquidity to earn fees
- 💰 **Fee System**: Configurable trading fees (default 3%)
- 🎯 **Slippage Protection**: Minimum output amount validation
- 📊 **Pool Analytics**: View reserves, balances, and LP tokens

## 🏗️ Architecture

### Core Components

- **Pool Management**: Create and manage token pairs
- **AMM Logic**: Automated market making with constant product formula
- **Liquidity Tokens**: LP tokens representing pool ownership
- **Fee Distribution**: Trading fees collected from swaps
- **Balance Tracking**: Internal token balance management

### Key Functions

| Function | Description |
|----------|-------------|
| `create-pool` | Initialize a new trading pair |
| `add-liquidity` | Deposit tokens to earn fees |
| `remove-liquidity` | Withdraw tokens and earned fees |
| `swap-exact-tokens-for-tokens` | Exchange tokens |
| `get-amount-out-preview` | Preview swap output |

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Basic understanding of Clarity and Stacks blockchain

### Setup

1. **Clone the repository**
```bash
git clone <repository-url>
cd decentralized-exchange
```

2. **Install dependencies**
```bash
npm install
```

3. **Run tests**
```bash
clarinet test
```

4. **Deploy locally**
```bash
clarinet console
```

## 💡 Usage Examples

### Creating a Pool

```clarity
;; Create STX/USDC pool with initial liquidity
(contract-call? .decentralized-exchange create-pool 
  'SP000000000000000000002Q6VF78.stx-token
  'SP000000000000000000002Q6VF78.usdc-token
  u1000000 ;; 1 STX
  u1000000 ;; 1000 USDC
)
```

### Adding Liquidity

```clarity
;; Add more liquidity to existing pool
(contract-call? .decentralized-exchange add-liquidity
  'SP000000000000000000002Q6VF78.stx-token
  'SP000000000000000000002Q6VF78.usdc-token
  u500000  ;; 0.5 STX
  u500000  ;; 500 USDC
)
```

### Swapping Tokens

```clarity
;; Swap 1 STX for USDC with 5% slippage tolerance
(contract-call? .decentralized-exchange swap-exact-tokens-for-tokens
  'SP000000000000000000000000000000000000000000000000000000000000000.stx-token
  'SP000000000000000000000000000000000000000000000000000000000000000.usdc-token
  u1000000  ;; 1 STX input
  u950000   ;; Minimum 950 USDC output
)
```

### Preview Swap Output

```clarity
;; Check how much USDC you'll get for 1 STX
(contract-call? .decentralized-exchange get-amount-out-preview
  'SP000000000000000000000000000000000000000000000000000000000000000.stx-token
  'SP000000000000000000000000000000000000000000000000000000000000000.usdc-token
  u1000000  ;; 1 STX
)
```

## 📈 AMM Logic Explained

### Constant Product Formula

The DEX uses the **constant product formula**: `x * y = k`

- `x` = Reserve of token X
- `y` = Reserve of token Y  
- `k` = Constant product

### Price Calculation

```
Price = Reserve_Y / Reserve_X
```

### Swap Calculation

```
Amount_Out = (Amount_In * Reserve_Out) / (Reserve_In + Amount_In)
```

*Note: Fees are deducted from input amount before calculation*

## 🔧 Configuration

### Fee Structure

- **Default Fee**: 3% (300 basis points)
- **Adjustable**: Contract owner can modify fee rate
- **Fee Distribution**: Collected in liquidity pools

### Error Codes

| Code | Error | Description |
|------|-------|-------------|
| u100 | `err-owner-only` | Only contract owner can execute |
| u101 | `err-insufficient-balance` | Insufficient token balance |
| u102 | `err-invalid-amount` | Invalid input amount |
| u103 | `err-pool-not-found` | Trading pair doesn't exist |
| u104 | `err-insufficient-liquidity` | Not enough liquidity |
| u105 | `err-zero-amount` | Amount cannot be zero |
| u106 | `err-slippage-too-high` | Slippage exceeds tolerance |

## 🧪 Testing

Run the test suite:

```bash
clarinet test
```

Test specific scenarios:
- Pool creation and management
- Liquidity provision and withdrawal
- Token swapping with various amounts
- Error handling and edge cases

## 📚 Educational Value

This DEX prototype teaches:

- 🔄 **AMM Mechanics**: How automated market makers work
- 💧 **Liquidity Management**: Pool creation and maintenance
- 💰 **DeFi Economics**: Fee structures and yield farming
- 🏗️ **Smart Contract Design**: Clarity best practices
- 🔐 **Security Patterns**: Input validation and error handling

## 🛠️ Development

### Project Structure

```
├── contracts/
│   └── decentralized-exchange.clar
├── tests/
│   └── decentralized-exchange_test.ts
├── Clarinet.toml
└── README.md
```

### Key Design Decisions

- **Simple AMM**: Constant product formula for educational clarity
- **Internal Balances**: Simplified token management
- **Pool Tokens**: LP tokens track ownership shares
- **Fee Collection**: Fees remain in pools for liquidity providers

## 🚨 Limitations

⚠️ **This is an educational prototype**:

- Not production-ready
- Simplified token handling
- No oracle integration
- Basic fee structure
- Limited governance features

## 📖 Further Reading

- [Automated Market Makers Explained](https://docs.uniswap.org/protocol/V2/concepts/protocol-overview/how-uniswap-works)
- [Clarity Language Reference](https://docs.stacks.co/clarity)
- [Stacks Blockchain Documentation](https://docs.stacks.co/)

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues and enhancement requests.

## 📄 License

This project is for educational purposes. Use at your own risk.

---

*Built with ❤️ for the Stacks ecosystem*
