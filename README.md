# BitFi - Decentralized Bitcoin Lending Protocol

BitFi is an innovative DeFi protocol built on the Stacks blockchain that enables users to use their Stacked STX as collateral for borrowing, creating a unique financial primitive that turns staked assets into productive capital.

## 🚀 Key Features

### Novel Collateralization with Stacked STX
- **Productive Staking**: Use your Stacked STX tokens as collateral while continuing to earn stacking rewards
- **Capital Efficiency**: Unlock liquidity from your staked assets without unstaking
- **Bitcoin-Native**: Built specifically for the Stacks/Bitcoin ecosystem

### Core Functionality
- **Vault System**: Create isolated collateral vaults with your STX
- **Flexible Borrowing**: Borrow against your collateral with competitive rates
- **Dynamic Interest Rates**: Algorithmically determined rates based on pool utilization
- **Automated Liquidations**: Robust liquidation engine to maintain protocol solvency

## 🏗️ Architecture

The protocol consists of three main smart contracts:

### 1. Stacking Collateral Contract (`stacking-collateral.clar`)
- Manages user vaults and collateral positions
- Handles deposits, withdrawals, borrowing, and repayments
- Implements safety checks and collateralization ratios
- Tracks stacking rewards and cycles

### 2. Lending Pool Contract (`lending-pool.clar`)
- Manages the lending pool liquidity
- Calculates dynamic interest rates based on utilization
- Handles supply and borrow rate calculations
- Manages reserve factors and protocol fees

### 3. Liquidation Engine Contract (`liquidation-engine.clar`)
- Monitors vault health and collateralization ratios
- Executes liquidations for undercollateralized positions
- Applies liquidation penalties to maintain protocol stability

## 📊 Key Parameters

- **Minimum Collateralization Ratio**: 150%
- **Base Interest Rate**: 5% APY
- **Optimal Utilization Rate**: 80%
- **Maximum Interest Rate**: 25% APY
- **Liquidation Penalty**: 10%
- **Reserve Factor**: 10%

## 🛠️ Development Setup

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) v2.6.0 or later
- [Node.js](https://nodejs.org/) v16 or later

### Installation

1. Clone the repository:
\`\`\`bash
git clone https://github.com/your-org/bitfi-stacking-collateral
cd bitfi-stacking-collateral
\`\`\`

2. Install Clarinet (if not already installed):
\`\`\`bash
# macOS
brew install clarinet

# Or download from GitHub releases
\`\`\`

3. Initialize the project:
\`\`\`bash
clarinet check
\`\`\`

### Running Tests

\`\`\`bash
clarinet test
\`\`\`

### Local Development

Start a local devnet:
\`\`\`bash
clarinet integrate
\`\`\`

## 🔧 Usage

### Creating a Vault

```clarity
;; Create a new vault with 1000 STX as collateral
(contract-call? .stacking-collateral create-vault u1000000000 u1)
