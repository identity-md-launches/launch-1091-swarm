// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Swarm} from "src/Swarm.sol";

contract BudgetManagerCode {}

/// @dev A factory whose distributor lookup costs a configurable amount of gas. The token's budget for
/// that lookup is fixed in its bytecode, and a lookup that exceeds it silently taxes claims instead
/// of reverting, so the boundary is pinned here from both sides.
contract BudgetedRegistry {
    uint64 public constant NUMBER = 42;
    Swarm public token;
    address public distributor;
    uint256 public lookupCost;

    /// @dev The token requires its factory to have code, so it cannot be built from a constructor.
    function deploy(address manager) external returns (Swarm) {
        token = new Swarm(address(this), manager, NUMBER);
        return token;
    }

    function configure(address distributor_, uint256 lookupCost_) external {
        distributor = distributor_;
        lookupCost = lookupCost_;
    }

    function move(address to, uint256 amount) external {
        token.transfer(to, amount);
    }

    function distributorOf(uint64 number) external view returns (address) {
        uint256 start = gasleft();
        uint256 cost = lookupCost;
        if (start < cost) {
            while (true) {}
        }
        while (start - gasleft() < cost) {}
        return number == NUMBER ? distributor : address(0);
    }
}

/// @dev A distributor that forwards a chosen gas stipend to its claim transfer, modelling a claimant
/// who submits the claim with a tight gas limit.
contract StingyDistributor {
    Swarm private immutable token;

    constructor(Swarm token_) {
        token = token_;
    }

    function claim(address to, uint256 amount, uint256 gasLimit) external returns (bool ok) {
        (ok,) = address(token).call{gas: gasLimit}(abi.encodeCall(token.transfer, (to, amount)));
    }
}

/// forge-config: default.fuzz.runs = 1000
contract SwarmLookupBudgetTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 ether;
    uint256 constant CLAIM = 1_000_000 ether;
    BudgetedRegistry registry;
    Swarm token;
    StingyDistributor stingy;
    address manager;
    address distributor = makeAddr("budget distributor");
    address claimant = makeAddr("budget claimant");
    address holder = makeAddr("budget holder");
    address other = makeAddr("budget other");

    function setUp() public {
        vm.chainId(1);
        manager = address(new BudgetManagerCode());
        registry = new BudgetedRegistry();
        token = registry.deploy(manager);
        stingy = new StingyDistributor(token);
        registry.move(distributor, SUPPLY / 10);
        registry.move(address(stingy), SUPPLY / 10);
        registry.move(holder, SUPPLY / 10);
    }

    function testDeploymentUnderTheBudgetedRegistry() public view {
        assertEq(token.factory(), address(registry));
        assertEq(token.launchNumber(), 42);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalBurned(), 0);
    }

    function testPinnedBudgetEdges() public {
        uint256[4] memory costs = [uint256(0), 45_000, 95_000, 105_000];
        bool[4] memory exempt = [true, true, true, false];
        for (uint256 i; i < costs.length; ++i) {
            uint256 snapshot = vm.snapshotState();
            registry.configure(distributor, costs[i]);
            vm.prank(distributor);
            assertTrue(token.transfer(claimant, CLAIM));
            if (exempt[i]) {
                assertEq(token.balanceOf(claimant), CLAIM, "a lookup inside the budget taxed the claim");
                assertEq(token.totalBurned(), 0);
            } else {
                assertEq(token.balanceOf(claimant), CLAIM - CLAIM / 100, "an over-budget lookup must fall back");
                assertEq(token.totalBurned(), CLAIM / 100);
            }
            assertTrue(vm.revertToStateAndDelete(snapshot));
        }
    }

    function testFuzzLookupInsideTheBudgetExemptsClaimsAndTaxesOrdinaryTransfers(uint256 costSeed) public {
        registry.configure(distributor, bound(costSeed, 0, 95_000));
        vm.prank(distributor);
        assertTrue(token.transfer(claimant, CLAIM));
        assertEq(token.balanceOf(claimant), CLAIM);
        assertEq(token.balanceOf(distributor), SUPPLY / 10 - CLAIM);
        assertEq(token.totalBurned(), 0);
        vm.prank(holder);
        assertTrue(token.transfer(other, 100 ether));
        assertEq(token.balanceOf(other), 99 ether);
        assertEq(token.totalBurned(), 1 ether);
    }

    /// @dev The documented fallback: a registry the token cannot afford to consult does not freeze
    /// transfers, but every claim through it loses 1% with no revert or event to say so.
    function testFuzzLookupOverTheBudgetSilentlyTaxesClaims(uint256 costSeed) public {
        registry.configure(distributor, bound(costSeed, 105_000, 5_000_000));
        vm.prank(distributor);
        assertTrue(token.transfer(claimant, CLAIM));
        assertEq(token.balanceOf(claimant), CLAIM - CLAIM / 100);
        assertEq(token.balanceOf(token.DEAD()), CLAIM / 100);
        assertEq(token.totalBurned(), CLAIM / 100);
        vm.prank(holder);
        assertTrue(token.transfer(other, 100 ether));
        assertEq(token.balanceOf(other), 99 ether);
    }

    /// @dev A claim submitted with too little gas must revert whole rather than complete taxed: the
    /// lookup forwards at most 63/64 of what remains, and a registry that runs out consumes all of
    /// it, so nothing is left to finish a transfer on the burn path.
    function testFuzzScarceClaimGasNeverTurnsAClaimIntoATaxedTransfer(uint256 costSeed, uint256 gasSeed) public {
        registry.configure(address(stingy), bound(costSeed, 0, 95_000));
        uint256 gasLimit = bound(gasSeed, 0, 250_000);
        uint256 beforeBurned = token.totalBurned();
        bool ok = stingy.claim(claimant, CLAIM, gasLimit);
        if (ok) {
            assertEq(token.balanceOf(claimant), CLAIM, "a claim that went through arrived short");
            assertEq(token.balanceOf(address(stingy)), SUPPLY / 10 - CLAIM);
        } else {
            assertEq(token.balanceOf(claimant), 0, "a failed claim moved tokens");
            assertEq(token.balanceOf(address(stingy)), SUPPLY / 10);
        }
        assertEq(token.totalBurned(), beforeBurned, "a claim was charged");
        assertEq(token.balanceOf(token.DEAD()), 0);
    }

    function testTightClaimGasRevertsWholeAndGenerousClaimGasSucceedsWhole() public {
        registry.configure(address(stingy), 45_000);
        assertFalse(stingy.claim(claimant, CLAIM, 30_000), "a 30,000-gas claim cannot complete");
        assertEq(token.balanceOf(claimant), 0);
        assertEq(token.balanceOf(address(stingy)), SUPPLY / 10);
        assertEq(token.totalBurned(), 0);
        assertTrue(stingy.claim(claimant, CLAIM, 400_000));
        assertEq(token.balanceOf(claimant), CLAIM);
        assertEq(token.totalBurned(), 0);
    }

    function testRegistryAnsweringZeroDistributorGrantsNothing() public {
        registry.configure(distributor, 0);
        vm.mockCall(
            address(registry), abi.encodeWithSignature("distributorOf(uint64)", uint64(42)), abi.encode(address(0))
        );
        vm.prank(distributor);
        assertTrue(token.transfer(claimant, CLAIM));
        vm.clearMockedCalls();
        assertEq(token.balanceOf(claimant), CLAIM - CLAIM / 100, "an unregistered launch number exempted a claim");
        assertEq(token.totalBurned(), CLAIM / 100);
    }
}
