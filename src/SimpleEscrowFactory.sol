// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./SimpleEscrow.sol";
import "./interfaces/IOrderMixin.sol";

/**
 * @title SimpleEscrowFactory
 * @notice Factory contract for deploying SimpleEscrow contracts with deterministic addresses using CREATE2
 * @dev Supports both direct creation and creation triggered by 1inch orders
 */
contract SimpleEscrowFactory is Ownable {
    using SafeERC20 for IERC20;

    // State variables
    mapping(address => bool) public deployedEscrows;  // Track deployed escrows
    address public oneInchAdapter;                    // Optional 1inch adapter address
    uint256 public escrowCount;                       // Total escrows created

    // Struct for batch creation
    struct EscrowParams {
        address token;
        address sender;
        address recipient;
        bytes32 hashlock;
        uint256 timelock;
        bytes32 salt;
    }

    // Events
    event EscrowCreated(
        address indexed escrow,
        address indexed sender,
        address indexed recipient,
        address token,
        bytes32 hashlock,
        uint256 timelock,
        uint256 chainId,
        bytes32 salt
    );

    event EscrowCreatedFrom1inch(
        address indexed escrow,
        bytes32 indexed orderHash,
        address indexed maker,
        uint256 makingAmount
    );

    /**
     * @notice Constructor
     * @param _oneInchAdapter Address of OneInchAdapter contract (can be zero for standalone deployment)
     */
    constructor(address _oneInchAdapter) Ownable(msg.sender) {
        oneInchAdapter = _oneInchAdapter;
    }

    /**
     * @notice Direct escrow creation without 1inch dependency
     * @param token ERC20 token for the swap
     * @param sender Address that will fund the escrow
     * @param recipient Address that can withdraw with preimage
     * @param hashlock Hash of the secret
     * @param timelock Refund timestamp
     * @param salt Salt for CREATE2 deployment
     * @return escrow Address of deployed escrow
     */
    function createEscrow(
        address token,
        address sender,
        address recipient,
        bytes32 hashlock,
        uint256 timelock,
        bytes32 salt
    ) external returns (address escrow) {
        return _createEscrow(token, sender, recipient, hashlock, timelock, salt);
    }

    /**
     * @notice Creates and immediately funds an escrow (convenience function)
     * @param token ERC20 token for the swap
     * @param sender Address that will fund the escrow
     * @param recipient Address that can withdraw with preimage
     * @param hashlock Hash of the secret
     * @param timelock Refund timestamp
     * @param salt Salt for CREATE2 deployment
     * @param amount Amount to fund the escrow with
     * @return escrow Address of deployed escrow
     */
    function createEscrowWithFunding(
        address token,
        address sender,
        address recipient,
        bytes32 hashlock,
        uint256 timelock,
        bytes32 salt,
        uint256 amount
    ) external returns (address escrow) {
        require(msg.sender == sender, "SimpleEscrowFactory: only sender can create and fund");
        require(amount > 0, "SimpleEscrowFactory: amount must be greater than 0");

        // Create escrow
        escrow = _createEscrow(token, sender, recipient, hashlock, timelock, salt);

        // Transfer tokens directly from sender to escrow
        IERC20(token).safeTransferFrom(msg.sender, escrow, amount);
        
        // Initialize the escrow with the transferred funds
        SimpleEscrow(escrow).initializeWithFunds(amount);
        
        return escrow;
    }

    /**
     * @notice Creates escrow from 1inch order data (compatibility layer)
     * @param order 1inch order struct
     * @param extension Encoded atomic swap parameters
     * @param makingAmount Amount being swapped
     * @return escrow Address of deployed escrow
     */
    function createEscrowFrom1inchOrder(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        uint256 makingAmount
    ) external returns (address escrow) {
        require(msg.sender == oneInchAdapter, "SimpleEscrowFactory: only 1inch adapter");

        // Decode extension parameters
        (bytes32 hashlock, address recipient, uint256 timeoutDuration, bytes32 salt) = 
            abi.decode(extension, (bytes32, address, uint256, bytes32));

        // Calculate timelock
        uint256 timelock = block.timestamp + timeoutDuration;

        // Create escrow using order parameters
        escrow = _createEscrow(
            order.makerAsset,
            order.maker,
            recipient,
            hashlock,
            timelock,
            salt
        );

        // Emit 1inch-specific event
        emit EscrowCreatedFrom1inch(
            escrow,
            keccak256(abi.encode(order)),
            order.maker,
            makingAmount
        );

        return escrow;
    }

    /**
     * @notice Creates multiple escrows in one transaction (gas optimization)
     * @param params Array of escrow parameters
     * @return escrows Array of deployed addresses
     */
    function batchCreateEscrows(
        EscrowParams[] calldata params
    ) external returns (address[] memory escrows) {
        uint256 length = params.length;
        require(length > 0, "SimpleEscrowFactory: empty params array");
        
        escrows = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            escrows[i] = _createEscrow(
                params[i].token,
                params[i].sender,
                params[i].recipient,
                params[i].hashlock,
                params[i].timelock,
                params[i].salt
            );
        }

        return escrows;
    }

    /**
     * @notice Internal function to create escrow (shared logic)
     * @param token ERC20 token for the swap
     * @param sender Address that will fund the escrow
     * @param recipient Address that can withdraw with preimage
     * @param hashlock Hash of the secret
     * @param timelock Refund timestamp
     * @param salt Salt for CREATE2 deployment
     * @return escrow Address of deployed escrow
     */
    function _createEscrow(
        address token,
        address sender,
        address recipient,
        bytes32 hashlock,
        uint256 timelock,
        bytes32 salt
    ) internal returns (address escrow) {
        // Validate parameters
        require(token != address(0), "SimpleEscrowFactory: token cannot be zero address");
        require(sender != address(0), "SimpleEscrowFactory: sender cannot be zero address");
        require(recipient != address(0), "SimpleEscrowFactory: recipient cannot be zero address");
        require(hashlock != bytes32(0), "SimpleEscrowFactory: hashlock cannot be zero");
        require(timelock > block.timestamp, "SimpleEscrowFactory: timelock must be in future");

        // Compute the address where the escrow will be deployed
        escrow = computeEscrowAddress(token, sender, recipient, hashlock, timelock, salt);
        
        // Check that escrow doesn't already exist
        require(!deployedEscrows[escrow], "SimpleEscrowFactory: escrow already exists");

        // Deploy the escrow using CREATE2
        bytes memory bytecode = abi.encodePacked(
            type(SimpleEscrow).creationCode,
            abi.encode(token, sender, recipient, hashlock, timelock)
        );

        assembly {
            escrow := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }

        require(escrow != address(0), "SimpleEscrowFactory: deployment failed");

        // Mark escrow as deployed and increment count
        deployedEscrows[escrow] = true;
        escrowCount++;

        // Emit event with chain ID for cross-chain coordination
        emit EscrowCreated(
            escrow,
            sender,
            recipient,
            token,
            hashlock,
            timelock,
            block.chainid,
            salt
        );

        return escrow;
    }

    /**
     * @notice Calculates escrow address before deployment (critical for cross-chain coordination)
     * @param token ERC20 token for the swap
     * @param sender Address that will fund the escrow
     * @param recipient Address that can withdraw with preimage
     * @param hashlock Hash of the secret
     * @param timelock Refund timestamp
     * @param salt Salt for CREATE2 deployment
     * @return Deterministic address where escrow will be deployed
     */
    function computeEscrowAddress(
        address token,
        address sender,
        address recipient,
        bytes32 hashlock,
        uint256 timelock,
        bytes32 salt
    ) public view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(SimpleEscrow).creationCode,
            abi.encode(token, sender, recipient, hashlock, timelock)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );

        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Checks if an escrow has been deployed at given address
     * @param escrow Address to check
     * @return bool indicating if escrow is deployed
     */
    function isEscrowDeployed(address escrow) external view returns (bool) {
        return deployedEscrows[escrow];
    }

    /**
     * @notice Fetches details from a deployed escrow (convenience function)
     * @param escrow Address of deployed escrow
     * @return EscrowDetails struct with all escrow information
     */
    function getEscrowDetails(address escrow) external view returns (SimpleEscrow.EscrowDetails memory) {
        require(deployedEscrows[escrow], "SimpleEscrowFactory: escrow not deployed by this factory");
        return SimpleEscrow(escrow).getDetails();
    }

    /**
     * @notice Returns the bytecode for escrow deployment (for external verification)
     * @param token ERC20 token for the swap
     * @param sender Address that will fund the escrow
     * @param recipient Address that can withdraw with preimage
     * @param hashlock Hash of the secret
     * @param timelock Refund timestamp
     * @return bytecode The complete bytecode used for deployment
     */
    function getEscrowBytecode(
        address token,
        address sender,
        address recipient,
        bytes32 hashlock,
        uint256 timelock
    ) external pure returns (bytes memory bytecode) {
        return abi.encodePacked(
            type(SimpleEscrow).creationCode,
            abi.encode(token, sender, recipient, hashlock, timelock)
        );
    }

    /**
     * @notice Allows updating the 1inch adapter address (only owner)
     * @param _oneInchAdapter New 1inch adapter address
     */
    function setOneInchAdapter(address _oneInchAdapter) external onlyOwner {
        oneInchAdapter = _oneInchAdapter;
    }
}