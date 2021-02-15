pragma solidity 0.6.7;

import "geb-treasury-reimbursement/NoSetupIncreasingTreasuryReimbursement.sol";

abstract contract DSValueLike {
    function getResultWithValidity() virtual external view returns (uint256, bool);
}

contract OSM is NoSetupIncreasingTreasuryReimbursement {
    // --- Stop ---
    uint256 public stopped;
    modifier stoppable { require(stopped == 0, "OSM/is-stopped"); _; }

    // --- Variables ---
    address public priceSource;
    uint16  constant ONE_HOUR = uint16(3600);
    uint16  public updateDelay = ONE_HOUR;
    uint64  public lastUpdateTime;

    // --- Structs ---
    struct Feed {
        uint128 value;
        uint128 isValid;
    }

    Feed currentFeed;
    Feed nextFeed;

    // --- Events ---
    event ModifyParameters(bytes32 parameter, uint256 val);
    event Start();
    event Stop();
    event ChangePriceSource(address priceSource);
    event ChangeDelay(uint16 delay);
    event RestartValue();
    event UpdateResult(uint256 newMedian, uint256 lastUpdateTime);

    constructor (address priceSource_) public {
        authorizedAccounts[msg.sender] = 1;
        priceSource = priceSource_;
        if (priceSource != address(0)) {
          (uint256 priceFeedValue, bool hasValidValue) = getPriceSourceUpdate();
          if (hasValidValue) {
            nextFeed = Feed(uint128(uint(priceFeedValue)), 1);
            currentFeed = nextFeed;
            lastUpdateTime = latestUpdateTime(currentTime());
            emit UpdateResult(uint(currentFeed.value), lastUpdateTime);
          }
        }
        emit AddAuthorization(msg.sender);
        emit ChangePriceSource(priceSource);
    }

    // --- Administration ---
    /*
    * @notify Modify a uint256 parameter
    * @param parameter The parameter name
    * @param val The new value for the parameter
    */
    function modifyParameters(bytes32 parameter, uint256 val) external isAuthorized {
        if (parameter == "baseUpdateCallerReward") {
          require(val < maxUpdateCallerReward, "OSM/invalid-base-caller-reward");
          baseUpdateCallerReward = val;
        }
        else if (parameter == "maxUpdateCallerReward") {
          require(val >= baseUpdateCallerReward, "OSM/invalid-max-reward");
          maxUpdateCallerReward = val;
        }
        else if (parameter == "perSecondCallerRewardIncrease") {
          require(val >= RAY, "OSM/invalid-reward-increase");
          perSecondCallerRewardIncrease = val;
        }
        else if (parameter == "maxRewardIncreaseDelay") {
          require(val > 0, "OSM/invalid-max-increase-delay");
          maxRewardIncreaseDelay = val;
        }
        else revert("OSM/modify-unrecognized-param");
        emit ModifyParameters(parameter, val);
    }

    // --- Math ---
    function add(uint64 x, uint64 y) internal pure returns (uint64 z) {
        z = x + y;
        require(z >= x);
    }

    // --- Core Logic ---
    /*
    * @notify Stop the DSM
    */
    function stop() external isAuthorized {
        stopped = 1;
        emit Stop();
    }
    /*
    * @notify Start the DSM
    */
    function start() external isAuthorized {
        stopped = 0;
        emit Start();
    }

    /*
    * @notify Change the oracle from which the DSM reads
    * @param priceSource_ The address of the oracle from which the DSM reads
    */
    function changePriceSource(address priceSource_) external isAuthorized {
        priceSource = priceSource_;
        emit ChangePriceSource(priceSource);
    }

    /*
    * @notify Helper that returns the current block timestamp
    */
    function currentTime() internal view returns (uint) {
        return block.timestamp;
    }

    /*
    * @notify Return the latest update time
    * @param timestamp Custom reference timestamp to determine the latest update time from
    */
    function latestUpdateTime(uint timestamp) internal view returns (uint64) {
        require(updateDelay != 0, "OSM/update-delay-is-zero");
        return uint64(timestamp - (timestamp % updateDelay));
    }

    /*
    * @notify Change the delay between updates
    * @param delay The new delay
    */
    function changeDelay(uint16 delay) external isAuthorized {
        require(delay > 0, "OSM/delay-is-zero");
        updateDelay = delay;
        emit ChangeDelay(updateDelay);
    }

    /*
    * @notify Restart/set to zero the feeds stored in the DSM
    */
    function restartValue() external isAuthorized {
        currentFeed = nextFeed = Feed(0, 0);
        stopped = 1;
        emit RestartValue();
    }

    /*
    * @notify View function that returns whether the delay between calls has been passed
    */
    function passedDelay() public view returns (bool ok) {
        return currentTime() >= uint(add(lastUpdateTime, uint64(updateDelay)));
    }

    /*
    * @notify Update the price feeds inside the DSM
    */
    function updateResult() external stoppable {
        // Check if the delay passed
        require(passedDelay(), "OSM/not-passed");
        // Read the price from the median
        (uint256 priceFeedValue, bool hasValidValue) = getPriceSourceUpdate();
        // If the value is valid, update storage
        if (hasValidValue) {
            // Get the caller's reward
            uint256 callerReward = getCallerReward(lastUpdateTime, updateDelay);
            // Update state
            currentFeed = nextFeed;
            nextFeed = Feed(uint128(uint(priceFeedValue)), 1);
            lastUpdateTime = latestUpdateTime(currentTime());
            // Emit event
            emit UpdateResult(uint(currentFeed.value), lastUpdateTime);
            // Pay the caller
            rewardCaller(msg.sender, callerReward);
        }
    }

    // --- Getters ---
    /*
    * @notify Internal helper that reads a price and its validity from the priceSource
    */
    function getPriceSourceUpdate() internal view returns (uint256, bool) {
        try DSValueLike(priceSource).getResultWithValidity() returns (uint256 priceFeedValue, bool hasValidValue) {
          return (priceFeedValue, hasValidValue);
        }
        catch(bytes memory) {
          return (0, false);
        }
    }
    /*
    * @notify Return the current feed value and its validity
    */
    function getResultWithValidity() external view returns (uint256,bool) {
        return (uint(currentFeed.value), currentFeed.isValid == 1);
    }
    /*
    * @notify Return the next feed's value and its validity
    */
    function getNextResultWithValidity() external view returns (uint256,bool) {
        return (nextFeed.value, nextFeed.isValid == 1);
    }
    /*
    * @notify Return the current feed's value only if it's valid, otherwise revert
    */
    function read() external view returns (uint256) {
        require(currentFeed.isValid == 1, "OSM/no-current-value");
        return currentFeed.value;
    }
}
