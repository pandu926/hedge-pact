// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {Position} from "@gmx/position/Position.sol";
import {EventUtils} from "@gmx/event/EventUtils.sol";
import {IBaseOrderUtils} from "@gmx/order/IBaseOrderUtils.sol";
import {IDepositUtils} from "@gmx/deposit/IDepositUtils.sol";
import {OracleUtils} from "@gmx/oracle/OracleUtils.sol";
import {Market} from "@gmx/market/Market.sol";
interface IData {
 function setUint(bytes32,uint256) external; function setAddress(bytes32,address) external; function setBool(bytes32,bool) external;
 function getUint(bytes32) external view returns(uint256);function getBytes32Count(bytes32) external view returns(uint256);
}
interface IReader {function getPosition(address,bytes32) external view returns(Position.Props memory);}
interface IOrders {
 function createOrder(address,uint256,IBaseOrderUtils.CreateOrderParams calldata,bool) external returns(bytes32);
 function executeOrder(bytes32,OracleUtils.SetPricesParams calldata) external;
}
interface IDeposits {
 function createDeposit(address,uint256,IDepositUtils.CreateDepositParams calldata) external returns(bytes32);
 function executeDeposit(bytes32,OracleUtils.SetPricesParams calldata) external;
}
interface IAdl {
 function updateAdlState(address,bool,OracleUtils.SetPricesParams calldata) external;
 function executeAdl(address,address,address,bool,uint256,OracleUtils.SetPricesParams calldata) external;
}
interface IMarkets {function createMarket(address,address,address,bytes32) external returns(Market.Props memory);}
interface IWrapped {function deposit() external payable;function transfer(address,uint256) external returns(bool);}
library K {
 function k(string memory s) internal pure returns(bytes32){return keccak256(abi.encode(s));}
 function token(string memory s,address t) internal pure returns(bytes32){return keccak256(abi.encode(k(s),t));}
 function side(string memory s,address m,bool b) internal pure returns(bytes32){return keccak256(abi.encode(k(s),m,b));}
}
struct Engine {
 address data; address reader; address orders; address orderVault; address deposits; address depositVault;
 address adl; address markets; address oracle; address wnt; address executor;
}
