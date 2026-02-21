// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/libraries/StateLibrary.sol";

import {TempestHook} from "../../src/TempestHook.sol";

/// @title TempestTestBase — Shared test setup for Tempest hook tests
/// @dev Deploys PoolManager and TempestHook at a mined address with correct flags
abstract contract TempestTestBase is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager public manager;
    TempestHook public hook;
    address public governance;

    // Hook flags: afterInitialize (bit 12), beforeSwap (bit 7), afterSwap (bit 6)
    uint160 constant HOOK_FLAGS =
        uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

    function setUp() public virtual {
        governance = address(this);

        // Deploy PoolManager
        manager = new PoolManager(address(0));

        // Mine a hook address with the correct flag bits
        // We use vm.etch to deploy at the correct address
        hook = TempestHook(payable(deployHookWithFlags()));

        // Fund hook for keeper rewards
        vm.deal(address(hook), 10 ether);
    }

    function deployHookWithFlags() internal returns (address) {
        // Find an address whose lower 14 bits match our required flags
        // afterInitialize = bit 12 = 0x1000
        // beforeSwap = bit 7 = 0x0080
        // afterSwap = bit 6 = 0x0040
        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        address hookAddr = address(flags);

        // Deploy at the flagged address using deployCodeTo (runs constructor at target address)
        bytes memory constructorArgs = abi.encode(address(manager), governance);
        deployCodeTo("TempestHook.sol:TempestHook", constructorArgs, hookAddr);

        return hookAddr;
    }

    /// @dev Helper to create a pool key with dynamic fee
    function createPoolKey(Currency currency0, Currency currency1) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }

    /// @dev Get the sqrtPriceX96 for tick 0 (price = 1.0)
    function getSqrtPriceAtTick0() internal pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(0);
    }
}
