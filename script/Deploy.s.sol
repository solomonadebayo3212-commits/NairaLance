// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {FreelanceEscrow} from "../src/FreelanceEscrow.sol";

contract DeployFreelanceEscrow is Script {

    // Sepolia cNGN and USDT token addresses
    // Replace these with real addresses when deploying to mainnet
    address constant CNGN_SEPOLIA = 0x1234567890123456789012345678901234567890;
    address constant USDT_SEPOLIA = 0x1234567890123456789012345678901234567891;

    function run() external returns (FreelanceEscrow) {
        vm.startBroadcast();

        FreelanceEscrow escrow = new FreelanceEscrow(
            CNGN_SEPOLIA,
            USDT_SEPOLIA
        );

        vm.stopBroadcast();

        return escrow;
    }
}
