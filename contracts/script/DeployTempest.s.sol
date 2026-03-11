// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {TempestHook} from "../src/TempestHook.sol";

/// @title DeployTempest — Deploy TempestHook via CREATE2 at a pre-mined address
contract DeployTempest is Script {
    function run() public {
        address poolManager = vm.envAddress("POOL_MANAGER");
        address governance = vm.envAddress("GOVERNANCE");
        bytes32 salt = vm.envBytes32("DEPLOY_SALT");
        uint256 keeperBaseReward = vm.envOr("KEEPER_BASE_REWARD", uint256(0.0005 ether));
        uint256 keeperGasOverhead = vm.envOr("KEEPER_GAS_OVERHEAD", uint256(150_000));
        uint16 keeperPremiumBps = uint16(vm.envOr("KEEPER_PREMIUM_BPS", uint256(5000)));
        uint256 initialFunding = vm.envOr("INITIAL_FUNDING", uint256(1 ether));

        console2.log("=== Deploying TempestHook ===");
        console2.log("Pool Manager:", poolManager);
        console2.log("Governance:", governance);
        console2.log("Salt:");
        console2.logBytes32(salt);

        vm.startBroadcast();

        // Deploy via CREATE2
        TempestHook hook = new TempestHook{salt: salt}(
            IPoolManager(poolManager),
            governance
        );

        console2.log("TempestHook deployed at:", address(hook));

        // Verify hook permissions match address
        Hooks.Permissions memory perms = Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });

        Hooks.validateHookPermissions(IHooks(address(hook)), perms);
        console2.log("Hook permissions validated successfully");

        // Configure keeper reward
        hook.setKeeperReward(keeperBaseReward, keeperGasOverhead, keeperPremiumBps);
        console2.log("Keeper base reward:", keeperBaseReward);
        console2.log("Keeper gas overhead:", keeperGasOverhead);
        console2.log("Keeper premium bps:", keeperPremiumBps);

        // Fund hook for keeper rewards
        if (initialFunding > 0) {
            (bool ok,) = address(hook).call{value: initialFunding}("");
            require(ok, "Funding failed");
            console2.log("Hook funded with:", initialFunding);
        }

        vm.stopBroadcast();

        console2.log("=== Deployment Complete ===");
    }
}
