// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {T} from "./Types.sol";
import {SpotVault} from "./Spot.sol";

contract Coordinator is AbstractReactive {
    uint256 constant SOURCE=84532;uint256 constant DEST=1301;
    uint256 constant REG_S=uint256(keccak256("SourceRegistered(bytes32,address,address,uint64)"));
    uint256 constant REG_D=uint256(keccak256("DestinationRegistered(bytes32,address,address,address,uint64)"));
    uint256 constant OBS=uint256(keccak256("ObservationPublished(bytes32,uint64,bytes)"));
    uint256 constant ACK=uint256(keccak256("Acknowledged(bytes32,uint64,uint256,uint256,uint8,bool)"));
    uint256 constant CRON=0xf02d6ea5c22a71cffe930a4523fcb4f129be6c804db50e4202fb4e0b07ccb514;
    address constant CRON_SOURCE=0x0000000000000000000000000000000000fffFfF;
    address public immutable manager=msg.sender;
    address public publisher;address public destinationFactory;bool public retired;bool public cronActive;
    struct Session {address owner;address account;address vault;address destinationOwner;address claimedSource;uint64 expiry;uint64 destinationExpiry;uint64 seq;uint64 retryAt;uint8 retries;bool bound;bool pending;T.Observation latest;}
    mapping(bytes32=>Session) public sessions;bytes32[3] public slots;
    event DecisionRequested(bytes32 indexed id,uint64 indexed seq,address vault,uint256 target,uint256 sourceTxHash);
    event ReceiptAccepted(bytes32 indexed id,uint64 indexed seq,uint256 spot,uint256 target,bool retryNeeded);
    event SessionBound(bytes32 indexed id,address source,address vault);
    event RetryExhausted(bytes32 indexed id,uint64 seq);
    constructor() payable {}
    function configure(address p,address d) external {require(msg.sender==manager && publisher==address(0),"manager");publisher=p;destinationFactory=d;
        SYSTEM.subscribe(SOURCE,p,REG_S,REACTIVE_IGNORE,REACTIVE_IGNORE,REACTIVE_IGNORE);
        SYSTEM.subscribe(SOURCE,p,OBS,REACTIVE_IGNORE,REACTIVE_IGNORE,REACTIVE_IGNORE);
        SYSTEM.subscribe(DEST,d,REG_D,REACTIVE_IGNORE,REACTIVE_IGNORE,REACTIVE_IGNORE);
        SYSTEM.subscribe(DEST,d,ACK,REACTIVE_IGNORE,REACTIVE_IGNORE,REACTIVE_IGNORE);
    }
    function react(LogRecord calldata r) external onlySystem {
        if(retired)return;
        if(r.chainId==block.chainid && r.contractAddress==CRON_SOURCE && r.topic0==CRON){_tick();return;}
        bytes32 id=bytes32(r.topic1);Session storage s=sessions[id];
        if(r.chainId==SOURCE && r.contractAddress==publisher && r.topic0==REG_S){
            (address account,uint64 expiry)=abi.decode(r.data,(address,uint64));
            if(s.account!=address(0) || expiry<=block.timestamp || expiry>block.timestamp+960)return;
            bool available;for(uint256 i;i<3;i++){if(slots[i]==bytes32(0) || sessions[slots[i]].expiry<block.timestamp){slots[i]=id;available=true;break;}}
            if(!available || address(this).balance<0.05 ether)return;
            s.owner=address(uint160(r.topic2));s.account=account;s.expiry=expiry;_bind(id,s);return;
        }
        if(r.chainId==DEST && r.contractAddress==destinationFactory && r.topic0==REG_D){
            if(s.vault!=address(0))return;
            (address vault,address source,uint64 expiry)=abi.decode(r.data,(address,address,uint64));
            s.destinationOwner=address(uint160(r.topic2));s.claimedSource=source;s.vault=vault;s.destinationExpiry=expiry;_bind(id,s);return;
        }
        if(!s.bound || s.expiry<block.timestamp)return;
        if(r.chainId==SOURCE && r.contractAddress==publisher && r.topic0==OBS){
            bytes memory raw=abi.decode(r.data,(bytes));T.Observation memory o=abi.decode(raw,(T.Observation));
            if(o.id!=id || o.seq<=s.seq || o.seq!=r.topic2 || o.time>block.timestamp+10 || o.time+120<block.timestamp || o.expires!=s.expiry)return;
            s.latest=o;s.seq=o.seq;s.retries=0;s.pending=true;s.retryAt=uint64(block.timestamp+5);
            _deliver(s);_cron(true);emit DecisionRequested(id,o.seq,s.vault,o.shortTokens,r.txHash);return;
        }
        if(r.chainId==DEST && r.contractAddress==destinationFactory && r.topic0==ACK){
            (uint256 spot,uint256 target,T.Mode mode,bool again)=abi.decode(r.data,(uint256,uint256,T.Mode,bool));
            if(r.topic2!=s.seq || !s.pending || target!=s.latest.shortTokens)return;
            s.pending=again && mode!=T.Mode.Quarantine && mode!=T.Mode.Recovery;
            emit ReceiptAccepted(id,s.seq,spot,target,s.pending);_syncCron();
        }
    }
    function _bind(bytes32 id,Session storage s) internal {
        if(s.bound || s.account==address(0) || s.vault==address(0) || s.owner!=s.destinationOwner || s.account!=s.claimedSource || s.expiry!=s.destinationExpiry)return;
        s.bound=true;SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0(DEST,s.vault,250000,abi.encodeCall(SpotVault.bind,(address(0),s.account,s.expiry))));emit SessionBound(id,s.account,s.vault);
    }
    function _deliver(Session storage s) internal {SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0(DEST,s.vault,250000,abi.encodeCall(SpotVault.bind,(address(0),s.account,s.expiry))));SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0(DEST,s.vault,700000,abi.encodeCall(SpotVault.receiveObservation,(address(0),s.latest))));}
    function _tick() internal {
        for(uint256 i;i<3;i++){bytes32 id=slots[i];if(id==0)continue;Session storage s=sessions[id];if(!s.pending)continue;
            if(block.timestamp>s.expiry || block.timestamp>s.latest.time+120 || s.retries>=3){s.pending=false;emit RetryExhausted(id,s.seq);continue;}
            if(block.timestamp<s.retryAt)continue;++s.retries;s.retryAt=uint64(block.timestamp+5);
            // A duplicate initial delivery is harmless; once the vault has accepted it, retry progresses actual settlement.
            _deliver(s);SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0(DEST,s.vault,700000,abi.encodeCall(SpotVault.retry,(address(0),s.seq))));
        }_syncCron();
    }
    function _syncCron() internal {bool pending;for(uint256 i;i<3;i++)if(sessions[slots[i]].pending)pending=true;_cron(pending);}
    function _cron(bool enabled) internal {if(enabled==cronActive)return;cronActive=enabled;if(enabled)SYSTEM.subscribe(block.chainid,CRON_SOURCE,CRON,REACTIVE_IGNORE,REACTIVE_IGNORE,REACTIVE_IGNORE);else SYSTEM.unsubscribe(block.chainid,CRON_SOURCE,CRON,REACTIVE_IGNORE,REACTIVE_IGNORE,REACTIVE_IGNORE);}
    function retire() external {require(msg.sender==manager && !retired,"manager");retired=true;_cron(false);
        SYSTEM.unsubscribe(SOURCE,publisher,REG_S,REACTIVE_IGNORE,REACTIVE_IGNORE,REACTIVE_IGNORE);SYSTEM.unsubscribe(SOURCE,publisher,OBS,REACTIVE_IGNORE,REACTIVE_IGNORE,REACTIVE_IGNORE);
        SYSTEM.unsubscribe(DEST,destinationFactory,REG_D,REACTIVE_IGNORE,REACTIVE_IGNORE,REACTIVE_IGNORE);SYSTEM.unsubscribe(DEST,destinationFactory,ACK,REACTIVE_IGNORE,REACTIVE_IGNORE,REACTIVE_IGNORE);
    }
    function withdrawRetired() external {require(msg.sender==manager && retired,"manager");_coverDebt();(bool ok,)=payable(manager).call{value:address(this).balance}("");require(ok,"withdraw");}
}
