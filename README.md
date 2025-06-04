# SPK Staking Tests

<!-- ![Foundry CI](https://github.com/{org}/{repo}/actions/workflows/ci.yml/badge.svg)
[![Foundry][foundry-badge]][foundry]
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/{org}/{repo}/blob/master/LICENSE) -->

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

This project contains comprehensive tests for the Symbiotic tokenized vault (sSPK) deployed on Ethereum mainnet.

## Overview

The test suite verifies the functionality of the Spark Protocol's Symbiotic vault deployment:

- **Vault Address**: `0x0542206DAD09b1b58f29155b4317F9Bf92CD2701`
- **SPK Token**: `0xc20059e0317DE91738d13af027DfC4a50781b066`
- **Spark Governance**: `0x3300f198988e4C9C63F75dF86De36421f06af8c4`
- **Burner Router**: `0xe244C36C8D6831829590c05F49bBb98B11965efb`

## Features Tested

### User Functionality
- ✅ **Deposits**: Users can deposit SPK tokens and receive sSPK shares
- ✅ **Withdrawals**: Users can initiate withdrawals (burns sSPK, creates withdrawal claim)
- ✅ **Claims**: Users can claim SPK after the 2-week epoch delay
- ✅ **Batch Claims**: Users can claim multiple epochs in a single transaction

### Admin Functionality
- ✅ **Role Verification**: Spark Governance has all required admin roles
- ✅ **Deposit Limits**: Admin can set and enable deposit limits
- ✅ **Deposit Whitelist**: Admin can enable whitelist and manage depositor permissions
- ✅ **Access Control**: Non-admin users are properly blocked from admin functions

### Integration Tests
- ✅ **Full Lifecycle**: Complete deposit → withdraw → wait → claim cycle
- ✅ **Epoch Management**: Proper epoch transitions and timing
- ✅ **Burner Router**: Configuration and ownership verification
- ✅ **Error Handling**: Proper reverts for invalid operations

## Setup

1. **Install Dependencies**
   ```bash
   forge install
   ```

2. **Set Environment Variables**
   Create a `.env` file with:
   ```bash
   MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY
   ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY  # Optional
   ```

3. **Run Tests**
   ```bash
   # Run all tests
   forge test

   # Run with verbose output
   forge test -vvv

   # Run specific test
   forge test --match-test test_UserDeposit -vvv

   # Run with gas reporting
   forge test --gas-report
   ```

## Test Categories

### Basic Vault Tests
- `test_VaultInitialization()`: Verifies vault configuration matches deployment
- `test_AdminRoles()`: Confirms Spark Governance has all required permissions

### Deposit Tests
- `test_UserDeposit()`: Single user deposit functionality
- `test_MultipleUserDeposits()`: Multiple users depositing simultaneously

### Withdrawal Tests
- `test_UserWithdrawal()`: Withdrawal initiation and share burning
- `test_ClaimAfterEpochDelay()`: Claiming after 2-week epoch delay
- `test_ClaimBatch()`: Batch claiming across multiple epochs

### Admin Tests
- `test_AdminCanSetDepositLimit()`: Admin deposit limit management
- `test_AdminCanSetDepositWhitelist()`: Admin whitelist management
- `test_NonAdminCannotCallAdminFunctions()`: Access control verification

### Integration Tests
- `test_FullDepositWithdrawClaimCycle()`: Complete user journey
- `test_VaultStakeAndSlashableBalance()`: Staking mechanism verification

### Error Condition Tests
- `test_DepositWithInsufficientBalance()`: Insufficient balance handling
- `test_WithdrawMoreThanBalance()`: Over-withdrawal protection
- `test_ClaimBeforeEpochDelay()`: Premature claim prevention

## Key Constants

- **Epoch Duration**: 2 weeks (1,209,600 seconds)
- **Burner Delay**: 31 days (2,678,400 seconds)
- **Slasher Veto Duration**: 3 days

## Symbiotic Protocol Architecture

The vault integrates with several Symbiotic components:

- **Network Restake Delegator**: `0x20ba8c54b62f1f4653289dcdf316d68199158fb6`
- **Veto Slasher**: `0xef4fa9b4529a9e983b18f223a284025f24d2f18b`
- **Burner Router**: Routes slashed tokens to Spark Governance

## Documentation

- [Symbiotic VaultTokenized API](https://docs.symbiotic.fi/contracts-api/core/VaultTokenized)
- [Symbiotic Protocol Overview](https://docs.symbiotic.fi/)

***
*The IP in this repository was assigned to Mars SPC Limited in respect of the MarsOne SP*
