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

import {TempestHook} from "../src/TempestHook.sol";
import {VolatilityEngine} from "../src/libraries/VolatilityEngine.sol";
import {FeeCurve} from "../src/libraries/FeeCurve.sol";
import {TempestTestBase} from "./utils/TempestTestBase.sol";

contract TempestHookTest is TempestTestBase {
    using PoolIdLibrary for PoolKey;

    // ─── Deployment ────────────────────────────────────────────────────

    function test_hookDeployedWithCorrectFlags() public view {
        uint160 addr = uint160(address(hook));
        assertTrue(addr & uint160(Hooks.AFTER_INITIALIZE_FLAG) != 0, "afterInitialize flag");
        assertTrue(addr & uint160(Hooks.BEFORE_SWAP_FLAG) != 0, "beforeSwap flag");
        assertTrue(addr & uint160(Hooks.AFTER_SWAP_FLAG) != 0, "afterSwap flag");
    }

    function test_governance() public view {
        assertEq(hook.governance(), governance);
    }

    function test_keeperReward() public view {
        assertEq(hook.keeperReward(), 0.001 ether);
    }

    function test_minUpdateInterval() public view {
        assertEq(hook.minUpdateInterval(), 300);
    }

    // ─── Governance Functions ──────────────────────────────────────────

    function test_setKeeperReward() public {
        hook.setKeeperReward(0.01 ether);
        assertEq(hook.keeperReward(), 0.01 ether);
    }

    function test_setKeeperReward_onlyGovernance() public {
        vm.prank(address(0xdead));
        vm.expectRevert(TempestHook.OnlyGovernance.selector);
        hook.setKeeperReward(0.01 ether);
    }

    function test_setMinUpdateInterval() public {
        hook.setMinUpdateInterval(600);
        assertEq(hook.minUpdateInterval(), 600);
    }

    function test_transferGovernance() public {
        address newGov = address(0xbeef);
        hook.transferGovernance(newGov);
        assertEq(hook.governance(), newGov);
    }

    function test_transferGovernance_onlyGovernance() public {
        vm.prank(address(0xdead));
        vm.expectRevert(TempestHook.OnlyGovernance.selector);
        hook.transferGovernance(address(0xbeef));
    }

    // ─── View Functions (before pool init) ─────────────────────────────

    function test_getVolatility_uninitializedPool_reverts() public {
        PoolId fakeId = PoolId.wrap(bytes32(uint256(0x1234)));
        vm.expectRevert(TempestHook.PoolNotInitialized.selector);
        hook.getVolatility(fakeId);
    }

    function test_getCurrentFee_uninitializedPool_reverts() public {
        PoolId fakeId = PoolId.wrap(bytes32(uint256(0x1234)));
        vm.expectRevert(TempestHook.PoolNotInitialized.selector);
        hook.getCurrentFee(fakeId);
    }

    function test_updateVolatility_uninitializedPool_reverts() public {
        PoolId fakeId = PoolId.wrap(bytes32(uint256(0x1234)));
        vm.expectRevert(TempestHook.PoolNotInitialized.selector);
        hook.updateVolatility(fakeId);
    }

    // ─── Receive ETH ───────────────────────────────────────────────────

    function test_receiveETH() public {
        uint256 balBefore = address(hook).balance;
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(hook).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(hook).balance, balBefore + 1 ether);
    }
}
