// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SimpleEscrow
 * @notice Minimalist Hash Time Locked Contract (HTLC) for atomic swaps
 * @dev Single unified contract for both source and destination chains
 */
contract SimpleEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Immutable variables (Set at creation)
    address public immutable token;      // ERC20 token to be swapped
    address public immutable sender;     // Party who deposits funds
    address public immutable recipient;  // Party who can withdraw with preimage
    bytes32 public immutable hashlock;   // Hash of the secret preimage
    uint256 public immutable timelock;   // Timestamp after which sender can refund

    // Mutable state variables
    uint256 public amount;              // Amount of tokens locked
    bool public funded;                 // Whether escrow has been funded
    bool public withdrawn;              // Whether funds have been withdrawn
    bool public refunded;              // Whether funds have been refunded
    bytes32 public preimage;           // Revealed secret (after withdrawal)

    // Events
    event EscrowFunded(
        address indexed sender,
        uint256 amount,
        address token
    );

    event EscrowWithdrawn(
        address indexed recipient,
        bytes32 preimage,
        uint256 amount
    );

    event EscrowRefunded(
        address indexed sender,
        uint256 amount
    );

    // Struct for getDetails return
    struct EscrowDetails {
        address token;
        address sender;
        address recipient;
        bytes32 hashlock;
        uint256 timelock;
        uint256 amount;
        bool funded;
        bool withdrawn;
        bool refunded;
        bytes32 preimage;
    }

    /**
     * @notice Constructor
     * @param _token ERC20 token contract address
     * @param _sender Address that will fund the escrow
     * @param _recipient Address that can withdraw with correct preimage
     * @param _hashlock keccak256 hash of the secret preimage
     * @param _timelock Unix timestamp after which refund is allowed
     */
    constructor(
        address _token,
        address _sender,
        address _recipient,
        bytes32 _hashlock,
        uint256 _timelock
    ) {
        require(_token != address(0), "SimpleEscrow: token cannot be zero address");
        require(_sender != address(0), "SimpleEscrow: sender cannot be zero address");
        require(_recipient != address(0), "SimpleEscrow: recipient cannot be zero address");
        require(_hashlock != bytes32(0), "SimpleEscrow: hashlock cannot be zero");
        require(_timelock > block.timestamp, "SimpleEscrow: timelock must be in future");

        token = _token;
        sender = _sender;
        recipient = _recipient;
        hashlock = _hashlock;
        timelock = _timelock;
    }

    /**
     * @notice Allows the sender to deposit tokens into the escrow
     * @param _amount Amount of tokens to deposit
     */
    function fund(uint256 _amount) external nonReentrant {
        require(msg.sender == sender, "SimpleEscrow: only sender can fund");
        require(!funded, "SimpleEscrow: already funded");
        require(_amount > 0, "SimpleEscrow: amount must be greater than 0");

        amount = _amount;
        funded = true;

        IERC20(token).safeTransferFrom(sender, address(this), _amount);

        emit EscrowFunded(sender, _amount, token);
    }

    /**
     * @notice Allows recipient to claim tokens by revealing the preimage
     * @param _preimage The secret preimage that hashes to hashlock
     */
    function withdraw(bytes32 _preimage) external nonReentrant {
        require(funded, "SimpleEscrow: not funded");
        require(!withdrawn, "SimpleEscrow: already withdrawn");
        require(!refunded, "SimpleEscrow: already refunded");
        require(block.timestamp < timelock, "SimpleEscrow: timelock expired");
        require(keccak256(abi.encode(_preimage)) == hashlock, "SimpleEscrow: invalid preimage");

        preimage = _preimage;
        withdrawn = true;

        IERC20(token).safeTransfer(recipient, amount);

        emit EscrowWithdrawn(recipient, _preimage, amount);
    }

    /**
     * @notice Allows sender to reclaim tokens after timeout
     */
    function refund() external nonReentrant {
        require(msg.sender == sender, "SimpleEscrow: only sender can refund");
        require(funded, "SimpleEscrow: not funded");
        require(!withdrawn, "SimpleEscrow: already withdrawn");
        require(!refunded, "SimpleEscrow: already refunded");
        require(block.timestamp >= timelock, "SimpleEscrow: timelock not expired");

        refunded = true;

        IERC20(token).safeTransfer(sender, amount);

        emit EscrowRefunded(sender, amount);
    }

    /**
     * @notice Returns all escrow details in a single call
     * @return EscrowDetails struct with all current state
     */
    function getDetails() external view returns (EscrowDetails memory) {
        return EscrowDetails({
            token: token,
            sender: sender,
            recipient: recipient,
            hashlock: hashlock,
            timelock: timelock,
            amount: amount,
            funded: funded,
            withdrawn: withdrawn,
            refunded: refunded,
            preimage: preimage
        });
    }

    /**
     * @notice Checks if withdrawal is currently possible
     * @return bool indicating if withdraw can be called successfully
     */
    function canWithdraw() external view returns (bool) {
        return funded && !withdrawn && !refunded && block.timestamp < timelock;
    }

    /**
     * @notice Checks if refund is currently possible
     * @return bool indicating if refund can be called successfully
     */
    function canRefund() external view returns (bool) {
        return funded && !withdrawn && !refunded && block.timestamp >= timelock;
    }
}