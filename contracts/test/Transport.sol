// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";

contract LocalProxy {
    function deliver(address requester, address recipient, bytes memory payload)
        external
        returns (bool ok, bytes memory result)
    {
        require(payload.length >= 36, "payload");
        assembly { mstore(add(payload, 36), requester) }
        (ok, result) = recipient.call(payload);
    }
}

contract LocalSystem {
    struct Request {
        address requester;
        uint256 chainId;
        address recipient;
        bytes payload;
    }

    Request[] internal requests;
    mapping(uint256 => LocalProxy) public proxies;

    function setProxy(uint256 chainId, LocalProxy proxy) external {
        proxies[chainId] = proxy;
    }

    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {}

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 calldata c) external {
        requests.push(Request(msg.sender, c.chainId, c.recipient, c.payload));
    }

    function count() external view returns (uint256) {
        return requests.length;
    }

    function forward(IReactive recipient, IReactive.LogRecord calldata record) external {
        recipient.react(record);
    }

    function deliver(uint256 index) external returns (bool, bytes memory) {
        Request storage r = requests[index];
        return proxies[r.chainId].deliver(r.requester, r.recipient, r.payload);
    }
}

/// @notice Inherits the existing LOCAL transport; no network/finality/fees are reproduced.
contract PerpLocalSystem is LocalSystem {
    uint256 public unsubscriptions;

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        ++unsubscriptions;
    }
}

interface VmPerp {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function etch(address target, bytes calldata code) external;
    function warp(uint256 timestamp) external;
    function prank(address sender) external;
    function expectRevert() external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}
