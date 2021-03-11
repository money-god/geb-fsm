pragma solidity >=0.6.7;

import "ds-test/test.sol";
import {DSValue} from "ds-value/value.sol";
import {DSToken} from "ds-token/token.sol";

import {MockTreasury} from "./mock/MockTreasury.sol";
import {SelfFundedDSM, ExternallyFundedDSM} from "../DSM.sol";
import "../FSMWrapper.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract SelfFundedDSMTest is DSTest {
    Hevm hevm;

    MockTreasury treasury;
    DSToken coin;
    DSValue feed;
    SelfFundedDSM dsm;

    uint WAD = 10 ** 18;

    uint256 baseCallerReward              = 15 ether;
    uint256 maxCallerReward               = 100 ether;
    uint256 initTokenAmount               = 100000000 ether;
    uint256 perSecondCallerRewardIncrease = 1000192559420674483977255848; // 100% over one hour

    function setUp() public {
        feed = new DSValue();                                      // create new feed
        feed.updateResult(uint(100 ether));                        // set feed to 100
        dsm = new SelfFundedDSM(address(feed), 1);                 // create new dsm linked to feed and with 99.99% deviation tolerance
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);   // get hevm instance
        hevm.warp(uint(dsm.updateDelay()));                        // warp 1 hop
        dsm.updateResult();                                        // set new next dsm value

        // Setting up increasingRewards - note: without these rewards are not paid out
        // Create token
        coin = new DSToken("RAI", "RAI");
        coin.mint(initTokenAmount);

        // Create treasury
        treasury = new MockTreasury(address(coin));
        coin.transfer(address(treasury), initTokenAmount);

        // pinger.setup(address(treasury), baseCallerReward, maxCallerReward, perSecondCallerRewardIncrease);
        dsm.modifyParameters("treasury", address(treasury));
        dsm.modifyParameters("maxUpdateCallerReward", maxCallerReward);
        dsm.modifyParameters("baseUpdateCallerReward", baseCallerReward);
        dsm.modifyParameters("perSecondCallerRewardIncrease", perSecondCallerRewardIncrease);

        // Setup treasury allowance
        treasury.setTotalAllowance(address(dsm), uint(-1));
        treasury.setPerBlockAllowance(address(dsm), uint(-1));
    }

    function testSetup() public {
        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), uint(100 ether));
        assertTrue(has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), uint(100 ether));
        assertTrue(has);
    }

    function testSetupInvalidPriceSource() public {
        feed = new DSValue();
        dsm = new SelfFundedDSM(address(feed), 1);

        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testSetupNullPriceSource() public {
        dsm = new SelfFundedDSM(address(0), 1);

        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testFailSetupRandomPriceSource() public {
        dsm = new SelfFundedDSM(address(0x123), 1);

        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testChangeValue() public {
        assertEq(dsm.priceSource(), address(feed));             //verify dsm source is feed
        DSValue feed2 = new DSValue();                          //create new feed
        dsm.changePriceSource(address(feed2));                  //change dsm source to new feed
        assertEq(dsm.priceSource(), address(feed2));            //verify dsm source is new feed
    }

    function testSetDelay() public {
        assertEq(uint(dsm.updateDelay()), 3600);                //verify interval is 1 hour
        dsm.changeDelay(uint16(7200));                          //change interval to 2 hours
        assertEq(uint(dsm.updateDelay()), 7200);                //verify interval is 2 hours
    }

    function testFailSetDelayZero() public {
        dsm.changeDelay(uint16(0));                             //attempt to change interval to 0
    }

    function testSetDeviation() public {
        assertEq(dsm.newPriceDeviation(), 1);
        dsm.changeNextPriceDeviation(WAD - 1);
        assertEq(dsm.newPriceDeviation(), WAD - 1);
    }

    function testFailSetDeviationWad() public {
        dsm.changeNextPriceDeviation(WAD);
    }

    function testFailSetDeviationAboveWad() public {
        dsm.changeNextPriceDeviation(WAD + 1);
    }

    function testVoid() public {
        assertTrue(dsm.stopped() == 0);                         //verify dsm is active
        hevm.warp(uint(dsm.updateDelay() * 2));                 //warp 2 updateDelay
        dsm.updateResult();                                     //set new curent and next dsm value
        (uint val, bool has) = dsm.getResultWithValidity();     //pull current dsm value
        assertEq(uint(val), 100 ether);                         //verify dsm value is 100
        assertTrue(has);                                        //verify dsm value is valid
        (val, has) = dsm.getNextResultWithValidity();           //pull next dsm value
        assertEq(uint(val), 100 ether);                         //verify next dsm value is 100
        assertTrue(has);                                        //verify next dsm value is valid
        dsm.restartValue();                                     //void all dsm values
        assertTrue(dsm.stopped() == 1);                         //verify dsm is inactive
        (val, has) = dsm.getResultWithValidity();               //pull current dsm value
        assertEq(uint(val), 0);                                 //verify current dsm value is 0
        assertTrue(!has);                                       //verify current dsm value is invalid
        (val, has) = dsm.getNextResultWithValidity();           //pull next dsm value
        assertEq(uint(val), 0);                                 //verify next dsm value is 0
        assertTrue(!has);                                       //verify next dsm value is invalid
    }

    function testUpdateValue() public {
        feed.updateResult(uint(101 ether));                     //set new feed value
        hevm.warp(uint(dsm.lastUpdateTime() * 2));              //warp 2 hops
        dsm.updateResult();                                     //set new current and next dsm value
        (uint val, bool has) = dsm.getResultWithValidity();     //pull current dsm value
        assertEq(uint(val), 100 ether);                         //verify current dsm value is 100
        assertTrue(has);                                        //verify current dsm value is valid
        (val, has) = dsm.getNextResultWithValidity();           //pull next dsm value
        assertEq(uint(val), 101 ether);                         //verify next dsm value is 101
        assertTrue(has);                                        //verify next dsm value is valid
        hevm.warp(uint(dsm.lastUpdateTime() * 3));              //warp 3 hops
        dsm.updateResult();                                     //set new current and next dsm value
        (val, has) = dsm.getResultWithValidity();               //pull current dsm value
        assertEq(uint(val), 101 ether);                         //verify current dsm value is 101
        assertTrue(has);                                        //verify current dsm value is valid
    }

    function testNextResultDeviatedAboveBound() public {
        dsm.changeNextPriceDeviation(0.95E18);
        feed.updateResult(uint(106 ether));
        hevm.warp(uint(dsm.lastUpdateTime() * 2));
        assertEq(uint(dsm.getNextPriceLowerBound()), 95E18);
        assertEq(uint(dsm.getNextPriceUpperBound()), 105E18);
        assertEq(uint(dsm.getNextBoundedPrice()), 100E18);
        dsm.updateResult();
        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), 100 ether);
        assertTrue(has);
        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), 106 ether);
        assertTrue(has);
        hevm.warp(uint(dsm.lastUpdateTime() * 3));
        assertEq(uint(dsm.getNextPriceLowerBound()), 95E18);
        assertEq(uint(dsm.getNextPriceUpperBound()), 105E18);
        assertEq(uint(dsm.getNextBoundedPrice()), 105E18);
        feed.updateResult(uint(80 ether));
        dsm.updateResult();
        (val, has) = dsm.getResultWithValidity();
        assertEq(uint(val), 105 ether);
        assertTrue(has);
        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), 80 ether);
        assertTrue(has);
        hevm.warp(uint(dsm.lastUpdateTime() * 4));
        assertEq(uint(dsm.getNextPriceLowerBound()), 99.75E18);
        assertEq(uint(dsm.getNextPriceUpperBound()), 110.25E18);
        assertEq(uint(dsm.getNextBoundedPrice()), 99.75E18);
        dsm.updateResult();
        (val, has) = dsm.getResultWithValidity();
        assertEq(uint(val), 99.75E18);
        assertTrue(has);
    }

    function testFailUpdateValue() public {
        feed.updateResult(uint(101 ether));                     //set new current and next dsm value
        hevm.warp(uint(dsm.lastUpdateTime() * 2 - 1));          //warp 2 hops - 1 second
        dsm.updateResult();                                     //attempt to set new current and next dsm value
    }

    function testConstructorDoesNotUpdateFeed() public {
        feed = new DSValue();                                      // create new feed
        dsm = new SelfFundedDSM(address(feed), 1);                 // create new dsm linked to feed and with 99.99% deviation tolerance

        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), 0);
        assertTrue(!has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), 0);
        assertTrue(!has);

        feed.updateResult(uint(100 ether));
        dsm.changeNextPriceDeviation(0.95E18);
        dsm.updateResult();

        hevm.warp(uint(dsm.lastUpdateTime()));
        assertEq(uint(dsm.getNextPriceLowerBound()), 0);
        assertEq(uint(dsm.getNextPriceUpperBound()), 0);
        assertEq(uint(dsm.getNextBoundedPrice()), 100E18);

        hevm.warp(uint(dsm.lastUpdateTime()) * 2);
        dsm.updateResult();

        (val, has) = dsm.getResultWithValidity();
        assertEq(uint(val), 100E18);
        assertTrue(has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), 100E18);
        assertTrue(has);

        feed.updateResult(uint(106 ether));
        hevm.warp(uint(dsm.lastUpdateTime()) * 3);
        dsm.updateResult();
        hevm.warp(uint(dsm.lastUpdateTime()) * 4);
        dsm.updateResult();

        (val, has) = dsm.getResultWithValidity();
        assertEq(uint(val), 105E18);
        assertTrue(has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), 106E18);
        assertTrue(has);
    }

    function burnCoinBalance() internal {
        coin.burn(coin.balanceOf(address(this)));
    }

    function testIncreasingRewards() public {
        hevm.warp(now + dsm.updateDelay());
        dsm.updateResult();
        assertEq(coin.balanceOf(address(this)), baseCallerReward);

        burnCoinBalance();
        hevm.warp(now + dsm.updateDelay() * 2); // 100% reward increase
        dsm.updateResult();
        assertEq(coin.balanceOf(address(this)), (baseCallerReward * 2) - 1); // 1 wei precision loss

        burnCoinBalance();
        hevm.warp(now + dsm.updateDelay() * 3); // 300% reward increase (2h, 100%/hour)
        dsm.updateResult();
        assertEq(coin.balanceOf(address(this)), (baseCallerReward * 4) - 1); // 1 wei precision loss

        burnCoinBalance();
        hevm.warp(now + dsm.updateDelay() * 4); // will pay out maxCallerReward
        dsm.updateResult();
        assertEq(coin.balanceOf(address(this)), maxCallerReward);

        burnCoinBalance();
        hevm.warp(now + 3 days); // long delay, will pay out maxCallerReward
        dsm.updateResult();
        assertEq(coin.balanceOf(address(this)), maxCallerReward);

        // no allowance in treasury
        treasury.setTotalAllowance(address(dsm), 0);
        burnCoinBalance();
        hevm.warp(now + dsm.updateDelay() * 3); // long delay, will pay out maxCallerReward
        dsm.updateResult();
        assertEq(coin.balanceOf(address(this)), 0); // no payout
        assertEq(dsm.lastUpdateTime(), now - (now % dsm.updateDelay())); // still updates
    }
}

contract ExternallyFundedDSMTest is DSTest {
    Hevm hevm;

    MockTreasury treasury;
    DSToken coin;
    DSValue feed;
    ExternallyFundedDSM dsm;
    FSMWrapper wrapper;

    uint WAD = 10 ** 18;

    uint256 baseCallerReward              = 15 ether;
    uint256 maxCallerReward               = 100 ether;
    uint256 initTokenAmount               = 100000000 ether;
    uint256 maxRewardIncreaseDelay        = 6 hours;
    uint256 perSecondCallerRewardIncrease = 1000192559420674483977255848; // 100% over one hour

    function setUp() public {
        feed = new DSValue();                                      // create new feed
        feed.updateResult(uint(100 ether));                        // set feed to 100

        dsm = new ExternallyFundedDSM(address(feed), 1);           // create new dsm linked to feed and with 99.99% deviation tolerance
        wrapper = new FSMWrapper(address(dsm), dsm.updateDelay()); // create the dsm wrapper
        dsm.modifyParameters("fsmWrapper", address(wrapper));      // set the wrapper inside the dsm

        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);   // get hevm instance
        hevm.warp(uint(dsm.updateDelay()));                        // warp 1 hop
        dsm.updateResult();                                        // set new next dsm value

        // Setting up increasingRewards - note: without these rewards are not paid out
        // Create token
        coin = new DSToken("RAI", "RAI");
        coin.mint(initTokenAmount);

        // Create treasury
        treasury = new MockTreasury(address(coin));
        coin.transfer(address(treasury), initTokenAmount);

        // pinger.setup(address(treasury), baseCallerReward, maxCallerReward, perSecondCallerRewardIncrease);
        wrapper.modifyParameters("treasury", address(treasury));
        wrapper.modifyParameters("maxUpdateCallerReward", maxCallerReward);
        wrapper.modifyParameters("baseUpdateCallerReward", baseCallerReward);
        wrapper.modifyParameters("perSecondCallerRewardIncrease", perSecondCallerRewardIncrease);
        wrapper.modifyParameters("maxRewardIncreaseDelay", maxRewardIncreaseDelay);

        // Setup treasury allowance
        treasury.setTotalAllowance(address(wrapper), uint(-1));
        treasury.setPerBlockAllowance(address(wrapper), uint(-1));
    }

    function testSetup() public {
        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), uint(100 ether));
        assertTrue(has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), uint(100 ether));
        assertTrue(has);
    }
    function testSetupInvalidPriceSource() public {
        feed = new DSValue();
        dsm = new ExternallyFundedDSM(address(feed), 1);

        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testSetupNullPriceSource() public {
        dsm = new ExternallyFundedDSM(address(0), 1);

        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testFailSetupRandomPriceSource() public {
        dsm = new ExternallyFundedDSM(address(0x123), 1);

        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testChangeValue() public {
        assertEq(dsm.priceSource(), address(feed));             //verify dsm source is feed
        DSValue feed2 = new DSValue();                          //create new feed
        dsm.changePriceSource(address(feed2));                  //change dsm source to new feed
        assertEq(dsm.priceSource(), address(feed2));            //verify dsm source is new feed
    }

    function testSetDelay() public {
        assertEq(uint(dsm.updateDelay()), 3600);                //verify interval is 1 hour
        dsm.changeDelay(uint16(7200));                          //change interval to 2 hours
        assertEq(uint(dsm.updateDelay()), 7200);                //verify interval is 2 hours
    }

    function testFailSetDelayZero() public {
        dsm.changeDelay(uint16(0));                             //attempt to change interval to 0
    }

    function testSetDeviation() public {
        assertEq(dsm.newPriceDeviation(), 1);
        dsm.changeNextPriceDeviation(WAD - 1);
        assertEq(dsm.newPriceDeviation(), WAD - 1);
    }

    function testFailSetDeviationWad() public {
        dsm.changeNextPriceDeviation(WAD);
    }

    function testFailSetDeviationAboveWad() public {
        dsm.changeNextPriceDeviation(WAD + 1);
    }

    function testVoid() public {
        assertTrue(dsm.stopped() == 0);                         //verify dsm is active
        hevm.warp(uint(dsm.updateDelay() * 2));                 //warp 2 updateDelay
        dsm.updateResult();                                     //set new curent and next dsm value
        (uint val, bool has) = dsm.getResultWithValidity();     //pull current dsm value
        assertEq(uint(val), 100 ether);                         //verify dsm value is 100
        assertTrue(has);                                        //verify dsm value is valid
        (val, has) = dsm.getNextResultWithValidity();           //pull next dsm value
        assertEq(uint(val), 100 ether);                         //verify next dsm value is 100
        assertTrue(has);                                        //verify next dsm value is valid
        dsm.restartValue();                                     //void all dsm values
        assertTrue(dsm.stopped() == 1);                         //verify dsm is inactive
        (val, has) = dsm.getResultWithValidity();               //pull current dsm value
        assertEq(uint(val), 0);                                 //verify current dsm value is 0
        assertTrue(!has);                                       //verify current dsm value is invalid
        (val, has) = dsm.getNextResultWithValidity();           //pull next dsm value
        assertEq(uint(val), 0);                                 //verify next dsm value is 0
        assertTrue(!has);                                       //verify next dsm value is invalid
    }

    function testUpdateValue() public {
        feed.updateResult(uint(101 ether));                     //set new feed value
        hevm.warp(uint(dsm.lastUpdateTime() * 2));              //warp 2 hops
        dsm.updateResult();                                     //set new current and next dsm value
        (uint val, bool has) = dsm.getResultWithValidity();     //pull current dsm value
        assertEq(uint(val), 100 ether);                         //verify current dsm value is 100
        assertTrue(has);                                        //verify current dsm value is valid
        (val, has) = dsm.getNextResultWithValidity();           //pull next dsm value
        assertEq(uint(val), 101 ether);                         //verify next dsm value is 101
        assertTrue(has);                                        //verify next dsm value is valid
        hevm.warp(uint(dsm.lastUpdateTime() * 3));              //warp 3 hops
        dsm.updateResult();                                     //set new current and next dsm value
        (val, has) = dsm.getResultWithValidity();               //pull current dsm value
        assertEq(uint(val), 101 ether);                         //verify current dsm value is 101
        assertTrue(has);                                        //verify current dsm value is valid
    }

    function testNextResultDeviatedAboveBound() public {
        dsm.changeNextPriceDeviation(0.95E18);
        feed.updateResult(uint(106 ether));
        hevm.warp(uint(dsm.lastUpdateTime() * 2));
        assertEq(uint(dsm.getNextPriceLowerBound()), 95E18);
        assertEq(uint(dsm.getNextPriceUpperBound()), 105E18);
        assertEq(uint(dsm.getNextBoundedPrice()), 100E18);
        dsm.updateResult();
        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), 100 ether);
        assertTrue(has);
        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), 106 ether);
        assertTrue(has);
        hevm.warp(uint(dsm.lastUpdateTime() * 3));
        assertEq(uint(dsm.getNextPriceLowerBound()), 95E18);
        assertEq(uint(dsm.getNextPriceUpperBound()), 105E18);
        assertEq(uint(dsm.getNextBoundedPrice()), 105E18);
        feed.updateResult(uint(80 ether));
        dsm.updateResult();
        (val, has) = dsm.getResultWithValidity();
        assertEq(uint(val), 105 ether);
        assertTrue(has);
        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), 80 ether);
        assertTrue(has);
        hevm.warp(uint(dsm.lastUpdateTime() * 4));
        assertEq(uint(dsm.getNextPriceLowerBound()), 99.75E18);
        assertEq(uint(dsm.getNextPriceUpperBound()), 110.25E18);
        assertEq(uint(dsm.getNextBoundedPrice()), 99.75E18);
        dsm.updateResult();
        (val, has) = dsm.getResultWithValidity();
        assertEq(uint(val), 99.75E18);
        assertTrue(has);
    }

    function testFailUpdateValue() public {
        feed.updateResult(uint(101 ether));                     //set new current and next dsm value
        hevm.warp(uint(dsm.lastUpdateTime() * 2 - 1));          //warp 2 hops - 1 second
        dsm.updateResult();                                     //attempt to set new current and next dsm value
    }

    function testConstructorDoesNotUpdateFeed() public {
        feed = new DSValue();                                      // create new feed
        dsm = new ExternallyFundedDSM(address(feed), 1);           // create new dsm linked to feed and with 99.99% deviation tolerance
        dsm.modifyParameters("fsmWrapper", address(wrapper));
        wrapper.modifyParameters("fsm", address(dsm));

        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), 0);
        assertTrue(!has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), 0);
        assertTrue(!has);

        feed.updateResult(uint(100 ether));
        dsm.changeNextPriceDeviation(0.95E18);
        dsm.updateResult();

        hevm.warp(uint(dsm.lastUpdateTime()));
        assertEq(uint(dsm.getNextPriceLowerBound()), 0);
        assertEq(uint(dsm.getNextPriceUpperBound()), 0);
        assertEq(uint(dsm.getNextBoundedPrice()), 100E18);

        hevm.warp(uint(dsm.lastUpdateTime()) * 2);
        dsm.updateResult();

        (val, has) = dsm.getResultWithValidity();
        assertEq(uint(val), 100E18);
        assertTrue(has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), 100E18);
        assertTrue(has);

        feed.updateResult(uint(106 ether));
        hevm.warp(uint(dsm.lastUpdateTime()) * 3);
        dsm.updateResult();
        hevm.warp(uint(dsm.lastUpdateTime()) * 4);
        dsm.updateResult();

        (val, has) = dsm.getResultWithValidity();
        assertEq(uint(val), 105E18);
        assertTrue(has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), 106E18);
        assertTrue(has);
    }

    function testWrapperBlacklistedDSM() public {
        feed.updateResult(uint(101 ether));                     //set new feed value
        hevm.warp(uint(dsm.lastUpdateTime() * 2));              //warp 2 hops
        wrapper.modifyParameters("fsm", address(0x1));          //change the fsm in the wrapper
        dsm.updateResult();                                     //set new current and next dsm value
        assertEq(coin.balanceOf(address(this)), 0);             //no reward received
        assertTrue(wrapper.lastReimburseTime() != now);
        assertEq(dsm.lastUpdateTime(), now);
    }

    function burnCoinBalance() internal {
        coin.burn(coin.balanceOf(address(this)));
    }

    function testIncreasingRewards() public {
        hevm.warp(now + dsm.updateDelay());
        dsm.updateResult();
        assertEq(coin.balanceOf(address(this)), baseCallerReward);

        burnCoinBalance();
        hevm.warp(now + dsm.updateDelay() * 2); // 100% reward increase
        dsm.updateResult();
        assertEq(coin.balanceOf(address(this)), (baseCallerReward * 2) - 1); // 1 wei precision loss

        burnCoinBalance();
        hevm.warp(now + dsm.updateDelay() * 3); // 300% reward increase (2h, 100%/hour)
        dsm.updateResult();
        assertEq(coin.balanceOf(address(this)), (baseCallerReward * 4) - 1); // 1 wei precision loss

        burnCoinBalance();
        hevm.warp(now + dsm.updateDelay() * 4); // will pay out maxCallerReward
        dsm.updateResult();
        assertEq(coin.balanceOf(address(this)), maxCallerReward);

        burnCoinBalance();
        hevm.warp(now + 3 days); // long delay, will pay out maxCallerReward
        dsm.updateResult();
        assertEq(coin.balanceOf(address(this)), maxCallerReward);

        // no allowance in treasury
        treasury.setTotalAllowance(address(wrapper), 0);
        burnCoinBalance();
        hevm.warp(now + dsm.updateDelay() * 3); // long delay, will pay out maxCallerReward
        dsm.updateResult();
        assertEq(coin.balanceOf(address(this)), 0); // no payout
        assertEq(dsm.lastUpdateTime(), now - (now % dsm.updateDelay())); // still updates
    }
}
