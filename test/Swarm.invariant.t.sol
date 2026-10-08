// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Swarm} from "../src/Swarm.sol";
import {LaunchHarness} from "./helpers/LaunchHarness.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

contract InvariantManagerCode {}

contract TransferHandler is Test {
    Swarm public immutable token;
    address[4] public holders;
    uint256 public lastBurned;

    constructor(Swarm token_) {
        token = token_;
        for (uint256 i; i < 4; ++i) {
            holders[i] = makeAddr(string.concat("holder-", vm.toString(i)));
        }
    }

    function transfer(uint256 senderSeed, uint256 recipientSeed, uint256 amountSeed) public {
        address from = holders[senderSeed % 4];
        address to = holders[recipientSeed % 4];
        uint256 amount = bound(amountSeed, 0, token.balanceOf(from));
        vm.prank(from);
        token.transfer(to, amount);
        _checkMonotonicBurn();
    }

    function transferFrom(uint256 senderSeed, uint256 recipientSeed, uint256 amountSeed) public {
        address from = holders[senderSeed % 4];
        address to = holders[recipientSeed % 4];
        uint256 amount = bound(amountSeed, 0, token.balanceOf(from));
        vm.prank(from);
        token.approve(address(this), amount);
        token.transferFrom(from, to, amount);
        assertEq(token.allowance(from, address(this)), 0);
        _checkMonotonicBurn();
    }

    function _checkMonotonicBurn() private {
        uint256 burned = token.totalBurned();
        assertGe(burned, lastBurned);
        lastBurned = burned;
    }
}

contract SwarmInvariantTest is StdInvariant, Test {
    Swarm token;
    TransferHandler handler;

    function setUp() public {
        vm.chainId(1);
        LaunchHarness factory = new LaunchHarness(IPoolManager(address(new InvariantManagerCode())));
        token = factory.deploy();
        handler = new TransferHandler(token);
        for (uint256 i; i < 4; ++i) {
            factory.move(handler.holders(i), token.totalSupply() / 4);
        }
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = TransferHandler.transfer.selector;
        selectors[1] = TransferHandler.transferFrom.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariantSupplyAndBurnAccounting() public view {
        uint256 sum = token.balanceOf(token.DEAD());
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.holders(i));
        }
        assertEq(sum, 1_000_000_000 ether);
        assertEq(token.totalSupply(), sum);
        assertEq(token.totalBurned(), token.balanceOf(token.DEAD()));
        assertEq(token.balanceOf(address(handler)), 0);
    }
}
