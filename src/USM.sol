pragma solidity >=0.6.7;

import "./uni/UniswapV2Library.sol";
import "./uni/UQ112x112.sol";

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
            let mark := msize()                       // end of memory ensures zero
            mstore(0x40, add(mark, 288))              // update free memory pointer
            mstore(mark, 0x20)                        // bytes type data offset
            mstore(add(mark, 0x20), 224)              // bytes size (padded)
            calldatacopy(add(mark, 0x40), 0, 224)     // bytes payload
            log4(mark, 288,                           // calldata
                 shl(224, shr(224, calldataload(0))), // msg.sig
                 caller(),                            // msg.sender
                 calldataload(4),                     // arg1
                 calldataload(36)                     // arg2
                )
        }
    }
}

contract USM is UniswapV2Library, Logging {
    using UQ112x112 for uint224;

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
        require(authorizedAccounts[msg.sender] == 1, "USM/account-not-authorized");
        _;
    }

    // --- Stop ---
    uint256 public stopped;
    modifier stoppable { require(stopped == 0, "USM/is-stopped"); _; }

    uint8   public   referenceTokenPosition;
    uint16  constant ONE_HOUR = uint16(3600);
    uint16  public   updateDelay = ONE_HOUR;
    uint32  public   pairLatestTradeTime;
    uint64  public   lastUpdateTime;
    uint256 public   latestAccumulator;

    address public   referenceToken;

    IUniswapV2Pair private _priceSource;

    struct Feed {
        uint224 value;
        uint256 isValid;
    }

    Feed currentFeed;
    Feed nextFeed;

    event LogValue(bytes32 value);

    constructor (address counterpartyToken_, address referenceToken_, uint8 referenceTokenPosition_) public {
        authorizedAccounts[msg.sender] = 1;
        // Create pair
        referenceTokenPosition = referenceTokenPosition_;
        (address cToken, address rToken) = sortTokens(counterpartyToken_, referenceToken_);
        _priceSource = IUniswapV2Pair(pairFor(cToken, rToken));
        // Check pair
        (uint112 counterpartyReserve, uint112 referenceReserve, uint32 pairTime) = _priceSource.getReserves();
        require(counterpartyReserve != 0 && referenceReserve != 0, "USM/no-liquidity");
        require(pairLatestTradeTime != 0);
        // Store accumulator value
        latestAccumulator = (referenceTokenPosition == 0) ? _priceSource.price0CumulativeLast() : _priceSource.price1CumulativeLast();
        // Set remaining params
        referenceToken = rToken;
        pairLatestTradeTime = pairTime;
    }

    function stop() external emitLog isAuthorized {
        stopped = 1;
    }
    function start() external emitLog isAuthorized {
        stopped = 0;
    }

    function currentTime() internal view returns (uint) {
        return block.timestamp;
    }

    function latestUpdateTime(uint timestamp) internal view returns (uint64) {
        require(updateDelay != 0, "USM/update-delay-is-zero");
        return uint32(timestamp - (timestamp % updateDelay));
    }

    function changeDelay(uint16 delay) external isAuthorized {
        require(delay > 0, "USM/delay-is-zero");
        updateDelay = delay;
    }

    function restartValue() external emitLog isAuthorized {
        currentFeed = nextFeed = Feed(0, 0);
        stopped = 1;
    }

    function passedDelay() public view returns (bool ok) {
        return currentTime() >= addition(lastUpdateTime, updateDelay);
    }

    function updateResult() external emitLog stoppable {
        require(passedDelay(), "USM/delay-not-passed");
        uint32 adjustedCurrentTime = uint32(currentTime() % 2**32);
        uint32 pairTradeTimeGap = adjustedCurrentTime - pairLatestTradeTime; // overflow is desired

        uint currentAccumulator = (referenceTokenPosition == 0) ?
          _priceSource.price0CumulativeLast() : _priceSource.price1CumulativeLast();
        (uint112 reserve0, uint112 reserve1, uint32 pairTime) = _priceSource.getReserves();

        require(reserve0 != 0 && reserve1 != 0, "USM/no-pair-liquidity");
        if (pairTime != adjustedCurrentTime) {
            currentAccumulator += (referenceTokenPosition == 0) ?
              uint(UQ112x112.encode(reserve1).uqdiv(reserve0)) * pairTradeTimeGap : uint(UQ112x112.encode(reserve0).uqdiv(reserve1)) * pairTradeTimeGap;
        }

        latestAccumulator = currentAccumulator;
        currentFeed = nextFeed;
        nextFeed = Feed(uint224((currentAccumulator - latestAccumulator) / pairTradeTimeGap), 1);
        pairLatestTradeTime = adjustedCurrentTime;
        lastUpdateTime = latestUpdateTime(currentTime());
        emit LogValue(bytes32(uint(currentFeed.value)));
    }

    function getResultWithValidity() external view returns (bytes32, bool) {
        return (bytes32(uint(currentFeed.value)), currentFeed.isValid == 1);
    }

    function getNextResultWithValidity() external view returns (bytes32, bool) {
        return (bytes32(uint(nextFeed.value)), nextFeed.isValid == 1);
    }

    function read() external view returns (bytes32) {
        require(currentFeed.isValid == 1, "USM/no-current-value");
        return (bytes32(uint(currentFeed.value)));
    }

    function priceSource() external view returns (address) {
        return address(_priceSource);
    }
}
