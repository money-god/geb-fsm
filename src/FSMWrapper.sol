pragma solidity 0.6.7;

import "geb-treasury-reimbursement/reimbursement/NoSetupIncreasingTreasuryReimbursement.sol";

abstract contract FSMLike {
    function stopped() virtual public view returns (uint256);
    function priceSource() virtual public view returns (address);
    function updateDelay() virtual public view returns (uint16);
    function lastUpdateTime() virtual public view returns (uint64);
    function newPriceDeviation() virtual public view returns (uint256);
    function passedDelay() virtual public view returns (bool);
    function getNextBoundedPrice() virtual public view returns (uint128);
    function getNextPriceLowerBound() virtual public view returns (uint128);
    function getNextPriceUpperBound() virtual public view returns (uint128);
    function getResultWithValidity() virtual external view returns (uint256, bool);
    function getNextResultWithValidity() virtual external view returns (uint256, bool);
    function read() virtual external view returns (uint256);
}

contract FSMWrapper is NoSetupIncreasingTreasuryReimbursement {
    // --- Vars ---
    // When the rate has last been relayed
    uint256 public lastReimburseTime;       // [timestamp]
    // Enforced gap between reimbursements
    uint256 public reimburseDelay;          // [seconds]

    FSMLike public fsm;

    constructor(address fsm_, uint256 reimburseDelay_) public NoSetupIncreasingTreasuryReimbursement() {
        require(fsm_ != address(0), "FSMWrapper/null-fsm");

        fsm            = FSMLike(fsm_);
        reimburseDelay = reimburseDelay_;

        emit ModifyParameters("reimburseDelay", reimburseDelay);
    }

    // --- Administration ---
    /*
    * @notice Change the addresses of contracts that this wrapper is connected to
    * @param parameter The contract whose address is changed
    * @param addr The new contract address
    */
    function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
        require(addr != address(0), "FSMWrapper/null-addr");
        if (parameter == "fsm") {
          fsm = FSMLike(addr);
        }
        else if (parameter == "treasury") {
          require(StabilityFeeTreasuryLike(addr).systemCoin() != address(0), "FSMWrapper/treasury-coin-not-set");
          treasury = StabilityFeeTreasuryLike(addr);
        }
        else revert("FSMWrapper/modify-unrecognized-param");
        emit ModifyParameters(
          parameter,
          addr
        );
    }
    /*
    * @notify Modify a uint256 parameter
    * @param parameter The parameter name
    * @param val The new parameter value
    */
    function modifyParameters(bytes32 parameter, uint256 val) external isAuthorized {
        if (parameter == "baseUpdateCallerReward") {
          require(val <= maxUpdateCallerReward, "FSMWrapper/invalid-base-caller-reward");
          baseUpdateCallerReward = val;
        }
        else if (parameter == "maxUpdateCallerReward") {
          require(val >= baseUpdateCallerReward, "FSMWrapper/invalid-max-caller-reward");
          maxUpdateCallerReward = val;
        }
        else if (parameter == "perSecondCallerRewardIncrease") {
          require(val >= RAY, "FSMWrapper/invalid-caller-reward-increase");
          perSecondCallerRewardIncrease = val;
        }
        else if (parameter == "maxRewardIncreaseDelay") {
          require(val > 0, "FSMWrapper/invalid-max-increase-delay");
          maxRewardIncreaseDelay = val;
        }
        else if (parameter == "reimburseDelay") {
          reimburseDelay = val;
        }
        else revert("FSMWrapper/modify-unrecognized-param");
        emit ModifyParameters(
          parameter,
          val
        );
    }

    // --- Renumeration Logic ---
    /*
    * @notice Renumerate the caller that updates the connected FSM
    * @param feeReceiver The address that will receive the reward for the update
    */
    function renumerateCaller(address feeReceiver) external {
        // Perform checks
        require(address(fsm) == msg.sender, "FSMWrapper/invalid-caller");
        require(feeReceiver != address(0), "FSMWrapper/null-fee-receiver");
        // Check delay between calls
        require(either(subtract(now, lastReimburseTime) >= reimburseDelay, lastReimburseTime == 0), "FSMWrapper/wait-more");
        // Get the caller's reward
        uint256 callerReward = getCallerReward(lastReimburseTime, reimburseDelay);
        // Store the timestamp of the update
        lastReimburseTime = now;
        // Pay the caller for updating the FSM
        rewardCaller(feeReceiver, callerReward);
    }

    // --- Wrapped Functionality ---
    /*
    * @notify Return whether the FSM is stopped
    */
    function stopped() public view returns (uint256) {
        return fsm.stopped();
    }
    /*
    * @notify Return the FSM price source
    */
    function priceSource() public view returns (address) {
        return fsm.priceSource();
    }
    /*
    * @notify Return the FSM update delay
    */
    function updateDelay() public view returns (uint16) {
        return fsm.updateDelay();
    }
    /*
    * @notify Return the FSM last update time
    */
    function lastUpdateTime() public view returns (uint64) {
        return fsm.lastUpdateTime();
    }
    /*
    * @notify Return the FSM's next price deviation
    */
    function newPriceDeviation() public view returns (uint256) {
        return fsm.newPriceDeviation();
    }
    /*
    * @notify Return whether the update delay has been passed in the FSM
    */
    function passedDelay() public view returns (bool) {
        return fsm.passedDelay();
    }
    /*
    * @notify Return the next bounded price from the FSM
    */
    function getNextBoundedPrice() public view returns (uint128) {
        return fsm.getNextBoundedPrice();
    }
    /*
    * @notify Return the next lower bound price from the FSM
    */
    function getNextPriceLowerBound() public view returns (uint128) {
        return fsm.getNextPriceLowerBound();
    }
    /*
    * @notify Return the next upper bound price from the FSM
    */
    function getNextPriceUpperBound() public view returns (uint128) {
        return fsm.getNextPriceUpperBound();
    }
    /*
    * @notify Return the result with its validity from the FSM
    */
    function getResultWithValidity() external view returns (uint256, bool) {
        (uint256 price, bool valid) = fsm.getResultWithValidity();
        return (price, valid);
    }
    /*
    * @notify Return the next result with its validity from the FSM
    */
    function getNextResultWithValidity() external view returns (uint256, bool) {
        (uint256 price, bool valid) = fsm.getNextResultWithValidity();
        return (price, valid);
    }
    /*
    * @notify Return the result from the FSM if it's valid
    */
    function read() external view returns (uint256) {
        return fsm.read();
    }
}
