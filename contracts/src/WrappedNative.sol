// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {TestAsset} from "./Types.sol";
// Fee WNT is backed by deposited testnet ETH. It has no public mint authority.
contract WrappedNative is TestAsset {
 constructor() TestAsset("Wrapped testnet ETH","WETH",18,address(0)){}
 function deposit() public payable {balanceOf[msg.sender]+=msg.value;totalSupply+=msg.value;emit Transfer(address(0),msg.sender,msg.value);}
 function withdraw(uint256 q) external {balanceOf[msg.sender]-=q;totalSupply-=q;emit Transfer(msg.sender,address(0),q);(bool ok,)=payable(msg.sender).call{value:q}("");require(ok,"native transfer");}
 receive() external payable {deposit();}
}
