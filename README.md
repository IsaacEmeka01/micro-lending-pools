# Micro-lending Pools for Developing Countries

A decentralized micro-lending platform built on Stacks blockchain that enables peer-to-peer lending using reputation-based collateral.

## Features

- **Reputation-based Collateral**: Borrowers use reputation scores instead of traditional collateral
- **Flexible Lending Pools**: Multiple pools with different terms and interest rates
- **Automatic Reputation Tracking**: Dynamic scoring based on payment history
- **Secure Token Transfers**: Built-in STX token handling
- **Contributor Earnings**: Lenders earn interest on their contributions
- **Admin Controls**: Platform oversight and emergency functions

## Smart Contract Functions

### Public Functions
- `initialize-reputation()`: Initialize user reputation profile
- `create-lending-pool()`: Create a new lending pool
- `contribute-to-pool()`: Add funds to a lending pool
- `request-loan()`: Request a loan from a pool
- `repay-loan()`: Make loan repayments

### Read-only Functions
- `get-user-reputation()`: Get user's reputation details
- `get-lending-pool()`: Get pool information
- `get-loan-details()`: Get loan information
- `check-loan-eligibility()`: Check if user can borrow

## Getting Started

1. Install Clarinet
2. Clone this repository
3. Run tests: `clarinet test`
4. Deploy to testnet: `clarinet deploy --testnet`

## License

MIT License