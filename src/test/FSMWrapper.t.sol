pragma solidity 0.6.7;

import "ds-test/test.sol";
import {DSValue} from "ds-value/value.sol";
import {DSToken} from "ds-token/token.sol";

import {DSM} from "../DSM.sol";
import {OSM} from "../OSM.sol";
import {FSMWrapper} from "../FSMWrapper.sol";

import {MockTreasury} from "./mock/MockTreasury.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract FSMWrapperTest is DSTest {
    Hevm hevm;

    DSValue feed;

    OSM osm;
    DSM dsm;

    DSToken coin;

    FSMWrapper wrapper;

    MockTreasury treasury;

    uint256 baseUpdateCallerReward        = 5 ether;
    uint256 maxUpdateCallerReward         = 10 ether;
    uint256 initTokenAmount               = 100000000 ether;
    uint256 perSecondCallerRewardIncrease = 1000192559420674483977255848; // 100% over one hour
    uint256 maxRewardIncreaseDelay        = 6 hours;
    uint256 reimburseDelay                = 3600;

    uint WAD = 10 ** 18;

    function setUp() public {
        // Create the main feed
        feed = new DSValue();
        feed.updateResult(uint(100 ether));

        // Create the OSM, DSM and HEVM contracts
        osm = new OSM(address(feed));
        dsm = new DSM(address(feed), 1);
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(uint(dsm.updateDelay()));

        // Update results for the OSM/DSM
        osm.updateResult();
        dsm.updateResult();

        wrapper = new FSMWrapper(address(osm), reimburseDelay);

        // Create the coin and the treasury
        coin = new DSToken("RAI", "RAI");
        treasury = new MockTreasury(address(coin));
        coin.mint(address(treasury), initTokenAmount);

        // Setup treasury allowance
        treasury.setTotalAllowance(address(wrapper), uint(-1));
        treasury.setPerBlockAllowance(address(wrapper), uint(-1));

        // Set the remaining params
        wrapper.modifyParameters("treasury", address(treasury));
        wrapper.modifyParameters("maxUpdateCallerReward", maxUpdateCallerReward);
        wrapper.modifyParameters("baseUpdateCallerReward", baseUpdateCallerReward);
        wrapper.modifyParameters("perSecondCallerRewardIncrease", perSecondCallerRewardIncrease);
        wrapper.modifyParameters("maxRewardIncreaseDelay", maxRewardIncreaseDelay);
    }

    function test_setup() public {
        assertEq(address(wrapper.fsm()), address(osm));
        assertEq(address(wrapper.treasury()), address(treasury));

        assertEq(wrapper.reimburseDelay(), reimburseDelay);
        assertEq(wrapper.maxUpdateCallerReward(), maxUpdateCallerReward);
        assertEq(wrapper.baseUpdateCallerReward(), baseUpdateCallerReward);
        assertEq(wrapper.perSecondCallerRewardIncrease(), perSecondCallerRewardIncrease);
        assertEq(wrapper.maxRewardIncreaseDelay(), maxRewardIncreaseDelay);
    }
    function test_modifyParameters() public {
        MockTreasury newTreasury = new MockTreasury(address(coin));

        // Modify
        wrapper.modifyParameters("fsm", address(0x2));
        wrapper.modifyParameters("treasury", address(newTreasury));

        wrapper.modifyParameters("maxUpdateCallerReward", maxUpdateCallerReward + 10);
        wrapper.modifyParameters("baseUpdateCallerReward", baseUpdateCallerReward + 10);
        wrapper.modifyParameters("perSecondCallerRewardIncrease", perSecondCallerRewardIncrease + 5);
        wrapper.modifyParameters("maxRewardIncreaseDelay", maxRewardIncreaseDelay + 20);
        wrapper.modifyParameters("reimburseDelay", reimburseDelay + 1 hours);

        // Checks
        assertEq(address(wrapper.fsm()), address(0x2));
        assertEq(address(wrapper.treasury()), address(newTreasury));

        assertEq(wrapper.reimburseDelay(), reimburseDelay + 1 hours);
        assertEq(wrapper.maxUpdateCallerReward(), maxUpdateCallerReward + 10);
        assertEq(wrapper.baseUpdateCallerReward(), baseUpdateCallerReward + 10);
        assertEq(wrapper.perSecondCallerRewardIncrease(), perSecondCallerRewardIncrease + 5);
        assertEq(wrapper.maxRewardIncreaseDelay(), maxRewardIncreaseDelay + 20);
    }
    function test_stopped() public {
        osm.stop();
        assertEq(wrapper.stopped(), 1);
        wrapper.modifyParameters("fsm", address(dsm));
        dsm.stop();
        assertEq(wrapper.stopped(), 1);
    }
    function test_priceSource() public {
        assertEq(wrapper.priceSource(), address(feed));
        wrapper.modifyParameters("fsm", address(dsm));
        assertEq(wrapper.priceSource(), address(feed));
    }
    function test_updateDelay() public {
        assertEq(uint(wrapper.updateDelay()), 1 hours);
        wrapper.modifyParameters("fsm", address(dsm));
        assertEq(uint(wrapper.updateDelay()), 1 hours);
    }
    function test_lastUpdateTime() public {
        assertEq(uint(wrapper.lastUpdateTime()), 1 hours);
        wrapper.modifyParameters("fsm", address(dsm));
        assertEq(uint(wrapper.lastUpdateTime()), 1 hours);
    }
    function test_newPriceDeviation() public {
        wrapper.modifyParameters("fsm", address(dsm));
        assertEq(uint(wrapper.newPriceDeviation()), 1);
    }
    function test_passedDelay() public {
        hevm.warp(now + 1 hours);

        assertTrue(wrapper.passedDelay());
        wrapper.modifyParameters("fsm", address(dsm));
        assertTrue(wrapper.passedDelay());
    }
    function test_getNextBoundedPrice() public {
        wrapper.modifyParameters("fsm", address(dsm));
        assertEq(uint(wrapper.getNextBoundedPrice()), 100 ether);
    }
    function test_getNextPriceLowerBound() public {
        wrapper.modifyParameters("fsm", address(dsm));
        assertEq(uint(wrapper.getNextPriceLowerBound()), 100);
    }
    function test_getNextPriceUpperBound() public {
        wrapper.modifyParameters("fsm", address(dsm));
        assertEq(uint(wrapper.getNextPriceUpperBound()), 199999999999999999900);
    }
    function test_getResultWithValidity() public {
        (uint256 price, bool valid) = wrapper.getResultWithValidity();
        assertEq(price, 100 ether);
        assertTrue(valid);

        wrapper.modifyParameters("fsm", address(dsm));

        (price, valid) = wrapper.getResultWithValidity();
        assertEq(price, 100 ether);
        assertTrue(valid);
    }
    function test_getNextResultWithValidity() public {
        (uint256 price, bool valid) = wrapper.getNextResultWithValidity();
        assertEq(price, 100 ether);
        assertTrue(valid);

        wrapper.modifyParameters("fsm", address(dsm));

        (price, valid) = wrapper.getNextResultWithValidity();
        assertEq(price, 100 ether);
        assertTrue(valid);
    }
    function test_read() public {
        assertEq(wrapper.read(), 100 ether);
        wrapper.modifyParameters("fsm", address(dsm));
        assertEq(wrapper.read(), 100 ether);
    }
    function test_renumerate() public {
        wrapper.modifyParameters("fsm", address(this));

        wrapper.renumerateCaller(address(0x1));
        assertEq(coin.balanceOf(address(0x1)), baseUpdateCallerReward);

        hevm.warp(now + wrapper.reimburseDelay());

        wrapper.renumerateCaller(address(0x1));
        assertEq(coin.balanceOf(address(0x1)), baseUpdateCallerReward * 2);
    }
    function test_renumerate_large_reimburseDelay() public {
        wrapper.modifyParameters("fsm", address(this));
        wrapper.modifyParameters("reimburseDelay", 365 days);

        wrapper.renumerateCaller(address(0x1));
        assertEq(coin.balanceOf(address(0x1)), baseUpdateCallerReward);

        hevm.warp(now + wrapper.reimburseDelay());

        wrapper.renumerateCaller(address(0x1));
        assertEq(coin.balanceOf(address(0x1)), baseUpdateCallerReward * 2);
    }
    function test_renumerate_after_long_delay() public {
        wrapper.modifyParameters("fsm", address(this));

        wrapper.renumerateCaller(address(0x1));
        assertEq(coin.balanceOf(address(0x1)), baseUpdateCallerReward);

        hevm.warp(now + wrapper.reimburseDelay() * 50);

        wrapper.renumerateCaller(address(0x1));
        assertEq(coin.balanceOf(address(0x1)), baseUpdateCallerReward + maxUpdateCallerReward);
    }
    function test_renumerate_no_funds_in_treasury() public {
        treasury.setTotalAllowance(address(this), uint(-1));
        treasury.setPerBlockAllowance(address(this), uint(-1));
        treasury.pullFunds(address(this), address(coin), initTokenAmount);

        wrapper.modifyParameters("fsm", address(this));

        wrapper.renumerateCaller(address(0x1));
        assertEq(coin.balanceOf(address(0x1)), 0);

        hevm.warp(now + wrapper.reimburseDelay());

        wrapper.renumerateCaller(address(0x1));
        assertEq(coin.balanceOf(address(0x1)), 0);
    }
    function testFail_invalid_renumerate_msg_sender() public {
        wrapper.modifyParameters("fsm", address(0x1));
        wrapper.renumerateCaller(address(0x1));
    }
    function testFail_renumerate_null_address() public {
        wrapper.modifyParameters("fsm", address(this));
        wrapper.renumerateCaller(address(0));
    }
    function testFail_renumerate_before_time_elapsed() public {
        wrapper.modifyParameters("fsm", address(this));
        wrapper.renumerateCaller(address(0x1));
        wrapper.renumerateCaller(address(0x1));
    }
}
