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
- **Veto Slasher**: `0xef4fa9b4529a9e983b18f223a284025f24d2f18b` 

## Features Tested

- ✅ **User Operations**: Deposits, withdrawals, claims, share transfers
- ✅ **Admin Functions**: Role verification, deposit limits, whitelists, pause/unpause
- ✅ **Security**: Access control, slashing protection, token drainage protection
- ✅ **Slashing Mechanism**: Authorized slashing, fund flows, veto windows, proportional impact
- ✅ **Symbiotic Integration**: Network/operator onboarding with real mainnet contracts
- ✅ **Edge Cases**: Zero amounts, insufficient balance, invalid parameters, boundary conditions
- ✅ **Governance Protection**: Burner delays, veto periods, unstaking protection
- ✅ **Math & Accounting**: Share calculations, epoch tracking, balance reconciliation

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
