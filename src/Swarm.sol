// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ILaunchFactory {
    function distributorOf(uint64 launchNumber) external view returns (address);
}

/// @notice Fixed-supply mainnet token. Ordinary transfers send floor(amount / 100) to DEAD.
/// @dev Launch distribution and PoolManager settlement are exempt to preserve exact amounts.
contract Swarm is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 ether;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address public immutable factory;
    address public immutable poolManager;
    uint64 public immutable launchNumber;
    /// @notice Accumulated automatic 1% charges; excludes voluntary transfers to DEAD.
    uint256 public totalBurned;

    error MainnetOnly();
    error InvalidLaunchConfiguration();

    constructor(address factory_, address poolManager_, uint64 launchNumber_) ERC20("swarm", "SWARM") {
        if (block.chainid != 1) revert MainnetOnly();
        if (
            factory_ != msg.sender || factory_.code.length == 0 || poolManager_.code.length == 0
                || factory_ == poolManager_ || poolManager_ == DEAD
        ) revert InvalidLaunchConfiguration();
        factory = factory_;
        poolManager = poolManager_;
        launchNumber = launchNumber_;
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from != address(0) && !_exempt(from, to)) {
            uint256 burned = amount / 100;
            if (burned != 0) {
                totalBurned += burned;
                super._update(from, DEAD, burned);
                amount -= burned;
            }
        }
        super._update(from, to, amount);
    }

    function _exempt(address from, address to) private view returns (bool) {
        if (msg.sender == factory || from == poolManager || to == poolManager) return true;
        // Static, gas-bounded lookup: a missing or broken registry must not freeze holder transfers.
        bytes memory input = abi.encodeCall(ILaunchFactory.distributorOf, (launchNumber));
        address registry = factory;
        bool ok;
        uint256 distributor;
        // Copy at most one word, even if the factory returns excessive data.
        assembly ("memory-safe") {
            ok := staticcall(30000, registry, add(input, 32), mload(input), 0, 32)
            ok := and(ok, eq(returndatasize(), 32))
            distributor := mload(0)
        }
        if (!ok) return false;
        return distributor != 0 && distributor == uint256(uint160(msg.sender));
    }
}
