# Manager

A collateralized debt vault that issues tokenized, synthetic treasury bills on ERC-20 based foreign currencies.

**Now deployed on Celo!** 🌴 See [CELO_MIGRATION.md](./CELO_MIGRATION.md) for migration details and deployment guide.

## Smart Contracts

A longer description of the smart contracts can be found in the [Yield v2 reference](https://docs.google.com/document/d/1WBrJx_5wxK1a4N_9b6IQV70d2TyyyFxpiTfjA6PuZaQ/edit).

### Oracles
Oracles return spot prices, borrowing rates and lending rates for the assets in the protocol.

### Join
Joins store assets, such as ERC20 or ERC721 tokens.

### FYToken
FYTokens are ERC20 tokens that are redeemable at maturity for their underlying asset, at an amount that starts at 1 and increases with the lending rate (`chi`).

### Cauldron
The Cauldron is responsible for the accounting in the Yield Protocol. Vaults are created to contain borrowing positions of one collateral asset type against one fyToken series. The debt in a given vault increases with the borrowing rate (`rate`) after maturity of the associated fyToken series.

When the value of the collateral in a vault falls below the value of the borrowed fyToken, the vault can be liquidated.

### Ladle
The Ladle is the gateway for all Cauldron integrations, and all asset movements in and out of the Joins (except fyToken redemptions). To implement certain features the Ladle integrates with YieldSpace Pools.

[Ladle recipe cookbook](https://docs.google.com/document/d/1-r9g99aZfGLd1Aa3FRxBXLybgfGzAZIuHWwufF-I8Js).

### Wand
The Wand bundles function calls into governance actions.

### Witch
The Witch is the liquidation engine for the Yield Protocol Vault v2.

## Warning
This code is provided as-is, with no guarantees of any kind.

### Pre Requisites
Before running any command, make sure to install dependencies:

```
$ yarn
```

### Lint Solidity
Lint the Solidity code:

```
$ yarn lint:sol
```

### Lint TypeScript
Lint the TypeScript code:

```
$ yarn lint:ts
```

### Coverage
Generate the code coverage report:

```
$ yarn coverage
```

### Test

#### Environment Setup
Create a `.env` file with RPC URLs for both Ethereum and Celo:

```bash
ETH=https://eth-mainnet.g.alchemy.com/v2/YOUR_ETH_API_KEY
CELO=https://celo-mainnet.g.alchemy.com/v2/YOUR_CELO_API_KEY
PRIVATE_KEY=0x...  # For deployments
GOVERNANCE=0x...   # Governance address
```

#### Run Tests
Compile and test the smart contracts with [Foundry](https://getfoundry.sh/):

```bash
# Load environment variables
source .env

# Run all tests (fast dev profile recommended)
./bin/test

# Run only Ethereum fork tests
./bin/test --match-path "src/test/oracles/Chainlink*.sol"

# Run only Celo fork tests
./bin/test --match-path "src/test/oracles/VariableIR*.sol"

# Run specific test with verbose output
./bin/test --match-contract MentoSpotOracleTest -vvv
```

**Performance Tip**: Use `./bin/test` (defaults to the dev profile) for fast compilation (~1-2s instead of 120s+).

See [src/test/README.md](./src/test/README.md) for comprehensive testing documentation.

### Deploy

#### Celo Deployment
Deploy to Celo mainnet:

```bash
source .env
forge script script/DeployMinimalCeloSystem.s.sol \
  --rpc-url $CELO_RPC_URL \
  --broadcast \
  --slow \
  -vvvv
```

**Deployed Contracts** (Chain ID: 42220):
- Cauldron: `0xdf9ce55F0389341221c70BbCe171bF5ab983c21F`
- Ladle: `0x71dc46418a0b368618999FEd7fC1237a7720E662`
- Witch: `0xdF4Bc5bef2aAeF3D78ad0B9369f39C5ABdBe081E`
- MentoOracle: `0xD89cF4B4c739a0100FC96d2Ab0167A081cc2bCEB`
- cKES Join: `0xA1f65d6B7FC4ABB1f7331cBBD441E478fb76E164`
- USDT Join: `0xCA12b75Bf6fb0A76b3B8D7Ed805071dBF6221A7d`
- fyUSDT: `0x8d0c33Bf1CEbE94109dd10632dd4D03096cDDe7e`

**Config**: cKES collateral, USDT debt, 150% ratio, 1M max debt. Oracle configured with cKES/USD (Mento) at 600s maxAge, 0.003-0.015 bounds.

**Idempotent**: Set env vars (`CAULDRON`, `LADLE`, etc) to reuse existing contracts. Script validates reused oracles and skips already-configured assets.

## Bug Bounty
Yield is offering bounties for bugs disclosed to us at [security@yield.is](mailto:security@yield.is). The bounty reward is up to $500,000, depending on severity. Please include full details of the vulnerability and steps/code to reproduce. We ask that you permit us time to review and remediate any findings before public disclosure.

## License
All files in this repository are released under the [GPLv3](https://github.com/yieldprotocol/fyDai/blob/master/LICENSE.md) license.
