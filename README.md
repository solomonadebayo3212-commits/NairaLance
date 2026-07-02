# NairaLance — Decentralized Freelance Escrow Platform

Nigeria's First Decentralized Freelance Escrow Platform

---

## Overview

NairaLance is a blockchain-based escrow platform that protects both freelancers and clients.
No middlemen. No banks. Just smart contracts enforcing the rules for everyone.

Platform fee: only 10% total (vs 25% on Upwork/Fiverr)
- Client pays: 6% on top of job amount
- Freelancer pays: 4% deducted from payment

---

## The Problem

For Freelancers:
- Upwork takes 20% of every payment
- Clients ghost after receiving work
- International payments blocked by Nigerian banks

For Clients:
- No guarantee freelancer will deliver
- No refund if work is never submitted
- No transparent dispute process

---

## How It Works

1. Client posts job and deposits any amount of cNGN or USDT plus 6% fee
2. Freelancer accepts the job
3. Freelancer submits work link (any URL: GitHub, Google Drive, Figma, IPFS, etc.)
4. Client approves and payment releases automatically

4 Protection Flows:
- Happy Path: Client approves, freelancer gets paid
- Client Ghosts: Deadline passes, freelancer claims payment automatically
- Freelancer Disappears: Deadline passes, client gets full refund
- Dispute: Arbiter reviews work link and splits payment fairly

---

## Tech Stack

- Solidity 0.8.24
- Foundry (build, test, deploy)
- OpenZeppelin (Ownable, ReentrancyGuard)
- Tokens: cNGN (Nigerian Naira) + USDT (Dollar)
- Network: Ethereum Sepolia Testnet

---

## Contract Architecture

Functions:
- createJob() — Client posts job with any amount of cNGN or USDT
- acceptJob() — Freelancer accepts open job
- submitWork() — Freelancer submits any work link
- approveAndRelease() — Client approves and releases payment
- claimPayment() — Freelancer claims after deadline if client ghosts
- claimRefund() — Client claims refund if freelancer never delivers
- raiseDispute() — Client raises a dispute
- resolveDispute() — Arbiter splits payment between parties
- withdrawFees() — Owner withdraws accumulated platform fees
- updateFees() — Owner updates fee percentages

Security:
- CEI pattern on every ETH/token transfer function
- Custom errors throughout (no revert strings)
- ReentrancyGuard on all transfer functions
- Token whitelist (only cNGN and USDT accepted)
- Fee cap at 15% maximum

---

## How to Install

git clone https://github.com/solomonadebayo3212-commits/NairaLance.git
cd NairaLance
forge build

---

## How to Run Tests

forge test -vvv

Expected: 39 tests passing, 0 failed

---

## How to Deploy

Create .env file:
PRIVATE_KEY=your_private_key
SEPOLIA_RPC_URL=your_sepolia_rpc_url

Deploy:
source .env
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast

---

## Deployed Contract

Network: Ethereum Sepolia Testnet
Contract Address: 0x10f29b499f03a5fb838beC89Da49a5c968ff9547
Etherscan: https://sepolia.etherscan.io/address/0x10f29b499f03a5fb838beC89Da49a5c968ff9547

Token Addresses on Sepolia:
cNGN: 0xA1A8892a746685FD8ae09FdCfAdce89fF6FB7234
USDT: 0x7169D38820dfd117C3FA1f22a697dBA58d90BA06

---

## Test Coverage

39 tests total:
- 15 happy path tests
- 23 revert tests
- 1 extra IPFS link test

All 39 passing with forge test -vvv

---

## Fee Math

Job Amount: 100,000 cNGN
Client deposits: 106,000 cNGN (job + 6%)
Freelancer receives: 96,000 cNGN (job minus 4%)
Platform earns: 10,000 cNGN (10% total)

---

## Known Limitations

- Arbiter (platform owner) has central control over disputes
- No privacy — all jobs and amounts visible on-chain
- cNGN and USDT only — no other tokens
- No frontend yet (coming soon)

---

## Future Improvements

- Frontend with React and ethers.js
- More token support
- Reputation system for freelancers
- On-chain ratings after job completion
- Mobile app

---

## Author

Built by Solomon Abodunrin Adebayo
Nigeria's First Decentralized Freelance Escrow Platform
Blockchain Dev Bootcamp Solo Project
