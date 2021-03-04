pragma solidity 0.6.7;

import "ds-test/test.sol";
import {DSValue} from "ds-value/value.sol";

import {DSM} from "../DSM.sol";
import {OSM} from "../OSM.sol";
import {FSMWrapper} from "../FSMWrapper.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract FSMWrapperTest is DSTest {
    Hevm hevm;

    DSValue feed;

    OSM osm;
    DSM dsm;

    FSMWrapper wrapper;

    uint256 reimburseDelay = 3600;

    uint WAD = 10 ** 18;

    function setUp() public {
        feed = new DSValue();                                      // create new feed
        feed.updateResult(uint(100 ether));                        // set feed to 100

        osm = new OSM(address(feed));                              // create new osm linked to feed
        dsm = new DSM(address(feed), 1);                           // create new dsm linked to feed and with 99.99% deviation tolerance
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);   // get hevm instance
        hevm.warp(uint(dsm.updateDelay()));                        // warp 1 hop

        osm.updateResult();                                        // set new next osm value
        dsm.updateResult();                                        // set new next dsm value

        wrapper = new FSMWrapper(address(osm), reimburseDelay);
    }

    function test_setup() public {
        assertEq(address(wrapper.fsm()), address(osm));
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
}
