// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice Minimal RuleEngine interface matching CMTAT's IEIP1404Wrapper
 */
interface IMockRuleEngine {
    function validateTransfer(
        address from,
        address to,
        uint256 amount
    ) external view returns (bool);

    function detectTransferRestriction(
        address from,
        address to,
        uint256 amount
    ) external view returns (uint8);

    function messageForTransferRestriction(
        uint8 restrictionCode
    ) external view returns (string memory);
}

/**
 * @title MockCMTATToken
 * @notice Minimal ERC20 token that mimics CMTAT's RuleEngine integration.
 * @dev This mock implements the core transfer validation pattern used by CMTAT:
 *      - Calls ruleEngine.validateTransfer() before allowing transfers
 *      - Allows switching the RuleEngine via setRuleEngine()
 *      - Supports minting for testing purposes
 *
 * ## How CMTAT Validates Transfers
 * In the real CMTAT token, _transfer() calls the ruleEngine to validate:
 * ```solidity
 * function _transfer(address from, address to, uint256 amount) internal override {
 *     if (address(ruleEngine) != address(0)) {
 *         require(
 *             ruleEngine.validateTransfer(from, to, amount),
 *             "Transfer rejected by rule engine"
 *         );
 *     }
 *     super._transfer(from, to, amount);
 * }
 * ```
 */
contract MockCMTATToken is ERC20, Ownable {
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The current RuleEngine contract (can be the adapter)
    IMockRuleEngine public ruleEngine;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when the RuleEngine is changed.
     * @param oldRuleEngine Previous RuleEngine address
     * @param newRuleEngine New RuleEngine address
     */
    event RuleEngineSet(address indexed oldRuleEngine, address indexed newRuleEngine);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Error thrown when a transfer is rejected by the RuleEngine.
     * @param restrictionCode The restriction code from the RuleEngine
     * @param message The human-readable rejection message
     */
    error TransferRejectedByRuleEngine(uint8 restrictionCode, string message);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes the token with name, symbol, and owner.
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param owner_ Initial owner
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_
    ) ERC20(name_, symbol_) Ownable(owner_) {}

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sets the RuleEngine contract.
     * @dev This is how CMTAT tokens switch to using the ACE adapter.
     * @param newRuleEngine The new RuleEngine contract address (or address(0) to disable)
     */
    function setRuleEngine(address newRuleEngine) external onlyOwner {
        address oldRuleEngine = address(ruleEngine);
        ruleEngine = IMockRuleEngine(newRuleEngine);
        emit RuleEngineSet(oldRuleEngine, newRuleEngine);
    }

    /**
     * @notice Mints tokens to an address (for testing).
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from an address (for testing).
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC20 OVERRIDES
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Override _update to add RuleEngine validation.
     * @dev Called by transfer, transferFrom, mint, and burn.
     *      Only validates for transfers (not mints/burns).
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        // Only validate actual transfers (not mints or burns)
        if (from != address(0) && to != address(0)) {
            _validateTransfer(from, to, amount);
        }

        super._update(from, to, amount);
    }

    /**
     * @notice Validates a transfer against the RuleEngine.
     * @dev Reverts with TransferRejectedByRuleEngine if validation fails.
     */
    function _validateTransfer(
        address from,
        address to,
        uint256 amount
    ) internal view {
        // Skip validation if no RuleEngine is set
        if (address(ruleEngine) == address(0)) {
            return;
        }

        // Call the RuleEngine to validate the transfer
        bool isValid = ruleEngine.validateTransfer(from, to, amount);

        if (!isValid) {
            // Get the restriction code and message for better error reporting
            uint8 restrictionCode = ruleEngine.detectTransferRestriction(from, to, amount);
            string memory message = ruleEngine.messageForTransferRestriction(restrictionCode);
            revert TransferRejectedByRuleEngine(restrictionCode, message);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Checks if a transfer would be allowed without executing it.
     * @dev Useful for UI pre-validation.
     * @param from Sender address
     * @param to Recipient address
     * @param amount Transfer amount
     * @return isValid True if transfer would be allowed
     */
    function canTransfer(
        address from,
        address to,
        uint256 amount
    ) external view returns (bool isValid) {
        if (address(ruleEngine) == address(0)) {
            return true;
        }
        return ruleEngine.validateTransfer(from, to, amount);
    }

    /**
     * @notice Gets the restriction code for a potential transfer.
     * @param from Sender address
     * @param to Recipient address
     * @param amount Transfer amount
     * @return restrictionCode 0 = no restriction, non-zero = restricted
     */
    function getTransferRestriction(
        address from,
        address to,
        uint256 amount
    ) external view returns (uint8 restrictionCode) {
        if (address(ruleEngine) == address(0)) {
            return 0;
        }
        return ruleEngine.detectTransferRestriction(from, to, amount);
    }

    /**
     * @notice Gets the human-readable message for a restriction code.
     * @param restrictionCode The restriction code
     * @return message The error message
     */
    function getRestrictionMessage(
        uint8 restrictionCode
    ) external view returns (string memory message) {
        if (address(ruleEngine) == address(0)) {
            return "No rule engine configured";
        }
        return ruleEngine.messageForTransferRestriction(restrictionCode);
    }
}
