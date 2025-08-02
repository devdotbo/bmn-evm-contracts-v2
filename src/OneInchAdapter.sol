// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./BaseExtension.sol";
import "./SimpleEscrowFactory.sol";
import "./interfaces/IOrderMixin.sol";

/**
 * @title OneInchAdapter
 * @notice Compatibility bridge between 1inch Limit Order Protocol and the simplified atomic swap system
 * @dev Implements IPostInteraction to receive callbacks from 1inch and trigger escrow creation
 */
contract OneInchAdapter is BaseExtension, Ownable, Pausable {
    using SafeERC20 for IERC20;

    // State variables
    SimpleEscrowFactory public immutable factory;
    address public immutable limitOrderProtocol;

    // Custom errors
    error InvalidExtensionData();
    error EscrowCreationFailed();
    error TokenTransferFailed();
    error OrderValidationFailed();
    error AdapterPaused();
    error UnauthorizedCaller();
    error InvalidTimeoutDuration();
    error InvalidParameters();
    error ZeroAmount();

    // Events
    event AtomicSwapInitiated(
        bytes32 indexed orderHash,
        address indexed escrow,
        address indexed maker,
        address taker,
        bytes32 hashlock,
        uint256 amount
    );

    event AtomicSwapFunded(
        address indexed escrow,
        uint256 amount,
        address token
    );

    event ExtensionDecoded(
        bytes32 indexed orderHash,
        bytes32 hashlock,
        address recipient,
        uint256 destinationChainId
    );

    event TokensRescued(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    // Modifier to ensure only limit order protocol can call
    modifier onlyLimitOrderProtocol() {
        if (msg.sender != limitOrderProtocol) {
            revert UnauthorizedCaller();
        }
        _;
    }

    /**
     * @notice Constructor
     * @param _factory SimpleEscrowFactory contract address
     * @param _limitOrderProtocol 1inch Limit Order Protocol address
     */
    constructor(
        address _factory,
        address _limitOrderProtocol
    ) Ownable(msg.sender) {
        if (_factory == address(0) || _limitOrderProtocol == address(0)) {
            revert InvalidParameters();
        }
        
        factory = SimpleEscrowFactory(_factory);
        limitOrderProtocol = _limitOrderProtocol;
    }

    /**
     * @notice Main callback from 1inch protocol after order execution
     * @dev Called by 1inch after tokens have been transferred
     */
    function _postInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal override onlyLimitOrderProtocol whenNotPaused {
        // Validate order parameters
        _validateOrder(order, makingAmount);

        // Decode extension data
        (
            bytes32 hashlock,
            address crossChainRecipient,
            uint256 timeoutDuration,
            uint256 destinationChainId,
            bytes32 escrowSalt
        ) = decodeExtension(extension);

        // Emit decoded extension event for monitoring
        emit ExtensionDecoded(orderHash, hashlock, crossChainRecipient, destinationChainId);

        // Calculate timelock
        uint256 timelock = block.timestamp + timeoutDuration;
        
        // Validate timeout duration (max 30 days)
        if (timeoutDuration == 0 || timeoutDuration > 30 days) {
            revert InvalidTimeoutDuration();
        }

        // Create escrow through factory
        address escrow;
        try factory.createEscrow(
            order.makerAsset,
            order.maker,
            crossChainRecipient,
            hashlock,
            timelock,
            escrowSalt
        ) returns (address _escrow) {
            escrow = _escrow;
        } catch {
            revert EscrowCreationFailed();
        }

        // Emit atomic swap initiated event
        emit AtomicSwapInitiated(
            orderHash,
            escrow,
            order.maker,
            taker,
            hashlock,
            makingAmount
        );

        // Transfer tokens from adapter to escrow
        // Note: Tokens should already be in this contract from 1inch protocol
        IERC20 token = IERC20(order.makerAsset);
        
        // Check balance
        uint256 balance = token.balanceOf(address(this));
        if (balance < makingAmount) {
            revert TokenTransferFailed();
        }

        // Transfer to escrow
        token.safeTransfer(escrow, makingAmount);

        // Fund the escrow
        SimpleEscrow(escrow).fund(makingAmount);

        // Emit funded event
        emit AtomicSwapFunded(escrow, makingAmount, order.makerAsset);
    }

    /**
     * @notice Decode extension data containing atomic swap parameters
     * @param extension Encoded extension data
     * @return hashlock Hash of the secret
     * @return recipient Cross-chain recipient address
     * @return timeoutDuration Timeout duration in seconds
     * @return destinationChainId Target chain ID
     * @return salt Salt for deterministic deployment
     */
    function decodeExtension(
        bytes calldata extension
    ) public pure returns (
        bytes32 hashlock,
        address recipient,
        uint256 timeoutDuration,
        uint256 destinationChainId,
        bytes32 salt
    ) {
        if (extension.length < 160) { // 32 + 20 + 32 + 32 + 32 = 148, padded to 160
            revert InvalidExtensionData();
        }

        // Decode the extension data
        (hashlock, recipient, timeoutDuration, destinationChainId, salt) = 
            abi.decode(extension, (bytes32, address, uint256, uint256, bytes32));

        // Validate decoded data
        if (hashlock == bytes32(0) || recipient == address(0) || salt == bytes32(0)) {
            revert InvalidExtensionData();
        }

        return (hashlock, recipient, timeoutDuration, destinationChainId, salt);
    }

    /**
     * @notice Internal validation of order parameters
     * @param order 1inch order data
     * @param makingAmount Amount being made
     */
    function _validateOrder(
        IOrderMixin.Order calldata order,
        uint256 makingAmount
    ) internal view {
        if (order.maker == address(0)) {
            revert OrderValidationFailed();
        }
        
        if (makingAmount == 0) {
            revert ZeroAmount();
        }
        
        if (order.makerAsset == address(0)) {
            revert OrderValidationFailed();
        }

        // Additional validation can be added here
    }

    /**
     * @notice Emergency function to rescue stuck tokens
     * @param token Token address to rescue
     * @param to Recipient address
     * @param amount Amount to rescue
     */
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (token == address(0) || to == address(0)) {
            revert InvalidParameters();
        }
        
        if (amount == 0) {
            revert ZeroAmount();
        }

        IERC20(token).safeTransfer(to, amount);
        
        emit TokensRescued(token, to, amount);
    }

    /**
     * @notice Pause the adapter
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the adapter
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Override to ensure no pre-interaction logic
     */
    function _preInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal override {
        // No pre-interaction logic needed
    }

    /**
     * @notice Override for dynamic making amount (not used, returns static amount)
     */
    function _getMakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal view override returns (uint256) {
        return order.makingAmount;
    }

    /**
     * @notice Override for dynamic taking amount (not used, returns static amount)
     */
    function _getTakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal view override returns (uint256) {
        return order.takingAmount;
    }
}