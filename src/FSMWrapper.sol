pragma solidity 0.6.7;

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

contract FSMWrapper {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
    * @notice Add auth to an account
    * @param account Account to add auth to
    */
    function addAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 1;
        emit AddAuthorization(account);
    }
    /**
    * @notice Remove auth from an account
    * @param account Account to remove auth from
    */
    function removeAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 0;
        emit RemoveAuthorization(account);
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "FSMWrapper/account-not-authorized");
        _;
    }

    // --- Vars ---
    FSMLike public fsm;

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event ModifyParameters(bytes32 parameter, address addr);

    constructor(address fsm_) public {
        authorizedAccounts[msg.sender] = 1;
        require(fsm_ != address(0), "FSMWrapper/null-fsm");
        fsm = FSMLike(fsm_);
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
        if (parameter == "fsm") {
          require(addr != address(0), "FSMWrapper/null-fsm");
          fsm = FSMLike(addr);
        }
        else revert("FSMWrapper/modify-unrecognized-param");
    }

    // --- Wrapped Functionality ---
    function stopped() public view returns (uint256) {
        return fsm.stopped();
    }
    function priceSource() public view returns (address) {
        return fsm.priceSource();
    }
    function updateDelay() public view returns (uint16) {
        return fsm.updateDelay();
    }
    function lastUpdateTime() public view returns (uint64) {
        return fsm.lastUpdateTime();
    }
    function newPriceDeviation() public view returns (uint256) {
        return fsm.newPriceDeviation();
    }
    function passedDelay() public view returns (bool) {
        return fsm.passedDelay();
    }
    function getNextBoundedPrice() public view returns (uint128) {
        return fsm.getNextBoundedPrice();
    }
    function getNextPriceLowerBound() public view returns (uint128) {
        return fsm.getNextPriceLowerBound();
    }
    function getNextPriceUpperBound() public view returns (uint128) {
        return fsm.getNextPriceUpperBound();
    }
    function getResultWithValidity() external view returns (uint256, bool) {
        (uint256 price, bool valid) = fsm.getResultWithValidity();
        return (price, valid);
    }
    function getNextResultWithValidity() external view returns (uint256, bool) {
        (uint256 price, bool valid) = fsm.getNextResultWithValidity();
        return (price, valid);
    }
    function read() external view returns (uint256) {
        return fsm.read();
    }
}
