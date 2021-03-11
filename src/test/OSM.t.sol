pragma solidity >=0.6.7;

import "ds-test/test.sol";
import {DSValue} from "ds-value/value.sol";
import {DSToken} from "ds-token/token.sol";

import {MockTreasury} from "./mock/MockTreasury.sol";
import {SelfFundedOSM, ExternallyFundedOSM} from "../OSM.sol";
import "../FSMWrapper.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract SelfFundedOSMTest is DSTest {
    Hevm hevm;

    MockTreasury treasury;
    DSToken coin;
    DSValue feed;
    SelfFundedOSM osm;

    uint256 baseUpdateCallerReward        = 15 ether;
    uint256 maxUpdateCallerReward         = 100 ether;
    uint256 initTokenAmount               = 100000000 ether;
    uint256 perSecondCallerRewardIncrease = 1000192559420674483977255848; // 100% over one hour

    function setUp() public {
        feed = new DSValue();                                    //create new feed
        feed.updateResult(uint(100 ether));                      //set feed to 100
        osm = new SelfFundedOSM(address(feed));                  //create new osm linked to feed
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D); //get hevm instance
        hevm.warp(uint(osm.updateDelay()));                      //warp 1 hop
        osm.updateResult();                                      //set new next osm value

        // Setting up increasing rewards - note: without these, rewards are not paid out
        // Create token
        coin = new DSToken("RAI", "RAI");
        coin.mint(initTokenAmount);

        // Create treasury
        treasury = new MockTreasury(address(coin));
        coin.transfer(address(treasury), initTokenAmount);

        // pinger.setup(address(treasury), baseUpdateCallerReward, maxUpdateCallerReward, perSecondCallerRewardIncrease);
        osm.modifyParameters("treasury", address(treasury));
        osm.modifyParameters("maxUpdateCallerReward", maxUpdateCallerReward);
        osm.modifyParameters("baseUpdateCallerReward", baseUpdateCallerReward);
        osm.modifyParameters("perSecondCallerRewardIncrease", perSecondCallerRewardIncrease);

        // Setup treasury allowance
        treasury.setTotalAllowance(address(osm), uint(-1));
        treasury.setPerBlockAllowance(address(osm), uint(-1));
    }

    function testSetup() public {
        (uint val, bool has) = osm.getResultWithValidity();
        assertEq(uint(val), uint(100 ether));
        assertTrue(has);

        (val, has) = osm.getNextResultWithValidity();
        assertEq(uint(val), uint(100 ether));
        assertTrue(has);
    }

    function testSetupInvalidPriceSource() public {
        feed = new DSValue();
        osm = new SelfFundedOSM(address(feed));

        (uint val, bool has) = osm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = osm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testSetupNullPriceSource() public {
        osm = new SelfFundedOSM(address(0));

        (uint val, bool has) = osm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = osm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testFailSetupRandomPriceSource() public {
        osm = new SelfFundedOSM(address(0x123));

        (uint val, bool has) = osm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = osm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testChangeValue() public {
        assertEq(osm.priceSource(), address(feed));             //verify osm source is feed
        DSValue feed2 = new DSValue();                          //create new feed
        osm.changePriceSource(address(feed2));                  //change osm source to new feed
        assertEq(osm.priceSource(), address(feed2));            //verify osm source is new feed
    }

    function testSetDelay() public {
        assertEq(uint(osm.updateDelay()), 3600);                //verify interval is 1 hour
        osm.changeDelay(uint16(7200));                          //change interval to 2 hours
        assertEq(uint(osm.updateDelay()), 7200);                //verify interval is 2 hours
    }

    function testFailSetDelayZero() public {
        osm.changeDelay(uint16(0));                             //attempt to change interval to 0
    }

    function testVoid() public {
        assertTrue(osm.stopped() == 0);                         //verify osm is active
        hevm.warp(uint(osm.updateDelay() * 2));                 //warp 2 updateDelay
        osm.updateResult();                                     //set new curent and next osm value
        (uint val, bool has) = osm.getResultWithValidity();     //pull current osm value
        assertEq(uint(val), 100 ether);                         //verify osm value is 100
        assertTrue(has);                                        //verify osm value is valid
        (val, has) = osm.getNextResultWithValidity();           //pull next osm value
        assertEq(uint(val), 100 ether);                         //verify next osm value is 100
        assertTrue(has);                                        //verify next osm value is valid
        osm.restartValue();                                     //void all osm values
        assertTrue(osm.stopped() == 1);                         //verify osm is inactive
        (val, has) = osm.getResultWithValidity();               //pull current osm value
        assertEq(uint(val), 0);                                 //verify current osm value is 0
        assertTrue(!has);                                       //verify current osm value is invalid
        (val, has) = osm.getNextResultWithValidity();           //pull next osm value
        assertEq(uint(val), 0);                                 //verify next osm value is 0
        assertTrue(!has);                                       //verify next osm value is invalid
    }

    function testUpdateValue() public {
        feed.updateResult(uint(101 ether));                     //set new feed value
        hevm.warp(uint(osm.lastUpdateTime() * 2));              //warp 2 hops
        osm.updateResult();                                     //set new current and next osm value
        (uint val, bool has) = osm.getResultWithValidity();     //pull current osm value
        assertEq(uint(val), 100 ether);                         //verify current osm value is 100
        assertTrue(has);                                        //verify current osm value is valid
        (val, has) = osm.getNextResultWithValidity();           //pull next osm value
        assertEq(uint(val), 101 ether);                         //verify next osm value is 101
        assertTrue(has);                                        //verify next osm value is valid
        hevm.warp(uint(osm.lastUpdateTime() * 3));              //warp 3 hops
        osm.updateResult();                                     //set new current and next osm value
        (val, has) = osm.getResultWithValidity();               //pull current osm value
        assertEq(uint(val), 101 ether);                         //verify current osm value is 101
        assertTrue(has);                                        //verify current osm value is valid
    }

    function testFailUpdateValue() public {
        feed.updateResult(uint(101 ether));                     //set new current and next osm value
        hevm.warp(uint(osm.lastUpdateTime() * 2 - 1));          //warp 2 hops - 1 second
        osm.updateResult();                                     //attempt to set new current and next osm value
    }

    function burnCoinBalance() internal {
        coin.burn(coin.balanceOf(address(this)));
    }

    function testIncreasingRewards() public {
        hevm.warp(now + osm.updateDelay());
        osm.updateResult();
        assertEq(coin.balanceOf(address(this)), baseUpdateCallerReward);

        burnCoinBalance();
        hevm.warp(now + osm.updateDelay() * 2); // 100% reward increase
        osm.updateResult();
        assertEq(coin.balanceOf(address(this)), (baseUpdateCallerReward * 2) - 1); // 1 wei precision loss

        burnCoinBalance();
        hevm.warp(now + osm.updateDelay() * 3); // 300% reward increase (2h, 100%/hour)
        osm.updateResult();
        assertEq(coin.balanceOf(address(this)), (baseUpdateCallerReward * 4) - 1); // 1 wei precision loss

        burnCoinBalance();
        hevm.warp(now + osm.updateDelay() * 4); // will pay out maxUpdateCallerReward
        osm.updateResult();
        assertEq(coin.balanceOf(address(this)), maxUpdateCallerReward);

        burnCoinBalance();
        hevm.warp(now + osm.updateDelay() * 400); // long delay, will pay out maxUpdateCallerReward
        osm.updateResult();
        assertEq(coin.balanceOf(address(this)), maxUpdateCallerReward);

        // no allowance in treasury
        treasury.setTotalAllowance(address(osm), 0);
        burnCoinBalance();
        hevm.warp(now + osm.updateDelay() * 3); // long delay, will pay out maxUpdateCallerReward
        osm.updateResult();
        assertEq(coin.balanceOf(address(this)), 0); // no payout
        assertEq(osm.lastUpdateTime(), now - (now % osm.updateDelay())); // still updates
    }
}

contract ExternallyFundedOSMTest is DSTest {
    Hevm hevm;

    MockTreasury treasury;
    DSToken coin;
    DSValue feed;
    ExternallyFundedOSM osm;
    FSMWrapper wrapper;

    uint256 baseUpdateCallerReward        = 15 ether;
    uint256 maxUpdateCallerReward         = 100 ether;
    uint256 initTokenAmount               = 100000000 ether;
    uint256 maxRewardIncreaseDelay        = 6 hours;
    uint256 perSecondCallerRewardIncrease = 1000192559420674483977255848; // 100% over one hour

    function setUp() public {
        feed = new DSValue();                                      //create new feed
        feed.updateResult(uint(100 ether));                        //set feed to 100

        osm = new ExternallyFundedOSM(address(feed));              //create new osm
        wrapper = new FSMWrapper(address(osm), osm.updateDelay()); // create the dsm wrapper
        osm.modifyParameters("fsmWrapper", address(wrapper));      // set the wrapper inside the dsm

        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);   //get hevm instance
        hevm.warp(uint(osm.updateDelay()));                        //warp 1 hop
        osm.updateResult();                                        //set new next osm value

        // Setting up increasing rewards - note: without these, rewards are not paid out
        // Create token
        coin = new DSToken("RAI", "RAI");
        coin.mint(initTokenAmount);

        // Create treasury
        treasury = new MockTreasury(address(coin));
        coin.transfer(address(treasury), initTokenAmount);

        // pinger.setup(address(treasury), baseUpdateCallerReward, maxUpdateCallerReward, perSecondCallerRewardIncrease);
        wrapper.modifyParameters("treasury", address(treasury));
        wrapper.modifyParameters("maxUpdateCallerReward", maxUpdateCallerReward);
        wrapper.modifyParameters("baseUpdateCallerReward", baseUpdateCallerReward);
        wrapper.modifyParameters("perSecondCallerRewardIncrease", perSecondCallerRewardIncrease);
        wrapper.modifyParameters("maxRewardIncreaseDelay", maxRewardIncreaseDelay);

        // Setup treasury allowance
        treasury.setTotalAllowance(address(wrapper), uint(-1));
        treasury.setPerBlockAllowance(address(wrapper), uint(-1));
    }

    function testSetup() public {
        (uint val, bool has) = osm.getResultWithValidity();
        assertEq(uint(val), uint(100 ether));
        assertTrue(has);

        (val, has) = osm.getNextResultWithValidity();
        assertEq(uint(val), uint(100 ether));
        assertTrue(has);
    }

    function testSetupInvalidPriceSource() public {
        feed = new DSValue();
        osm = new ExternallyFundedOSM(address(feed));

        (uint val, bool has) = osm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = osm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testSetupNullPriceSource() public {
        osm = new ExternallyFundedOSM(address(0));

        (uint val, bool has) = osm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = osm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testFailSetupRandomPriceSource() public {
        osm = new ExternallyFundedOSM(address(0x123));

        (uint val, bool has) = osm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = osm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testChangeValue() public {
        assertEq(osm.priceSource(), address(feed));             //verify osm source is feed
        DSValue feed2 = new DSValue();                          //create new feed
        osm.changePriceSource(address(feed2));                  //change osm source to new feed
        assertEq(osm.priceSource(), address(feed2));            //verify osm source is new feed
    }

    function testSetDelay() public {
        assertEq(uint(osm.updateDelay()), 3600);                //verify interval is 1 hour
        osm.changeDelay(uint16(7200));                          //change interval to 2 hours
        assertEq(uint(osm.updateDelay()), 7200);                //verify interval is 2 hours
    }

    function testFailSetDelayZero() public {
        osm.changeDelay(uint16(0));                             //attempt to change interval to 0
    }

    function testWrapperBlacklistedOSM() public {
        feed.updateResult(uint(101 ether));                     //set new feed value
        hevm.warp(uint(osm.lastUpdateTime() * 2));              //warp 2 hops
        wrapper.modifyParameters("fsm", address(0x1));          //change the fsm in the wrapper
        osm.updateResult();                                     //set new current and next osm value
        assertEq(coin.balanceOf(address(this)), 0);             //no reward received
        assertTrue(wrapper.lastReimburseTime() != now);
        assertEq(osm.lastUpdateTime(), now);
    }

    function testVoid() public {
        assertTrue(osm.stopped() == 0);                         //verify osm is active
        hevm.warp(uint(osm.updateDelay() * 2));                 //warp 2 updateDelay
        osm.updateResult();                                     //set new curent and next osm value
        (uint val, bool has) = osm.getResultWithValidity();     //pull current osm value
        assertEq(uint(val), 100 ether);                         //verify osm value is 100
        assertTrue(has);                                        //verify osm value is valid
        (val, has) = osm.getNextResultWithValidity();           //pull next osm value
        assertEq(uint(val), 100 ether);                         //verify next osm value is 100
        assertTrue(has);                                        //verify next osm value is valid
        osm.restartValue();                                     //void all osm values
        assertTrue(osm.stopped() == 1);                         //verify osm is inactive
        (val, has) = osm.getResultWithValidity();               //pull current osm value
        assertEq(uint(val), 0);                                 //verify current osm value is 0
        assertTrue(!has);                                       //verify current osm value is invalid
        (val, has) = osm.getNextResultWithValidity();           //pull next osm value
        assertEq(uint(val), 0);                                 //verify next osm value is 0
        assertTrue(!has);                                       //verify next osm value is invalid
    }

    function testUpdateValue() public {
        feed.updateResult(uint(101 ether));                     //set new feed value
        hevm.warp(uint(osm.lastUpdateTime() * 2));              //warp 2 hops
        osm.updateResult();                                     //set new current and next osm value
        (uint val, bool has) = osm.getResultWithValidity();     //pull current osm value
        assertEq(uint(val), 100 ether);                         //verify current osm value is 100
        assertTrue(has);                                        //verify current osm value is valid
        (val, has) = osm.getNextResultWithValidity();           //pull next osm value
        assertEq(uint(val), 101 ether);                         //verify next osm value is 101
        assertTrue(has);                                        //verify next osm value is valid
        hevm.warp(uint(osm.lastUpdateTime() * 3));              //warp 3 hops
        osm.updateResult();                                     //set new current and next osm value
        (val, has) = osm.getResultWithValidity();               //pull current osm value
        assertEq(uint(val), 101 ether);                         //verify current osm value is 101
        assertTrue(has);                                        //verify current osm value is valid
    }

    function testFailUpdateValue() public {
        feed.updateResult(uint(101 ether));                     //set new current and next osm value
        hevm.warp(uint(osm.lastUpdateTime() * 2 - 1));          //warp 2 hops - 1 second
        osm.updateResult();                                     //attempt to set new current and next osm value
    }

    function burnCoinBalance() internal {
        coin.burn(coin.balanceOf(address(this)));
    }

    function testIncreasingRewards() public {
        hevm.warp(now + osm.updateDelay());
        osm.updateResult();
        assertEq(coin.balanceOf(address(this)), baseUpdateCallerReward);

        burnCoinBalance();
        hevm.warp(now + osm.updateDelay() * 2); // 100% reward increase
        osm.updateResult();
        assertEq(coin.balanceOf(address(this)), (baseUpdateCallerReward * 2) - 1); // 1 wei precision loss

        burnCoinBalance();
        hevm.warp(now + osm.updateDelay() * 3); // 300% reward increase (2h, 100%/hour)
        osm.updateResult();
        assertEq(coin.balanceOf(address(this)), (baseUpdateCallerReward * 4) - 1); // 1 wei precision loss

        burnCoinBalance();
        hevm.warp(now + osm.updateDelay() * 4); // will pay out maxUpdateCallerReward
        osm.updateResult();
        assertEq(coin.balanceOf(address(this)), maxUpdateCallerReward);

        burnCoinBalance();
        hevm.warp(now + osm.updateDelay() * 400); // long delay, will pay out maxUpdateCallerReward
        osm.updateResult();
        assertEq(coin.balanceOf(address(this)), maxUpdateCallerReward);

        // no allowance in treasury
        treasury.setTotalAllowance(address(wrapper), 0);
        burnCoinBalance();
        hevm.warp(now + osm.updateDelay() * 3); // long delay, will pay out maxUpdateCallerReward
        osm.updateResult();
        assertEq(coin.balanceOf(address(this)), 0); // no payout
        assertEq(osm.lastUpdateTime(), now - (now % osm.updateDelay())); // still updates
    }
}
