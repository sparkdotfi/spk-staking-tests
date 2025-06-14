# Symbiotic Vault Test Suite

This test suite provides comprehensive testing for the Symbiotic sSPK vault deployed on mainnet. The tests are organized into modular files for better maintainability and clarity.

## Test Structure

### BaseTest.sol
**Common base class** inherited by all test files
- **Setup**: Mainnet fork configuration and contract initialization
- **Constants**: All mainnet addresses and deployment parameters
- **Helper Functions**: Token distribution, epoch initialization, utility functions
- **Test Users**: Alice, Bob, Charlie, and attacker addresses

### Test Files Overview

| File | Tests | Description |
|------|-------|-------------|
| **VaultInitializationTest.sol** | 8 | Basic vault setup, configuration, and admin roles |
| **DepositWithdrawalTest.sol** | 10 | Core deposit/withdrawal functionality and ERC20 features |
| **AdminTest.sol** | 8 | Admin functions, access control, and governance features |
| **EdgeCaseTest.sol** | 10 | Edge cases, error conditions, and input validation |
| **SlashingTest.sol** | 13 | Slashing functionality and Symbiotic ecosystem integration |
| **IntegrationTest.sol** | 6 | Complex workflows and multi-component integration |

**Total: 55 tests, all passing** ✅

## Test Categories

### 🔧 Vault Initialization Tests
- Vault configuration and metadata
- Admin role verification  
- Delegator and slasher setup
- Burner router configuration
- Epoch system functionality
- ERC20 interface compliance

### 💰 Deposit & Withdrawal Tests  
- Single and multi-user deposits
- Withdrawal initiation and claiming
- Batch claims across epochs
- Redeem functionality (shares → assets)
- Vault token transferability
- Share accounting verification

### 👑 Admin Tests
- Deposit limits and enforcement
- Whitelist functionality
- Access control verification
- Burner router governance
- Governance protection mechanisms (31-day delays)

### ⚠️ Edge Case Tests
- Zero amount operations
- Invalid recipients and parameters
- Insufficient balance scenarios
- Premature claims
- Input validation

### ⚔️ Slashing Tests
- Access control (only veto slasher can slash)
- Real slashing scenarios with fund flow
- Multiple slashing events
- Impact on user withdrawals
- Proportional slashing effects
- Veto window timing
- Complete fund flow: vault → burner → governance
- Network and operator onboarding concepts

### 🔗 Integration Tests
- Full deposit→withdraw→claim cycles
- Multi-user complex scenarios
- Ecosystem component integration
- Security protection mechanisms
- Cross-component workflows

## Key Test Features

### 🔐 Security Focus
- **Slashing Protection**: Only authorized slasher can call `onSlash()`
- **Access Control**: All admin functions properly protected
- **Fund Safety**: No unauthorized token drainage possible
- **User Protection**: 31-day governance delays protect unstaking users

### 💸 Slashing Mechanics
- **Immediate Effect**: Slashed funds leave vault immediately
- **Fund Flow**: vault → burner router → Spark Governance  
- **No Transfer Delays**: 31-day delay is for governance protection, not transfers
- **Proportional Impact**: All users affected equally by percentage
- **Share Preservation**: User shares remain, but underlying value decreases

### ⏰ Timing & Delays
- **Epochs**: 2-week periods for withdrawal processing
- **Unstaking**: 28 days (2 epochs) to complete withdrawals
- **Veto Window**: 3 days for potential slashing veto
- **Governance Protection**: 31 days delay for parameter changes

### 🌊 Fund Flows
```
Deposits: User → Vault (SPK) → User (sSPK shares)
Withdrawals: User (sSPK) → Vault → User (withdrawal shares) → User (SPK after delay)
Slashing: Vault → Burner Router → Spark Governance (immediate)
```

## Running Tests

### All Tests
```bash
forge test --summary
```

### Specific Test File
```bash
forge test --match-contract VaultInitializationTest
forge test --match-contract SlashingTest  
forge test --match-contract IntegrationTest
```

### Specific Test Function
```bash
forge test --match-test test_RealSlashingScenario -vv
forge test --match-test test_CompleteSlashingFundFlow -vv
```

## Environment Setup

Requires `MAINNET_RPC_URL` environment variable:

```bash
export MAINNET_RPC_URL="your-mainnet-rpc-endpoint"
```

## Key Addresses (Mainnet)

| Component | Address |
|-----------|---------|
| **sSPK Vault** | `0x0542206DAD09b1b58f29155b4317F9Bf92CD2701` |
| **SPK Token** | `0xc20059e0317DE91738d13af027DfC4a50781b066` |
| **Spark Governance** | `0x3300f198988e4C9C63F75dF86De36421f06af8c4` |
| **Burner Router** | `0xe244C36C8D6831829590c05F49bBb98B11965efb` |
| **Network Delegator** | `0x20ba8C54B62F1F4653289DCdf316d68199158Fb6` |
| **Veto Slasher** | `0xeF4fa9b4529A9e983B18F223A284025f24d2F18B` |

