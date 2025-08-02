// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISimpleEscrowFactory} from "./interfaces/ISimpleEscrowFactory.sol";
import {ISimpleEscrow} from "./interfaces/ISimpleEscrow.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title LightningBridge
 * @notice Enables atomic swaps between EVM chains and the Bitcoin Lightning Network
 * @dev Coordinates HTLCs across both systems using the same preimage
 */
contract LightningBridge is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Enums ============

    enum SwapState {
        None,
        Initiated,      // Swap has been initiated
        LightningPaid,  // Lightning payment confirmed by resolver
        Completed,      // Swap completed successfully
        Expired         // Swap timed out
    }

    enum SwapDirection {
        EVMToLightning,
        LightningToEVM
    }

    // ============ Structs ============

    struct LightningSwap {
        // EVM side details
        address evmEscrow;        // SimpleEscrow contract address
        address initiator;        // Who started the swap
        address evmToken;         // Token being swapped on EVM
        uint256 evmAmount;        // Amount in EVM token
        
        // Lightning side details
        bytes32 paymentHash;      // Same as hashlock in SimpleEscrow
        uint256 satoshiAmount;    // Amount in satoshis
        string lightningInvoice;  // BOLT11 invoice (set off-chain)
        
        // Swap metadata
        SwapState state;          // Current state of swap
        SwapDirection direction;  // Direction of the swap
        uint256 createdAt;        // Timestamp of creation
        uint256 timelock;         // Expiry timestamp
        bytes32 preimage;         // Revealed after completion
        address recipient;        // Recipient for Lightning→EVM swaps
    }

    // ============ State Variables ============

    ISimpleEscrowFactory public immutable escrowFactory;
    
    mapping(bytes32 => LightningSwap) public swaps;
    mapping(address => bytes32[]) public userSwaps;
    
    address public resolver;
    uint256 public swapCounter;
    
    // Configuration
    uint256 public minSatoshiAmount = 1000;          // Minimum Lightning amount
    uint256 public maxSatoshiAmount = 10_000_000;    // Maximum Lightning amount
    uint256 public defaultSwapTimeout = 3600;        // Default 1 hour timeout
    
    // ============ Events ============

    event EVMToLightningInitiated(
        bytes32 indexed paymentHash,
        address indexed initiator,
        address evmEscrow,
        uint256 evmAmount,
        uint256 satoshiAmount,
        uint256 timelock
    );

    event LightningToEVMInitiated(
        bytes32 indexed paymentHash,
        address indexed recipient,
        string lightningInvoice,
        uint256 evmAmount,
        uint256 satoshiAmount
    );

    event LightningInvoiceSet(
        bytes32 indexed paymentHash,
        string invoice
    );

    event LightningPaymentConfirmed(
        bytes32 indexed paymentHash,
        bytes32 preimage,
        address indexed confirmedBy
    );

    event SwapCompleted(
        bytes32 indexed paymentHash,
        address indexed initiator,
        uint256 evmAmount,
        uint256 satoshiAmount
    );

    event SwapExpired(
        bytes32 indexed paymentHash,
        address indexed initiator
    );

    event ResolverUpdated(
        address indexed oldResolver,
        address indexed newResolver
    );

    event ConfigurationUpdated(
        uint256 minSatoshiAmount,
        uint256 maxSatoshiAmount,
        uint256 defaultSwapTimeout
    );

    // ============ Errors ============

    error InvalidAmount();
    error InvalidTimelock();
    error InvalidPaymentHash();
    error InvalidPreimage();
    error SwapNotFound();
    error SwapAlreadyExists();
    error InvalidSwapState();
    error UnauthorizedResolver();
    error SwapNotExpired();
    error InvalidDirection();
    error InvalidRecipient();
    error InvalidInvoice();
    error EscrowCreationFailed();
    error TransferFailed();

    // ============ Modifiers ============

    modifier onlyResolver() {
        if (msg.sender != resolver) revert UnauthorizedResolver();
        _;
    }

    modifier validPaymentHash(bytes32 paymentHash) {
        if (paymentHash == bytes32(0)) revert InvalidPaymentHash();
        _;
    }

    modifier swapExists(bytes32 paymentHash) {
        if (swaps[paymentHash].state == SwapState.None) revert SwapNotFound();
        _;
    }

    // ============ Constructor ============

    constructor(address _escrowFactory) Ownable(msg.sender) {
        if (_escrowFactory == address(0)) revert InvalidRecipient();
        escrowFactory = ISimpleEscrowFactory(_escrowFactory);
    }

    // ============ Core Functions ============

    /**
     * @notice Initiate a swap from EVM tokens to Lightning payment
     * @param evmToken The ERC20 token to swap
     * @param evmAmount Amount of tokens to lock
     * @param satoshiAmount Expected Lightning payment in satoshis
     * @param paymentHash Hash of the preimage (used in both systems)
     * @param timelock Expiry time for the swap (must be > block.timestamp)
     * @return escrow Address of created SimpleEscrow
     */
    function initiateEVMToLightning(
        address evmToken,
        uint256 evmAmount,
        uint256 satoshiAmount,
        bytes32 paymentHash,
        uint256 timelock
    ) external whenNotPaused nonReentrant validPaymentHash(paymentHash) returns (address escrow) {
        // Validations
        if (evmAmount == 0) revert InvalidAmount();
        if (satoshiAmount < minSatoshiAmount || satoshiAmount > maxSatoshiAmount) revert InvalidAmount();
        if (timelock <= block.timestamp) revert InvalidTimelock();
        if (swaps[paymentHash].state != SwapState.None) revert SwapAlreadyExists();

        // Create escrow with factory
        escrow = escrowFactory.createEscrow(
            evmToken,
            msg.sender,      // sender
            address(this),   // recipient (bridge will release with preimage)
            paymentHash,     // hashlock
            timelock,
            keccak256(abi.encodePacked(msg.sender, block.timestamp, swapCounter))
        );

        if (escrow == address(0)) revert EscrowCreationFailed();

        // Store swap details
        LightningSwap storage swap = swaps[paymentHash];
        swap.evmEscrow = escrow;
        swap.initiator = msg.sender;
        swap.evmToken = evmToken;
        swap.evmAmount = evmAmount;
        swap.paymentHash = paymentHash;
        swap.satoshiAmount = satoshiAmount;
        swap.state = SwapState.Initiated;
        swap.direction = SwapDirection.EVMToLightning;
        swap.createdAt = block.timestamp;
        swap.timelock = timelock;

        // Track user swaps
        userSwaps[msg.sender].push(paymentHash);
        swapCounter++;

        emit EVMToLightningInitiated(
            paymentHash,
            msg.sender,
            escrow,
            evmAmount,
            satoshiAmount,
            timelock
        );
    }

    /**
     * @notice Initiate a swap from Lightning payment to EVM tokens
     * @param lightningInvoice BOLT11 Lightning invoice
     * @param evmToken Token to receive on EVM
     * @param evmAmount Amount to receive
     * @param recipient Who receives the EVM tokens
     * @return paymentHash The payment hash from the invoice
     */
    function initiateLightningToEVM(
        string calldata lightningInvoice,
        address evmToken,
        uint256 evmAmount,
        address recipient
    ) external whenNotPaused nonReentrant returns (bytes32 paymentHash) {
        // Validations
        if (bytes(lightningInvoice).length == 0) revert InvalidInvoice();
        if (evmAmount == 0) revert InvalidAmount();
        if (recipient == address(0)) revert InvalidRecipient();

        // Extract payment hash from invoice (simplified - in production use proper BOLT11 decoder)
        paymentHash = keccak256(abi.encodePacked(lightningInvoice, block.timestamp));
        
        if (swaps[paymentHash].state != SwapState.None) revert SwapAlreadyExists();

        // For Lightning→EVM, we need the resolver to create and fund the escrow after Lightning payment
        // Store swap details for resolver to process
        LightningSwap storage swap = swaps[paymentHash];
        swap.initiator = msg.sender;
        swap.evmToken = evmToken;
        swap.evmAmount = evmAmount;
        swap.paymentHash = paymentHash;
        swap.lightningInvoice = lightningInvoice;
        swap.state = SwapState.Initiated;
        swap.direction = SwapDirection.LightningToEVM;
        swap.createdAt = block.timestamp;
        swap.timelock = block.timestamp + defaultSwapTimeout;
        swap.recipient = recipient;
        swap.satoshiAmount = 10000; // Default amount - in production extract from invoice

        // Track user swaps
        userSwaps[msg.sender].push(paymentHash);
        userSwaps[recipient].push(paymentHash);
        swapCounter++;

        emit LightningToEVMInitiated(
            paymentHash,
            recipient,
            lightningInvoice,
            evmAmount,
            swap.satoshiAmount
        );
    }

    /**
     * @notice Resolver sets the Lightning invoice after creation
     * @param paymentHash The payment hash for the swap
     * @param invoice The BOLT11 invoice string
     */
    function setLightningInvoice(
        bytes32 paymentHash,
        string calldata invoice
    ) external onlyResolver swapExists(paymentHash) {
        LightningSwap storage swap = swaps[paymentHash];
        
        if (swap.state != SwapState.Initiated) revert InvalidSwapState();
        if (swap.direction != SwapDirection.EVMToLightning) revert InvalidDirection();
        
        swap.lightningInvoice = invoice;
        
        emit LightningInvoiceSet(paymentHash, invoice);
    }

    /**
     * @notice Resolver confirms Lightning payment and reveals preimage
     * @param paymentHash The payment hash for the swap
     * @param preimage The preimage that hashes to the payment hash
     */
    function confirmLightningPayment(
        bytes32 paymentHash,
        bytes32 preimage
    ) external onlyResolver swapExists(paymentHash) nonReentrant {
        // Validate preimage
        if (sha256(abi.encodePacked(preimage)) != paymentHash) revert InvalidPreimage();
        
        LightningSwap storage swap = swaps[paymentHash];
        
        if (swap.state != SwapState.Initiated) revert InvalidSwapState();
        
        swap.preimage = preimage;
        swap.state = SwapState.LightningPaid;
        
        emit LightningPaymentConfirmed(paymentHash, preimage, msg.sender);

        // For Lightning→EVM swaps, resolver needs to create and fund escrow
        if (swap.direction == SwapDirection.LightningToEVM) {
            // Create escrow for the recipient
            address escrow = escrowFactory.createEscrow(
                swap.evmToken,
                resolver,           // Resolver funds it
                swap.recipient,     // Recipient withdraws with preimage
                paymentHash,
                swap.timelock,
                keccak256(abi.encodePacked(paymentHash, block.timestamp))
            );
            
            if (escrow == address(0)) revert EscrowCreationFailed();
            swap.evmEscrow = escrow;
        }
    }

    /**
     * @notice Withdraw EVM funds using the revealed preimage
     * @param paymentHash The payment hash for the swap
     */
    function withdrawEVMFunds(bytes32 paymentHash) external swapExists(paymentHash) nonReentrant {
        LightningSwap storage swap = swaps[paymentHash];
        
        if (swap.state != SwapState.LightningPaid) revert InvalidSwapState();
        if (swap.direction != SwapDirection.EVMToLightning) revert InvalidDirection();
        if (swap.preimage == bytes32(0)) revert InvalidPreimage();
        
        // Withdraw from escrow using preimage
        ISimpleEscrow escrow = ISimpleEscrow(swap.evmEscrow);
        escrow.withdraw(swap.preimage);
        
        // Transfer funds to resolver
        IERC20(swap.evmToken).safeTransfer(resolver, swap.evmAmount);
        
        swap.state = SwapState.Completed;
        
        emit SwapCompleted(
            paymentHash,
            swap.initiator,
            swap.evmAmount,
            swap.satoshiAmount
        );
    }

    /**
     * @notice Expire a swap that has timed out
     * @param paymentHash The payment hash for the swap
     */
    function expireSwap(bytes32 paymentHash) external swapExists(paymentHash) nonReentrant {
        LightningSwap storage swap = swaps[paymentHash];
        
        if (swap.state == SwapState.Completed || swap.state == SwapState.Expired) {
            revert InvalidSwapState();
        }
        
        if (block.timestamp <= swap.timelock) revert SwapNotExpired();
        
        swap.state = SwapState.Expired;
        
        emit SwapExpired(paymentHash, swap.initiator);
    }

    // ============ View Functions ============

    /**
     * @notice Get detailed information about a swap
     * @param paymentHash The payment hash to query
     * @return swap The complete swap details
     */
    function getSwapDetails(bytes32 paymentHash) external view returns (LightningSwap memory) {
        return swaps[paymentHash];
    }

    /**
     * @notice Get all swap payment hashes for a user
     * @param user The user address to query
     * @return Array of payment hashes
     */
    function getUserSwaps(address user) external view returns (bytes32[] memory) {
        return userSwaps[user];
    }

    /**
     * @notice Calculate payment hash from preimage
     * @param preimage The preimage to hash
     * @return The SHA256 hash of the preimage
     */
    function calculatePaymentHash(bytes32 preimage) external pure returns (bytes32) {
        return sha256(abi.encodePacked(preimage));
    }

    /**
     * @notice Check if a swap can be withdrawn
     * @param paymentHash The payment hash to check
     * @return True if the swap can be withdrawn
     */
    function canWithdraw(bytes32 paymentHash) external view returns (bool) {
        LightningSwap storage swap = swaps[paymentHash];
        return swap.state == SwapState.LightningPaid && 
               swap.direction == SwapDirection.EVMToLightning &&
               swap.preimage != bytes32(0);
    }

    /**
     * @notice Check if a swap can be expired
     * @param paymentHash The payment hash to check
     * @return True if the swap can be expired
     */
    function canExpire(bytes32 paymentHash) external view returns (bool) {
        LightningSwap storage swap = swaps[paymentHash];
        return swap.state == SwapState.Initiated && 
               block.timestamp > swap.timelock;
    }

    // ============ Admin Functions ============

    /**
     * @notice Update the resolver address
     * @param _resolver The new resolver address
     */
    function setResolver(address _resolver) external onlyOwner {
        if (_resolver == address(0)) revert InvalidRecipient();
        address oldResolver = resolver;
        resolver = _resolver;
        emit ResolverUpdated(oldResolver, _resolver);
    }

    /**
     * @notice Update configuration parameters
     * @param _minSatoshiAmount New minimum satoshi amount
     * @param _maxSatoshiAmount New maximum satoshi amount
     * @param _defaultSwapTimeout New default swap timeout
     */
    function updateConfiguration(
        uint256 _minSatoshiAmount,
        uint256 _maxSatoshiAmount,
        uint256 _defaultSwapTimeout
    ) external onlyOwner {
        if (_minSatoshiAmount == 0 || _minSatoshiAmount >= _maxSatoshiAmount) revert InvalidAmount();
        if (_defaultSwapTimeout < 300) revert InvalidTimelock(); // Minimum 5 minutes
        
        minSatoshiAmount = _minSatoshiAmount;
        maxSatoshiAmount = _maxSatoshiAmount;
        defaultSwapTimeout = _defaultSwapTimeout;
        
        emit ConfigurationUpdated(_minSatoshiAmount, _maxSatoshiAmount, _defaultSwapTimeout);
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency function to recover stuck tokens
     * @param token The token to recover
     * @param to The address to send tokens to
     * @param amount The amount to recover
     */
    function emergencyTokenRecovery(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (to == address(0)) revert InvalidRecipient();
        IERC20(token).safeTransfer(to, amount);
    }
}