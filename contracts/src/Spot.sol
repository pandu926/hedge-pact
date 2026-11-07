// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {T,IERC,TestAsset} from "./Types.sol";
import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";

// Isolated constant-product sandbox pool. Only its vault can sell into this pool.
contract SpotPool {
    IERC public immutable asset; IERC public immutable stable;
    address public immutable vault;
    bool public failSwaps;
    constructor(address a,address s,address v){asset=IERC(a);stable=IERC(s);vault=v;}
    function setFault(bool f) external {require(msg.sender==vault,"vault");failSwaps=f;}
    function quote(uint256 q) public view returns(uint256){uint256 x=asset.balanceOf(address(this));uint256 y=stable.balanceOf(address(this));return y*q*997/(x*1000+q*997);}
    function sell(uint256 q,uint256 minOut) external returns(uint256 out){
        require(msg.sender==vault && !failSwaps,"swap disabled");out=quote(q);require(out>=minOut && out>0,"slippage");
        require(asset.transferFrom(msg.sender,address(this),q) && stable.transfer(msg.sender,out),"transfer");
    }
    function drain(address to,uint256 q) external {require(msg.sender==vault,"vault");require(stable.transfer(to,q),"transfer");}
}
interface ISpotFactory {function acknowledge(bytes32,uint64,uint256,uint256,T.Mode,bool) external;}

contract SpotVault is AbstractCallback {
    address public immutable manager; bytes32 public immutable id;
    address public immutable factory; address public immutable proxy; address public immutable coordinator;
    TestAsset public immutable asset; TestAsset public immutable stable; SpotPool public immutable pool;
    uint256 public immutable createdBlock;
    address public source;
    uint64 public lastSeq; uint64 public lastSourceTime; uint64 public expires;
    uint64 public incident; uint64 public approvedIncident; uint64 public healthySince; uint8 public healthyCount;
    T.Mode public mode; bool public active; bool public everArmed; bool public intakeClosed; bool public closed;
    uint256 public target; uint256 public refPrice=5000e18; uint64 public refTime;
    T.Observation internal latest;
    event Bound(bytes32 indexed id,address source);
    event Settled(bytes32 indexed id,uint64 indexed seq,uint256 sold,uint256 received,uint256 spot,uint256 target,T.Mode mode,bool retry);
    event Incident(uint64 indexed incident,T.Mode mode,bytes32 reason);
    modifier owner(){require(msg.sender==manager,"manager");_;}
    modifier callback(address r){require(msg.sender==proxy && r==coordinator,"callback");_;}
    constructor(address m,bytes32 i,address p,address c) payable AbstractCallback(IPayable(payable(p)),c){
        manager=m;id=i;factory=msg.sender;proxy=p;coordinator=c;createdBlock=block.number;refTime=uint64(block.timestamp);
        asset=new TestAsset("Hedge Pact sandbox ETH","hpETH",18,address(this));
        stable=new TestAsset("Hedge Pact sandbox USD","hpUSD",6,address(this));pool=new SpotPool(address(asset),address(stable),address(this));
        asset.mint(address(this),100e18);asset.mint(address(pool),100000e18);stable.mint(address(pool),500000000e6);
        asset.approve(address(pool),type(uint256).max);
    }
    function bind(address r,address s,uint64 e) external callback(r){require(!closed && s!=address(0) && e>block.timestamp,"bind");if(source!=address(0)){require(source==s && expires==e,"binding");return;}source=s;expires=e;emit Bound(id,s);}
    function setReference(uint256 price) external owner {require(price>0,"price");refPrice=price;refTime=uint64(block.timestamp);uint256 desired=asset.balanceOf(address(pool))*price/1e30;uint256 current=stable.balanceOf(address(pool));if(desired>current)stable.mint(address(pool),desired-current);else if(current>desired)pool.drain(manager,current-desired);}
    function scenario(uint8 kind) external owner {
        require(!closed,"closed");
        if(kind==0){pool.setFault(false);refPrice=5000e18;refTime=uint64(block.timestamp);}
        else if(kind==1){refPrice=7000e18;refTime=uint64(block.timestamp);}
        else if(kind==2){refTime=0;}
        else if(kind==3){pool.drain(manager,stable.balanceOf(address(pool))*99/100);}
        else if(kind==4){pool.setFault(true);}
        else revert("scenario");
    }
    function approveRecovery(uint64 current) external owner {require(current==incident && current!=0,"incident");approvedIncident=current;}
    function receiveObservation(address r,T.Observation calldata o) external callback(r){
        require(o.id==id && source!=address(0) && !closed,"strategy");
        if(o.seq<=lastSeq)return;
        require(o.time<=block.timestamp+10 && o.expires==expires,"time");
        lastSeq=o.seq;lastSourceTime=o.time;latest=o;target=o.shortTokens;if(o.armed)everArmed=true;active=o.armed || (everArmed && o.shortTokens==0);
        if(!active || block.timestamp>expires || block.timestamp>o.time+120){_quarantine("STALE_OR_INACTIVE");_ack(0,0,false);return;}
        uint256 diff=o.venuePrice>refPrice?o.venuePrice-refPrice:refPrice-o.venuePrice;
        if(refPrice==0 || block.timestamp>refTime+120 || block.timestamp>o.priceTime+120 || diff*10000>refPrice*200){_quarantine("REFERENCE_UNSAFE");_ack(0,0,false);return;}
        // A quarantined incident requires fresh observations over time AND a manager's current-incident approval.
        if(mode==T.Mode.Quarantine || mode==T.Mode.Recovery){
            mode=T.Mode.Recovery;intakeClosed=true;
            if(healthyCount==0)healthySince=uint64(block.timestamp);++healthyCount;
            if(healthyCount<3 || block.timestamp<healthySince+30 || approvedIncident!=incident){_ack(0,0,false);return;}
        }
        _settle();
    }
    function retry(address r,uint64 seq) external callback(r){
        if(closed || seq!=lastSeq || !active || block.timestamp>expires || block.timestamp>latest.time+120 || mode==T.Mode.Quarantine || mode==T.Mode.Recovery)return;
        uint256 diff=latest.venuePrice>refPrice?latest.venuePrice-refPrice:refPrice-latest.venuePrice;
        if(block.timestamp>refTime+120 || refPrice==0 || diff*10000>refPrice*200){_quarantine("REFERENCE_UNSAFE");_ack(0,0,false);return;}_settle();
    }
    function _settle() internal {
        uint256 spot=asset.balanceOf(address(this));uint256 q=spot>target?spot-target:0;
        if(q==0){mode=T.Mode.Normal;intakeClosed=false;_ack(0,0,false);return;}
        intakeClosed=true;mode=T.Mode.Defensive;if(q>25e18)q=25e18;
        // 18-decimal ETH * 18-decimal USD / 1e30 => 6-decimal stable.
        uint256 minOut=q*refPrice*9900/10000/1e30;
        try pool.sell(q,minOut) returns(uint256 out){_ack(q,out,asset.balanceOf(address(this))>target);}
        catch{mode=T.Mode.Watch;_ack(0,0,true);}
    }
    function _quarantine(bytes32 why) internal {if(mode!=T.Mode.Quarantine && mode!=T.Mode.Recovery){++incident;approvedIncident=0;}healthyCount=0;healthySince=0;mode=T.Mode.Quarantine;intakeClosed=true;emit Incident(incident,mode,why);}
    function _ack(uint256 q,uint256 out,bool retryNeeded) internal {
        uint256 spot=asset.balanceOf(address(this));
        if(!retryNeeded && spot<=target && mode==T.Mode.Defensive){mode=T.Mode.Normal;intakeClosed=false;}
        emit Settled(id,lastSeq,q,out,spot,target,mode,retryNeeded);
        ISpotFactory(factory).acknowledge(id,lastSeq,spot,target,mode,retryNeeded);
    }
    // Retiring is chain-local. A live GMX hedge on the source must be closed separately.
    function emergencyRetire() external owner {closed=true;active=false;intakeClosed=true;mode=T.Mode.Closed;}
    function withdraw() external owner {require(closed,"retire first");asset.transfer(manager,asset.balanceOf(address(this)));stable.transfer(manager,stable.balanceOf(address(this)));}
    function withdrawGas() external owner {require(closed,"retire first");_coverDebt();(bool ok,)=payable(manager).call{value:address(this).balance}("");require(ok,"gas refund");}
    function balances() external view returns(uint256,uint256){return(asset.balanceOf(address(this)),stable.balanceOf(address(this)));}
}

contract SpotFactory {
    address public immutable proxy; address public immutable coordinator;
    mapping(bytes32=>address) public vaults; mapping(address=>address[]) internal owned;
    event DestinationRegistered(bytes32 indexed id,address indexed manager,address vault,address source,uint64 expires);
    event Acknowledged(bytes32 indexed id,uint64 indexed seq,uint256 spot,uint256 target,T.Mode mode,bool retryNeeded);
    constructor(address p,address c){proxy=p;coordinator=c;}
    // id is authenticated by the source registration before bind succeeds.
    function create(uint256 nonce,address source,uint64 expires) external payable returns(address v){require(msg.value>=0.00005 ether,"callback gas reserve");bytes32 id=keccak256(abi.encode(uint256(84532),msg.sender,nonce));require(vaults[id]==address(0) && source!=address(0),"exists/source");v=address(new SpotVault{value:msg.value}(msg.sender,id,proxy,coordinator));vaults[id]=v;owned[msg.sender].push(v);emit DestinationRegistered(id,msg.sender,v,source,expires);}
    function list(address owner) external view returns(address[] memory){return owned[owner];}
    function acknowledge(bytes32 id,uint64 seq,uint256 spot,uint256 target,T.Mode mode,bool retryNeeded) external {require(vaults[id]==msg.sender,"vault");emit Acknowledged(id,seq,spot,target,mode,retryNeeded);}
}
