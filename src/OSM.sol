pragma solidity >=0.5.15;

import "ds-value/value.sol";

contract Logging {
    event LogNote(
        bytes4   indexed  sig,
        address  indexed  usr,
        bytes32  indexed  arg1,
        bytes32  indexed  arg2,
        bytes             data
    ) anonymous;

    modifier emitLog {
        _;
        assembly {
            // log an 'anonymous' event with a constant 6 words of calldata
            // and four indexed topics: selector, caller, arg1 and arg2
            let mark := msize                         // end of memory ensures zero
            mstore(0x40, add(mark, 288))              // update free memory pointer
            mstore(mark, 0x20)                        // bytes type data offset
            mstore(add(mark, 0x20), 224)              // bytes size (padded)
            calldatacopy(add(mark, 0x40), 0, 224)     // bytes payload
            log4(mark, 288,                           // calldata
                 shl(224, shr(224, calldataload(0))), // msg.sig
                 caller,                              // msg.sender
                 calldataload(4),                     // arg1
                 calldataload(36)                     // arg2
                )
        }
    }
}

contract OSM is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
    * @notice Add auth to an account
    * @param account Account to add auth to
    */
    function addAuthorization(address account) external emitLog isAuthorized {
        authorizedAccounts[account] = 1;
    }
    /**
    * @notice Remove auth from an account
    * @param account Account to remove auth from
    */
    function removeAuthorization(address account) external emitLog isAuthorized {
        authorizedAccounts[account] = 0;
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "OSM/account-not-authorized");
        _;
    }

    // --- Stop ---
    uint256 public stopped;
    modifier stoppable { require(stopped == 0, "OSM/is-stopped"); _; }

    // --- Math ---
    function add(uint64 x, uint64 y) internal pure returns (uint64 z) {
        z = x + y;
        require(z >= x);
    }

    address public priceSource;
    uint16  constant ONE_HOUR = uint16(3600);
    uint16  public updateDelay = ONE_HOUR;
    uint64  public lastUpdateTime;

    struct Feed {
        uint128 value;
        uint128 isValid;
    }

    Feed currentFeed;
    Feed nextFeed;

    event LogValue(bytes32 value);

    constructor (address priceSource_) public {
        authorizedAccounts[msg.sender] = 1;
        priceSource = priceSource_;
    }

    function stop() external emitLog isAuthorized {
        stopped = 1;
    }
    function start() external emitLog isAuthorized {
        stopped = 0;
    }

    function changePriceSource(address priceSource_) external emitLog isAuthorized {
        priceSource = priceSource_;
    }

    function currentTime() internal view returns (uint) {
        return block.timestamp;
    }

    function latestUpdateTime(uint timestamp) internal view returns (uint64) {
        require(updateDelay != 0, "OSM/update-delay-is-zero");
        return uint64(timestamp - (timestamp % updateDelay));
    }

    function changeDelay(uint16 delay) external isAuthorized {
        require(delay > 0, "OSM/delay-is-zero");
        updateDelay = delay;
    }

    function restartValue() external emitLog isAuthorized {
        currentFeed = nextFeed = Feed(0, 0);
        stopped = 1;
    }

    function passedDelay() public view returns (bool ok) {
        return currentTime() >= add(lastUpdateTime, updateDelay);
    }

    function updateResult() external emitLog stoppable {
        require(passedDelay(), "OSM/not-passed");
        (bytes32 priceFeedValue, bool hasValidValue) = DSValue(priceSource).getResultWithValidity();
        if (hasValidValue) {
            currentFeed = nextFeed;
            nextFeed = Feed(uint128(uint(priceFeedValue)), 1);
            lastUpdateTime = latestUpdateTime(currentTime());
            emit LogValue(bytes32(uint(currentFeed.value)));
        }
    }

    function getResultWithValidity() external view returns (bytes32,bool) {
        return (bytes32(uint(currentFeed.value)), currentFeed.isValid == 1);
    }

    function getNextResultWithValidity() external view returns (bytes32,bool) {
        return (bytes32(uint(nextFeed.value)), nextFeed.isValid == 1);
    }

    function read() external view returns (bytes32) {
        require(currentFeed.isValid == 1, "OSM/no-current-value");
        return (bytes32(uint(currentFeed.value)));
    }
}