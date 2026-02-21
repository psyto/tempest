// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {TempestHook} from "../src/TempestHook.sol";

/// @title MineAddress — Brute-force a CREATE2 salt for TempestHook
/// @notice The hook address must have specific bits set to match hook permissions:
///         - Bit 12: AFTER_INITIALIZE_FLAG (0x1000)
///         - Bit 7:  BEFORE_SWAP_FLAG (0x0080)
///         - Bit 6:  AFTER_SWAP_FLAG (0x0040)
///         Required flags mask: 0x10C0
contract MineAddress is Script {
    // Required hook permission flags
    uint160 constant FLAGS = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

    function run() public {
        address deployer = vm.envAddress("DEPLOYER");
        address poolManager = vm.envAddress("POOL_MANAGER");
        address governance = vm.envAddress("GOVERNANCE");

        bytes memory creationCode = abi.encodePacked(
            type(TempestHook).creationCode, abi.encode(poolManager, governance)
        );
        bytes32 initCodeHash = keccak256(creationCode);

        console2.log("Mining CREATE2 address for TempestHook...");
        console2.log("Deployer:", deployer);
        console2.log("Required flags (hex):", uint256(FLAGS));
        console2.log("Init code hash:");
        console2.logBytes32(initCodeHash);

        uint256 maxAttempts = vm.envOr("MAX_ATTEMPTS", uint256(1_000_000));

        for (uint256 salt = 0; salt < maxAttempts; salt++) {
            address predicted = computeCreate2Address(deployer, bytes32(salt), initCodeHash);

            if (uint160(predicted) & FLAGS == FLAGS) {
                // Also verify no unexpected flags are set (optional strictness)
                // For now, just ensure required flags are present
                console2.log("=== FOUND ===");
                console2.log("Salt:", salt);
                console2.log("Salt (hex):");
                console2.logBytes32(bytes32(salt));
                console2.log("Address:", predicted);
                console2.log("Attempts:", salt + 1);
                return;
            }

            if (salt % 100_000 == 0 && salt > 0) {
                console2.log("Checked", salt, "salts...");
            }
        }

        console2.log("No valid salt found in", maxAttempts, "attempts");
    }

    function computeCreate2Address(address deployer, bytes32 salt, bytes32 initCodeHash)
        internal
        pure
        returns (address)
    {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
    }
}
