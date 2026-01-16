// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";

/**
 * @title MockPolicyEngine
 * @notice Mock implementation of ACE PolicyEngine for testing the adapter.
 * @dev Allows configuring check() behavior to simulate various policy scenarios:
 *      - Allow all transfers (default)
 *      - Reject all transfers
 *      - Reject specific addresses (from or to)
 *      - Reject amounts above a threshold
 *      - Track call counts for verification
 */
contract MockPolicyEngine is IPolicyEngine {
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Whether to reject all check() calls
    bool public rejectAll;

    /// @notice Whether to revert with unknown error instead of PolicyRejected
    bool public revertWithUnknownError;

    /// @notice Maximum allowed transfer amount (0 = no limit)
    uint256 public maxAmount;

    /// @notice Addresses that are blocked from sending
    mapping(address => bool) public blockedFrom;

    /// @notice Addresses that are blocked from receiving
    mapping(address => bool) public blockedTo;

    /// @notice Counter for check() calls
    uint256 public checkCallCount;

    /// @notice Counter for run() calls
    uint256 public runCallCount;

    /// @notice Last payload received by check()
    Payload public lastCheckPayload;

    /// @notice Last payload received by run()
    Payload public lastRunPayload;

    /// @notice State variable that can be modified by run() to test VIEW limitation
    uint256 public stateModifiedByRun;

    /// @notice Custom rejection message
    string public rejectionMessage = "Transfer rejected by policy";

    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIGURATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sets whether to reject all transfers.
     * @param _reject True to reject all, false to allow
     */
    function setRejectAll(bool _reject) external {
        rejectAll = _reject;
    }

    /**
     * @notice Sets whether to revert with unknown error instead of PolicyRejected.
     * @param _revertUnknown True to use unknown error
     */
    function setRevertWithUnknownError(bool _revertUnknown) external {
        revertWithUnknownError = _revertUnknown;
    }

    /**
     * @notice Sets the maximum allowed transfer amount.
     * @param _maxAmount Maximum amount (0 = no limit)
     */
    function setMaxAmount(uint256 _maxAmount) external {
        maxAmount = _maxAmount;
    }

    /**
     * @notice Blocks or unblocks an address from sending.
     * @param addr The address to configure
     * @param blocked True to block, false to allow
     */
    function setBlockedFrom(address addr, bool blocked) external {
        blockedFrom[addr] = blocked;
    }

    /**
     * @notice Blocks or unblocks an address from receiving.
     * @param addr The address to configure
     * @param blocked True to block, false to allow
     */
    function setBlockedTo(address addr, bool blocked) external {
        blockedTo[addr] = blocked;
    }

    /**
     * @notice Sets a custom rejection message.
     * @param _message The rejection message
     */
    function setRejectionMessage(string calldata _message) external {
        rejectionMessage = _message;
    }

    /**
     * @notice Resets all call counters.
     */
    function resetCounters() external {
        checkCallCount = 0;
        runCallCount = 0;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // IPOLICYENGINE IMPLEMENTATION
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @inheritdoc IPolicyEngine
     * @dev View-only policy check. Does NOT modify state.
     */
    function check(Payload calldata payload) external view override {
        // Note: We can't increment checkCallCount here because this is a view function
        // For testing, we track this via lastCheckPayload comparison

        // Check rejection conditions
        _validatePayload(payload);
    }

    /**
     * @inheritdoc IPolicyEngine
     * @dev State-changing policy run. Modifies state and can call postRun hooks.
     */
    function run(Payload calldata payload) external override {
        runCallCount++;
        lastRunPayload = payload;

        // Modify state to demonstrate the difference between check() and run()
        stateModifiedByRun++;

        // Check rejection conditions
        _validatePayload(payload);
    }

    /**
     * @notice Internal validation logic shared by check() and run().
     * @dev Reverts with PolicyRejected or custom error based on configuration.
     */
    function _validatePayload(Payload calldata payload) internal view {
        // Reject all mode
        if (rejectAll) {
            if (revertWithUnknownError) {
                revert("Unknown error");
            }
            revert PolicyRejected(rejectionMessage);
        }

        // Decode transfer parameters (from, to, amount)
        if (payload.data.length >= 96) {
            (address from, address to, uint256 amount) = abi.decode(payload.data, (address, address, uint256));

            // Check blocked sender
            if (blockedFrom[from]) {
                revert PolicyRejected("Sender is blocked");
            }

            // Check blocked recipient
            if (blockedTo[to]) {
                revert PolicyRejected("Recipient is blocked");
            }

            // Check max amount
            if (maxAmount > 0 && amount > maxAmount) {
                revert PolicyRejected("Amount exceeds maximum");
            }
        }
    }

    /**
     * @notice Allows tracking check() calls externally (since check is view).
     * @dev Call this after check() to simulate incrementing the counter.
     */
    function trackCheckCall(Payload calldata payload) external {
        checkCallCount++;
        lastCheckPayload = payload;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STUB IMPLEMENTATIONS (not used by adapter)
    // ═══════════════════════════════════════════════════════════════════════════

    function attach() external override {}
    function detach() external override {}
    function setExtractor(bytes4, address) external override {}
    function setExtractors(bytes4[] calldata, address) external override {}
    function getExtractor(bytes4) external pure override returns (address) { return address(0); }
    function setPolicyMapper(address, address) external override {}
    function getPolicyMapper(address) external pure override returns (address) { return address(0); }
    function addPolicy(address, bytes4, address, bytes32[] calldata) external override {}
    function addPolicyAt(address, bytes4, address, bytes32[] calldata, uint256) external override {}
    function removePolicy(address, bytes4, address) external override {}
    function getPolicies(address, bytes4) external pure override returns (address[] memory) {
        return new address[](0);
    }
    function setDefaultPolicyAllow(bool) external override {}
    function setTargetDefaultPolicyAllow(address, bool) external override {}
}
