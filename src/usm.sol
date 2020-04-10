pragma solidity >=0.5.15;

import "./uni/UniswapV2Library.sol";
import "./uni/UQ112x112.sol";

contract LibNote {
    event LogNote(
        bytes4   indexed  sig,
        address  indexed  usr,
        bytes32  indexed  arg1,
        bytes32  indexed  arg2,
        bytes             data
    ) anonymous;

    modifier note {
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

contract USM is UniswapV2Library, LibNote {
    using UQ112x112 for uint224;

    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "USM/not-authorized");
        _;
    }

    // --- Stop ---
    uint256 public stopped;
    modifier stoppable { require(stopped == 0, "USM/is-stopped"); _; }

    uint8   public   side;
    uint16  constant ONE_HOUR = uint16(3600);
    uint16  public   hop = ONE_HOUR;
    uint32  public   rho;
    uint64  public   zzz;
    uint256 public   last;

    address public main;
    address public ref;

    IUniswapV2Pair public pair;

    struct Feed {
        uint224 val;
        uint256 has;
    }

    Feed cur;
    Feed nxt;

    event LogValue(bytes32 val);

    constructor (address main_, address ref_, uint8 side_) public {
        wards[msg.sender] = 1;
        // Create pair
        side = side_;
        (main, ref) = sortTokens(main_, ref_);
        pair = IUniswapV2Pair(pairFor(main, ref));
        // Check pair
        uint112 mainReserve;
        uint112 refReserve;
        (mainReserve, refReserve, rho) = pair.getReserves();
        require(mainReserve != 0 && refReserve != 0, "USM/no-liquidity");
        require(rho != 0);
        // Store accumulator value
        last = (side == 0) ? pair.price0CumulativeLast() : pair.price1CumulativeLast();
    }

    function stop() external note auth {
        stopped = 1;
    }
    function start() external note auth {
        stopped = 0;
    }

    function era() internal view returns (uint) {
        return block.timestamp;
    }

    function prev(uint ts) internal view returns (uint64) {
        require(hop != 0, "USM/hop-is-zero");
        return uint32(ts - (ts % hop));
    }

    function step(uint16 ts) external auth {
        require(ts > 0, "USM/ts-is-zero");
        hop = ts;
    }

    function void() external note auth {
        cur = nxt = Feed(0, 0);
        stopped = 1;
    }

    function pass() public view returns (bool ok) {
        return era() >= add(zzz, hop);
    }

    function poke() external note stoppable {
        require(pass(), "USM/not-passed");
        uint32 late = uint32(era() % 2**32);
        uint32 gap = late - rho; // overflow is desired

        uint acc = (side == 0) ? pair.price0CumulativeLast() : pair.price1CumulativeLast();
        (uint112 reserve0, uint112 reserve1, uint32 pairTime) = pair.getReserves();

        require(reserve0 != 0 && reserve1 != 0, "USM/no-pair-liquidity");
        if (pairTime != late) {
            acc += (side == 0) ? uint(UQ112x112.encode(reserve1).uqdiv(reserve0)) * gap : uint(UQ112x112.encode(reserve0).uqdiv(reserve1)) * gap;
        }

        last = acc;
        cur = nxt;
        nxt = Feed(uint224((acc - last) / gap), 1);
        rho = late;
        zzz = prev(era());
        emit LogValue(bytes32(uint(cur.val)));
    }

    function peek() external view returns (bytes32,bool) {
        return (bytes32(uint(cur.val)), cur.has == 1);
    }

    function peep() external view returns (bytes32,bool) {
        return (bytes32(uint(nxt.val)), nxt.has == 1);
    }

    function read() external view returns (bytes32) {
        require(cur.has == 1, "USM/no-current-value");
        return (bytes32(uint(cur.val)));
    }
}
