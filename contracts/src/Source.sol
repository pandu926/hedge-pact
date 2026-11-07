// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {T,TestAsset,IERC} from "./Types.sol";
import {Engine,K,IData,IReader,IOrders,IDeposits,IAdl,IMarkets,IWrapped,Position,EventUtils,IBaseOrderUtils,IDepositUtils,OracleUtils,Market} from "./GmxInterfaces.sol";
import {Order} from "@gmx/order/Order.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract SandboxPrices {
 address public immutable factory=msg.sender;
 struct Price {uint256 value;uint64 time;}
 mapping(address=>Price) public prices;
 function set(address t,uint256 p) external {require(msg.sender==factory,"factory");prices[t]=Price(p,uint64(block.timestamp));}
 function getOraclePrice(address t,bytes calldata) external view returns(OracleUtils.ValidatedPrice memory){Price memory p=prices[t];require(p.value>0,"price");return OracleUtils.ValidatedPrice(t,p.value,p.value,p.time,address(this));}
 function shouldAdjustTimestamp() external pure returns(bool){return false;}
 function isChainlinkOnChainProvider() external pure returns(bool){return false;}
}
interface IPublisher {function publish(bytes32) external;}
contract SourceAccount {
 address public manager; bytes32 public id; address public factory; address public market; address public collateral;
 address public indexToken; Engine public engine; bool public armed; bool public retired; uint64 public expires;uint256 public createdBlock;
 function initialize(address m,bytes32 i,address mk,address c,address ix,Engine calldata e,uint64 expiry) external {
  require(factory==address(0),"initialized");factory=msg.sender;manager=m;id=i;market=mk;collateral=c;indexToken=ix;engine=e;expires=expiry;createdBlock=block.number;
 }
 function position() public view returns(Position.Props memory){return IReader(engine.reader).getPosition(engine.data,keccak256(abi.encode(address(this),market,collateral,false)));}
 function shortTokens() external view returns(uint256){return position().numbers.sizeInTokens;}
 function setArmed(bool b) external {require(msg.sender==factory && (!retired || !b),"factory");armed=b;}
 function afterOrderExecution(bytes32,EventUtils.EventLogData calldata order,EventUtils.EventLogData calldata) external {
  require(msg.sender==engine.orders || msg.sender==engine.adl || msg.sender==engine.executor,"handler");
  bool own;bool ownMarket;for(uint256 j;j<order.addressItems.items.length;j++){EventUtils.AddressKeyValue calldata x=order.addressItems.items[j];if(keccak256(bytes(x.key))==keccak256("account"))own=x.value==address(this);if(keccak256(bytes(x.key))==keccak256("market"))ownMarket=x.value==market;}
  require(own && ownMarket,"position");IPublisher(factory).publish(id);
 }
 function afterOrderCancellation(bytes32,EventUtils.EventLogData calldata,EventUtils.EventLogData calldata) external {require(msg.sender==engine.orders,"handler");IPublisher(factory).publish(id);}
 function afterOrderFrozen(bytes32,EventUtils.EventLogData calldata,EventUtils.EventLogData calldata) external {require(msg.sender==engine.orders,"handler");IPublisher(factory).publish(id);}
 function emergencyRetire() external {require(msg.sender==manager,"manager");armed=false;retired=true;}
 function withdraw() external {require(msg.sender==manager && retired && position().numbers.sizeInUsd==0,"close first");IERC(collateral).transfer(manager,IERC(collateral).balanceOf(address(this)));}
 receive() external payable {}
}
contract SourceFactory {
 using K for string;
 Engine public engine;SandboxPrices public immutable prices;address public immutable implementation;
 address public immutable admin; address public coordinator; uint64[3] public leases;mapping(bytes32=>uint256) public lastPublishedTokens;
 mapping(bytes32=>address) public accounts;mapping(address=>address[]) internal owned;
 mapping(address=>uint256) public nonces;mapping(bytes32=>uint64) public seq;mapping(bytes32=>uint8) public observations;
 mapping(bytes32=>bytes32) public pending;mapping(bytes32=>bytes32) public pendingDeposit;
 event SourceRegistered(bytes32 indexed id,address indexed manager,address account,uint64 expires);
 event ObservationPublished(bytes32 indexed id,uint64 indexed seq,bytes payload);
 event OrderCreated(bytes32 indexed id,bytes32 key,bool increase);
 constructor(Engine memory e){engine=e;admin=msg.sender;prices=new SandboxPrices();implementation=address(new SourceAccount());}
 function list(address m) external view returns(address[] memory){return owned[m];}
 function setCoordinator(address c) external {require(msg.sender==admin && coordinator==address(0),"admin");coordinator=c;}
 function create() external returns(address a){
  bool available;for(uint256 j;j<3;j++){if(leases[j]<block.timestamp){leases[j]=uint64(block.timestamp+900);available=true;break;}}require(available,"three sessions already active");uint256 nonce=nonces[msg.sender]++;bytes32 id=keccak256(abi.encode(uint256(84532),msg.sender,nonce));
  TestAsset ix=new TestAsset("Isolated sandbox ETH","sETH",18,address(this));TestAsset usd=new TestAsset("Isolated sandbox USD","sUSD",6,address(this));
  Market.Props memory mk=IMarkets(engine.markets).createMarket(address(ix),address(ix),address(usd),bytes32(0));
  a=Clones.clone(implementation);uint64 expiry=uint64(block.timestamp+900);
  SourceAccount(payable(a)).initialize(msg.sender,id,mk.marketToken,address(usd),address(ix),engine,expiry);
  accounts[id]=a;owned[msg.sender].push(a);_configureMarket(mk.marketToken,address(ix),address(usd),a);
  // The faucet is deliberately synthetic. The collateral and liquidity cannot represent user funds.
  usd.mint(address(this),100000e6);ix.mint(address(this),1000e18);usd.mint(address(this),2000000e6);
  prices.set(address(ix),5000e12);prices.set(address(usd),1e24);prices.set(engine.wnt,5000e12);
  emit SourceRegistered(id,msg.sender,a,expiry);
 }
 modifier owner(bytes32 id){require(accounts[id]!=address(0) && SourceAccount(payable(accounts[id])).manager()==msg.sender,"manager");_;}
 function seed(bytes32 id) external payable owner(id) {
  require(pendingDeposit[id]==bytes32(0),"pending");SourceAccount a=SourceAccount(payable(accounts[id]));address ix=a.indexToken();address usd=a.collateral();
  require(IData(engine.data).getUint(keccak256(abi.encode(K.k("POOL_AMOUNT"),a.market(),usd)))==0,"seeded");
  IERC(ix).transfer(engine.depositVault,1000e18);IERC(usd).transfer(engine.depositVault,2000000e6);_fee(engine.depositVault);
  IDepositUtils.CreateDepositParams memory p;p.addresses.receiver=address(a);p.addresses.market=a.market();p.addresses.initialLongToken=ix;p.addresses.initialShortToken=usd;p.executionFee=msg.value;
  pendingDeposit[id]=IDeposits(engine.deposits).createDeposit(address(a),0,p);
 }
 function executeSeed(bytes32 id) external owner(id){bytes32 key=pendingDeposit[id];require(key!=0,"seed");_touch(id);IDeposits(engine.deposits).executeDeposit(key,_oracle(id));pendingDeposit[id]=0;}
 function openShort(bytes32 id) external payable owner(id){SourceAccount a=SourceAccount(payable(accounts[id]));require(!a.armed() && !a.retired() && a.position().numbers.sizeInUsd==0 && pending[id]==0,"state");IERC(a.collateral()).transfer(engine.orderVault,100000e6);_createOrder(id,500000e30,true);}
 function closeShort(bytes32 id) external payable owner(id){SourceAccount a=SourceAccount(payable(accounts[id]));a.setArmed(false);_createOrder(id,a.position().numbers.sizeInUsd,false);}
 function _createOrder(bytes32 id,uint256 usd,bool increase) internal {
  require(pending[id]==0 && usd>0,"order");SourceAccount a=SourceAccount(payable(accounts[id]));_fee(engine.orderVault);
  IBaseOrderUtils.CreateOrderParams memory p;p.addresses.receiver=address(a);p.addresses.cancellationReceiver=address(a);p.addresses.callbackContract=address(a);p.addresses.market=a.market();p.addresses.initialCollateralToken=a.collateral();
  p.numbers.sizeDeltaUsd=usd;p.numbers.executionFee=msg.value;p.numbers.callbackGasLimit=700000;p.numbers.acceptablePrice=increase?0:type(uint256).max;p.orderType=increase?Order.OrderType.MarketIncrease:Order.OrderType.MarketDecrease;
  bytes32 key=IOrders(engine.orders).createOrder(address(a),0,p,false);pending[id]=key;emit OrderCreated(id,key,increase);
 }
 function execute(bytes32 id) external owner(id){bytes32 key=pending[id];require(key!=0,"pending");_touch(id);IOrders(engine.orders).executeOrder(key,_oracle(id));pending[id]=0;publish(id);}
 function arm(bytes32 id) external owner(id){SourceAccount a=SourceAccount(payable(accounts[id]));require(a.shortTokens()==100e18 && block.timestamp<a.expires() && coordinator!=address(0),"hedge/lease");a.setArmed(true);publish(id);}
 function disarm(bytes32 id) external owner(id){SourceAccount(payable(accounts[id])).setArmed(false);publish(id);}
 function adl(bytes32 id,uint256 reduceUsd) external owner(id){SourceAccount a=SourceAccount(payable(accounts[id]));require(a.armed() && reduceUsd>0 && block.timestamp<=a.expires(),"armed");
  prices.set(a.indexToken(),2500e12);prices.set(a.collateral(),1e24);prices.set(engine.wnt,5000e12);
  IAdl(engine.adl).updateAdlState(a.market(),false,_oracle(id));IAdl(engine.adl).executeAdl(address(a),a.market(),a.collateral(),false,reduceUsd,_oracle(id));publish(id);
 }
 function refresh(bytes32 id) external {require(accounts[id]!=address(0),"id");publish(id);}
 function publish(bytes32 id) public {
  SourceAccount a=SourceAccount(payable(accounts[id]));require(address(a)!=address(0),"id");uint256 q=a.shortTokens();require(msg.sender==address(a) || msg.sender==a.manager() || q!=lastPublishedTokens[id],"unchanged");lastPublishedTokens[id]=q;
  // Permissionless refresh reads current GMX truth. It never refreshes the oracle timestamp.
  if(observations[id]>=20 || block.timestamp>a.expires())return;
  ++observations[id];uint64 s=++seq[id];(uint256 p,uint64 pt)=prices.prices(a.indexToken());
  T.Observation memory o=T.Observation(id,s,uint64(block.timestamp),a.expires(),a.shortTokens(),p*1e6,5000e18,pt,a.armed() && !a.retired());
  emit ObservationPublished(id,s,abi.encode(o));
 }
 function _touch(bytes32 id) internal {SourceAccount a=SourceAccount(payable(accounts[id]));(uint256 p,)=prices.prices(a.indexToken());prices.set(a.indexToken(),p);prices.set(a.collateral(),1e24);prices.set(engine.wnt,5000e12);}
 function _oracle(bytes32 id) internal view returns(OracleUtils.SetPricesParams memory p){SourceAccount a=SourceAccount(payable(accounts[id]));p.tokens=new address[](3);p.providers=new address[](3);p.data=new bytes[](3);p.tokens[0]=a.indexToken();p.tokens[1]=a.collateral();p.tokens[2]=engine.wnt;for(uint256 i;i<3;i++)p.providers[i]=address(prices);}
 function _fee(address vault) internal {if(msg.value>0){IWrapped(engine.wnt).deposit{value:msg.value}();require(IWrapped(engine.wnt).transfer(vault,msg.value),"fee");}}
 function _configureMarket(address m,address ix,address usd,address a) internal {
  IData d=IData(engine.data);
  address[3] memory tokens=[ix,usd,engine.wnt];for(uint256 i;i<3;i++){d.setUint(K.token("TOKEN_TRANSFER_GAS_LIMIT",tokens[i]),200000);d.setAddress(keccak256(abi.encode(K.k("ORACLE_PROVIDER_FOR_TOKEN"),engine.oracle,tokens[i])),address(prices));}
  d.setBool(K.token("IS_ORACLE_PROVIDER_ENABLED",address(prices)),true);
  d.setAddress(keccak256(abi.encode(K.k("SAVED_CALLBACK_CONTRACT"),a,m)),a);
  d.setUint(K.token("MIN_COLLATERAL_FACTOR",m),1e28);
  for(uint256 i;i<2;i++){bool side=i==0;
   d.setUint(K.side("MAX_OPEN_INTEREST",m,side),10000000e30);d.setUint(K.side("RESERVE_FACTOR",m,side),9e29);d.setUint(K.side("OPEN_INTEREST_RESERVE_FACTOR",m,side),9e29);
   d.setUint(keccak256(abi.encode(K.k("MAX_PNL_FACTOR"),K.k("MAX_PNL_FACTOR_FOR_TRADERS"),m,side)),9e29);
   d.setUint(keccak256(abi.encode(K.k("MAX_PNL_FACTOR"),K.k("MAX_PNL_FACTOR_FOR_DEPOSITS"),m,side)),9e29);
   d.setUint(keccak256(abi.encode(K.k("MAX_PNL_FACTOR"),K.k("MAX_PNL_FACTOR_FOR_ADL"),m,side)),1e29);
   d.setUint(K.side("MIN_PNL_FACTOR_AFTER_ADL",m,side),2e28);
   d.setUint(keccak256(abi.encode(K.k("MAX_COLLATERAL_SUM"),m,ix,side)),type(uint128).max);d.setUint(keccak256(abi.encode(K.k("MAX_COLLATERAL_SUM"),m,usd,side)),type(uint128).max);
   address t=side?ix:usd;d.setUint(keccak256(abi.encode(K.k("MAX_POOL_AMOUNT"),m,t)),type(uint128).max);d.setUint(keccak256(abi.encode(K.k("MAX_POOL_USD_FOR_DEPOSIT"),m,t)),1e45);
  }
 }
}
