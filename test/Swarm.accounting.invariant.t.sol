// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Swarm} from "src/Swarm.sol";
import {LaunchHarness} from "./helpers/LaunchHarness.sol";

contract AccountingManagerCode {}

/// @dev Ghosts start from the known allocation and change only after a successful operation.
/// No balance or allowance expectation is copied from the token's observed post-state.
contract SwarmAccountingHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 ether;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    Swarm public immutable token;
    address public immutable distributor;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public expectedBurned;
    uint256 public voluntaryDeadReceipts;

    constructor(Swarm token_, address distributor_) {
        token = token_;
        distributor = distributor_;
        for (uint256 i; i < 4; ++i) {
            actors[i] = makeAddr(string.concat("accounting actor ", vm.toString(i)));
            expectedBalance[actors[i]] = SUPPLY / 5;
        }
        expectedBalance[distributor] = SUPPLY / 5;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % 4];
        address to = _recipient(toSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % 4];
        address to = _recipient(toSeed);
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 amount = mode % 3 == 0 ? 0 : mode % 3 == 1 ? type(uint256).max : bound(amountSeed, 0, SUPPLY);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spendAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = _recipient(toSeed);
        uint256 allowed = expectedAllowance[from][spender];
        uint256 maximum = expectedBalance[from] < allowed ? expectedBalance[from] : allowed;
        uint256 amount = bound(amountSeed, 0, maximum);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (allowed != type(uint256).max) expectedAllowance[from][spender] -= amount;
        _recordTransfer(from, to, amount);
    }

    function unauthorizedSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address from = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = _recipient(toSeed);
        // Revoke first so every generated call exercises a failure, including self-spending.
        vm.prank(from);
        token.approve(spender, 0);
        expectedAllowance[from][spender] = 0;
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(from, to, 1);
    }

    function overdraw(uint256 fromSeed, uint256 toSeed, uint256 excessSeed) external {
        address from = actors[fromSeed % 4];
        address to = _recipient(toSeed);
        uint256 amount = expectedBalance[from] + bound(excessSeed, 1, SUPPLY);
        vm.prank(from);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        token.transfer(to, amount);
    }

    function invalidRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        token.approve(spender, amount);
        expectedAllowance[from][spender] = amount;
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(from, address(0), amount);
    }

    function claim(uint256 toSeed, uint256 amountSeed) external {
        address to = actors[toSeed % 4];
        uint256 amount = bound(amountSeed, 0, expectedBalance[distributor]);
        vm.prank(distributor);
        assertTrue(token.transfer(to, amount));
        // Protected launch requirement: claims arrive whole.
        expectedBalance[distributor] -= amount;
        expectedBalance[to] += amount;
    }

    function _recipient(uint256 seed) private view returns (address) {
        return seed % 5 == 4 ? DEAD : actors[seed % 5];
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        uint256 charge = amount / 100;
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount - charge;
        expectedBalance[DEAD] += charge;
        expectedBurned += charge;
        if (to == DEAD) voluntaryDeadReceipts += amount - charge;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract SwarmAccountingInvariantTest is StdInvariant, Test {
    Swarm token;
    LaunchHarness factory;
    SwarmAccountingHandler handler;
    address distributor = makeAddr("accounting distributor");

    function setUp() public {
        vm.chainId(1);
        factory = new LaunchHarness(IPoolManager(address(new AccountingManagerCode())));
        token = factory.deploy();
        factory.setDistributor(distributor);
        handler = new SwarmAccountingHandler(token, distributor);
        for (uint256 i; i < 4; ++i) {
            factory.move(handler.actors(i), 200_000_000 ether);
        }
        factory.move(distributor, 200_000_000 ether);

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.transferFullBalance.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.spendAllowance.selector;
        selectors[4] = handler.unauthorizedSpend.selector;
        selectors[5] = handler.overdraw.selector;
        selectors[6] = handler.invalidRecipient.selector;
        selectors[7] = handler.claim.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariantIndividualBalancesAndAllowancesMatchIndependentLedger() public view {
        uint256 sum = token.balanceOf(token.DEAD()) + token.balanceOf(distributor);
        assertEq(token.balanceOf(distributor), handler.expectedBalance(distributor));
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "actor balance drift");
            sum += token.balanceOf(actor);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender), "allowance drift");
            }
        }
        assertEq(sum, 1_000_000_000 ether);
        assertEq(token.totalSupply(), sum);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(token.poolManager()), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariantBurnCounterAndSinkIncludeExactlyTheirRespectiveReceipts() public view {
        assertEq(token.totalBurned(), handler.expectedBurned());
        assertEq(token.balanceOf(token.DEAD()), handler.expectedBalance(token.DEAD()));
        assertEq(token.balanceOf(token.DEAD()), token.totalBurned() + handler.voluntaryDeadReceipts());
    }

    function testHandlerExercisesAllowanceLifecycleAndFailureRollback() public {
        handler.approve(0, 1, 1000, 2);
        handler.spendAllowance(0, 1, 2, 100);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), 900);
        handler.unauthorizedSpend(0, 1, 2);
        handler.invalidRecipient(0, 1, 100);
        handler.overdraw(0, 0, 1);
        handler.claim(3, 1000);
        handler.transfer(3, 4, 100);
        handler.transferFullBalance(2, 2);
        invariantIndividualBalancesAndAllowancesMatchIndependentLedger();
        invariantBurnCounterAndSinkIncludeExactlyTheirRespectiveReceipts();
        assertGt(token.totalBurned(), 0);
    }
}
