pragma solidity >=0.6.7;

import "ds-test/test.sol";
import {DSValue} from "ds-value/value.sol";
import {DSM} from "../DSM.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract DSMTest is DSTest {
    Hevm hevm;

    DSValue feed;
    DSM dsm;

    uint WAD = 10 ** 18;

    function setUp() public {
        feed = new DSValue();                                      // create new feed
        feed.updateResult(uint(100 ether));                        // set feed to 100
        dsm = new DSM(address(feed), 1);                           // create new dsm linked to feed and with 99.99% deviation tolerance
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);   // get hevm instance
        hevm.warp(uint(dsm.updateDelay()));                        // warp 1 hop
        dsm.updateResult();                                        // set new next dsm value
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
        dsm = new DSM(address(feed), 1);

        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testSetupNullPriceSource() public {
        dsm = new DSM(address(0), 1);

        (uint val, bool has) = dsm.getResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);

        (val, has) = dsm.getNextResultWithValidity();
        assertEq(uint(val), uint(0));
        assertTrue(!has);
    }

    function testFailSetupRandomPriceSource() public {
        dsm = new DSM(address(0x123), 1);

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
        assertEq(uint(dsm.updateDelay()), 3600);             //verify interval is 1 hour
        dsm.changeDelay(uint16(7200));                       //change interval to 2 hours
        assertEq(uint(dsm.updateDelay()), 7200);             //verify interval is 2 hours
    }

    function testFailSetDelayZero() public {
        dsm.changeDelay(uint16(0));                          //attempt to change interval to 0
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
}
