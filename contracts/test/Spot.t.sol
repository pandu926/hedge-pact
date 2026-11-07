// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
import {Test} from "forge-std/Test.sol";
import {T} from "../src/Types.sol";
import {SpotFactory,SpotVault} from "../src/Spot.sol";
import {Coordinator} from "../src/Coordinator.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {LocalProxy,PerpLocalSystem} from "./Transport.sol";

contract BillingProxy {
    receive() external payable {}
    function debt(address) external pure returns(uint256){return 0;}
    function deliver(address requester,address recipient,bytes memory payload) external returns(bool ok){assembly{mstore(add(payload,36),requester)}(ok,)=recipient.call(payload);if(ok)SpotVault(payable(recipient)).pay(1e12);}
}
contract SpotTest is Test {
    LocalProxy proxy;SpotFactory factory;SpotVault v;address rc=address(0xC0);bytes32 id;uint64 expiry;
    function setUp() public {vm.warp(1000);vm.deal(address(this),1 ether);proxy=new LocalProxy();factory=new SpotFactory(address(proxy),rc);id=keccak256(abi.encode(uint256(84532),address(this),uint256(0)));expiry=1900;v=SpotVault(payable(factory.create{value:0.001 ether}(0,address(0xAA),expiry)));_deliver(abi.encodeCall(v.bind,(address(0),address(0xAA),expiry)));}
    function _deliver(bytes memory payload) internal { (bool ok,bytes memory err)=proxy.deliver(rc,address(v),payload);if(!ok)assembly{revert(add(err,32),mload(err))} }
    function o(uint64 seq,uint256 target) internal view returns(T.Observation memory){return T.Observation(id,seq,uint64(block.timestamp),expiry,target,5000e18,5000e18,uint64(block.timestamp),true);}
    function _observe(uint64 seq,uint256 target) internal {_deliver(abi.encodeCall(v.receiveObservation,(address(0),o(seq,target))));}
    function testDestinationProxyCanCollectCallbackFee() public {
        BillingProxy billing=new BillingProxy();SpotFactory fundedFactory=new SpotFactory(address(billing),rc);
        SpotVault funded=SpotVault(payable(fundedFactory.create{value:0.001 ether}(0,address(0xAA),expiry)));
        assertTrue(billing.deliver(rc,address(funded),abi.encodeCall(funded.bind,(address(0),address(0xAA),expiry))));
        assertEq(address(billing).balance,1e12);assertEq(address(funded).balance,0.001 ether-1e12);
        vm.expectRevert();funded.pay(1);
    }
    function testFactoryRequiresCallbackGasReserve() public {vm.expectRevert();factory.create(1,address(0xAA),expiry);}
    function testActualSettlementAndBoundedTrade() public {_observe(1,60e18);(uint256 spot,uint256 usd)=v.balances();assertEq(spot,75e18);assertGt(usd,0);_deliver(abi.encodeCall(v.retry,(address(0),uint64(1))));(spot,)=v.balances();assertEq(spot,60e18);assertEq(uint256(v.mode()),uint256(T.Mode.Normal));}
    function testDuplicateAndOutOfOrderCannotOversell() public {_observe(2,80e18);_observe(1,0);_observe(2,0);assertEq(v.asset().balanceOf(address(v)),80e18);}
    function testSmallCrossChainClockSkewAccepted() public {T.Observation memory obs=o(1,80e18);obs.time=1002;_deliver(abi.encodeCall(v.receiveObservation,(address(0),obs)));assertEq(v.asset().balanceOf(address(v)),80e18);}
    function testExcessiveFutureObservationRejected() public {T.Observation memory obs=o(1,0);obs.time=1011;(bool ok,)=proxy.deliver(rc,address(v),abi.encodeCall(v.receiveObservation,(address(0),obs)));assertFalse(ok);}
    function testWrongStrategyRejected() public {T.Observation memory obs=o(1,0);obs.id=bytes32(uint256(2));(bool ok,)=proxy.deliver(rc,address(v),abi.encodeCall(v.receiveObservation,(address(0),obs)));assertFalse(ok);}
    function testProxyAndSenderBothAuthenticated() public {vm.expectRevert();v.receiveObservation(rc,o(1,0));(bool ok,)=proxy.deliver(address(0xBAD),address(v),abi.encodeCall(v.receiveObservation,(address(0),o(1,0))));assertFalse(ok);}
    function testPriceDisagreementQuarantinesWithoutTrade() public {v.scenario(1);_observe(1,60e18);assertEq(uint256(v.mode()),uint256(T.Mode.Quarantine));assertEq(v.asset().balanceOf(address(v)),100e18);assertTrue(v.intakeClosed());}
    function testStaleReferenceNoTrade() public {v.scenario(2);_observe(1,60e18);assertEq(v.asset().balanceOf(address(v)),100e18);assertEq(uint256(v.mode()),2);}
    function testSwapFailureKeepsActualBalanceThenRetrySettles() public {v.scenario(4);_observe(1,80e18);assertEq(v.asset().balanceOf(address(v)),100e18);v.scenario(0);_deliver(abi.encodeCall(v.retry,(address(0),uint64(1))));assertEq(v.asset().balanceOf(address(v)),80e18);}
    function testThinLiquiditySlippageNoTrade() public {v.scenario(3);_observe(1,80e18);assertEq(v.asset().balanceOf(address(v)),100e18);}
    function testRecoveryNeedsCurrentApprovalAndThreeSpacedObservations() public {v.scenario(1);_observe(1,80e18);v.scenario(0);v.approveRecovery(1);_observe(2,80e18);vm.warp(1015);_observe(3,80e18);assertEq(v.asset().balanceOf(address(v)),100e18);vm.warp(1031);_observe(4,80e18);assertEq(v.asset().balanceOf(address(v)),80e18);v.scenario(1);_observe(5,60e18);assertEq(v.incident(),2);assertEq(v.approvedIncident(),0);}
    function testCannotPreapproveFutureIncident() public {vm.expectRevert();v.approveRecovery(1);}
    function testRetryCannotRefreshStaleObservation() public {v.scenario(4);_observe(1,80e18);v.scenario(0);vm.warp(1121);_deliver(abi.encodeCall(v.retry,(address(0),uint64(1))));assertEq(v.asset().balanceOf(address(v)),100e18);}
    function testExpiryDisablesTrading() public {vm.warp(1901);_observe(1,60e18);assertEq(v.asset().balanceOf(address(v)),100e18);}
    function testTwoUsersIsolatedAndIdentifierCannotBeSquatted() public {vm.deal(address(0xBEEF),1 ether);vm.prank(address(0xBEEF));SpotVault b=SpotVault(payable(factory.create{value:0.001 ether}(0,address(0xBB),expiry)));assertTrue(b.id()!=id);vm.prank(address(0xBEEF));vm.expectRevert();v.scenario(4);_observe(1,80e18);assertEq(b.asset().balanceOf(address(b)),100e18);}
    function testEmergencyLocalWithdraw() public {vm.expectRevert();v.withdraw();v.emergencyRetire();v.withdraw();assertEq(v.asset().balanceOf(address(this)),100e18);assertTrue(v.closed());}
    function testFuzzSettlementNeverBelowRemoteShort(uint96 q) public {uint256 target=bound(uint256(q),0,100e18);_observe(1,target);for(uint256 i;i<4;i++)_deliver(abi.encodeCall(v.retry,(address(0),uint64(1))));assertGe(v.asset().balanceOf(address(v)),target);}
}
contract CoordinatorTest is Test {
    PerpLocalSystem sys;LocalProxy proxy;Coordinator c;SpotFactory sf;SpotVault v;
    address publisher=address(0x123);bytes32 id;uint64 expiry;
    function setUp() public {vm.warp(1000);vm.chainId(5318007);PerpLocalSystem template=new PerpLocalSystem();vm.etch(address(0x8888888888888888888888888888888888888888),address(template).code);sys=PerpLocalSystem(address(0x8888888888888888888888888888888888888888));proxy=new LocalProxy();sys.setProxy(1301,proxy);vm.deal(address(this),10 ether);c=new Coordinator{value:1 ether}();sf=new SpotFactory(address(proxy),address(c));c.configure(publisher,address(sf));id=keccak256(abi.encode(uint256(84532),address(this),uint256(0)));expiry=1900;v=SpotVault(payable(sf.create{value:0.001 ether}(0,address(0xAA),expiry)));}
    function record(uint256 chain,address emitter,string memory signature,uint256 topic2,bytes memory data) internal view returns(IReactive.LogRecord memory r){r.chainId=chain;r.contractAddress=emitter;r.topic0=uint256(keccak256(bytes(signature)));r.topic1=uint256(id);r.topic2=topic2;r.data=data;r.opCode=3;}
    function bind() internal {sys.forward(c,record(84532,publisher,"SourceRegistered(bytes32,address,address,uint64)",uint256(uint160(address(this))),abi.encode(address(0xAA),expiry)));sys.forward(c,record(1301,address(sf),"DestinationRegistered(bytes32,address,address,address,uint64)",uint256(uint160(address(this))),abi.encode(address(v),address(0xAA),expiry)));(bool ok,)=sys.deliver(0);assertTrue(ok);}
    function observe(uint64 seq) internal {T.Observation memory o=T.Observation(id,seq,uint64(block.timestamp),expiry,60e18,5000e18,5000e18,uint64(block.timestamp),true);sys.forward(c,record(84532,publisher,"ObservationPublished(bytes32,uint64,bytes)",seq,abi.encode(abi.encode(o))));}
    function cron() internal {IReactive.LogRecord memory r;r.chainId=5318007;r.contractAddress=0x0000000000000000000000000000000000fffFfF;r.topic0=0xf02d6ea5c22a71cffe930a4523fcb4f129be6c804db50e4202fb4e0b07ccb514;sys.forward(c,r);}
    function testRegistrationAndActualCrossChainSettlement() public {bind();observe(1);assertTrue(c.cronActive());for(uint256 i=1;i<sys.count();i++){(bool ok,)=sys.deliver(i);assertTrue(ok);}assertEq(v.asset().balanceOf(address(v)),75e18);vm.warp(1006);uint256 start=sys.count();cron();for(uint256 i=start;i<sys.count();i++){(bool ok,)=sys.deliver(i);assertTrue(ok);}assertEq(v.asset().balanceOf(address(v)),60e18);sys.forward(c,record(1301,address(sf),"Acknowledged(bytes32,uint64,uint256,uint256,uint8,bool)",1,abi.encode(60e18,60e18,T.Mode.Normal,false)));assertFalse(c.cronActive());}
    function testMissingAckBoundedRetriesStopCron() public {bind();observe(1);for(uint256 i;i<4;i++){vm.warp(1006+i*6);cron();}assertFalse(c.cronActive());assertLt(sys.count(),15);}
    function testSourceRegistrationToleratesSmallChainClockSkew() public {expiry=1902;bind();assertEq(v.source(),address(0xAA));}
    function testWrongPublisherIgnored() public {bind();IReactive.LogRecord memory r=record(84532,address(0xBAD),"ObservationPublished(bytes32,uint64,bytes)",1,abi.encode(bytes("")));sys.forward(c,r);assertEq(sys.count(),1);}
    function testUnboundObservationIgnored() public {observe(1);assertEq(sys.count(),0);}
    function testRejectDirectReactiveCall() public {vm.expectRevert();c.react(record(1,publisher,"x",0,bytes("")));}
    function testExpiredSessionStops() public {bind();observe(1);vm.warp(1901);cron();assertFalse(c.cronActive());}
}
