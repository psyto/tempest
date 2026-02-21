// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FeeCurve} from "../src/libraries/FeeCurve.sol";

contract FeeCurveTest is Test {
    FeeCurve.FeeConfig defaultConfig;

    function setUp() public {
        defaultConfig = FeeCurve.defaultConfig();
    }

    // ─── Default Config ────────────────────────────────────────────────

    function test_defaultConfig_isValid() public view {
        assertTrue(FeeCurve.validate(defaultConfig));
    }

    // ─── getFee at control points ──────────────────────────────────────

    function test_getFee_atFloor() public view {
        uint24 fee = FeeCurve.getFee(defaultConfig, 0);
        assertEq(fee, 5, "Floor fee should be 5 bps");
    }

    function test_getFee_atPoint1() public view {
        uint24 fee = FeeCurve.getFee(defaultConfig, 2000);
        assertEq(fee, 10, "Fee at 2000 bps vol should be 10 bps");
    }

    function test_getFee_atPoint2() public view {
        uint24 fee = FeeCurve.getFee(defaultConfig, 3500);
        assertEq(fee, 30, "Fee at 3500 bps vol should be 30 bps");
    }

    function test_getFee_atPoint3() public view {
        uint24 fee = FeeCurve.getFee(defaultConfig, 5000);
        assertEq(fee, 60, "Fee at 5000 bps vol should be 60 bps");
    }

    function test_getFee_atPoint4() public view {
        uint24 fee = FeeCurve.getFee(defaultConfig, 7500);
        assertEq(fee, 150, "Fee at 7500 bps vol should be 150 bps");
    }

    function test_getFee_atCap() public view {
        uint24 fee = FeeCurve.getFee(defaultConfig, 15000);
        assertEq(fee, 500, "Cap fee should be 500 bps");
    }

    // ─── Interpolation ─────────────────────────────────────────────────

    function test_getFee_interpolation_segment1() public view {
        // Midpoint between (0, 5) and (2000, 10)
        uint24 fee = FeeCurve.getFee(defaultConfig, 1000);
        // Expected: 5 + (10-5) * 1000/2000 = 5 + 2.5 = 7 (truncated)
        assertEq(fee, 7);
    }

    function test_getFee_interpolation_segment2() public view {
        // Midpoint between (2000, 10) and (3500, 30)
        uint24 fee = FeeCurve.getFee(defaultConfig, 2750);
        // Expected: 10 + (30-10) * 750/1500 = 10 + 10 = 20
        assertEq(fee, 20);
    }

    function test_getFee_interpolation_segment3() public view {
        // Midpoint between (3500, 30) and (5000, 60)
        uint24 fee = FeeCurve.getFee(defaultConfig, 4250);
        // Expected: 30 + (60-30) * 750/1500 = 30 + 15 = 45
        assertEq(fee, 45);
    }

    function test_getFee_interpolation_segment4() public view {
        // Midpoint between (5000, 60) and (7500, 150)
        uint24 fee = FeeCurve.getFee(defaultConfig, 6250);
        // Expected: 60 + (150-60) * 1250/2500 = 60 + 45 = 105
        assertEq(fee, 105);
    }

    function test_getFee_interpolation_segment5() public view {
        // Midpoint between (7500, 150) and (15000, 500)
        uint24 fee = FeeCurve.getFee(defaultConfig, 11250);
        // Expected: 150 + (500-150) * 3750/7500 = 150 + 175 = 325
        assertEq(fee, 325);
    }

    // ─── Boundary conditions ───────────────────────────────────────────

    function test_getFee_belowFloor() public view {
        // vol = 0 is exactly at vol0, should return fee0
        uint24 fee = FeeCurve.getFee(defaultConfig, 0);
        assertEq(fee, 5);
    }

    function test_getFee_aboveCap() public view {
        // Way above cap
        uint24 fee = FeeCurve.getFee(defaultConfig, 100000);
        assertEq(fee, 500, "Above cap should return cap fee");
    }

    // ─── Monotonicity ──────────────────────────────────────────────────

    function test_getFee_monotonicallyIncreasing() public view {
        uint24 prevFee = 0;
        for (uint64 vol = 0; vol <= 15000; vol += 100) {
            uint24 fee = FeeCurve.getFee(defaultConfig, vol);
            assertGe(fee, prevFee, "Fee should be monotonically increasing");
            prevFee = fee;
        }
    }

    // ─── Validation ────────────────────────────────────────────────────

    function test_validate_validConfig() public view {
        assertTrue(FeeCurve.validate(defaultConfig));
    }

    function test_validate_invalidConfig_unsorted() public pure {
        FeeCurve.FeeConfig memory config = FeeCurve.FeeConfig({
            vol0: 0,
            fee0: 5,
            vol1: 3500,
            fee1: 10, // Swapped vol1 and vol2
            vol2: 2000,
            fee2: 30,
            vol3: 5000,
            fee3: 60,
            vol4: 7500,
            fee4: 150,
            vol5: 15000,
            fee5: 500
        });
        assertFalse(FeeCurve.validate(config));
    }

    function test_validate_invalidConfig_duplicateVols() public pure {
        FeeCurve.FeeConfig memory config = FeeCurve.FeeConfig({
            vol0: 0,
            fee0: 5,
            vol1: 2000,
            fee1: 10,
            vol2: 2000,
            fee2: 30, // Same as vol1
            vol3: 5000,
            fee3: 60,
            vol4: 7500,
            fee4: 150,
            vol5: 15000,
            fee5: 500
        });
        assertFalse(FeeCurve.validate(config));
    }

    // ─── Custom config ─────────────────────────────────────────────────

    function test_getFee_customConfig() public pure {
        FeeCurve.FeeConfig memory config = FeeCurve.FeeConfig({
            vol0: 0,
            fee0: 1,
            vol1: 1000,
            fee1: 5,
            vol2: 2000,
            fee2: 20,
            vol3: 3000,
            fee3: 50,
            vol4: 5000,
            fee4: 100,
            vol5: 10000,
            fee5: 300
        });

        assertEq(FeeCurve.getFee(config, 0), 1);
        assertEq(FeeCurve.getFee(config, 1000), 5);
        assertEq(FeeCurve.getFee(config, 10000), 300);
        assertEq(FeeCurve.getFee(config, 20000), 300); // Above cap
    }

    // ─── Gas benchmark ─────────────────────────────────────────────────

    function test_getFee_gas() public view {
        uint256 gasStart = gasleft();
        FeeCurve.getFee(defaultConfig, 4000);
        uint256 gasUsed = gasStart - gasleft();
        assertLt(gasUsed, 15000, "getFee should be < 15000 gas");
    }
}
