// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IExtractor} from "@chainlink/policy-management/interfaces/IExtractor.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CMTATTransferExtractor
 * @author CMTAT ACE Adapter
 * @notice Extracts transfer parameters from ERC20 and CMTAT-specific function calls.
 * @dev This extractor supports:
 *      - `transfer(address to, uint256 amount)` - Standard ERC20 transfer
 *      - `transferFrom(address from, address to, uint256 amount)` - Standard ERC20 transferFrom
 *      - `validateTransfer(address from, address to, uint256 amount)` - CMTAT validation call
 *
 * The extractor returns three parameters:
 * - PARAM_FROM: The sender address
 * - PARAM_TO: The recipient address
 * - PARAM_AMOUNT: The transfer amount
 *
 * ## Usage
 * This extractor is designed to work with the ACERuleEngineAdapter. The adapter constructs
 * payloads with the appropriate selector and data, which this extractor parses.
 *
 * ## Gas Optimization
 * - Uses pure function for stateless extraction
 * - Efficient selector comparison using bytes4
 * - Direct abi.decode without intermediate storage
 */
contract CMTATTransferExtractor is IExtractor {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Parameter key for the sender/from address in transfer operations
    bytes32 public constant PARAM_FROM = keccak256("from");

    /// @notice Parameter key for the recipient/to address in transfer operations
    bytes32 public constant PARAM_TO = keccak256("to");

    /// @notice Parameter key for the amount being transferred
    bytes32 public constant PARAM_AMOUNT = keccak256("amount");

    /// @notice Function selector for ERC20 transfer(address,uint256)
    bytes4 public constant SELECTOR_TRANSFER = IERC20.transfer.selector;

    /// @notice Function selector for ERC20 transferFrom(address,address,uint256)
    bytes4 public constant SELECTOR_TRANSFER_FROM = IERC20.transferFrom.selector;

    /// @notice Function selector for CMTAT validateTransfer(address,address,uint256)
    /// @dev This is the same signature as transferFrom but used during validation
    bytes4 public constant SELECTOR_VALIDATE_TRANSFER = bytes4(keccak256("validateTransfer(address,address,uint256)"));

    // ═══════════════════════════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @inheritdoc IExtractor
     * @notice Extracts transfer parameters from the payload.
     * @dev Handles three function selectors:
     *      - transfer(address,uint256): from = payload.sender
     *      - transferFrom(address,address,uint256): from = decoded parameter
     *      - validateTransfer(address,address,uint256): from = decoded parameter
     *
     * @param payload The policy engine payload containing selector and calldata
     * @return parameters Array of three parameters: PARAM_FROM, PARAM_TO, PARAM_AMOUNT
     */
    function extract(
        IPolicyEngine.Payload calldata payload
    ) external pure override returns (IPolicyEngine.Parameter[] memory parameters) {
        address from;
        address to;
        uint256 amount;

        bytes4 selector = payload.selector;

        if (selector == SELECTOR_TRANSFER) {
            // transfer(address to, uint256 amount) - from is the sender
            from = payload.sender;
            (to, amount) = abi.decode(payload.data, (address, uint256));
        } else if (selector == SELECTOR_TRANSFER_FROM || selector == SELECTOR_VALIDATE_TRANSFER) {
            // transferFrom(address from, address to, uint256 amount)
            // validateTransfer(address from, address to, uint256 amount)
            (from, to, amount) = abi.decode(payload.data, (address, address, uint256));
        } else {
            revert IPolicyEngine.UnsupportedSelector(selector);
        }

        // Build the parameter array
        parameters = new IPolicyEngine.Parameter[](3);
        parameters[0] = IPolicyEngine.Parameter(PARAM_FROM, abi.encode(from));
        parameters[1] = IPolicyEngine.Parameter(PARAM_TO, abi.encode(to));
        parameters[2] = IPolicyEngine.Parameter(PARAM_AMOUNT, abi.encode(amount));

        return parameters;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Returns the list of supported function selectors.
     * @return selectors Array of supported function selectors
     */
    function supportedSelectors() external pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = SELECTOR_TRANSFER;
        selectors[1] = SELECTOR_TRANSFER_FROM;
        selectors[2] = SELECTOR_VALIDATE_TRANSFER;
        return selectors;
    }

    /**
     * @notice Checks if a selector is supported by this extractor.
     * @param selector The function selector to check
     * @return supported True if the selector is supported
     */
    function isSupported(bytes4 selector) external pure returns (bool supported) {
        return selector == SELECTOR_TRANSFER ||
               selector == SELECTOR_TRANSFER_FROM ||
               selector == SELECTOR_VALIDATE_TRANSFER;
    }
}
