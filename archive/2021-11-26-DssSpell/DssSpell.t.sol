// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.6.12;

import "./DssSpell.t.base.sol";

contract DssSpellTest is DssSpellTestBase {

    address constant SAS_WALLET     = 0xb1f950a51516a697E103aaa69E152d839182f6Fe;
    address constant IS_WALLET      = 0xd1F2eEf8576736C1EbA36920B957cd2aF07280F4;
    address constant DECO_WALLET    = 0xF482D1031E5b172D42B2DAA1b6e5Cbf6519596f7;
    address constant RWF_WALLET     = 0x9e1585d9CA64243CE43D42f7dD7333190F66Ca09;
    address constant COM_WALLET     = 0x1eE3ECa7aEF17D1e74eD7C447CcBA61aC76aDbA9;
    address constant MKT_WALLET     = 0xDCAF2C84e1154c8DdD3203880e5db965bfF09B60;

    uint256 constant DEC_01_2021    = 1638316800;
    uint256 constant DEC_31_2021    = 1640908800;
    uint256 constant JAN_01_2022    = 1640995200;
    uint256 constant APR_30_2022    = 1651276800;
    uint256 constant JUN_30_2022    = 1656547200;
    uint256 constant AUG_01_2022    = 1659312000;
    uint256 constant NOV_30_2022    = 1669766400;
    uint256 constant DEC_31_2022    = 1672444800;
    uint256 constant SEP_01_2024    = 1725148800;

    function testSpellIsCast_GENERAL() public {
        string memory description = new DssSpell().description();
        assertTrue(bytes(description).length > 0, "TestError/spell-description-length");
        // DS-Test can't handle strings directly, so cast to a bytes32.
        assertEq(stringToBytes32(spell.description()),
                stringToBytes32(description), "TestError/spell-description");

        if(address(spell) != address(spellValues.deployed_spell)) {
            assertEq(spell.expiration(), block.timestamp + spellValues.expiration_threshold, "TestError/spell-expiration");
        } else {
            assertEq(spell.expiration(), spellValues.deployed_spell_created + spellValues.expiration_threshold, "TestError/spell-expiration");

            // If the spell is deployed compare the on-chain bytecode size with the generated bytecode size.
            // extcodehash doesn't match, potentially because it's address-specific, avenue for further research.
            address depl_spell = spellValues.deployed_spell;
            address code_spell = address(new DssSpell());
            assertEq(getExtcodesize(depl_spell), getExtcodesize(code_spell), "TestError/spell-codesize");
        }

        assertTrue(spell.officeHours() == spellValues.office_hours_enabled, "TestError/spell-office-hours");

        vote(address(spell));
        scheduleWaitAndCast(address(spell));
        assertTrue(spell.done(), "TestError/spell-not-done");

        checkSystemValues(afterSpell);

        checkCollateralValues(afterSpell);
    }

    function giveTokensGUSD(DSTokenAbstract token, uint256 amount) internal {
        // Special exception GUSD has its storage in a separate contract
        address STORE = 0xc42B14e49744538e3C239f8ae48A1Eaaf35e68a0;

        // Edge case - balance is already set for some reason
        if (token.balanceOf(address(this)) == amount) return;

        for (uint256 i = 0; i < 200; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                STORE,
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                STORE,
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (token.balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    STORE,
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false, "TestError/GiveTokens-slot-not-found");
    }

    function checkPsmIlkIntegrationGUSD(
        bytes32 _ilk,
        GemJoinAbstract join,
        ClipAbstract clip,
        address pip,
        PsmAbstract psm,
        uint256 tin,
        uint256 tout
    ) public {
        DSTokenAbstract token = DSTokenAbstract(join.gem());

        assertTrue(pip != address(0));

        spotter.poke(_ilk);

        // Authorization
        assertEq(join.wards(pauseProxy), 1);
        assertEq(join.wards(address(psm)), 1);
        assertEq(psm.wards(pauseProxy), 1);
        assertEq(vat.wards(address(join)), 1);
        assertEq(clip.wards(address(end)), 1);

        // Check toll in/out
        assertEq(psm.tin(), tin);
        assertEq(psm.tout(), tout);

        uint256 amount = 1000 * (10 ** token.decimals());
        giveTokensGUSD(token, amount);

        // Approvals
        token.approve(address(join), amount);
        dai.approve(address(psm), uint256(-1));

        // Convert all TOKEN to DAI
        psm.sellGem(address(this), amount);
        amount -= amount * tin / WAD;
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), amount * (10 ** (18 - token.decimals())));

        // Convert all DAI to TOKEN
        amount -= amount * tout / WAD;
        psm.buyGem(address(this), amount);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(this)), amount);

        // Dump all dai for next run
        vat.move(address(this), address(0x0), vat.dai(address(this)));
    }

    function testCollateralIntegrations() public {
        vote(address(spell));
        scheduleWaitAndCast(address(spell));
        assertTrue(spell.done());

        // Insert new collateral tests here
        checkIlkIntegration(
            "WBTC-C",
            GemJoinAbstract(addr.addr("MCD_JOIN_WBTC_C")),
            ClipAbstract(addr.addr("MCD_CLIP_WBTC_C")),
            addr.addr("PIP_WBTC"),
            true,
            true,
            false
        );
        checkPsmIlkIntegrationGUSD(
            "PSM-GUSD-A",
            GemJoinAbstract(addr.addr("MCD_JOIN_PSM_GUSD_A")),
            ClipAbstract(addr.addr("MCD_CLIP_PSM_GUSD_A")),
            addr.addr("PIP_GUSD"),
            PsmAbstract(addr.addr("MCD_PSM_GUSD_A")),
            0,
            0
        );
    }

    function testLerpSurplusBuffer() public {
        vote(address(spell));
        scheduleWaitAndCast(address(spell));
        assertTrue(spell.done());

        LerpAbstract lerp = LerpAbstract(lerpFactory.lerps("Increase SB - 20211126"));

        uint256 duration = 210 days;
        hevm.warp(block.timestamp + duration / 2);
        assertEq(vow.hump(), 60 * MILLION * RAD);
        lerp.tick();
        assertEq(vow.hump(), 75 * MILLION * RAD);
        hevm.warp(block.timestamp + duration / 2);
        lerp.tick();
        assertEq(vow.hump(), 90 * MILLION * RAD);
        assertTrue(lerp.done());
    }

    function testNewChainlogValues() public {
        vote(address(spell));
        scheduleWaitAndCast(address(spell));
        assertTrue(spell.done());

        // Insert new chainlog values tests here
        assertEq(chainLog.getAddress("MCD_JOIN_WBTC_C"), addr.addr("MCD_JOIN_WBTC_C"));
        assertEq(chainLog.getAddress("MCD_CLIP_WBTC_C"), addr.addr("MCD_CLIP_WBTC_C"));
        assertEq(chainLog.getAddress("MCD_CLIP_CALC_WBTC_C"), addr.addr("MCD_CLIP_CALC_WBTC_C"));

        assertEq(chainLog.getAddress("MCD_JOIN_PSM_GUSD_A"), addr.addr("MCD_JOIN_PSM_GUSD_A"));
        assertEq(chainLog.getAddress("MCD_CLIP_PSM_GUSD_A"), addr.addr("MCD_CLIP_PSM_GUSD_A"));
        assertEq(chainLog.getAddress("MCD_CLIP_CALC_PSM_GUSD_A"), addr.addr("MCD_CLIP_CALC_PSM_GUSD_A"));
        assertEq(chainLog.getAddress("MCD_PSM_GUSD_A"), addr.addr("MCD_PSM_GUSD_A"));

        assertEq(chainLog.version(), "1.9.11");
    }

    function testNewIlkRegistryValues() public {
        vote(address(spell));
        scheduleWaitAndCast(address(spell));
        assertTrue(spell.done());

        // Insert new ilk registry values tests here
        assertEq(reg.pos("WBTC-C"), 45);
        assertEq(reg.join("WBTC-C"), addr.addr("MCD_JOIN_WBTC_C"));
        assertEq(reg.gem("WBTC-C"), addr.addr("WBTC"));
        assertEq(reg.dec("WBTC-C"), DSTokenAbstract(addr.addr("WBTC")).decimals());
        assertEq(reg.class("WBTC-C"), 1);
        assertEq(reg.pip("WBTC-C"), addr.addr("PIP_WBTC"));
        assertEq(reg.xlip("WBTC-C"), addr.addr("MCD_CLIP_WBTC_C"));
        assertEq(reg.name("WBTC-C"), "Wrapped BTC");
        assertEq(reg.symbol("WBTC-C"), "WBTC");

        assertEq(reg.pos("PSM-GUSD-A"), 46);
        assertEq(reg.join("PSM-GUSD-A"), addr.addr("MCD_JOIN_PSM_GUSD_A"));
        assertEq(reg.gem("PSM-GUSD-A"), addr.addr("GUSD"));
        assertEq(reg.dec("PSM-GUSD-A"), DSTokenAbstract(addr.addr("GUSD")).decimals());
        assertEq(reg.class("PSM-GUSD-A"), 1);
        assertEq(reg.pip("PSM-GUSD-A"), addr.addr("PIP_GUSD"));
        assertEq(reg.xlip("PSM-GUSD-A"), addr.addr("MCD_CLIP_PSM_GUSD_A"));
        assertEq(reg.name("PSM-GUSD-A"), "Gemini dollar");
        assertEq(reg.symbol("PSM-GUSD-A"), "GUSD");
    }

    function testDaiVests() public {
        uint256 lastId = vestDai.ids();

        vote(address(spell));
        scheduleWaitAndCast(address(spell));
        assertTrue(spell.done());

        // General sanity checks
        // Confirm all new dai vests are under the upper limit of 2M / year
        // Manually specify special exceptions
        for(uint256 i = lastId + 1; i <= vestDai.ids(); i++) {
            assertTrue(vestDai.usr(i) != address(0));
            assertGt(vestDai.bgn(i), block.timestamp - 90 days);       // Start time is above ~3 months ago
            assertEq(vestDai.clf(i), vestDai.bgn(i));
            assertEq(vestDai.mgr(i), address(0));
            assertEq(vestDai.res(i), 1);
            assertEq(vestDai.rxd(i), 0);

            uint256 rate = vestDai.tot(i) / (vestDai.fin(i) - vestDai.bgn(i));       // DAI / sec
            assertLt(rate, 2_000_000 * WAD / 365 days);
        }

        // Verify individual payments
        checkDaiVest(++lastId, RWF_WALLET, JAN_01_2022, DEC_31_2022, 1_860_000);
        checkDaiVest(++lastId, COM_WALLET, DEC_01_2021, DEC_31_2021, 12_242);
        checkDaiVest(++lastId, COM_WALLET, JAN_01_2022, JUN_30_2022, 257_500);
        checkDaiVest(++lastId, SAS_WALLET, DEC_01_2021, NOV_30_2022, 1_130_393);
        checkDaiVest(++lastId, IS_WALLET, DEC_01_2021, AUG_01_2022, 366_563);
        checkDaiVest(++lastId, MKT_WALLET, DEC_01_2021, APR_30_2022, 424_944);
        checkDaiVest(++lastId, DECO_WALLET, DEC_01_2021, SEP_01_2024, 5_121_875);
    }

    function testOneTimePaymentDistributions() public {
        uint256 prevSin      = vat.sin(address(vow));
        uint256 prevDaiSas   = dai.balanceOf(SAS_WALLET);
        uint256 prevDaiIs    = dai.balanceOf(IS_WALLET);
        uint256 prevDaiDeco  = dai.balanceOf(DECO_WALLET);

        uint256 amountSas    = 245_738;
        uint256 amountIs     = 195_443;
        uint256 amountDeco   = 465_625;
        uint256 amountTotal  = amountSas + amountIs + amountDeco;

        assertEq(vat.can(address(pauseProxy), address(daiJoin)), 1);

        vote(address(spell));
        spell.schedule();
        hevm.warp(spell.nextCastTime());
        spell.cast();
        assertTrue(spell.done());

        assertEq(vat.can(address(pauseProxy), address(daiJoin)), 1);

        assertEq(vat.sin(address(vow)) - prevSin, amountTotal * RAD);
        assertEq(dai.balanceOf(SAS_WALLET) - prevDaiSas, amountSas * WAD);
        assertEq(dai.balanceOf(IS_WALLET) - prevDaiIs, amountIs * WAD);
        assertEq(dai.balanceOf(DECO_WALLET) - prevDaiDeco, amountDeco * WAD);
    }


    function testFailWrongDay() public {
        require(spell.officeHours() == spellValues.office_hours_enabled);
        if (spell.officeHours()) {
            vote(address(spell));
            scheduleWaitAndCastFailDay();
        } else {
            revert("Office Hours Disabled");
        }
    }

    function testFailTooEarly() public {
        require(spell.officeHours() == spellValues.office_hours_enabled);
        if (spell.officeHours()) {
            vote(address(spell));
            scheduleWaitAndCastFailEarly();
        } else {
            revert("Office Hours Disabled");
        }
    }

    function testFailTooLate() public {
        require(spell.officeHours() == spellValues.office_hours_enabled);
        if (spell.officeHours()) {
            vote(address(spell));
            scheduleWaitAndCastFailLate();
        } else {
            revert("Office Hours Disabled");
        }
    }

    function testOnTime() public {
        vote(address(spell));
        scheduleWaitAndCast(address(spell));
    }

    function testCastCost() public {
        vote(address(spell));
        spell.schedule();

        castPreviousSpell();
        hevm.warp(spell.nextCastTime());
        uint256 startGas = gasleft();
        spell.cast();
        uint256 endGas = gasleft();
        uint256 totalGas = startGas - endGas;

        assertTrue(spell.done());
        // Fail if cast is too expensive
        assertTrue(totalGas <= 10 * MILLION);
    }

    function test_nextCastTime() public {
        hevm.warp(1606161600); // Nov 23, 20 UTC (could be cast Nov 26)

        vote(address(spell));
        spell.schedule();

        uint256 monday_1400_UTC = 1606744800; // Nov 30, 2020
        uint256 monday_2100_UTC = 1606770000; // Nov 30, 2020

        // Day tests
        hevm.warp(monday_1400_UTC);                                    // Monday,   14:00 UTC
        assertEq(spell.nextCastTime(), monday_1400_UTC);               // Monday,   14:00 UTC

        if (spell.officeHours()) {
            hevm.warp(monday_1400_UTC - 1 days);                       // Sunday,   14:00 UTC
            assertEq(spell.nextCastTime(), monday_1400_UTC);           // Monday,   14:00 UTC

            hevm.warp(monday_1400_UTC - 2 days);                       // Saturday, 14:00 UTC
            assertEq(spell.nextCastTime(), monday_1400_UTC);           // Monday,   14:00 UTC

            hevm.warp(monday_1400_UTC - 3 days);                       // Friday,   14:00 UTC
            assertEq(spell.nextCastTime(), monday_1400_UTC - 3 days);  // Able to cast

            hevm.warp(monday_2100_UTC);                                // Monday,   21:00 UTC
            assertEq(spell.nextCastTime(), monday_1400_UTC + 1 days);  // Tuesday,  14:00 UTC

            hevm.warp(monday_2100_UTC - 1 days);                       // Sunday,   21:00 UTC
            assertEq(spell.nextCastTime(), monday_1400_UTC);           // Monday,   14:00 UTC

            hevm.warp(monday_2100_UTC - 2 days);                       // Saturday, 21:00 UTC
            assertEq(spell.nextCastTime(), monday_1400_UTC);           // Monday,   14:00 UTC

            hevm.warp(monday_2100_UTC - 3 days);                       // Friday,   21:00 UTC
            assertEq(spell.nextCastTime(), monday_1400_UTC);           // Monday,   14:00 UTC

            // Time tests
            uint256 castTime;

            for(uint256 i = 0; i < 5; i++) {
                castTime = monday_1400_UTC + i * 1 days; // Next day at 14:00 UTC
                hevm.warp(castTime - 1 seconds); // 13:59:59 UTC
                assertEq(spell.nextCastTime(), castTime);

                hevm.warp(castTime + 7 hours + 1 seconds); // 21:00:01 UTC
                if (i < 4) {
                    assertEq(spell.nextCastTime(), monday_1400_UTC + (i + 1) * 1 days); // Next day at 14:00 UTC
                } else {
                    assertEq(spell.nextCastTime(), monday_1400_UTC + 7 days); // Next monday at 14:00 UTC (friday case)
                }
            }
        }
    }

    function testFail_notScheduled() public view {
        spell.nextCastTime();
    }

    function test_use_eta() public {
        hevm.warp(1606161600); // Nov 23, 20 UTC (could be cast Nov 26)

        vote(address(spell));
        spell.schedule();

        uint256 castTime = spell.nextCastTime();
        assertEq(castTime, spell.eta());
    }

    // function test_OSMs() public {
    //     vote(address(spell));
    //     spell.schedule();
    //     hevm.warp(spell.nextCastTime());
    //     spell.cast();
    //     assertTrue(spell.done());

    //     // Track OSM authorizations here

    //     address YEARN_PROXY = 0x208EfCD7aad0b5DD49438E0b6A0f38E951A50E5f;
    //     assertEq(OsmAbstract(addr.addr("PIP_YFI")).bud(YEARN_PROXY), 1);

    //     // Gnosis
    //     address GNOSIS = 0xD5885fbCb9a8a8244746010a3BC6F1C6e0269777;
    //     assertEq(OsmAbstract(addr.addr("PIP_WBTC")).bud(GNOSIS), 1);
    //     assertEq(OsmAbstract(addr.addr("PIP_LINK")).bud(GNOSIS), 1);
    //     assertEq(OsmAbstract(addr.addr("PIP_COMP")).bud(GNOSIS), 1);
    //     assertEq(OsmAbstract(addr.addr("PIP_YFI")).bud(GNOSIS), 1);
    //     assertEq(OsmAbstract(addr.addr("PIP_ZRX")).bud(GNOSIS), 1);

    //     // Instadapp
    //     address INSTADAPP = 0xDF3CDd10e646e4155723a3bC5b1191741DD90333;
    //     assertEq(OsmAbstract(addr.addr("PIP_ETH")).bud(INSTADAPP), 1);
    // }

    // function test_Medianizers() public {
    //     vote(address(spell));
    //     spell.schedule();
    //     hevm.warp(spell.nextCastTime());
    //     spell.cast();
    //     assertTrue(spell.done());

    //     // Track Median authorizations here

    //     address SET_AAVE    = 0x8b1C079f8192706532cC0Bf0C02dcC4fF40d045D;
    //     address AAVEUSD_MED = OsmAbstract(addr.addr("PIP_AAVE")).src();
    //     assertEq(MedianAbstract(AAVEUSD_MED).bud(SET_AAVE), 1);

    //     address SET_LRC     = 0x1D5d9a2DDa0843eD9D8a9Bddc33F1fca9f9C64a0;
    //     address LRCUSD_MED  = OsmAbstract(addr.addr("PIP_LRC")).src();
    //     assertEq(MedianAbstract(LRCUSD_MED).bud(SET_LRC), 1);

    //     address SET_YFI     = 0x1686d01Bd776a1C2A3cCF1579647cA6D39dd2465;
    //     address YFIUSD_MED  = OsmAbstract(addr.addr("PIP_YFI")).src();
    //     assertEq(MedianAbstract(YFIUSD_MED).bud(SET_YFI), 1);

    //     address SET_ZRX     = 0xFF60D1650696238F81BE53D23b3F91bfAAad938f;
    //     address ZRXUSD_MED  = OsmAbstract(addr.addr("PIP_ZRX")).src();
    //     assertEq(MedianAbstract(ZRXUSD_MED).bud(SET_ZRX), 1);

    //     address SET_UNI     = 0x3c3Afa479d8C95CF0E1dF70449Bb5A14A3b7Af67;
    //     address UNIUSD_MED  = OsmAbstract(addr.addr("PIP_UNI")).src();
    //     assertEq(MedianAbstract(UNIUSD_MED).bud(SET_UNI), 1);
    // }

    function test_auth() public {
        checkAuth(false);
    }

    function test_auth_in_sources() public {
        checkAuth(true);
    }

    // Verifies that the bytecode of the action of the spell used for testing
    // matches what we'd expect.
    //
    // Not a complete replacement for Etherscan verification, unfortunately.
    // This is because the DssSpell bytecode is non-deterministic because it
    // deploys the action in its constructor and incorporates the action
    // address as an immutable variable--but the action address depends on the
    // address of the DssSpell which depends on the address+nonce of the
    // deploying address. If we had a way to simulate a contract creation by
    // an arbitrary address+nonce, we could verify the bytecode of the DssSpell
    // instead.
    //
    // Vacuous until the deployed_spell value is non-zero.
    function test_bytecode_matches() public {
        address expectedAction = (new DssSpell()).action();
        address actualAction   = spell.action();
        uint256 expectedBytecodeSize;
        uint256 actualBytecodeSize;
        assembly {
            expectedBytecodeSize := extcodesize(expectedAction)
            actualBytecodeSize   := extcodesize(actualAction)
        }

        uint256 metadataLength = getBytecodeMetadataLength(expectedAction);
        assertTrue(metadataLength <= expectedBytecodeSize);
        expectedBytecodeSize -= metadataLength;

        metadataLength = getBytecodeMetadataLength(actualAction);
        assertTrue(metadataLength <= actualBytecodeSize);
        actualBytecodeSize -= metadataLength;

        assertEq(actualBytecodeSize, expectedBytecodeSize);
        uint256 size = actualBytecodeSize;
        uint256 expectedHash;
        uint256 actualHash;
        assembly {
            let ptr := mload(0x40)

            extcodecopy(expectedAction, ptr, 0, size)
            expectedHash := keccak256(ptr, size)

            extcodecopy(actualAction, ptr, 0, size)
            actualHash := keccak256(ptr, size)
        }
        assertEq(expectedHash, actualHash);
    }
}