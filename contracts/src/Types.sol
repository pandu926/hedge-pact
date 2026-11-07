// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

library T {
    enum Mode { Normal, Watch, Quarantine, Defensive, Recovery, Closed }
    struct Observation {
        bytes32 id;
        uint64 seq;
        uint64 time;
        uint64 expires;
        uint256 shortTokens;
        uint256 venuePrice;
        uint256 refPrice;
        uint64 priceTime;
        bool armed;
    }
}
interface IERC {
    function balanceOf(address) external view returns(uint256);
    function transfer(address,uint256) external returns(bool);
    function approve(address,uint256) external returns(bool);
    function transferFrom(address,address,uint256) external returns(bool);
}
// These tokens are explicitly synthetic test assets; they have no backing or value.
contract TestAsset {
    string public name; string public symbol; uint8 public immutable decimals;
    address public immutable minter;
    uint256 public totalSupply;
    mapping(address=>uint256) public balanceOf;
    mapping(address=>mapping(address=>uint256)) public allowance;
    event Transfer(address indexed from,address indexed to,uint256 value);
    event Approval(address indexed owner,address indexed spender,uint256 value);
    constructor(string memory n,string memory s,uint8 d,address m){name=n;symbol=s;decimals=d;minter=m;}
    function mint(address a,uint256 q) external {require(msg.sender==minter,"minter");balanceOf[a]+=q;totalSupply+=q;emit Transfer(address(0),a,q);}
    function approve(address a,uint256 q) external returns(bool){allowance[msg.sender][a]=q;emit Approval(msg.sender,a,q);return true;}
    function transfer(address a,uint256 q) external returns(bool){_move(msg.sender,a,q);return true;}
    function transferFrom(address f,address a,uint256 q) external returns(bool){if(allowance[f][msg.sender]!=type(uint256).max)allowance[f][msg.sender]-=q;_move(f,a,q);return true;}
    function _move(address f,address a,uint256 q) internal {require(a!=address(0),"zero");balanceOf[f]-=q;balanceOf[a]+=q;emit Transfer(f,a,q);}
}
